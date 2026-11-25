package local_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/local"
)

const multiEventICS = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//dankcal-test//EN
BEGIN:VEVENT
UID:multi-1@dankcal
DTSTAMP:20260506T120000Z
DTSTART:20260507T140000Z
DTEND:20260507T150000Z
SUMMARY:First
END:VEVENT
BEGIN:VEVENT
UID:multi-2@dankcal
DTSTAMP:20260506T120000Z
DTSTART:20260508T140000Z
DTEND:20260508T150000Z
SUMMARY:Second
END:VEVENT
END:VCALENDAR
`

func newTestEvent(summary string) *calendar.Event {
	return &calendar.Event{
		Summary:     summary,
		Description: "a description",
		Location:    "somewhere",
		Status:      calendar.EventConfirmed,
		Start:       time.Date(2026, 6, 1, 9, 0, 0, 0, time.UTC),
		End:         time.Date(2026, 6, 1, 10, 0, 0, 0, time.UTC),
	}
}

func findEvent(t *testing.T, events []calendar.Event, uid string) calendar.Event {
	t.Helper()
	for _, ev := range events {
		if ev.UID == uid {
			return ev
		}
	}
	t.Fatalf("event %q not found", uid)
	return calendar.Event{}
}

func TestDirCalendarCreateUpdateDelete(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, os.Mkdir(filepath.Join(root, "work"), 0o755))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "dir:work"}

	created, err := provider.CreateEvent(ctx, cal, newTestEvent("Standup"))
	require.NoError(t, err)
	require.NotEmpty(t, created.UID)
	require.Equal(t, created.UID, created.RemoteID)
	require.FileExists(t, filepath.Join(root, "work", created.UID+".ics"))

	dup := newTestEvent("Dup")
	dup.UID = created.UID
	_, err = provider.CreateEvent(ctx, cal, dup)
	require.ErrorContains(t, err, "already exists")

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 1)
	require.Equal(t, "Standup", events[0].Summary)
	require.Equal(t, "a description", events[0].Description)
	require.Equal(t, calendar.EventConfirmed, events[0].Status)
	require.False(t, events[0].AllDay)

	updated := newTestEvent("Standup (moved)")
	updated.UID = created.UID
	updated.Status = calendar.EventTentative
	_, err = provider.UpdateEvent(ctx, cal, updated)
	require.NoError(t, err)

	events, err = provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 1)
	require.Equal(t, "Standup (moved)", events[0].Summary)
	require.Equal(t, calendar.EventTentative, events[0].Status)

	require.NoError(t, provider.DeleteEvent(ctx, cal, *created))
	require.NoFileExists(t, filepath.Join(root, "work", created.UID+".ics"))

	events, err = provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Empty(t, events)

	require.ErrorContains(t, provider.DeleteEvent(ctx, cal, *created), "event not found")
}

func TestDirCalendarSanitizesUIDFilename(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, os.Mkdir(filepath.Join(root, "work"), 0o755))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "dir:work"}

	ev := newTestEvent("Weird UID")
	ev.UID = "a/b:c*d@dankcal"
	created, err := provider.CreateEvent(ctx, cal, ev)
	require.NoError(t, err)
	require.Equal(t, "a/b:c*d@dankcal", created.UID)
	require.FileExists(t, filepath.Join(root, "work", "a_b_c_d@dankcal.ics"))

	updated := newTestEvent("Renamed")
	updated.UID = created.UID
	_, err = provider.UpdateEvent(ctx, cal, updated)
	require.NoError(t, err)

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 1)
	require.Equal(t, "Renamed", events[0].Summary)

	require.NoError(t, provider.DeleteEvent(ctx, cal, *created))
	require.NoFileExists(t, filepath.Join(root, "work", "a_b_c_d@dankcal.ics"))
}

func TestDirCalendarDeleteFromMultiEventFile(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "shared")
	require.NoError(t, os.Mkdir(dir, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, "imported.ics"), []byte(multiEventICS), 0o600))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "dir:shared"}

	require.NoError(t, provider.DeleteEvent(ctx, cal, calendar.Event{UID: "multi-1@dankcal"}))
	require.FileExists(t, filepath.Join(dir, "imported.ics"))

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 1)
	require.Equal(t, "multi-2@dankcal", events[0].UID)

	require.NoError(t, provider.DeleteEvent(ctx, cal, calendar.Event{UID: "multi-2@dankcal"}))
	require.NoFileExists(t, filepath.Join(dir, "imported.ics"))
}

func TestFileCalendarCreateUpdateDelete(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "personal.ics")
	require.NoError(t, os.WriteFile(path, []byte(sampleICS), 0o600))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "file:personal.ics"}

	ev := newTestEvent("Dentist")
	ev.UID = "demo-2@dankcal"
	created, err := provider.CreateEvent(ctx, cal, ev)
	require.NoError(t, err)
	require.Equal(t, "demo-2@dankcal", created.UID)
	require.Equal(t, "demo-2@dankcal", created.RemoteID)

	_, err = provider.CreateEvent(ctx, cal, ev)
	require.ErrorContains(t, err, "already exists")

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 2)
	require.Equal(t, "Lunch with Alice", findEvent(t, events, "demo-1@dankcal").Summary)
	require.Equal(t, "Dentist", findEvent(t, events, "demo-2@dankcal").Summary)

	updated := newTestEvent("Dentist (rescheduled)")
	updated.UID = "demo-2@dankcal"
	_, err = provider.UpdateEvent(ctx, cal, updated)
	require.NoError(t, err)

	events, err = provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 2)
	require.Equal(t, "Dentist (rescheduled)", findEvent(t, events, "demo-2@dankcal").Summary)
	require.Equal(t, "Lunch with Alice", findEvent(t, events, "demo-1@dankcal").Summary)

	missing := newTestEvent("Ghost")
	missing.UID = "nope@dankcal"
	_, err = provider.UpdateEvent(ctx, cal, missing)
	require.ErrorContains(t, err, "event not found")

	require.NoError(t, provider.DeleteEvent(ctx, cal, calendar.Event{UID: "demo-2@dankcal"}))
	require.NoError(t, provider.DeleteEvent(ctx, cal, calendar.Event{UID: "demo-1@dankcal"}))
	require.FileExists(t, path)

	events, err = provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Empty(t, events)

	require.ErrorContains(t, provider.DeleteEvent(ctx, cal, calendar.Event{UID: "demo-1@dankcal"}), "event not found")
}

func TestAllDayAndRecurrenceRoundtrip(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, os.Mkdir(filepath.Join(root, "work"), 0o755))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "dir:work"}

	ev := newTestEvent("Vacation")
	ev.AllDay = true
	ev.Start = time.Date(2026, 7, 1, 0, 0, 0, 0, time.UTC)
	ev.End = time.Date(2026, 7, 8, 0, 0, 0, 0, time.UTC)
	ev.Recurrence = &calendar.Recurrence{RRule: []string{"FREQ=YEARLY"}}

	created, err := provider.CreateEvent(ctx, cal, ev)
	require.NoError(t, err)

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 1)

	got := findEvent(t, events, created.UID)
	require.True(t, got.AllDay)
	require.NotNil(t, got.Recurrence)
	require.Equal(t, []string{"FREQ=YEARLY"}, got.Recurrence.RRule)
	require.Equal(t, "2026-07-01", got.Start.Format("2006-01-02"))
	require.Equal(t, "2026-07-08", got.End.Format("2006-01-02"))
}

func TestDirCalendarWritesOccurrenceOverride(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, os.Mkdir(filepath.Join(root, "work"), 0o755))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "dir:work"}

	master := newTestEvent("Weekly")
	master.UID = "weekly@dankcal"
	master.Recurrence = &calendar.Recurrence{RRule: []string{"FREQ=WEEKLY"}}
	_, err = provider.CreateEvent(ctx, cal, master)
	require.NoError(t, err)

	occurrence := master.Start.AddDate(0, 0, 7)
	override := newTestEvent("Weekly (moved)")
	override.UID = "weekly@dankcal/20260608T090000Z"
	override.RecurringID = "weekly@dankcal"
	override.OriginalStart = occurrence
	override.Start = occurrence.Add(2 * time.Hour)
	override.End = occurrence.Add(3 * time.Hour)

	updated, err := provider.UpdateEvent(ctx, cal, override)
	require.NoError(t, err)
	require.Equal(t, "weekly@dankcal/20260608T090000Z", updated.UID)
	require.Equal(t, "weekly@dankcal", updated.RecurringID)

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 2)

	got := findEvent(t, events, "weekly@dankcal/20260608T090000Z")
	require.Equal(t, "Weekly (moved)", got.Summary)
	require.Equal(t, "weekly@dankcal", got.RecurringID)
	require.True(t, got.OriginalStart.Equal(occurrence))
	require.True(t, got.Start.Equal(override.Start))

	series := findEvent(t, events, "weekly@dankcal")
	require.NotNil(t, series.Recurrence)
	require.Equal(t, []string{"FREQ=WEEKLY"}, series.Recurrence.RRule)

	override.Summary = "Weekly (moved again)"
	_, err = provider.UpdateEvent(ctx, cal, override)
	require.NoError(t, err)

	events, err = provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 2)
	require.Equal(t, "Weekly (moved again)", findEvent(t, events, override.UID).Summary)
}

func TestDirCalendarMasterUpdatePreservesOverrides(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, os.Mkdir(filepath.Join(root, "work"), 0o755))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "dir:work"}

	master := newTestEvent("Weekly")
	master.UID = "weekly@dankcal"
	master.Recurrence = &calendar.Recurrence{RRule: []string{"FREQ=WEEKLY"}}
	_, err = provider.CreateEvent(ctx, cal, master)
	require.NoError(t, err)

	occurrence := master.Start.AddDate(0, 0, 7)
	override := newTestEvent("Weekly (moved)")
	override.UID = "weekly@dankcal/20260608T090000Z"
	override.RecurringID = "weekly@dankcal"
	override.OriginalStart = occurrence
	override.Start = occurrence.Add(2 * time.Hour)
	override.End = occurrence.Add(3 * time.Hour)
	_, err = provider.UpdateEvent(ctx, cal, override)
	require.NoError(t, err)

	renamed := newTestEvent("Standup")
	renamed.UID = master.UID
	renamed.Recurrence = master.Recurrence
	_, err = provider.UpdateEvent(ctx, cal, renamed)
	require.NoError(t, err)

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 2)
	require.Equal(t, "Standup", findEvent(t, events, master.UID).Summary)

	kept := findEvent(t, events, override.UID)
	require.Equal(t, "Weekly (moved)", kept.Summary)
	require.Equal(t, "weekly@dankcal", kept.RecurringID)
	require.True(t, kept.OriginalStart.Equal(occurrence))
	require.True(t, kept.Start.Equal(override.Start))
}

func TestDirCalendarRebasesOccurrenceOverride(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, os.Mkdir(filepath.Join(root, "work"), 0o755))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "dir:work"}

	master := newTestEvent("Weekly")
	master.UID = "weekly@dankcal"
	master.Recurrence = &calendar.Recurrence{RRule: []string{"FREQ=WEEKLY"}}
	_, err = provider.CreateEvent(ctx, cal, master)
	require.NoError(t, err)

	occurrence := master.Start.AddDate(0, 0, 7)
	override := newTestEvent("Weekly (moved)")
	override.UID = "weekly@dankcal/20260608T090000Z"
	override.RecurringID = "weekly@dankcal"
	override.OriginalStart = occurrence
	override.Start = occurrence.Add(2 * time.Hour)
	override.End = occurrence.Add(3 * time.Hour)
	_, err = provider.UpdateEvent(ctx, cal, override)
	require.NoError(t, err)

	mapping, err := provider.RebaseEventOccurrences(ctx, cal, *master, 6*time.Hour)
	require.NoError(t, err)
	require.Equal(t, map[string]string{
		"weekly@dankcal/20260608T090000Z": "weekly@dankcal/20260608T150000Z",
	}, mapping)

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 2)

	rebased := findEvent(t, events, "weekly@dankcal/20260608T150000Z")
	require.Equal(t, "Weekly (moved)", rebased.Summary)
	require.True(t, rebased.OriginalStart.Equal(occurrence.Add(6*time.Hour)))
	require.True(t, rebased.Start.Equal(override.Start))
}

func TestDirCalendarRemovesOccurrenceOverride(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, os.Mkdir(filepath.Join(root, "work"), 0o755))

	provider, err := local.New(calendar.Account{ID: "t"}, root)
	require.NoError(t, err)

	ctx := context.Background()
	cal := calendar.Calendar{ID: "cal-1", RemoteID: "dir:work"}

	master := newTestEvent("Weekly")
	master.UID = "weekly@dankcal"
	master.Recurrence = &calendar.Recurrence{RRule: []string{"FREQ=WEEKLY"}}
	_, err = provider.CreateEvent(ctx, cal, master)
	require.NoError(t, err)

	occurrence := master.Start.AddDate(0, 0, 7)
	override := newTestEvent("Weekly (moved)")
	override.UID = "weekly@dankcal/20260608T090000Z"
	override.RecurringID = "weekly@dankcal"
	override.OriginalStart = occurrence
	override.Start = occurrence.Add(2 * time.Hour)
	override.End = occurrence.Add(3 * time.Hour)

	updated, err := provider.UpdateEvent(ctx, cal, override)
	require.NoError(t, err)

	require.NoError(t, provider.RemoveEventOccurrence(ctx, cal, *updated))

	events, err := provider.ListEvents(ctx, cal, calendar.ListEventsOptions{})
	require.NoError(t, err)
	require.Len(t, events, 1)
	require.Equal(t, "weekly@dankcal", events[0].UID)
	require.NotNil(t, events[0].Recurrence)
}
