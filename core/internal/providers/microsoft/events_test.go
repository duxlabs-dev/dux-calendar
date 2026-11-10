package microsoft

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

func TestGraphDescription(t *testing.T) {
	outlookHTML := `<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"><style>body { font-family: Calibri; }</style></head><body><div>Agenda:<ul><li>Review <b>Q2 numbers</b></li><li>Plan next sprint</li></ul>Docs: <a href="https://example.com/doc">https://example.com/doc</a></div></body></html>`

	tests := []struct {
		name     string
		event    graphEvent
		contains []string
		want     string
	}{
		{
			name:  "nil body falls back to preview",
			event: graphEvent{BodyPreview: "preview text"},
			want:  "preview text",
		},
		{
			name:  "empty body falls back to preview",
			event: graphEvent{BodyPreview: "preview text", Body: &graphBody{ContentType: "html", Content: "  \r\n "}},
			want:  "preview text",
		},
		{
			name:  "text body passes through trimmed",
			event: graphEvent{Body: &graphBody{ContentType: "text", Content: "plain text\r\n\r\n"}},
			want:  "plain text",
		},
		{
			name:     "html body converts to markdown",
			event:    graphEvent{Body: &graphBody{ContentType: "html", Content: outlookHTML}},
			contains: []string{"- Review **Q2 numbers**", "- Plan next sprint", "https://example.com/doc"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := graphDescription(tt.event)
			if tt.want != "" && got != tt.want {
				t.Fatalf("graphDescription() = %q, want %q", got, tt.want)
			}
			for _, sub := range tt.contains {
				if !strings.Contains(got, sub) {
					t.Errorf("graphDescription() = %q, missing %q", got, sub)
				}
			}
		})
	}
}

func TestGraphToEventMapsFields(t *testing.T) {
	g := graphEvent{
		ID:             "evt-1",
		ChangeKey:      "ck-1",
		Subject:        "Standup",
		BodyPreview:    "daily sync",
		WebLink:        "https://outlook.example/evt-1",
		Location:       &graphLocation{DisplayName: "Teams"},
		Start:          &graphDateTime{DateTime: "2026-05-07T14:00:00.0000000", TimeZone: "UTC"},
		End:            &graphDateTime{DateTime: "2026-05-07T14:30:00.0000000", TimeZone: "UTC"},
		SeriesMasterID: "series-1",
		Organizer: &graphRecipient{
			EmailAddress: graphEmailAddress{Address: "boss@example.com", Name: "Boss"},
		},
		Attendees: []graphAttendee{
			{
				EmailAddress: graphEmailAddress{Address: "dev@example.com", Name: "Dev"},
				Type:         "optional",
				Status:       &graphResponseStatus{Response: "accepted"},
			},
			{
				EmailAddress: graphEmailAddress{Address: "qa@example.com"},
				Type:         "required",
			},
		},
		ShowAs:               "free",
		Sensitivity:          "private",
		CreatedDateTime:      "2026-05-01T10:00:00Z",
		LastModifiedDateTime: "2026-05-02T11:00:00Z",
	}

	ev := graphToEvent(g)

	assert.Equal(t, "evt-1", ev.UID)
	assert.Equal(t, "evt-1", ev.RemoteID)
	assert.Equal(t, "ck-1", ev.Etag)
	assert.Equal(t, "Standup", ev.Summary)
	assert.Equal(t, "daily sync", ev.Description)
	assert.Equal(t, "Teams", ev.Location)
	assert.Equal(t, "https://outlook.example/evt-1", ev.URL)
	assert.Equal(t, "series-1", ev.RecurringID)
	assert.Equal(t, time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC), ev.Start)
	assert.Equal(t, time.Date(2026, 5, 7, 14, 30, 0, 0, time.UTC), ev.End)
	assert.Equal(t, "transparent", ev.Transparency)
	assert.Equal(t, "private", ev.Visibility)
	assert.Equal(t, time.Date(2026, 5, 1, 10, 0, 0, 0, time.UTC), ev.Created)
	assert.Equal(t, time.Date(2026, 5, 2, 11, 0, 0, 0, time.UTC), ev.Updated)

	require.NotNil(t, ev.Organizer)
	assert.Equal(t, "boss@example.com", ev.Organizer.Email)
	assert.True(t, ev.Organizer.Organizer)

	require.Len(t, ev.Attendees, 2)
	assert.True(t, ev.Attendees[0].Optional)
	assert.Equal(t, "accepted", ev.Attendees[0].Status)
	assert.False(t, ev.Attendees[1].Optional)
}

