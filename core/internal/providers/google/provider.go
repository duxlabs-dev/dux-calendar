package google

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"google.golang.org/api/calendar/v3"
	"google.golang.org/api/googleapi"
	"google.golang.org/api/option"
	gtasks "google.golang.org/api/tasks/v1"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/oauth"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/oauthbase"
	"github.com/duxlabs-dev/dux-calendar/core/internal/tzcache"
	"github.com/duxlabs-dev/dux-go/log"
)

const maxPageSize = 2500

type Provider struct {
	account        cal.Account
	svc            *calendar.Service
	tasksSvc       *gtasks.Service
	notices        []string
	quotaOnce      sync.Once
	quota          *quotaGate
	tasksQuotaOnce sync.Once
	tasksQuota     *quotaGate
	retryMu        sync.Mutex
	retryWait      time.Duration
}

func (p *Provider) Notices() []string { return p.notices }

func New(ctx context.Context, account cal.Account, secrets cal.SecretStore) (*Provider, error) {
	src, err := oauthbase.LoadTokenSource(ctx, secrets, account, SecretKeyApp, SecretKeyToken,
		func(c oauth.GoogleAppCredentials) *oauth2.Config { return oauth.GoogleConfig(c, "") })
	if err != nil {
		return nil, err
	}

	svc, err := calendar.NewService(ctx, option.WithTokenSource(src))
	if err != nil {
		return nil, fmt.Errorf("init google calendar service: %w", err)
	}
	tasksSvc, err := gtasks.NewService(ctx, option.WithTokenSource(src))
	if err != nil {
		return nil, fmt.Errorf("init google tasks service: %w", err)
	}

	return &Provider{account: account, svc: svc, tasksSvc: tasksSvc}, nil
}

func (p *Provider) Kind() cal.AccountKind { return cal.AccountGoogle }
func (p *Provider) Account() cal.Account  { return p.account }

// ListCalendars discovers event calendars and task lists from two independent
// Google APIs. Either may be disabled in the user's Cloud project, so a
// "service disabled" failure on one degrades to a soft notice while the other
// still syncs; only when both are unreachable does the account fail outright.
// Tasks is metered and served separately, so any non-auth Tasks failure skips
// task lists for the cycle instead of stopping events (#138).
func (p *Provider) ListCalendars(ctx context.Context) ([]cal.Calendar, error) {
	p.notices = nil

	cals, calErr := p.listEventCalendars(ctx)
	taskLists, taskErr := p.listTaskLists(ctx)

	switch {
	case calErr != nil && taskErr != nil:
		return nil, fmt.Errorf("list google calendars: %w", classifyAuthErr(errors.Join(calErr, taskErr)))
	case calErr != nil && isServiceDisabled(calErr):
		p.notices = append(p.notices, cal.NoticeCalendarsUnavailable)
		log.Warnf("account %s: Google Calendar API disabled, syncing tasks only: %v", p.account.ID, calErr)
		return taskLists, nil
	case calErr != nil:
		return nil, fmt.Errorf("list google calendars: %w", classifyAuthErr(calErr))
	case taskErr == nil:
		return append(cals, taskLists...), nil
	case isOptionalServiceUnavailable(taskErr):
		p.notices = append(p.notices, cal.NoticeTasksUnavailable)
		log.Warnf("account %s: Google Tasks unavailable, syncing calendars only: %v", p.account.ID, taskErr)
		return cals, nil
	case errors.Is(taskErr, cal.ErrReauthRequired):
		return nil, taskErr
	}

	log.Warnf("account %s: Google Tasks failed, syncing calendars only: %v", p.account.ID, taskErr)
	return cals, nil
}

