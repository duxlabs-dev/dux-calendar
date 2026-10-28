package sync

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/duxlabs-dev/dux-calendar/core/ent"
	entaccount "github.com/duxlabs-dev/dux-calendar/core/ent/account"
	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/eventconv"
	"github.com/duxlabs-dev/dux-calendar/core/internal/keyring"
	"github.com/duxlabs-dev/dux-calendar/core/internal/notify"
	"github.com/duxlabs-dev/dux-calendar/core/internal/taskconv"
	"github.com/duxlabs-dev/dux-calendar/core/repo"
	"github.com/duxlabs-dev/dux-go/log"
)

type Notifier func(topic string, data any)

// Sender delivers a desktop popup when an account newly requires
// reauthentication, since the IPC "accounts" event alone only reaches the
// Settings UI when it happens to be open.
type Sender interface {
	Send(n notify.Notification) (uint32, error)
}

const (
	// minInterval floors how often an account may be re-synced so a provider
	// hint can never busy-loop the engine.
	minInterval = time.Minute
	// maxWake caps how long the loop parks; a backstop against a missed wake or
	// an undetected clock change, not the normal path.
	maxWake = time.Hour
	// keyringLockedRetry polls a locked keyring until the user unlocks it.
	keyringLockedRetry = minInterval
)

type Engine struct {
	repo       *repo.Repo
	registry   *calendar.Registry
	secrets    calendar.SecretStore
	interval   time.Duration
	intervalFn func() time.Duration
	notify     Notifier
	sender     Sender
	now        func() time.Time

	wake chan struct{}

	mu            sync.Mutex
	nextDue       map[string]time.Time
	keyringLocked map[string]bool
	running       bool
	stop          chan struct{}
}

func NewEngine(r *repo.Repo, registry *calendar.Registry, secrets calendar.SecretStore, interval time.Duration) *Engine {
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	return &Engine{
		repo:          r,
		registry:      registry,
		secrets:       secrets,
		interval:      interval,
		now:           time.Now,
		wake:          make(chan struct{}, 1),
		nextDue:       make(map[string]time.Time),
		keyringLocked: make(map[string]bool),
		stop:          make(chan struct{}),
	}
}

func (e *Engine) SetNotifier(n Notifier) { e.notify = n }

// SetSender wires a desktop notifier used to alert the user when an account
// needs reauthentication. Optional: a nil sender leaves that popup silent.
func (e *Engine) SetSender(s Sender) { e.sender = s }

func (e *Engine) publish(topic string, data any) {
	if e.notify == nil {
		return
	}
	e.notify(topic, data)
}

// Wake triggers an immediate scheduling pass; concurrent calls coalesce.
func (e *Engine) Wake() {
	select {
	case e.wake <- struct{}{}:
	default:
	}
}

// WatchMutations wakes the engine when accounts change so adds and removals
// reschedule promptly. Event and calendar mutations are deliberately not
// watched: the engine writes those, so hooking them would loop.
func (e *Engine) WatchMutations(client *ent.Client) {
	client.Account.Use(func(next ent.Mutator) ent.Mutator {
		return ent.MutateFunc(func(ctx context.Context, m ent.Mutation) (ent.Value, error) {
			v, err := next.Mutate(ctx, m)
			if err == nil {
				e.Wake()
			}
			return v, err
		})
	})
}

func (e *Engine) Start(ctx context.Context) {
	e.mu.Lock()
	if e.running {
		e.mu.Unlock()
		return
	}
	e.running = true
	e.mu.Unlock()

	go e.loop(ctx)
}

func (e *Engine) Stop() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.running {
		return
	}
	close(e.stop)
	e.running = false
	e.stop = make(chan struct{})
}

// loop parks a timer until the soonest account is due, waking early on demand.
// NewTimer(0) runs the first pass immediately.
func (e *Engine) loop(ctx context.Context) {
	timer := time.NewTimer(0)
	defer timer.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-e.stop:
			return
		case <-e.wake:
		case <-timer.C:
		}

		e.runDue(ctx)
		resetTimer(timer, e.untilNext())
	}
}

