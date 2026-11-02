package calendar

import (
	"context"
	"errors"
	"time"
)

// ErrReauthRequired marks a sync failure as a dead credential: the stored
// token was rejected and the account must be re-authorized. Providers wrap it
// around the underlying error so the sync engine can flag the account.
var ErrReauthRequired = errors.New("reauthentication required")

type Provider interface {
	Kind() AccountKind
	Account() Account

	ListCalendars(ctx context.Context) ([]Calendar, error)
	Sync(ctx context.Context, cal Calendar, cursor SyncCursor) (*SyncResult, error)
	ListEvents(ctx context.Context, cal Calendar, opts ListEventsOptions) ([]Event, error)

	CreateEvent(ctx context.Context, cal Calendar, ev *Event) (*Event, error)
	UpdateEvent(ctx context.Context, cal Calendar, ev *Event) (*Event, error)
	DeleteEvent(ctx context.Context, cal Calendar, ev Event) error

	Close() error
}

// TaskWriter is implemented by providers that support writing tasks (VTODO).
// Read-only providers (e.g. iCal subscriptions) omit it; callers must type-assert
// before offering create, edit, complete, or delete. Reads flow through Sync,
// which returns TaskChanges for task calendars.
type TaskWriter interface {
	CreateTask(ctx context.Context, cal Calendar, t *Task) (*Task, error)
	UpdateTask(ctx context.Context, cal Calendar, t *Task) (*Task, error)
	DeleteTask(ctx context.Context, cal Calendar, t Task) error
}

// Notice codes are soft, non-fatal sync warnings a provider can surface when it
// partially degrades — e.g. a Google account whose Tasks API is disabled still
// syncs calendars. The GUI maps these to a buried, actionable hint per account
// kind; an account that fails entirely uses the hard ErrReauthRequired path.
const (
	NoticeTasksUnavailable     = "tasks_unavailable"
	NoticeCalendarsUnavailable = "calendars_unavailable"
	// Apple stopped serving upgraded Reminders over CalDAV (iOS 13+); iCloud
	// answers with placeholder items pointing at support.apple.com/HT210220.
	NoticeICloudRemindersUpgraded = "icloud_reminders_upgraded"
	NoticeItemsSkipped            = "items_skipped"
	NoticeCalendarSyncFailed      = "calendar_sync_failed"
)

// NoticeReporter is implemented by providers that may partially degrade during a
// sync. The engine reads the accumulated codes once the pass completes and
// persists them as the account's sync notice (clearing them when none remain).
type NoticeReporter interface {
	Notices() []string
}

// OccurrenceRebaser is implemented by providers that can move every exception
// in a series by delta so the overrides keep matching the shifted master. The
// returned map is keyed by the old override UID and carries the new one.
type OccurrenceRebaser interface {
	RebaseEventOccurrences(ctx context.Context, cal Calendar, master Event, delta time.Duration) (map[string]string, error)
}

// Responder is implemented by providers that can submit the current user's RSVP
// response to an event independently of a full event update. response is one of
// the canonical Response* values. Providers that do not implement it fall back
// to a full UpdateEvent with the self attendee's status changed.
type Responder interface {
	RespondToEvent(ctx context.Context, cal Calendar, ev *Event, response string) (*Event, error)
}

// Importer stores a private copy of an event organized elsewhere without
// making the user its organizer; providers lacking it get the copy stripped of
// organizer and attendees.
type Importer interface {
	ImportEvent(ctx context.Context, cal Calendar, ev *Event) (*Event, error)
}

type ProviderFactory interface {
	Kind() AccountKind
	Build(ctx context.Context, account Account, secrets SecretStore) (Provider, error)
}

type SecretStore interface {
	Get(ctx context.Context, accountID, key string) ([]byte, error)
	Set(ctx context.Context, accountID, key string, value []byte) error
	Delete(ctx context.Context, accountID, key string) error
}