func (p *Provider) listEventCalendars(ctx context.Context) ([]cal.Calendar, error) {
	res, err := googleCall(ctx, p, true, func() (*calendar.CalendarList, error) { return p.svc.CalendarList.List().Context(ctx).Do() })
	if err != nil {
		return nil, err
	}

	out := make([]cal.Calendar, 0, len(res.Items))
	for _, item := range res.Items {
		out = append(out, cal.Calendar{
			AccountID:   p.account.ID,
			RemoteID:    item.Id,
			Name:        item.Summary,
			Description: item.Description,
			Color:       item.BackgroundColor,
			TimeZone:    item.TimeZone,
			ReadOnly:    item.AccessRole == "reader" || item.AccessRole == "freeBusyReader",
		})
	}
	return out, nil
}

// isServiceDisabled reports whether err is Google's "API not enabled for this
// project" 403, which is a fixable configuration issue rather than a credential
// failure, so callers can degrade gracefully and point the user at the console.
func isServiceDisabled(err error) bool {
	var apiErr *googleapi.Error
	if !errors.As(err, &apiErr) || apiErr.Code != http.StatusForbidden {
		return false
	}
	for _, e := range apiErr.Errors {
		if e.Reason == "accessNotConfigured" {
			return true
		}
	}
	return strings.Contains(apiErr.Message, "has not been used in project") ||
		strings.Contains(apiErr.Message, "it is disabled")
}

// isOptionalServiceUnavailable identifies failures that should disable Google
// Tasks without blocking Calendar. Older account tokens lack the Tasks scope
// because it was added after Calendar support shipped.
func isOptionalServiceUnavailable(err error) bool {
	if isServiceDisabled(err) {
		return true
	}
	var apiErr *googleapi.Error
	if !errors.As(err, &apiErr) || apiErr.Code != http.StatusForbidden {
		return false
	}
	for _, e := range apiErr.Errors {
		if e.Reason == "insufficientPermissions" {
			return true
		}
	}
	return strings.Contains(strings.ToLower(apiErr.Message), "insufficient authentication scopes")
}

func (p *Provider) Sync(ctx context.Context, c cal.Calendar, cursor cal.SyncCursor) (*cal.SyncResult, error) {
	if c.HoldsTasks() {
		return p.syncTasks(ctx, c)
	}
	return p.syncEvents(ctx, c, cursor)
}

func (p *Provider) syncEvents(ctx context.Context, c cal.Calendar, cursor cal.SyncCursor) (*cal.SyncResult, error) {
	changes, nextToken, err := p.syncPages(ctx, c, cursor.Token)
	if err != nil {
		var apiErr *googleapi.Error
		if cursor.Token == "" || !errors.As(err, &apiErr) || apiErr.Code != http.StatusGone {
			return nil, classifyAuthErr(err)
		}
		// Sync token expired; restart with a full listing.
		cursor.Token = ""
		if changes, nextToken, err = p.syncPages(ctx, c, ""); err != nil {
			return nil, classifyAuthErr(err)
		}
	}

	return &cal.SyncResult{
		Cursor:       cal.SyncCursor{CalendarID: cursor.CalendarID, Token: nextToken},
		Changes:      changes,
		More:         false,
		FullSnapshot: cursor.Token == "",
	}, nil
}

func (p *Provider) syncPages(ctx context.Context, c cal.Calendar, syncToken string) ([]cal.EventChange, string, error) {
	var (
		changes   []cal.EventChange
		pageToken string
	)

	for {
		call := p.svc.Events.List(c.RemoteID).
			Context(ctx).
			SingleEvents(false).
			ShowDeleted(true).
			MaxResults(maxPageSize)
		if syncToken != "" {
			call = call.SyncToken(syncToken)
		}
		if pageToken != "" {
			call = call.PageToken(pageToken)
		}

		res, err := googleCall(ctx, p, true, func() (*calendar.Events, error) { return call.Do() })
		if err != nil {
			return nil, "", fmt.Errorf("sync google events: %w", err)
		}

		for _, item := range res.Items {
			switch {
			case item.Status != "cancelled":
				changes = append(changes, cal.EventChange{Type: cal.ChangeUpsert, Event: fromGoogleEvent(c, item)})
			case item.RecurringEventId != "":
				// Cancelled instances of a series are kept as exception rows
				// so expansion can suppress the occurrences they remove.
				changes = append(changes, cal.EventChange{Type: cal.ChangeUpsert, Event: fromGoogleEvent(c, item)})
			case syncToken != "":
				changes = append(changes, cal.EventChange{Type: cal.ChangeDelete, RemoteID: item.Id})
			}
		}

		if res.NextPageToken == "" {
			return changes, res.NextSyncToken, nil
		}
		pageToken = res.NextPageToken
	}
}

