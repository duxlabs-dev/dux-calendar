package ipc

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/duxlabs-dev/dux-calendar/core/ent/account"
	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/mocks"
	"github.com/duxlabs-dev/dux-calendar/core/repo"
)

func TestEventUpdateOccurrenceScopeWritesOverride(t *testing.T) {
	f := newIcsFixture(t, account.KindLocal, false)
	ctx := context.Background()

	masterStart := time.Date(2026, 6, 1, 9, 0, 0, 0, time.UTC)
	master, err := f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: "cal",
		UID:        "weekly",
		Summary:    "Weekly",
		Start:      masterStart,
		End:        masterStart.Add(time.Hour),
		Recurrence: map[string]any{"rrule": []string{"FREQ=WEEKLY"}},
	})
	require.NoError(t, err)

	occurrence := masterStart.AddDate(0, 0, 7)
	provider := mocks.NewMockProvider(t)
	provider.EXPECT().Close().Return(nil)
	provider.EXPECT().Kind().Return(calendar.AccountLocal)

	var updated calendar.Event
	provider.EXPECT().UpdateEvent(mock.Anything, mock.Anything, mock.Anything).
		RunAndReturn(func(_ context.Context, _ calendar.Calendar, ev *calendar.Event) (*calendar.Event, error) {
			updated = *ev
			return ev, nil
		})
	f.register(t, calendar.AccountLocal, provider)

	resultOf(t, routeAndRead(t, Request{ID: 1, Method: "events.update", Params: map[string]any{
		"id":              master.ID,
		"scope":           "occurrence",
		"summary":         "Weekly (moved)",
		"start":           occurrence.Add(2 * time.Hour).Format(time.RFC3339),
		"end":             occurrence.Add(3 * time.Hour).Format(time.RFC3339),
		"allDay":          false,
		"occurrenceStart": occurrence.Format(time.RFC3339),
	}}, f.deps))

	assert.Equal(t, "Weekly (moved)", updated.Summary)
	assert.Equal(t, "weekly", updated.RecurringID)
	assert.True(t, updated.OriginalStart.Equal(occurrence))
	assert.Equal(t, "weekly/20260608T090000Z", updated.UID)
	assert.Nil(t, updated.Recurrence)
	assert.True(t, updated.Start.Equal(occurrence.Add(2*time.Hour)))
	assert.True(t, updated.End.Equal(occurrence.Add(3*time.Hour)))

	stored, err := f.repo.GetEventByUID(ctx, updated.UID, "cal")
	require.NoError(t, err)
	assert.Equal(t, "weekly", stored.RecurringID)
	require.NotNil(t, stored.OriginalStart)
	assert.True(t, stored.OriginalStart.Equal(occurrence))
}

