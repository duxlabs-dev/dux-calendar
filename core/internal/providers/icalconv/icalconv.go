// Package icalconv converts iCalendar components to and from the domain Event
// model. It is shared by every provider that speaks iCalendar (local files and
// CalDAV) so the mapping lives in one place and behaves identically.
package icalconv

import (
	"strings"
	"time"

	ical "github.com/emersion/go-ical"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

const prodID = "-//dankcalendar//dankcalendar//EN"

// NewCalendar returns an empty VCALENDAR carrying the required VERSION and
// PRODID properties.
func NewCalendar() *ical.Calendar {
	out := ical.NewCalendar()
	out.Props.SetText(ical.PropVersion, "2.0")
	out.Props.SetText(ical.PropProductID, prodID)
	return out
}

// CalendarFromEvent wraps a single event in its own VCALENDAR, as written to a
// CalDAV object or a one-event file.
func CalendarFromEvent(ev *cal.Event, uid string) *ical.Calendar {
	out := NewCalendar()
	out.Children = append(out.Children, BuildEvent(ev, uid).Component)
	return out
}

// ComponentUID returns a component's UID, or "" if it has none.
func ComponentUID(comp *ical.Component) string {
	if p := comp.Props.Get(ical.PropUID); p != nil {
		return p.Value
	}
	return ""
}

// CalendarColor returns a VCALENDAR's color: RFC 7986 COLOR first, then the
// Apple extension most calendars in the wild carry.
func CalendarColor(doc *ical.Calendar) string {
	if doc == nil {
		return ""
	}
	for _, name := range []string{ical.PropColor, "X-APPLE-CALENDAR-COLOR"} {
		p := doc.Props.Get(name)
		if p == nil {
			continue
		}
		if v := strings.TrimSpace(p.Value); v != "" {
			return v
		}
	}
	return ""
}

// EventFromComponent maps a VEVENT to a domain event. It reports false when the
// component has no UID. RemoteID and Etag are left to the caller, which knows
// the transport (a file UID or a CalDAV path/etag).
func EventFromComponent(calID string, comp *ical.Component, tz *TZResolver) (cal.Event, bool) {
	uid := ComponentUID(comp)
	if uid == "" {
		return cal.Event{}, false
	}

	ev := cal.Event{
		CalendarID:   calID,
		UID:          uid,
		Summary:      propText(comp, ical.PropSummary),
		Description:  propText(comp, ical.PropDescription),
		Location:     propText(comp, ical.PropLocation),
		Status:       statusFromComponent(comp),
		Transparency: transparencyFromComponent(comp),
	}

	if rid := comp.Props.Get(ical.PropRecurrenceID); rid != nil {
		ev.UID = uid + "/" + rid.Value
		ev.RecurringID = uid
		if t, _, _, ok := parseDateTime(rid, tz); ok {
			ev.OriginalStart = t
		}
	}
	if urlProp := comp.Props.Get(ical.PropURL); urlProp != nil {
		ev.URL = urlProp.Value
	}
	ev.MeetingURL = meetingURLFromComponent(comp)

	applyTimes(comp, &ev, tz)
	applyRecurrence(comp, &ev, tz)
	applyAttendees(comp, &ev)
	applyAlarms(comp, &ev)

	return ev, true
}

func applyTimes(comp *ical.Component, ev *cal.Event, tz *TZResolver) {
	if start, zone, allDay, ok := parseDateTime(comp.Props.Get(ical.PropDateTimeStart), tz); ok {
		ev.Start = start
		ev.AllDay = allDay
		ev.StartTimeZone = zone
	}

	endProp := comp.Props.Get(ical.PropDateTimeEnd)
	durProp := comp.Props.Get(ical.PropDuration)
	switch {
	case endProp != nil:
		if end, zone, _, ok := parseDateTime(endProp, tz); ok {
			ev.End = end
			ev.EndTimeZone = zone
			return
		}
		ev.End = ev.Start
	case durProp != nil:
		dur, err := durProp.Duration()
		if err != nil {
			ev.End = ev.Start
			return
		}
		ev.End = ev.Start.Add(dur)
	case ev.AllDay:
		ev.End = ev.Start.Add(24 * time.Hour)
	default:
		ev.End = ev.Start
	}
}

// parseDateTime reads a DTSTART/DTEND/RECURRENCE-ID value, resolving its TZID
// through tz. It reports the resolved IANA zone name (empty for UTC, floating,
// or fixed-offset values) and whether the value is an all-day date. Unlike
// go-ical's DateTime, an unresolvable TZID never yields a zero time: the literal
// wall-clock is kept.
func parseDateTime(prop *ical.Prop, tz *TZResolver) (when time.Time, zone string, allDay bool, ok bool) {
	if prop == nil {
		return time.Time{}, "", false, false
	}

	raw := strings.TrimSpace(prop.Value)
	switch {
	case prop.ValueType() == ical.ValueDate || len(raw) == 8:
		t, err := time.ParseInLocation("20060102", raw, time.UTC)
		return t, "", true, err == nil
	case strings.HasSuffix(raw, "Z"):
		t, err := time.ParseInLocation("20060102T150405Z", raw, time.UTC)
		return t, "", false, err == nil
	}

	naive, err := time.ParseInLocation("20060102T150405", raw, time.UTC)
	if err != nil {
		return time.Time{}, "", false, false
	}

	tzid := prop.Params.Get(ical.ParamTimezoneID)
	loc, name := tz.floating()
	if tzid != "" {
		loc, name = tz.location(tzid, naive)
	}
	t, err := time.ParseInLocation("20060102T150405", raw, loc)
	return t, name, false, err == nil
}

func applyRecurrence(comp *ical.Component, ev *cal.Event, tz *TZResolver) {
	ev.Recurrence = recurrenceFromComponent(comp, tz)
}

func recurrenceFromComponent(comp *ical.Component, tz *TZResolver) *cal.Recurrence {
	rrules := rawValues(comp, ical.PropRecurrenceRule)
	rdates := tz.normalizeDateList(comp.Props.Values(ical.PropRecurrenceDates))
	exdates := tz.normalizeDateList(comp.Props.Values(ical.PropExceptionDates))
	if len(rrules)+len(rdates)+len(exdates) == 0 {
		return nil
	}
	return &cal.Recurrence{RRule: rrules, RDate: rdates, ExDate: exdates}
}

// normalizeDateList rewrites RDATE/EXDATE values to absolute UTC instants,
// resolving each property's own TZID. go-ical drops the TZID parameter from the
// raw value, so without this a cross-zone exclusion would be parsed in the wrong
// zone and miss its occurrence. DATE values and existing UTC values pass through
// unchanged.
func (r *TZResolver) normalizeDateList(props []ical.Prop) []string {
	var out []string
	for _, prop := range props {
		tzid := prop.Params.Get(ical.ParamTimezoneID)
		isDate := prop.ValueType() == ical.ValueDate
		for raw := range strings.SplitSeq(prop.Value, ",") {
			raw = strings.TrimSpace(raw)
			switch {
			case raw == "":
				continue
			case isDate || len(raw) == 8 || strings.HasSuffix(raw, "Z"):
				out = append(out, raw)
			default:
				if t, ok := r.resolveValue(tzid, raw); ok {
					out = append(out, t.UTC().Format("20060102T150405Z"))
					continue
				}
				out = append(out, raw)
			}
		}
	}
	return out
}

func applyAttendees(comp *ical.Component, ev *cal.Event) {
	for _, prop := range comp.Props.Values(ical.PropAttendee) {
		ev.Attendees = append(ev.Attendees, attendeeFromProp(prop))
	}
	org := comp.Props.Get(ical.PropOrganizer)
	if org == nil {
		return
	}
	attendee := attendeeFromProp(*org)
	attendee.Organizer = true
	ev.Organizer = &attendee
}

func attendeeFromProp(prop ical.Prop) cal.Attendee {
	role := prop.Params.Get(ical.ParamRole)
	return cal.Attendee{
		Email:       StripMailto(prop.Value),
		DisplayName: prop.Params.Get(ical.ParamCommonName),
		Role:        role,
		Status:      strings.ToLower(prop.Params.Get(ical.ParamParticipationStatus)),
		Optional:    strings.EqualFold(role, "OPT-PARTICIPANT"),
	}
}

// transparencyFromComponent reads TRANSP as the lower-case value the rest of
// the app uses; an absent property stays empty, which reads as busy.
func transparencyFromComponent(comp *ical.Component) string {
	prop := comp.Props.Get(ical.PropTransparency)
	if prop == nil {
		return ""
	}
	switch strings.ToUpper(prop.Value) {
	case "TRANSPARENT":
		return "transparent"
	case "OPAQUE":
		return "opaque"
	default:
		return ""
	}
}

func statusFromComponent(comp *ical.Component) cal.EventStatus {
	prop := comp.Props.Get(ical.PropStatus)
	if prop == nil {
		return cal.EventConfirmed
	}
	switch strings.ToUpper(prop.Value) {
	case "TENTATIVE":
		return cal.EventTentative
	case "CANCELLED":
		return cal.EventCancelled
	default:
		return cal.EventConfirmed
	}
}

// meetingURLFromComponent recovers a video meeting link, preferring the
// conference properties providers emit (Google's X-GOOGLE-CONFERENCE, Outlook's
// X-MICROSOFT-SKYPETEAMSMEETINGURL, RFC 7986 CONFERENCE) before scanning the
// description and location for a known link.
func meetingURLFromComponent(comp *ical.Component) string {
	if v := propValue(comp, "X-GOOGLE-CONFERENCE"); v != "" {
		return v
	}
	if v := propValue(comp, "X-MICROSOFT-SKYPETEAMSMEETINGURL"); v != "" {
		return v
	}
	if v := conferencePropURL(comp); v != "" {
		return v
	}
	return cal.MeetingURLInText(propText(comp, ical.PropDescription), propText(comp, ical.PropLocation))
}

// conferencePropURL returns the best RFC 7986 CONFERENCE join link: an http(s)
// URI, preferring one advertised with the VIDEO feature. Audio-only dial-ins
// (tel: URIs) are skipped.
func conferencePropURL(comp *ical.Component) string {
	var fallback string
	for _, prop := range comp.Props.Values("CONFERENCE") {
		if !strings.HasPrefix(prop.Value, "http://") && !strings.HasPrefix(prop.Value, "https://") {
			continue
		}
		if strings.Contains(strings.ToUpper(prop.Params.Get("FEATURE")), "VIDEO") {
			return prop.Value
		}
		if fallback == "" {
			fallback = prop.Value
		}
	}
	return fallback
}

func propText(comp *ical.Component, name string) string {
	text, err := comp.Props.Text(name)
	if err != nil {
		return ""
	}
	return text
}

func rawValues(comp *ical.Component, name string) []string {
	props := comp.Props.Values(name)
	if len(props) == 0 {
		return nil
	}
	out := make([]string, 0, len(props))
	for _, prop := range props {
		out = append(out, prop.Value)
	}
	return out
}

// StripMailto drops a leading mailto: scheme from an iCalendar address value.
func StripMailto(value string) string {
	if len(value) >= 7 && strings.EqualFold(value[:7], "mailto:") {
		return value[7:]
	}
	return value
}

// ReplaceMasterComponent replaces the VEVENT with uid that has no
// RECURRENCE-ID, leaving exception components untouched.
func ReplaceMasterComponent(doc *ical.Calendar, uid string, comp *ical.Component) bool {
	for i, child := range doc.Children {
		if child.Name != ical.CompEvent || ComponentUID(child) != uid {
			continue
		}
		if child.Props.Get(ical.PropRecurrenceID) != nil {
			continue
		}
		doc.Children[i] = comp
		return true
	}
	return false
}

// BuildEvent renders a domain event as a VEVENT component.
func BuildEvent(ev *cal.Event, uid string) *ical.Event {
	event := ical.NewEvent()
	props := event.Props
	props.SetText(ical.PropUID, uid)
	props.SetDateTime(ical.PropDateTimeStamp, time.Now().UTC())
	props.SetText(ical.PropSummary, ev.Summary)
	if ev.Description != "" {
		props.SetText(ical.PropDescription, ev.Description)
	}
	if ev.Location != "" {
		props.SetText(ical.PropLocation, ev.Location)
	}
	if ev.URL != "" {
		setRaw(props, ical.PropURL, ev.URL)
	}
	if ev.MeetingURL != "" {
		setRaw(props, "X-GOOGLE-CONFERENCE", ev.MeetingURL)
	}
	if status := statusValue(ev.Status); status != "" {
		props.SetText(ical.PropStatus, status)
	}
	switch ev.Transparency {
	case "transparent", "opaque":
		props.SetText(ical.PropTransparency, strings.ToUpper(ev.Transparency))
	}

	setEventTimes(props, ev)
	setRecurrence(props, ev.Recurrence)
	setAttendees(props, ev)
	addAlarms(event.Component, ev.Reminders)

	return event
}

func setEventTimes(props ical.Props, ev *cal.Event) {
	switch {
	case ev.AllDay:
		props.SetDate(ical.PropDateTimeStart, ev.Start)
		end := ev.End
		if !end.After(ev.Start) {
			end = ev.Start.Add(24 * time.Hour)
		}
		props.SetDate(ical.PropDateTimeEnd, end)
	default:
		props.SetDateTime(ical.PropDateTimeStart, inZone(ev.Start, ev.StartTimeZone))
		end := ev.End
		if end.IsZero() {
			end = ev.Start
		}
		props.SetDateTime(ical.PropDateTimeEnd, inZone(end, ev.EndTimeZone))
	}
}

// inZone renders t in its stored zone so SetDateTime writes a TZID instead of
// forcing UTC (issue #80); empty or unknown zones stay UTC.
func inZone(t time.Time, tz string) time.Time {
	loc, _ := loadZone(tz)
	if loc == nil {
		return t.UTC()
	}
	return t.In(loc)
}

func setRecurrence(props ical.Props, rec *cal.Recurrence) {
	if rec == nil {
		return
	}
	for _, rule := range rec.RRule {
		setRawAdd(props, ical.PropRecurrenceRule, rule)
	}
	for _, rdate := range rec.RDate {
		setRawAdd(props, ical.PropRecurrenceDates, rdate)
	}
	for _, exdate := range rec.ExDate {
		setRawAdd(props, ical.PropExceptionDates, exdate)
	}
}

func setAttendees(props ical.Props, ev *cal.Event) {
	for _, attendee := range ev.Attendees {
		props.Add(attendeeProp(ical.PropAttendee, attendee))
	}
	if ev.Organizer == nil || ev.Organizer.Email == "" {
		return
	}
	props.Set(attendeeProp(ical.PropOrganizer, *ev.Organizer))
}

func attendeeProp(name string, attendee cal.Attendee) *ical.Prop {
	prop := ical.NewProp(name)
	prop.Value = "mailto:" + attendee.Email
	if attendee.DisplayName != "" {
		prop.Params.Set(ical.ParamCommonName, attendee.DisplayName)
	}
	if attendee.Role != "" {
		prop.Params.Set(ical.ParamRole, attendee.Role)
	}
	if attendee.Status != "" {
		prop.Params.Set(ical.ParamParticipationStatus, strings.ToUpper(attendee.Status))
	}
	return prop
}

func statusValue(status cal.EventStatus) string {
	switch status {
	case cal.EventConfirmed:
		return "CONFIRMED"
	case cal.EventTentative:
		return "TENTATIVE"
	case cal.EventCancelled:
		return "CANCELLED"
	}
	return ""
}

func setRaw(props ical.Props, name, value string) {
	prop := ical.NewProp(name)
	prop.Value = value
	props.Set(prop)
}

func setRawAdd(props ical.Props, name, value string) {
	prop := ical.NewProp(name)
	prop.Value = value
	props.Add(prop)
}