func (p *Provider) ListEvents(ctx context.Context, c cal.Calendar, opts cal.ListEventsOptions) ([]cal.Event, error) {
	limit := int64(opts.Limit)
	if limit <= 0 {
		limit = maxPageSize
	}

	call := p.svc.Events.List(c.RemoteID).
		Context(ctx).
		SingleEvents(true).
		OrderBy("startTime").
		MaxResults(limit)
	if !opts.Start.IsZero() {
		call = call.TimeMin(opts.Start.Format(time.RFC3339))
	}
	if !opts.End.IsZero() {
		call = call.TimeMax(opts.End.Format(time.RFC3339))
	}
	if opts.Query != "" {
		call = call.Q(opts.Query)
	}

	res, err := googleCall(ctx, p, true, func() (*calendar.Events, error) { return call.Do() })
	if err != nil {
		return nil, fmt.Errorf("list google events: %w", err)
	}

	out := make([]cal.Event, 0, len(res.Items))
	for _, item := range res.Items {
		out = append(out, *fromGoogleEvent(c, item))
	}
	return out, nil
}

func (p *Provider) CreateEvent(ctx context.Context, c cal.Calendar, ev *cal.Event) (*cal.Event, error) {
	created, err := googleCall(ctx, p, false, func() (*calendar.Event, error) {
		return p.svc.Events.Insert(c.RemoteID, toGoogleEvent(ev)).Context(ctx).Do()
	})
	if err != nil {
		return nil, fmt.Errorf("create google event: %w", err)
	}
	return fromGoogleEvent(c, created), nil
}

func (p *Provider) ImportEvent(ctx context.Context, c cal.Calendar, ev *cal.Event) (*cal.Event, error) {
	item := toGoogleEvent(ev)
	item.ICalUID = ev.UID
	if ev.Organizer != nil {
		item.Organizer = &calendar.EventOrganizer{Email: ev.Organizer.Email, DisplayName: ev.Organizer.DisplayName}
	}
	imported, err := googleCall(ctx, p, false, func() (*calendar.Event, error) { return p.svc.Events.Import(c.RemoteID, item).Context(ctx).Do() })
	if err != nil {
		return nil, fmt.Errorf("import google event: %w", err)
	}
	return fromGoogleEvent(c, imported), nil
}

func (p *Provider) UpdateEvent(ctx context.Context, c cal.Calendar, ev *cal.Event) (*cal.Event, error) {
	if ev.RemoteID == "" {
		return nil, errors.New("update google event: missing remote id")
	}

	updated, err := googleCall(ctx, p, false, func() (*calendar.Event, error) {
		return p.svc.Events.Update(c.RemoteID, ev.RemoteID, toGoogleEvent(ev)).Context(ctx).Do()
	})
	if err != nil {
		return nil, fmt.Errorf("update google event: %w", err)
	}
	return fromGoogleEvent(c, updated), nil
}