func TestGraphToEventStatus(t *testing.T) {
	tests := []struct {
		name  string
		event graphEvent
		want  cal.EventStatus
	}{
		{"cancelled", graphEvent{IsCancelled: true}, cal.EventCancelled},
		{
			"tentative",
			graphEvent{ResponseStatus: &graphResponseStatus{Response: "tentativelyAccepted"}},
			cal.EventTentative,
		},
		{"default confirmed", graphEvent{}, cal.EventConfirmed},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, graphToEvent(tc.event).Status)
		})
	}
}

func TestGraphShowAsRoundTrip(t *testing.T) {
	tests := []struct {
		showAs, transparency, sent string
	}{
		{"free", "transparent", "free"},
		{"busy", "opaque", "busy"},
		{"oof", "", ""},
		{"", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.showAs, func(t *testing.T) {
			ev := graphToEvent(graphEvent{ID: "x", ShowAs: tt.showAs})
			assert.Equal(t, tt.transparency, ev.Transparency)
			assert.Equal(t, tt.sent, eventToGraph(&ev).ShowAs, "an edit must not overwrite showAs it cannot represent")
		})
	}
}

func TestParseGraphTime(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want time.Time
	}{
		{"plain", "2026-05-07T14:00:00", time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC)},
		{"fractional seconds", "2026-05-07T14:00:00.1234567", time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC)},
		{"invalid", "yesterday", time.Time{}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, parseGraphTime(tc.raw))
		})
	}
}

func TestEventToGraphTimedEvent(t *testing.T) {
	ev := &cal.Event{
		Summary:     "Review",
		Description: "PR review",
		Location:    "Room 2",
		Start:       time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC),
		End:         time.Date(2026, 5, 7, 15, 0, 0, 0, time.UTC),
		Attendees: []cal.Attendee{
			{Email: "dev@example.com", DisplayName: "Dev"},
			{Email: "guest@example.com", Optional: true},
		},
	}

	g := eventToGraph(ev)

	assert.Equal(t, "Review", g.Subject)
	require.NotNil(t, g.Body)
	assert.Equal(t, "PR review", g.Body.Content)
	require.NotNil(t, g.Location)
	assert.Equal(t, "Room 2", g.Location.DisplayName)

	require.NotNil(t, g.Start)
	assert.Equal(t, "2026-05-07T14:00:00", g.Start.DateTime)
	assert.Equal(t, "UTC", g.Start.TimeZone)
	require.NotNil(t, g.End)
	assert.Equal(t, "2026-05-07T15:00:00", g.End.DateTime)

	require.Len(t, g.Attendees, 2)
	assert.Equal(t, "required", g.Attendees[0].Type)
	assert.Equal(t, "optional", g.Attendees[1].Type)
}

func TestEventToGraphAllDayNormalizesToMidnight(t *testing.T) {
	ev := &cal.Event{
		Summary: "Conference",
		AllDay:  true,
		Start:   time.Date(2026, 5, 7, 9, 30, 0, 0, time.UTC),
		End:     time.Date(2026, 5, 7, 17, 0, 0, 0, time.UTC),
	}

	g := eventToGraph(ev)

	assert.True(t, g.IsAllDay)
	assert.Equal(t, "2026-05-07T00:00:00", g.Start.DateTime)
	assert.Equal(t, "2026-05-08T00:00:00", g.End.DateTime, "same-day all-day event should span one full day")
}
