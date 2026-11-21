package google

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/api/calendar/v3"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

// Google rejects recurring events whose start/end lack an explicit time zone
// ("Missing time zone definition for start time").
func TestToGoogleEventRecurringSetsTimeZone(t *testing.T) {
	ev := &cal.Event{
		Summary:    "standup",
		Start:      time.Date(2026, 7, 10, 16, 0, 0, 0, time.UTC),
		End:        time.Date(2026, 7, 10, 16, 30, 0, 0, time.UTC),
		Recurrence: &cal.Recurrence{RRule: []string{"FREQ=WEEKLY;BYDAY=FR"}},
	}

	out := toGoogleEvent(ev)
	require.NotNil(t, out.Start)
	require.NotNil(t, out.End)
	assert.Equal(t, "UTC", out.Start.TimeZone)
	assert.Equal(t, "UTC", out.End.TimeZone)
	assert.Equal(t, []string{"RRULE:FREQ=WEEKLY;BYDAY=FR"}, out.Recurrence)
}

func TestToGoogleEventNonRecurringLeavesTimeZoneEmpty(t *testing.T) {
	ev := &cal.Event{
		Summary: "one-off",
		Start:   time.Date(2026, 7, 10, 16, 0, 0, 0, time.UTC),
		End:     time.Date(2026, 7, 10, 16, 30, 0, 0, time.UTC),
	}

	out := toGoogleEvent(ev)
	require.NotNil(t, out.Start)
	assert.Empty(t, out.Start.TimeZone)
	assert.Empty(t, out.Recurrence)
}

// Google echoes exclusions in the event's zone (EXDATE;TZID=...) while our
// expander reads bare values in the series zone; parsing must pin them to UTC.
func TestFromGoogleRecurrenceNormalizesZonedDates(t *testing.T) {
	rec := fromGoogleRecurrence([]string{
		"RRULE:FREQ=DAILY",
		"EXDATE;TZID=America/New_York:20260728T090000",
		"RDATE;TZID=America/New_York:20260801T090000,20260802T090000",
		"EXDATE:20260730T130000Z",
	})

	require.NotNil(t, rec)
	assert.Equal(t, []string{"FREQ=DAILY"}, rec.RRule)
	assert.Equal(t, []string{"20260728T130000Z", "20260730T130000Z"}, rec.ExDate)
	assert.Equal(t, []string{"20260801T130000Z,20260802T130000Z"}, rec.RDate)
}

func TestFromGoogleRecurrenceKeepsFloatingAndDateValues(t *testing.T) {
	rec := fromGoogleRecurrence([]string{
		"RRULE:FREQ=DAILY",
		"EXDATE:20260728T090000",
		"EXDATE;VALUE=DATE;TZID=America/New_York:20260729",
	})

	require.NotNil(t, rec)
	assert.Equal(t, []string{"20260728T090000", "20260729"}, rec.ExDate)
}

func TestToGoogleEventRecurringExistingZoneKept(t *testing.T) {
	ev := &cal.Event{
		Summary:       "standup",
		Start:         time.Date(2026, 7, 10, 16, 0, 0, 0, time.UTC),
		End:           time.Date(2026, 7, 10, 16, 30, 0, 0, time.UTC),
		StartTimeZone: "America/New_York",
		EndTimeZone:   "America/New_York",
		Recurrence:    &cal.Recurrence{RRule: []string{"FREQ=DAILY"}},
	}

	out := toGoogleEvent(ev)
	assert.Equal(t, "America/New_York", out.Start.TimeZone)
	assert.Equal(t, "America/New_York", out.End.TimeZone)
}

// The API requires minutes on every override, but the SDK JSON-omits the zero
// value ("at start") unless forced, yielding "Missing override reminder
// minutes." 400s.
func TestToGoogleEventReminderAtStartSerializesMinutes(t *testing.T) {
	ev := &cal.Event{
		Summary:   "standup",
		Start:     time.Date(2026, 7, 10, 16, 0, 0, 0, time.UTC),
		End:       time.Date(2026, 7, 10, 16, 30, 0, 0, time.UTC),
		Reminders: []cal.Reminder{{Method: "popup", Minutes: 0}},
	}

	out := toGoogleEvent(ev)
	require.NotNil(t, out.Reminders)
	require.Len(t, out.Reminders.Overrides, 1)

	data, err := out.Reminders.Overrides[0].MarshalJSON()
	require.NoError(t, err)
	assert.Contains(t, string(data), `"minutes":0`)
}

// Third-party integrations create all-day events whose exclusive end date
// equals the start date, or omit the end entirely; Google shows those as
// one-day events (#77).
func TestFromGoogleEventNormalizesDegenerateAllDayEnd(t *testing.T) {
	c := cal.Calendar{ID: "cal-1"}
	cases := []struct {
		name string
		item *calendar.Event
		end  time.Time
	}{
		{
			name: "end equals start",
			item: &calendar.Event{
				Id:    "e1",
				Start: &calendar.EventDateTime{Date: "2026-08-16"},
				End:   &calendar.EventDateTime{Date: "2026-08-16"},
			},
			end: time.Date(2026, 8, 17, 0, 0, 0, 0, time.UTC),
		},
		{
			name: "end missing",
			item: &calendar.Event{
				Id:    "e2",
				Start: &calendar.EventDateTime{Date: "2026-08-16"},
			},
			end: time.Date(2026, 8, 17, 0, 0, 0, 0, time.UTC),
		},
		{
			name: "well-formed exclusive end kept",
			item: &calendar.Event{
				Id:    "e3",
				Start: &calendar.EventDateTime{Date: "2026-08-16"},
				End:   &calendar.EventDateTime{Date: "2026-08-18"},
			},
			end: time.Date(2026, 8, 18, 0, 0, 0, 0, time.UTC),
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ev := fromGoogleEvent(c, tc.item)
			require.True(t, ev.AllDay)
			assert.Equal(t, tc.end, ev.End)
		})
	}
}

// Cancelled recurring instances arrive without start or end; their zero times
// mark them for deletion and must stay untouched.
func TestFromGoogleEventKeepsCancelledInstanceTimesZero(t *testing.T) {
	ev := fromGoogleEvent(cal.Calendar{ID: "cal-1"}, &calendar.Event{
		Id:     "e4",
		Status: "cancelled",
	})
	assert.True(t, ev.Start.IsZero())
	assert.True(t, ev.End.IsZero())
}