// RespondToEvent patches only the attendees collection, setting the current
// user's responseStatus. A non-organizer attendee may change just their own
// reply; sending the full list preserves everyone else's status. Occurrence
// replies (ev.OriginalStart set) patch the per-instance event instead of the
// recurring master.
func (p *Provider) RespondToEvent(ctx context.Context, c cal.Calendar, ev *cal.Event, response string) (*cal.Event, error) {
	if ev.RemoteID == "" {
		return nil, errors.New("respond google event: missing remote id")
	}

	self := strings.ToLower(p.account.ID)
	attendees := toGoogleAttendees(ev.Attendees)
	found := false
	for _, a := range attendees {
		if !strings.EqualFold(a.Email, self) {
			continue
		}
		a.ResponseStatus = toGoogleResponse(response)
		found = true
	}
	if !found {
		return nil, fmt.Errorf("respond google event: %q is not an attendee", self)
	}

	remoteID := ev.RemoteID
	if !ev.OriginalStart.IsZero() && ev.RecurringID != "" {
		remoteID = googleInstanceID(ev.RemoteID, ev.OriginalStart, ev.AllDay)
	}

	updated, err := googleCall(ctx, p, false, func() (*calendar.Event, error) {
		return p.svc.Events.Patch(c.RemoteID, remoteID, &calendar.Event{Attendees: attendees}).Context(ctx).Do()
	})
	if err != nil {
		return nil, fmt.Errorf("respond google event: %w", err)
	}
	return fromGoogleEvent(c, updated), nil
}

// googleInstanceID addresses one occurrence of a recurring event: the master id
// plus the occurrence's original start, in the format instances() ids use.
func googleInstanceID(masterID string, originalStart time.Time, allDay bool) string {
	if allDay {
		return masterID + "_" + originalStart.UTC().Format("20060102")
	}
	return masterID + "_" + originalStart.UTC().Format("20060102T150405Z")
}

func toGoogleResponse(canonical string) string {
	switch canonical {
	case cal.ResponseAccepted:
		return "accepted"
	case cal.ResponseDeclined:
		return "declined"
	case cal.ResponseTentative:
		return "tentative"
	default:
		return "needsAction"
	}
}

func (p *Provider) DeleteEvent(ctx context.Context, c cal.Calendar, ev cal.Event) error {
	if ev.RemoteID == "" {
		return errors.New("delete google event: missing remote id")
	}

	_, err := googleCall(ctx, p, false, func() (*struct{}, error) {
		return nil, p.svc.Events.Delete(c.RemoteID, ev.RemoteID).Context(ctx).Do()
	})
	if err == nil {
		return nil
	}

	var apiErr *googleapi.Error
	if errors.As(err, &apiErr) && (apiErr.Code == http.StatusNotFound || apiErr.Code == http.StatusGone) {
		return nil
	}
	return fmt.Errorf("delete google event: %w", err)
}

// fromGoogleEvent uses item.Id (not ICalUID) for both UID and RemoteID:
// recurrence exceptions share an ICalUID and would collide on the
// (calendar, uid) unique index.
func fromGoogleEvent(c cal.Calendar, item *calendar.Event) *cal.Event {
	ev := &cal.Event{
		CalendarID:   c.ID,
		UID:          item.Id,
		RemoteID:     item.Id,
		Etag:         item.Etag,
		Summary:      item.Summary,
		Description:  item.Description,
		Location:     item.Location,
		URL:          item.HtmlLink,
		MeetingURL:   fromGoogleMeetingURL(item),
		Status:       fromGoogleStatus(item.Status),
		Recurrence:   fromGoogleRecurrence(item.Recurrence),
		RecurringID:  item.RecurringEventId,
		Attendees:    fromGoogleAttendees(item.Attendees),
		Transparency: item.Transparency,
		Visibility:   item.Visibility,
	}

	ev.Start, ev.AllDay, ev.StartTimeZone = fromGoogleTime(item.Start)
	ev.End, _, ev.EndTimeZone = fromGoogleTime(item.End)
	ev.OriginalStart, _, _ = fromGoogleTime(item.OriginalStartTime)

	// Third-party integrations create all-day events whose exclusive end date
	// equals the start date (or is missing); stored verbatim they span no day
	// at all and vanish from every view (#77). Google renders them as one-day
	// events, so must we.
	if ev.AllDay && !ev.End.After(ev.Start) {
		ev.End = ev.Start.AddDate(0, 0, 1)
	}

	if item.Organizer != nil {
		ev.Organizer = &cal.Attendee{
			Email:       item.Organizer.Email,
			DisplayName: item.Organizer.DisplayName,
			Organizer:   true,
		}
	}

	if item.Reminders != nil {
		for _, o := range item.Reminders.Overrides {
			ev.Reminders = append(ev.Reminders, cal.Reminder{Method: o.Method, Minutes: int(o.Minutes)})
		}
	}

	ev.Created, _ = time.Parse(time.RFC3339, item.Created)
	ev.Updated, _ = time.Parse(time.RFC3339, item.Updated)
	return ev
}

