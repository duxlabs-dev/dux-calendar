package settings

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLoadFrom(t *testing.T) {
	tests := []struct {
		name    string
		content string
		want    func(UISettings) UISettings
	}{
		{
			name:    "missing file returns defaults",
			content: "",
			want:    func(d UISettings) UISettings { return d },
		},
		{
			name:    "invalid json returns defaults",
			content: "{not json",
			want:    func(d UISettings) UISettings { return d },
		},
		{
			name:    "partial file overrides only present keys",
			content: `{"remindersEnabled": false, "snoozeMinutes": 15}`,
			want: func(d UISettings) UISettings {
				d.RemindersEnabled = false
				d.SnoozeMinutes = 15
				return d
			},
		},
		{
			name:    "zero snooze falls back to default",
			content: `{"snoozeMinutes": 0}`,
			want:    func(d UISettings) UISettings { return d },
		},
		{
			name:    "non-positive ui scale falls back to default",
			content: `{"uiScale": 0}`,
			want:    func(d UISettings) UISettings { return d },
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "ui-settings.json")
			if tt.content != "" {
				require.NoError(t, os.WriteFile(path, []byte(tt.content), 0o600))
			}
			assert.Equal(t, tt.want(Defaults()), loadFrom(path))
		})
	}
}

func TestAllDayClock(t *testing.T) {
	tests := []struct {
		name   string
		value  string
		hour   int
		minute int
	}{
		{"valid", "18:30", 18, 30},
		{"midnight", "00:00", 0, 0},
		{"malformed falls back", "9am", 9, 0},
		{"empty falls back", "", 9, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := Defaults()
			s.AllDayReminderTime = tt.value
			hour, minute := s.AllDayClock()
			assert.Equal(t, tt.hour, hour)
			assert.Equal(t, tt.minute, minute)
		})
	}
}

func TestReminderOverrideResolve(t *testing.T) {
	ptrBool := func(b bool) *bool { return &b }
	ptrInt := func(i int) *int { return &i }
	ptrStr := func(s string) *string { return &s }

	t.Run("nil override returns base unchanged", func(t *testing.T) {
		base := Defaults()
		var o *ReminderOverride
		assert.Equal(t, base, o.Resolve(base))
	})

	t.Run("only set fields win", func(t *testing.T) {
		base := Defaults()
		o := &ReminderOverride{DefaultReminderMinutes: ptrInt(30), AllDayTime: ptrStr("07:30")}
		got := o.Resolve(base)
		assert.Equal(t, 30, got.DefaultReminderMinutes)
		assert.Equal(t, "07:30", got.AllDayReminderTime)
		assert.Equal(t, base.SnoozeMinutes, got.SnoozeMinutes)
		assert.Equal(t, base.ReminderPersist, got.ReminderPersist)
	})

	t.Run("override can mute an enabled calendar", func(t *testing.T) {
		base := Defaults()
		o := &ReminderOverride{Enabled: ptrBool(false)}
		assert.False(t, o.Resolve(base).RemindersEnabled)
	})

	t.Run("override cannot force on when global is off", func(t *testing.T) {
		base := Defaults()
		base.RemindersEnabled = false
		o := &ReminderOverride{Enabled: ptrBool(true)}
		assert.False(t, o.Resolve(base).RemindersEnabled)
	})

	t.Run("non-positive snooze override is ignored", func(t *testing.T) {
		base := Defaults()
		o := &ReminderOverride{SnoozeMinutes: ptrInt(0)}
		assert.Equal(t, base.SnoozeMinutes, o.Resolve(base).SnoozeMinutes)
	})

	t.Run("IsEmpty", func(t *testing.T) {
		var nilOverride *ReminderOverride
		assert.True(t, nilOverride.IsEmpty())
		assert.True(t, (&ReminderOverride{}).IsEmpty())
		assert.False(t, (&ReminderOverride{Enabled: ptrBool(false)}).IsEmpty())
	})
}
