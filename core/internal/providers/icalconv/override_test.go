package icalconv

import (
	"bytes"
	"testing"
	"time"

	ical "github.com/emersion/go-ical"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

func overrideEvent() *cal.Event {
	occurrence := time.Date(2026, 8, 17, 9, 0, 0, 0, time.UTC)
	return &cal.Event{
		UID:           "standup/20260817T090000Z",
		RecurringID:   "standup",
		OriginalStart: occurrence,
		Summary:       "Standup (moved)",
		Description:   "moved to the afternoon",
		Start:         occurrence.Add(5 * time.Hour),
		End:           occurrence.Add(5*time.Hour + 30*time.Minute),
		Attendees: []cal.Attendee{
			{Email: "me@example.com", Status: "accepted"},
			{Email: "peer@example.com"},
		},
		Reminders: []cal.Reminder{{Method: "popup", Minutes: 10}},
	}
}

func TestApplyEventOverrideCreatesException(t *testing.T) {
	doc := participationDoc(t, recurringInviteICS)
	ev := overrideEvent()

	rid, err := ApplyEventOverride(doc, ev)
	require.NoError(t, err)
	assert.Equal(t, "20260817T090000Z", rid)
	require.Len(t, doc.Events(), 2)

	var buf bytes.Buffer
	require.NoError(t, ical.NewEncoder(&buf).Encode(doc))
	reparsed := participationDoc(t, buf.String())

	tz := NewTZResolver(reparsed, "")
	var master, exception cal.Event
	for _, comp := range reparsed.Events() {
		parsed, ok := EventFromComponent("cal", comp.Component, tz)
		require.True(t, ok)
		if parsed.RecurringID == "" {
			master = parsed
		} else {
			exception = parsed
		}
	}

	assert.Equal(t, "Standup", master.Summary)
	require.NotNil(t, master.Recurrence)
	assert.Equal(t, []string{"FREQ=WEEKLY"}, master.Recurrence.RRule)

	assert.Equal(t, "Standup (moved)", exception.Summary)
	assert.Equal(t, "moved to the afternoon", exception.Description)
	assert.Equal(t, "standup/20260817T090000Z", exception.UID)
	assert.Equal(t, "standup", exception.RecurringID)
	assert.True(t, exception.OriginalStart.Equal(ev.OriginalStart))
	assert.True(t, exception.Start.Equal(ev.Start))
	assert.True(t, exception.End.Equal(ev.End))
	assert.Nil(t, exception.Recurrence)
	assert.Len(t, exception.Attendees, 2)
	assert.Equal(t, []cal.Reminder{{Method: "popup", Minutes: 10}}, exception.Reminders)
}

func TestApplyEventOverrideUpdatesExistingException(t *testing.T) {
	doc := participationDoc(t, recurringInviteICS)
	ev := overrideEvent()

	_, err := ApplyEventOverride(doc, ev)
	require.NoError(t, err)

	ev.Summary = "Standup (moved again)"
	ev.Start = ev.OriginalStart.Add(-2 * time.Hour)
	ev.End = ev.Start.Add(time.Hour)
	_, err = ApplyEventOverride(doc, ev)
	require.NoError(t, err)
	require.Len(t, doc.Events(), 2)

	tz := NewTZResolver(doc, "")
	var exceptions int
	for _, comp := range doc.Events() {
		parsed, ok := EventFromComponent("cal", comp.Component, tz)
		require.True(t, ok)
		if parsed.RecurringID == "" {
			continue
		}
		exceptions++
		assert.Equal(t, "Standup (moved again)", parsed.Summary)
		assert.True(t, parsed.Start.Equal(ev.Start))
		assert.True(t, parsed.End.Equal(ev.End))
	}
	assert.Equal(t, 1, exceptions)
}

func TestApplyEventOverrideRequiresOccurrenceStart(t *testing.T) {
	doc := participationDoc(t, recurringInviteICS)
	_, err := ApplyEventOverride(doc, &cal.Event{RecurringID: "standup"})
	assert.ErrorContains(t, err, "occurrence start")
}
