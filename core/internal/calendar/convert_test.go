package calendar_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

func TestRemindersToMaps(t *testing.T) {
	assert.Nil(t, calendar.RemindersToMaps(nil))

	got := calendar.RemindersToMaps([]calendar.Reminder{{Method: "popup", Minutes: 10}})
	assert.Equal(t, []map[string]any{{"method": "popup", "minutes": 10}}, got)

	anchored := []calendar.Reminder{{Method: "popup", Minutes: 15, Related: calendar.ReminderRelatedEnd}}
	maps := calendar.RemindersToMaps(anchored)
	assert.Equal(t, []map[string]any{{"method": "popup", "minutes": 15, "related": "end"}}, maps)
	assert.Equal(t, anchored, calendar.RemindersFromMaps(maps))
}