// fromGoogleMeetingURL prefers a video entry point from conferenceData, then the
// legacy hangoutLink, then a known link in the description or location (e.g. a
// Zoom meeting added through an add-on, which leaves conferenceData empty).
func fromGoogleMeetingURL(item *calendar.Event) string {
	if item.ConferenceData != nil {
		for _, ep := range item.ConferenceData.EntryPoints {
			if ep.EntryPointType == "video" && ep.Uri != "" {
				return ep.Uri
			}
		}
	}
	if item.HangoutLink != "" {
		return item.HangoutLink
	}
	return cal.MeetingURLInText(item.Description, item.Location)
}

func fromGoogleStatus(s string) cal.EventStatus {
	switch s {
	case "tentative":
		return cal.EventTentative
	case "cancelled":
		return cal.EventCancelled
	default:
		return cal.EventConfirmed
	}
}

func fromGoogleTime(t *calendar.EventDateTime) (time.Time, bool, string) {
	switch {
	case t == nil:
		return time.Time{}, false, ""
	case t.Date != "":
		parsed, _ := time.ParseInLocation("2006-01-02", t.Date, time.UTC)
		return parsed, true, t.TimeZone
	default:
		parsed, _ := time.Parse(time.RFC3339, t.DateTime)
		return parsed, false, t.TimeZone
	}
}

func fromGoogleRecurrence(lines []string) *cal.Recurrence {
	if len(lines) == 0 {
		return nil
	}

	rec := &cal.Recurrence{}
	for _, line := range lines {
		name, value, found := strings.Cut(line, ":")
		if !found {
			continue
		}
		// RDATE/EXDATE may carry params (e.g. ;TZID=), so match the
		// property name before any parameters.
		prop, params, _ := strings.Cut(name, ";")
		switch strings.ToUpper(prop) {
		case "RRULE":
			rec.RRule = append(rec.RRule, value)
		case "RDATE":
			rec.RDate = append(rec.RDate, normalizeDateValues(params, value))
		case "EXDATE":
			rec.ExDate = append(rec.ExDate, normalizeDateValues(params, value))
		}
	}

	if len(rec.RRule) == 0 && len(rec.RDate) == 0 && len(rec.ExDate) == 0 {
		return nil
	}
	return rec
}

// normalizeDateValues rewrites a TZID-qualified RDATE/EXDATE value list to
// absolute UTC instants; the expander reads bare values in the series zone,
// which need not match the TZID Google reports.
func normalizeDateValues(params, value string) string {
	tzid := ""
	for param := range strings.SplitSeq(params, ";") {
		if v, ok := strings.CutPrefix(param, "TZID="); ok {
			tzid = v
		}
	}
	if tzid == "" {
		return value
	}
	loc, err := tzcache.Load(tzid)
	if err != nil {
		return value
	}

	parts := strings.Split(value, ",")
	for i, raw := range parts {
		raw = strings.TrimSpace(raw)
		parts[i] = raw
		if len(raw) == 8 || strings.HasSuffix(raw, "Z") {
			continue
		}
		t, perr := time.ParseInLocation("20060102T150405", raw, loc)
		if perr != nil {
			continue
		}
		parts[i] = t.UTC().Format("20060102T150405Z")
	}
	return strings.Join(parts, ",")
}

