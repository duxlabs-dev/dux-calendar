package caldav

import (
	"strings"
	"testing"
	"time"

	ical "github.com/emersion/go-ical"
	"github.com/emersion/go-webdav/caldav"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

func decodeICS(t *testing.T, ics string) *ical.Calendar {
	t.Helper()
	parsed, err := ical.NewDecoder(strings.NewReader(ics)).Decode()
	require.NoError(t, err)
	return parsed
}

func wrapVEvent(body string) string {
	return "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//test//EN\nBEGIN:VEVENT\n" +
		body + "END:VEVENT\nEND:VCALENDAR\n"
}

func TestEventsFromObjectParsesCoreFields(t *testing.T) {
	ics := wrapVEvent(`UID:meet-1
DTSTAMP:20260101T000000Z
DTSTART:20260507T140000Z
DTEND:20260507T150000Z
SUMMARY:Planning
DESCRIPTION:Quarterly planning
LOCATION:Room 4
STATUS:TENTATIVE
URL:https://example.com/meet
ORGANIZER;CN=Alice:mailto:alice@example.com
ATTENDEE;CN=Bob;ROLE=OPT-PARTICIPANT;PARTSTAT=ACCEPTED:mailto:bob@example.com
`)

	obj := caldav.CalendarObject{Path: "/cal/meet-1.ics", ETag: `"v1"`, Data: decodeICS(t, ics)}
	events := eventsFromObject(cal.Calendar{ID: "cal-1"}, obj)
	require.Len(t, events, 1)

	ev := events[0]
	assert.Equal(t, "cal-1", ev.CalendarID)
	assert.Equal(t, "meet-1", ev.UID)
	assert.Equal(t, "/cal/meet-1.ics", ev.RemoteID)
	assert.Equal(t, `"v1"`, ev.Etag)
	assert.Equal(t, "Planning", ev.Summary)
	assert.Equal(t, "Quarterly planning", ev.Description)
	assert.Equal(t, "Room 4", ev.Location)
	assert.Equal(t, "https://example.com/meet", ev.URL)
	assert.Equal(t, cal.EventTentative, ev.Status)
	assert.Equal(t, time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC), ev.Start.UTC())
	assert.Equal(t, time.Date(2026, 5, 7, 15, 0, 0, 0, time.UTC), ev.End.UTC())
	assert.False(t, ev.AllDay)

	require.NotNil(t, ev.Organizer)
	assert.Equal(t, "alice@example.com", ev.Organizer.Email)
	assert.Equal(t, "Alice", ev.Organizer.DisplayName)
	assert.True(t, ev.Organizer.Organizer)

	require.Len(t, ev.Attendees, 1)
	assert.Equal(t, "bob@example.com", ev.Attendees[0].Email)
	assert.Equal(t, "Bob", ev.Attendees[0].DisplayName)
	assert.Equal(t, "accepted", ev.Attendees[0].Status)
	assert.True(t, ev.Attendees[0].Optional)
}

func TestEventsFromObjectSkipsMissingUID(t *testing.T) {
	ics := wrapVEvent(`DTSTAMP:20260101T000000Z
DTSTART:20260507T140000Z
SUMMARY:No UID
`)
	events := eventsFromObject(cal.Calendar{}, caldav.CalendarObject{Data: decodeICS(t, ics)})
	assert.Empty(t, events)
}

func TestEventsFromObjectRecurrenceOverride(t *testing.T) {
	ics := wrapVEvent(`UID:series-1
DTSTAMP:20260101T000000Z
RECURRENCE-ID:20260508T140000Z
DTSTART:20260508T160000Z
DTEND:20260508T170000Z
SUMMARY:Moved instance
`)
	events := eventsFromObject(cal.Calendar{}, caldav.CalendarObject{Data: decodeICS(t, ics)})
	require.Len(t, events, 1)

	ev := events[0]
	assert.Equal(t, "series-1/20260508T140000Z", ev.UID)
	assert.Equal(t, "series-1", ev.RecurringID)
	assert.Equal(t, time.Date(2026, 5, 8, 14, 0, 0, 0, time.UTC), ev.OriginalStart.UTC())
}

func TestEventsFromObjectDurationEnd(t *testing.T) {
	ics := wrapVEvent(`UID:dur-1
DTSTAMP:20260101T000000Z
DTSTART:20260507T140000Z
DURATION:PT45M
SUMMARY:Short one
`)
	events := eventsFromObject(cal.Calendar{}, caldav.CalendarObject{Data: decodeICS(t, ics)})
	require.Len(t, events, 1)
	assert.Equal(t, events[0].Start.Add(45*time.Minute), events[0].End)
}

func TestEventsFromObjectAllDayDefaultsToOneDay(t *testing.T) {
	ics := wrapVEvent(`UID:day-1
DTSTAMP:20260101T000000Z
DTSTART;VALUE=DATE:20260507
SUMMARY:Holiday
`)
	events := eventsFromObject(cal.Calendar{}, caldav.CalendarObject{Data: decodeICS(t, ics)})
	require.Len(t, events, 1)
	assert.True(t, events[0].AllDay)
	assert.Equal(t, events[0].Start.Add(24*time.Hour), events[0].End)
}

func TestEventsFromObjectRecurrenceProps(t *testing.T) {
	ics := wrapVEvent(`UID:rec-1
DTSTAMP:20260101T000000Z
DTSTART:20260507T140000Z
DTEND:20260507T150000Z
RRULE:FREQ=WEEKLY;BYDAY=TH
EXDATE:20260514T140000Z
SUMMARY:Weekly
`)
	events := eventsFromObject(cal.Calendar{}, caldav.CalendarObject{Data: decodeICS(t, ics)})
	require.Len(t, events, 1)

	rec := events[0].Recurrence
	require.NotNil(t, rec)
	assert.Equal(t, []string{"FREQ=WEEKLY;BYDAY=TH"}, rec.RRule)
	assert.Equal(t, []string{"20260514T140000Z"}, rec.ExDate)
	assert.Empty(t, rec.RDate)
}