// resetTimer rearms t, draining a pending fire so the next select sees only the
// new deadline.
func resetTimer(t *time.Timer, d time.Duration) {
	if !t.Stop() {
		select {
		case <-t.C:
		default:
		}
	}
	t.Reset(d)
}

// untilNext is the delay until the soonest account is due, capped at maxWake.
func (e *Engine) untilNext() time.Duration {
	e.mu.Lock()
	defer e.mu.Unlock()

	if len(e.nextDue) == 0 {
		return maxWake
	}

	now := e.now()
	soonest := maxWake
	for _, due := range e.nextDue {
		switch d := due.Sub(now); {
		case d <= 0:
			return 0
		case d < soonest:
			soonest = d
		}
	}
	return soonest
}

func (e *Engine) runDue(ctx context.Context) {
	accounts, err := e.repo.ListAccounts(ctx)
	if err != nil {
		log.Warnf("list accounts: %v", err)
		return
	}

	now := e.now()
	for _, acc := range accounts {
		if !e.due(acc.ID, now) {
			continue
		}
		if err := e.SyncAccount(ctx, acc); err != nil {
			logSyncError(acc.ID, err)
		}
	}
	e.pruneSchedule(accounts)
}

func (e *Engine) due(accountID string, now time.Time) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	due, ok := e.nextDue[accountID]
	return !ok || !due.After(now)
}

// SetIntervalFunc supplies a live poll interval consulted each scheduling pass;
// a zero/negative return is ignored.
func (e *Engine) SetIntervalFunc(fn func() time.Duration) {
	e.mu.Lock()
	e.intervalFn = fn
	e.mu.Unlock()
	e.Wake()
}

func (e *Engine) baseInterval() time.Duration {
	e.mu.Lock()
	fn := e.intervalFn
	interval := e.interval
	e.mu.Unlock()
	if fn == nil {
		return interval
	}
	if v := fn(); v > 0 {
		interval = v
	}
	return interval
}

func (e *Engine) schedule(accountID string, retryAfter time.Duration) {
	interval := e.baseInterval()
	if retryAfter > 0 {
		interval = retryAfter
	}
	if interval < minInterval {
		interval = minInterval
	}
	e.mu.Lock()
	e.nextDue[accountID] = e.now().Add(interval)
	e.mu.Unlock()
}

// pruneSchedule drops schedule entries for accounts that no longer exist.
func (e *Engine) pruneSchedule(accounts []*ent.Account) {
	live := make(map[string]struct{}, len(accounts))
	for _, acc := range accounts {
		live[acc.ID] = struct{}{}
	}
	e.mu.Lock()
	for id := range e.nextDue {
		if _, ok := live[id]; !ok {
			delete(e.nextDue, id)
			delete(e.keyringLocked, id)
		}
	}
	e.mu.Unlock()
}

func (e *Engine) SyncAll(ctx context.Context) error {
	accounts, err := e.repo.ListAccounts(ctx)
	if err != nil {
		return fmt.Errorf("list accounts: %w", err)
	}

	for _, acc := range accounts {
		if err := e.SyncAccount(ctx, acc); err != nil {
			logSyncError(acc.ID, err)
		}
	}
	return nil
}

func logSyncError(accountID string, err error) {
	if errors.Is(err, keyring.ErrLocked) {
		log.Debugf("account %s sync deferred: %v", accountID, err)
		return
	}
	log.Warnf("account %s sync error: %v", accountID, err)
}

func (e *Engine) SyncAccount(ctx context.Context, acc *ent.Account) error {
	retryAfter, err := e.syncAccount(ctx, acc)
	retryAfter = max(retryAfter, deferredRetryAfter(err))
	e.recordAuthState(ctx, acc, err)
	if e.recordKeyringLocked(acc.ID, errors.Is(err, keyring.ErrLocked)) {
		retryAfter = keyringLockedRetry
	}
	e.recordSyncFailure(ctx, acc, err)
	e.schedule(acc.ID, retryAfter)
	return err
}

