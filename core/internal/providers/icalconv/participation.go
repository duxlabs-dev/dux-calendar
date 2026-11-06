package icalconv

import (
	"fmt"
	"strings"
	"time"

	ical "github.com/emersion/go-ical"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

// ApplyParticipation stamps email's PARTSTAT for ev inside doc, leaving every
// other component and property untouched. A series reply (zero OriginalStart)
// patches the recurring master in place; an occurrence reply patches the
// matching exception component, deriving a new one from the master when the
// occurrence has never been overridden. It returns the RECURRENCE-ID value the
// occurrence is stored under ("" for series replies) so callers can mirror the
// synthetic "<uid>/<recurrence-id>" UID that EventFromComponent assigns.
func ApplyParticipation(doc *ical.Calendar, ev *cal.Event, email, status string) (string, error) {
	masterUID := ev.UID
	if ev.RecurringID != "" {
		masterUID = ev.RecurringID
	}

	tz := NewTZResolver(doc, ev.StartTimeZone)
	var master *ical.Component
	for _, child := range doc.Children {
		if child.Name != ical.CompEvent || ComponentUID(child) != masterUID {
			continue
		}
		rid := child.Props.Get(ical.PropRecurrenceID)
		if rid == nil {
			master = child
			continue
		}
		if ev.OriginalStart.IsZero() {
			continue
		}
		if t, _, _, ok := parseDateTime(rid, tz); ok && t.Equal(ev.OriginalStart) {
			return rid.Value, setAttendeeStatus(child, email, status)
		}
	}
	if master == nil {
		return "", fmt.Errorf("event %q not found in calendar object", masterUID)
	}

	if ev.OriginalStart.IsZero() {
		return "", setAttendeeStatus(master, email, status)
	}

	exception := deriveException(master, ev)
	if err := setAttendeeStatus(exception, email, status); err != nil {
		return "", err
	}
	doc.Children = append(doc.Children, exception)
	return exception.Props.Get(ical.PropRecurrenceID).Value, nil
}

// deriveException clones the recurring master into a single-occurrence
// override: same descriptive properties and alarms, times moved to the
// occurrence, recurrence rules dropped, RECURRENCE-ID naming the instance.
func deriveException(master *ical.Component, ev *cal.Event) *ical.Component {
	comp := ical.NewComponent(ical.CompEvent)
	for name, props := range master.Props {
		switch name {
		case ical.PropRecurrenceRule, ical.PropRecurrenceDates, ical.PropExceptionDates, ical.PropDuration:
			continue
		}
		cloned := make([]ical.Prop, len(props))
		for i, prop := range props {
			cloned[i] = prop
			if prop.Params == nil {
				continue
			}
			params := make(ical.Params, len(prop.Params))
			for key, values := range prop.Params {
				params[key] = append([]string(nil), values...)
			}
			cloned[i].Params = params
		}
		comp.Props[name] = cloned
	}
	comp.Children = append(comp.Children, master.Children...)

	setEventTimes(comp.Props, ev)
	setRecurrenceID(comp.Props, ev)
	comp.Props.SetDateTime(ical.PropDateTimeStamp, time.Now().UTC())
	return comp
}

func setAttendeeStatus(comp *ical.Component, email, status string) error {
	props := comp.Props[ical.PropAttendee]
	for i := range props {
		if !strings.EqualFold(StripMailto(props[i].Value), email) {
			continue
		}
		if props[i].Params == nil {
			props[i].Params = make(ical.Params)
		}
		props[i].Params.Set(ical.ParamParticipationStatus, strings.ToUpper(status))
		return nil
	}
	return fmt.Errorf("%q is not an attendee of event %q", email, ComponentUID(comp))
}
