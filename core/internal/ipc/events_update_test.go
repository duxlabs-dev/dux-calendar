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