// A sync that dies before any calendar runs (provider build, ListCalendars)
// would otherwise leave the account looking healthy (#138): needs_reauth stays
// false and the notice keeps whatever the last good cycle wrote.
func (e *Engine) recordSyncFailure(ctx context.Context, acc *ent.Account, err error) {
	switch {
	case err == nil, errors.Is(err, context.Canceled):
		return
	case errors.Is(err, keyring.ErrLocked), errors.Is(err, calendar.ErrReauthRequired):
		return
	}
	e.setSyncNotice(ctx, acc, calendar.NoticeCalendarSyncFailed)
}

func (e *Engine) recordKeyringLocked(accountID string, locked bool) bool {
	e.mu.Lock()
	was := e.keyringLocked[accountID]
	if locked {
		e.keyringLocked[accountID] = true
	} else {
		delete(e.keyringLocked, accountID)
	}
	e.mu.Unlock()

	if was != locked {
		e.publish("accounts", map[string]any{"type": "changed", "accountId": accountID})
	}
	return locked
}

func (e *Engine) syncAccount(ctx context.Context, acc *ent.Account) (time.Duration, error) {
	provider, err := e.registry.Build(ctx, accountToDomain(acc), e.secrets)
	if err != nil {
		return 0, err
	}
	defer provider.Close()

	remoteCals, err := provider.ListCalendars(ctx)
	if err != nil {
		return 0, fmt.Errorf("list calendars: %w", err)
	}
	var retryAfter time.Duration
	calendarFailed := false
	for _, rc := range remoteCals {
		stored, err := e.repo.UpsertCalendar(ctx, repo.UpsertCalendarInput{
			AccountID:           acc.ID,
			RemoteID:            rc.RemoteID,
			Name:                rc.Name,
			Description:         rc.Description,
			Color:               calendar.NormalizeColor(rc.Color),
			TimeZone:            rc.TimeZone,
			ReadOnly:            rc.ReadOnly,
			Hidden:              rc.Hidden,
			SupportedComponents: rc.SupportedComponents,
		})
		if err != nil {
			log.Warnf("upsert calendar %q: %v", rc.RemoteID, err)
			continue
		}

		if stored.SyncDisabled {
			continue
		}

		rc.ID = stored.ID
		rc.Color = stored.Color
		ra, err := e.syncCalendar(ctx, provider, rc, stored.SyncToken)
		if err != nil {
			log.Warnf("sync calendar %q: %v", rc.RemoteID, err)
			calendarFailed = true
			retryAfter = max(retryAfter, deferredRetryAfter(err))
			continue
		}
		if ra > retryAfter {
			retryAfter = ra
		}
	}

	e.recordSyncNotice(ctx, acc, provider, calendarFailed)
	e.publish("sync", map[string]any{"type": "completed", "accountId": acc.ID})
	return retryAfter, nil
}

// recordSyncNotice persists the provider's soft, non-fatal notices (e.g. a
// disabled Tasks API) for the GUI. Writes only on change.
func (e *Engine) recordSyncNotice(ctx context.Context, acc *ent.Account, provider calendar.Provider, calendarFailed bool) {
	var codes []string
	if reporter, ok := provider.(calendar.NoticeReporter); ok {
		codes = append(codes, reporter.Notices()...)
	}
	if calendarFailed {
		codes = append(codes, calendar.NoticeCalendarSyncFailed)
	}
	e.setSyncNotice(ctx, acc, strings.Join(codes, ","))
}

func (e *Engine) setSyncNotice(ctx context.Context, acc *ent.Account, notice string) {
	if notice == acc.SyncNotice {
		return
	}
	if err := e.repo.SetAccountSyncNotice(ctx, acc.ID, notice); err != nil {
		log.Warnf("record sync notice for %s: %v", acc.ID, err)
		return
	}
	acc.SyncNotice = notice
	e.publish("accounts", map[string]any{"type": "changed", "accountId": acc.ID})
}