func TestEventUpdateSeriesRebasesOverrideSlots(t *testing.T) {
	f := newIcsFixture(t, account.KindLocal, false)
	ctx := context.Background()

	masterStart := time.Date(2026, 6, 1, 9, 0, 0, 0, time.UTC)
	master, err := f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: "cal",
		UID:        "weekly",
		Summary:    "Weekly",
		Start:      masterStart,
		End:        masterStart.Add(time.Hour),
		Recurrence: map[string]any{"rrule": []string{"FREQ=WEEKLY"}},
	})
	require.NoError(t, err)

	occurrence := masterStart.AddDate(0, 0, 7)
	moved := occurrence.Add(5 * time.Hour)
	override, err := f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID:    "cal",
		UID:           "weekly/20260608T090000Z",
		Summary:       "Weekly (moved)",
		Start:         moved,
		End:           moved.Add(time.Hour),
		RecurringID:   "weekly",
		OriginalStart: occurrence,
	})
	require.NoError(t, err)

	provider := mocks.NewMockProvider(t)
	provider.EXPECT().Close().Return(nil)
	provider.EXPECT().UpdateEvent(mock.Anything, mock.Anything, mock.Anything).
		RunAndReturn(func(_ context.Context, _ calendar.Calendar, ev *calendar.Event) (*calendar.Event, error) {
			return ev, nil
		})
	f.register(t, calendar.AccountLocal, provider)

	resultOf(t, routeAndRead(t, Request{ID: 1, Method: "events.update", Params: map[string]any{
		"id":      master.ID,
		"scope":   "series",
		"summary": "Weekly (new time)",
		"start":   masterStart.Add(6 * time.Hour).Format(time.RFC3339),
		"end":     masterStart.Add(7 * time.Hour).Format(time.RFC3339),
		"allDay":  false,
	}}, f.deps))

	stored, err := f.repo.GetEvent(ctx, override.ID)
	require.NoError(t, err)
	require.NotNil(t, stored.OriginalStart)
	assert.True(t, stored.OriginalStart.Equal(occurrence.Add(6*time.Hour)))
	assert.True(t, stored.Start.Equal(moved))

	from := masterStart.Add(-24 * time.Hour)
	to := masterStart.AddDate(0, 0, 22)
	events, _, err := f.repo.ListEvents(ctx, repo.ListEventsParams{
		Filter: repo.EventFilter{From: &from, To: &to, IncludeRecurring: true},
	})
	require.NoError(t, err)
	require.Len(t, events, 4)

	var movedCount int
	for _, ev := range events {
		if ev.Summary == "Weekly (moved)" {
			movedCount++
			assert.Equal(t, 14, ev.Start.Hour())
			continue
		}
		require.Equal(t, "Weekly (new time)", ev.Summary)
		assert.Equal(t, 15, ev.Start.Hour())
	}
	assert.Equal(t, 1, movedCount)
}

func TestEventUpdateSeriesCollapsesEditedException(t *testing.T) {
	f := newIcsFixture(t, account.KindLocal, false)
	ctx := context.Background()

	masterStart := time.Date(2026, 6, 1, 9, 0, 0, 0, time.UTC)
	_, err := f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: "cal",
		UID:        "weekly",
		Summary:    "Weekly",
		Start:      masterStart,
		End:        masterStart.Add(time.Hour),
		Recurrence: map[string]any{"rrule": []string{"FREQ=WEEKLY"}},
	})
	require.NoError(t, err)

	occurrence := masterStart.AddDate(0, 0, 7)
	moved := occurrence.Add(5 * time.Hour)
	override, err := f.repo.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID:    "cal",
		UID:           "weekly/20260608T090000Z",
		Summary:       "Weekly (moved)",
		Start:         moved,
		End:           moved.Add(time.Hour),
		RecurringID:   "weekly",
		OriginalStart: occurrence,
	})
	require.NoError(t, err)

	provider := mocks.NewMockProvider(t)
	provider.EXPECT().Close().Return(nil)
	provider.EXPECT().UpdateEvent(mock.Anything, mock.Anything, mock.Anything).
		RunAndReturn(func(_ context.Context, _ calendar.Calendar, ev *calendar.Event) (*calendar.Event, error) {
			return ev, nil
		})
	f.register(t, calendar.AccountLocal, provider)

	resultOf(t, routeAndRead(t, Request{ID: 1, Method: "events.update", Params: map[string]any{
		"id":      override.ID,
		"scope":   "series",
		"summary": "Weekly (new time)",
		"start":   occurrence.Add(6 * time.Hour).Format(time.RFC3339),
		"end":     occurrence.Add(7 * time.Hour).Format(time.RFC3339),
		"allDay":  false,
	}}, f.deps))

	_, err = f.repo.GetEvent(ctx, override.ID)
	require.Error(t, err)

	from := masterStart.Add(-24 * time.Hour)
	to := masterStart.AddDate(0, 0, 15)
	events, _, err := f.repo.ListEvents(ctx, repo.ListEventsParams{
		Filter: repo.EventFilter{From: &from, To: &to, IncludeRecurring: true},
	})
	require.NoError(t, err)
	require.Len(t, events, 3)
	for _, ev := range events {
		require.Equal(t, "Weekly (new time)", ev.Summary)
		assert.Equal(t, 15, ev.Start.Hour())
	}
}