func fromGoogleAttendees(items []*calendar.EventAttendee) []cal.Attendee {
	if len(items) == 0 {
		return nil
	}

	out := make([]cal.Attendee, 0, len(items))
	for _, a := range items {
		out = append(out, cal.Attendee{
			Email:       a.Email,
			DisplayName: a.DisplayName,
			Status:      a.ResponseStatus,
			Optional:    a.Optional,
			Organizer:   a.Organizer,
		})
	}
	return out
}

func toGoogleAttendees(attendees []cal.Attendee) []*calendar.EventAttendee {
	if len(attendees) == 0 {
		return nil
	}
	out := make([]*calendar.EventAttendee, 0, len(attendees))
	for _, a := range attendees {
		out = append(out, &calendar.EventAttendee{
			Email:          a.Email,
			DisplayName:    a.DisplayName,
			ResponseStatus: a.Status,
			Optional:       a.Optional,
			Organizer:      a.Organizer,
		})
	}
	return out
}

func toGoogleEvent(ev *cal.Event) *calendar.Event {
	out := &calendar.Event{
		Summary:      ev.Summary,
		Description:  ev.Description,
		Location:     ev.Location,
		Status:       string(ev.Status),
		Transparency: ev.Transparency,
	}

	if ev.AllDay {
		out.Start = &calendar.EventDateTime{Date: ev.Start.Format("2006-01-02")}
		end := ev.End
		// Google all-day end dates are exclusive.
		if end.IsZero() || end.Format("2006-01-02") == ev.Start.Format("2006-01-02") {
			end = ev.Start.AddDate(0, 0, 1)
		}
		out.End = &calendar.EventDateTime{Date: end.Format("2006-01-02")}
	} else {
		out.Start = toGoogleDateTime(ev.Start, ev.StartTimeZone)
		out.End = toGoogleDateTime(ev.End, ev.EndTimeZone)
	}

	if ev.Recurrence != nil {
		for _, r := range ev.Recurrence.RRule {
			out.Recurrence = append(out.Recurrence, "RRULE:"+r)
		}
		for _, r := range ev.Recurrence.RDate {
			out.Recurrence = append(out.Recurrence, "RDATE:"+r)
		}
		for _, r := range ev.Recurrence.ExDate {
			out.Recurrence = append(out.Recurrence, "EXDATE:"+r)
		}
		// Google requires an explicit time zone on recurring events; our
		// times are stored UTC, so expand the series in UTC when the event
		// carries no zone of its own.
		if !ev.AllDay {
			if out.Start.TimeZone == "" {
				out.Start.TimeZone = "UTC"
			}
			if out.End.TimeZone == "" {
				out.End.TimeZone = "UTC"
			}
		}
	}

	out.Attendees = toGoogleAttendees(ev.Attendees)

	if len(ev.Reminders) > 0 {
		overrides := make([]*calendar.EventReminder, 0, len(ev.Reminders))
		for _, r := range ev.Reminders {
			overrides = append(overrides, &calendar.EventReminder{
				Method:  r.Method,
				Minutes: int64(r.Minutes),
				// Minutes is required on every override but JSON-omits at 0
				// ("at start"), which the API rejects with a 400.
				ForceSendFields: []string{"Minutes"},
			})
		}
		out.Reminders = &calendar.EventReminders{
			Overrides: overrides,
			// UseDefault is false, which JSON-omits unless forced.
			ForceSendFields: []string{"UseDefault"},
		}
	}

	return out
}

func toGoogleDateTime(t time.Time, tz string) *calendar.EventDateTime {
	dt := &calendar.EventDateTime{}
	if tz != "" {
		if loc, err := tzcache.Load(tz); err == nil {
			t = t.In(loc)
		}
		dt.TimeZone = tz
	}
	dt.DateTime = t.Format(time.RFC3339)
	return dt
}

func (p *Provider) Close() error { return nil }

func classifyAuthErr(err error) error {
	return oauthbase.ClassifyAuthErr(err, func(e error) bool {
		var apiErr *googleapi.Error
		return errors.As(e, &apiErr) && apiErr.Code == http.StatusUnauthorized
	})
}
