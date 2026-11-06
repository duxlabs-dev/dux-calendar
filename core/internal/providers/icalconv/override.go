package icalconv

import (
	"errors"
	"fmt"
	"strings"
	"time"

	ical "github.com/emersion/go-ical"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

// ApplyEventOverride writes ev as a single-occurrence override of the recurring
// series in doc. It creates an exception VEVENT derived from the master when
// the occurrence has never been overridden, and updates an existing exception
// otherwise. It returns the RECURRENCE-ID value the override is stored under.
func ApplyEventOverride(doc *ical.Calendar, ev *cal.Event) (string, error) {
	if doc == nil {
		return "", errors.New("calendar object is empty")
	}
	if ev.RecurringID == "" {
		return "", errors.New("event has no recurring id")
	}
	if ev.OriginalStart.IsZero() {
		return "", errors.New("event has no occurrence start")
	}

	tz := NewTZResolver(doc, ev.StartTimeZone)
	var master, override *ical.Component
	for _, child := range doc.Children {
		if child.Name != ical.CompEvent || ComponentUID(child) != ev.RecurringID {
			continue
		}
		rid := child.Props.Get(ical.PropRecurrenceID)
		switch {
		case rid == nil:
			if master == nil {
				master = child
			}
		case override == nil:
			if t, _, _, ok := parseDateTime(rid, tz); ok && t.Equal(ev.OriginalStart) {
				override = child
			}
		}
	}
	if master == nil {
		return "", fmt.Errorf("event %q not found in calendar object", ev.RecurringID)
	}
	if override == nil {
		override = deriveException(master, ev)
		doc.Children = append(doc.Children, override)
	}

	applyOverride(override, ev)
	rid := override.Props.Get(ical.PropRecurrenceID)
	if rid == nil {
		return "", errors.New("override has no recurrence id")
	}
	return rid.Value, nil
}

// RemoveEventOverride drops the exception component for ev's occurrence. It
// reports false when the object has no matching override.
func RemoveEventOverride(doc *ical.Calendar, ev *cal.Event) (bool, error) {
	if doc == nil {
		return false, errors.New("calendar object is empty")
	}
	if ev.RecurringID == "" {
		return false, errors.New("event has no recurring id")
	}
	if ev.OriginalStart.IsZero() {
		return false, errors.New("event has no occurrence start")
	}

	tz := NewTZResolver(doc, ev.StartTimeZone)
	for i, child := range doc.Children {
		if child.Name != ical.CompEvent || ComponentUID(child) != ev.RecurringID {
			continue
		}
		rid := child.Props.Get(ical.PropRecurrenceID)
		if rid == nil {
			continue
		}
		t, _, _, ok := parseDateTime(rid, tz)
		if !ok || !t.Equal(ev.OriginalStart) {
			continue
		}
		doc.Children = append(doc.Children[:i], doc.Children[i+1:]...)
		return true, nil
	}
	return false, nil
}

func applyOverride(comp *ical.Component, ev *cal.Event) {
	props := comp.Props
	props.SetText(ical.PropSummary, ev.Summary)
	setOrDelText(props, ical.PropDescription, ev.Description)
	setOrDelText(props, ical.PropLocation, ev.Location)
	setOrDelRaw(props, ical.PropURL, ev.URL)
	setOrDelRaw(props, "X-GOOGLE-CONFERENCE", ev.MeetingURL)

	if status := statusValue(ev.Status); status == "" {
		props.Del(ical.PropStatus)
	} else {
		props.SetText(ical.PropStatus, status)
	}
	switch ev.Transparency {
	case "transparent", "opaque":
		props.SetText(ical.PropTransparency, strings.ToUpper(ev.Transparency))
	default:
		props.Del(ical.PropTransparency)
	}

	props.Del(ical.PropRecurrenceRule)
	props.Del(ical.PropRecurrenceDates)
	props.Del(ical.PropExceptionDates)
	props.Del(ical.PropDuration)
	setEventTimes(props, ev)
	setRecurrenceID(props, ev)

	props.Del(ical.PropAttendee)
	props.Del(ical.PropOrganizer)
	setAttendees(props, ev)

	comp.Children = removeAlarms(comp.Children)
	addAlarms(comp, ev.Reminders)
	props.SetDateTime(ical.PropDateTimeStamp, time.Now().UTC())
}

// RebaseEventOverrides moves every exception's RECURRENCE-ID by delta, leaving
// each exception's own DTSTART untouched. The returned map is keyed by the old
// override UID and carries the new one.
func RebaseEventOverrides(doc *ical.Calendar, masterUID string, delta time.Duration) map[string]string {
	mapping := map[string]string{}
	if doc == nil || delta == 0 {
		return mapping
	}

	tz := NewTZResolver(doc, "")
	for _, child := range doc.Children {
		if child.Name != ical.CompEvent || ComponentUID(child) != masterUID {
			continue
		}
		rid := child.Props.Get(ical.PropRecurrenceID)
		if rid == nil {
			continue
		}
		when, _, _, ok := parseDateTime(rid, tz)
		if !ok {
			continue
		}

		oldValue := rid.Value
		rebaseRecurrenceID(child.Props, rid, when.Add(delta))
		newValue := child.Props.Get(ical.PropRecurrenceID).Value
		mapping[masterUID+"/"+oldValue] = masterUID + "/" + newValue
	}
	return mapping
}

func rebaseRecurrenceID(props ical.Props, rid *ical.Prop, moved time.Time) {
	raw := strings.TrimSpace(rid.Value)
	switch {
	case rid.ValueType() == ical.ValueDate || len(raw) == 8:
		props.SetDate(ical.PropRecurrenceID, moved)
	case strings.HasSuffix(raw, "Z"):
		props.SetDateTime(ical.PropRecurrenceID, moved.UTC())
	case rid.Params.Get(ical.ParamTimezoneID) != "":
		if loc, _ := loadZone(rid.Params.Get(ical.ParamTimezoneID)); loc != nil {
			props.SetDateTime(ical.PropRecurrenceID, moved.In(loc))
			return
		}
		props.SetDateTime(ical.PropRecurrenceID, moved.UTC())
	default:
		prop := ical.NewProp(ical.PropRecurrenceID)
		prop.Value = moved.Format("20060102T150405")
		props.Set(prop)
	}
}

// setRecurrenceID writes the RECURRENCE-ID naming the overridden instance.
func setRecurrenceID(props ical.Props, ev *cal.Event) {
	if ev.AllDay {
		props.SetDate(ical.PropRecurrenceID, ev.OriginalStart)
		return
	}
	props.SetDateTime(ical.PropRecurrenceID, inZone(ev.OriginalStart, ev.StartTimeZone))
}

func setOrDelText(props ical.Props, name, value string) {
	if value == "" {
		props.Del(name)
		return
	}
	props.SetText(name, value)
}

func setOrDelRaw(props ical.Props, name, value string) {
	if value == "" {
		props.Del(name)
		return
	}
	setRaw(props, name, value)
}

func removeAlarms(children []*ical.Component) []*ical.Component {
	kept := children[:0]
	for _, child := range children {
		if child.Name != ical.CompAlarm {
			kept = append(kept, child)
		}
	}
	return kept
}