// recordAuthState flips the account's needs_reauth flag when a sync reveals the
// credentials are dead (or recovers). It only writes on a state change so a
// revoked account does not churn the database or spam the UI every cycle.
func (e *Engine) recordAuthState(ctx context.Context, acc *ent.Account, syncErr error) {
	needsReauth := errors.Is(syncErr, calendar.ErrReauthRequired)
	if needsReauth == acc.NeedsReauth {
		return
	}

	authError := ""
	if needsReauth {
		authError = syncErr.Error()
	}
	if err := e.repo.SetAccountAuthState(ctx, acc.ID, needsReauth, authError); err != nil {
		log.Warnf("record auth state for %s: %v", acc.ID, err)
		return
	}

	acc.NeedsReauth = needsReauth
	acc.AuthError = authError
	e.publish("accounts", map[string]any{"type": "changed", "accountId": acc.ID})

	if needsReauth && e.sender != nil {
		if _, err := e.sender.Send(notify.Notification{
			Summary: "Dux Calendar",
			Body:    fmt.Sprintf("%s needs to sign in again to keep syncing.", acc.DisplayName),
			Urgency: notify.UrgencyNormal,
		}); err != nil {
			log.Warnf("send reauth notification for %s: %v", acc.ID, err)
		}
	}
}

func (e *Engine) syncCalendar(ctx context.Context, provider calendar.Provider, cal calendar.Calendar, token string) (time.Duration, error) {
	cursor := calendar.SyncCursor{CalendarID: cal.ID, Token: token}
	var (
		snapshot      bool
		eventUIDs     []string
		taskUIDs      []string
		changedEvents int
		changedTasks  int
		retryAfter    time.Duration
		color         string
	)
	touchedSeries := map[string]struct{}{}
	seriesUIDs := map[string][]string{}

	for {
		result, err := provider.Sync(ctx, cal, cursor)
		if err != nil {
			return 0, err
		}
		retryAfter = result.RetryAfter
		if result.Color != "" {
			color = result.Color
		}

		stored, err := e.repo.GetCalendar(ctx, cal.ID)
		if err != nil {
			return 0, err
		}
		if stored.SyncDisabled {
			return retryAfter, nil
		}

		if err := e.applyChanges(ctx, cal, result.Changes); err != nil {
			return 0, err
		}
		changedEvents += len(result.Changes)

		for _, id := range result.SeriesTouched {
			touchedSeries[id] = struct{}{}
		}
		for _, ch := range result.Changes {
			if ch.Type == calendar.ChangeUpsert && ch.Event != nil && ch.Event.RecurringID != "" {
				seriesUIDs[ch.Event.RecurringID] = append(seriesUIDs[ch.Event.RecurringID], ch.Event.UID)
			}
		}

		if err := e.applyTaskChanges(ctx, cal, result.TaskChanges); err != nil {
			return 0, err
		}
		changedTasks += len(result.TaskChanges)

		if result.FullSnapshot {
			snapshot = true
			for _, ch := range result.Changes {
				if ch.Type == calendar.ChangeUpsert && ch.Event != nil {
					eventUIDs = append(eventUIDs, ch.Event.UID)
				}
			}
			for _, ch := range result.TaskChanges {
				if ch.Type == calendar.ChangeUpsert && ch.Task != nil {
					taskUIDs = append(taskUIDs, ch.Task.UID)
				}
			}
		}

		if err := e.repo.SetCalendarSyncToken(ctx, cal.ID, result.Cursor.Token); err != nil {
			return 0, fmt.Errorf("persist sync token: %w", err)
		}

		cursor = result.Cursor
		if result.More {
			continue
		}

		if snapshot {
			pruned, err := e.pruneSnapshot(ctx, cal, eventUIDs, taskUIDs)
			if err != nil {
				return 0, err
			}
			changedEvents += pruned.events
			changedTasks += pruned.tasks
		} else {
			for id := range touchedSeries {
				n, err := e.repo.DeleteEventsInSeriesNotInUIDs(ctx, cal.ID, id, seriesUIDs[id])
				if err != nil {
					return 0, fmt.Errorf("reconcile series %q: %w", id, err)
				}
				changedEvents += n
			}
		}

		if c := calendar.NormalizeColor(color); c != "" && c != cal.Color {
			if err := e.repo.SetCalendarColor(ctx, cal.ID, c); err != nil {
				return 0, fmt.Errorf("persist calendar color: %w", err)
			}
			e.publish("calendars", map[string]any{"type": "changed", "calendarId": cal.ID})
		}

		if changedEvents > 0 {
			e.publish("events", map[string]any{"type": "changed", "calendarId": cal.ID})
		}
		if changedTasks > 0 {
			e.publish("tasks", map[string]any{"type": "changed", "calendarId": cal.ID})
		}
		return retryAfter, nil
	}
}

type prunedCounts struct {
	events int
	tasks  int
}

// pruneSnapshot removes rows absent from a full snapshot. A calendar that holds
// only one component type has no rows of the other, so pruning it is a harmless
// no-op rather than a special case.
func (e *Engine) pruneSnapshot(ctx context.Context, cal calendar.Calendar, eventUIDs, taskUIDs []string) (prunedCounts, error) {
	var out prunedCounts
	if cal.HoldsEvents() {
		n, err := e.repo.DeleteEventsNotInUIDs(ctx, cal.ID, eventUIDs)
		if err != nil {
			return out, fmt.Errorf("prune events: %w", err)
		}
		out.events = n
	}
	if cal.HoldsTasks() {
		n, err := e.repo.DeleteTasksNotInUIDs(ctx, cal.ID, taskUIDs)
		if err != nil {
			return out, fmt.Errorf("prune tasks: %w", err)
		}
		out.tasks = n
	}
	return out, nil
}

func (e *Engine) applyChanges(ctx context.Context, cal calendar.Calendar, changes []calendar.EventChange) error {
	for _, ch := range changes {
		switch ch.Type {
		case calendar.ChangeUpsert:
			if ch.Event == nil {
				continue
			}
			ev := ch.Event
			if _, err := e.repo.UpsertEvent(ctx, eventconv.UpsertInput(cal.ID, ev)); err != nil {
				return fmt.Errorf("upsert event %q: %w", ev.UID, err)
			}
		case calendar.ChangeDelete:
			if err := e.repo.DeleteEventByUID(ctx, cal.ID, ch.RemoteID); err != nil {
				return fmt.Errorf("delete event %q: %w", ch.RemoteID, err)
			}
		}
	}
	return nil
}

func (e *Engine) applyTaskChanges(ctx context.Context, cal calendar.Calendar, changes []calendar.TaskChange) error {
	for _, ch := range changes {
		switch ch.Type {
		case calendar.ChangeUpsert:
			if ch.Task == nil {
				continue
			}
			t := ch.Task
			if _, err := e.repo.UpsertTask(ctx, taskconv.UpsertInput(cal.ID, t)); err != nil {
				return fmt.Errorf("upsert task %q: %w", t.UID, err)
			}
		case calendar.ChangeDelete:
			if err := e.repo.DeleteTaskByUID(ctx, cal.ID, ch.RemoteID); err != nil {
				return fmt.Errorf("delete task %q: %w", ch.RemoteID, err)
			}
		}
	}
	return nil
}

func accountToDomain(a *ent.Account) calendar.Account {
	return calendar.Account{
		ID:          a.ID,
		Kind:        calendar.AccountKind(a.Kind),
		DisplayName: a.DisplayName,
		Settings:    a.Settings,
		CreatedAt:   a.CreatedAt,
		UpdatedAt:   a.UpdatedAt,
	}
}

var _ = entaccount.IDEQ

// Providers can defer a retry without sleeping on the serial account loop.
// errors.As keeps the hint visible through contextual error wrapping.
func deferredRetryAfter(err error) time.Duration {
	var hint interface{ RetryAfter() time.Duration }
	if errors.As(err, &hint) {
		return hint.RetryAfter()
	}
	return 0
}
