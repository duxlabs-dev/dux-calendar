package ipc

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/duxlabs-dev/dux-calendar/core/ent"
	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/eventconv"
	"github.com/duxlabs-dev/dux-calendar/core/internal/rsvp"
	"github.com/duxlabs-dev/dux-calendar/core/internal/settings"
	"github.com/duxlabs-dev/dux-calendar/core/internal/tzcache"
	"github.com/duxlabs-dev/dux-go/log"
)

const (
	editScopeLegacy     = ""
	editScopeSeries     = "series"
	editScopeOccurrence = "occurrence"
)

func handleEventCreate(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	calendarID := ParamString(req.Params, "calendarId")
	if calendarID == "" {
		w.RespondError(req.ID, "calendarId is required")
		return
	}

	ev, err := eventFromParams(calendar.Event{Status: calendar.EventConfirmed}, req.Params)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	switch {
	case ev.Summary == "":
		w.RespondError(req.ID, "summary is required")
		return
	case ev.Start.IsZero() || ev.End.IsZero():
		w.RespondError(req.ID, "start and end are required (RFC3339)")
		return
	}

	// Locally created events carry the machine's zone so providers write a
	// TZID instead of forcing UTC (#80).
	if tz := tzcache.LocalName(); !ev.AllDay && tz != "" {
		if ev.StartTimeZone == "" {
			ev.StartTimeZone = tz
		}
		if ev.EndTimeZone == "" {
			ev.EndTimeZone = tz
		}
	}

	provider, domCal, err := providerForCalendar(ctx, deps, calendarID)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	defer provider.Close()

	created, err := provider.CreateEvent(ctx, domCal, &ev)
	if err != nil {
		w.RespondError(req.ID, fmt.Sprintf("create event: %v", err))
		return
	}

	stored, err := persistEvent(ctx, deps, domCal.ID, created)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	publishEventsChanged(deps, domCal.ID)
	w.Respond(req.ID, mapEvent(stored))
}

func handleEventUpdate(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	id := ParamString(req.Params, "id")
	if id == "" {
		w.RespondError(req.ID, "id is required")
		return
	}

	entEv, err := deps.Repo.GetEvent(ctx, id)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	if entEv.Edges.Calendar == nil {
		w.RespondError(req.ID, "event has no calendar")
		return
	}
	calendarID := entEv.Edges.Calendar.ID

	scope := ParamString(req.Params, "scope")
	switch scope {
	case editScopeSeries, editScopeOccurrence:
	case editScopeLegacy:
		// Legacy callers (drag/drop) omit scope and keep editing the row sent.
	default:
		w.RespondError(req.ID, "scope must be series or occurrence")
		return
	}

	// An exception row represents one instance; series-wide edits and the base
	// fields for an occurrence edit come from its master.
	master := entEv
	if scope != editScopeLegacy && entEv.RecurringID != "" {
		if fetched, ferr := deps.Repo.FindEventByUID(ctx, calendarID, entEv.RecurringID); ferr == nil {
			master = fetched
		}
	}
	isSeries := len(master.Recurrence) > 0

	allDay := master.AllDay
	var occStart time.Time
	if raw := ParamString(req.Params, "occurrenceStart"); raw != "" {
		parsed, perr := parseOccurrenceStart(raw, allDay)
		if perr != nil {
			w.RespondError(req.ID, perr.Error())
			return
		}
		occStart = parsed
	}
	if scope != editScopeLegacy && occStart.IsZero() && entEv.OriginalStart != nil {
		occStart = *entEv.OriginalStart
	}

	var ev calendar.Event
	if scope == editScopeOccurrence {
		if !isSeries {
			w.RespondError(req.ID, "event is not recurring")
			return
		}
		if occStart.IsZero() {
			w.RespondError(req.ID, "occurrenceStart is required to edit one occurrence")
			return
		}

		base := domainEventFromEnt(master)
		if entEv.RecurringID != "" {
			base = domainEventFromEnt(entEv)
		}
		ev, err = eventFromParams(base, req.Params)
		if err != nil {
			w.RespondError(req.ID, err.Error())
			return
		}
		ev.ID = ""
		ev.Recurrence = nil
		ev.RecurringID = master.UID
		ev.OriginalStart = occStart
		ev.UID = master.UID + "/" + exDateValue(occStart, master.AllDay)
	} else {
		ev, err = eventFromParams(domainEventFromEnt(master), req.Params)
		if err != nil {
			w.RespondError(req.ID, err.Error())
			return
		}
		if !occStart.IsZero() && isSeries {
			ev = shiftSeriesTimes(ev, master.Start, occStart)
		}
	}

	provider, domCal, err := providerForCalendar(ctx, deps, calendarID)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	defer provider.Close()

	if scope == editScopeOccurrence {
		switch provider.Kind() {
		case calendar.AccountLocal, calendar.AccountCalDAV:
		default:
			w.RespondError(req.ID, "editing a single occurrence is not supported for this calendar")
			return
		}
	}

	updated, err := provider.UpdateEvent(ctx, domCal, &ev)
	if err != nil {
		w.RespondError(req.ID, fmt.Sprintf("update event: %v", err))
		return
	}

	stored, err := persistEvent(ctx, deps, domCal.ID, updated)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	publishEventsChanged(deps, domCal.ID)
	w.Respond(req.ID, mapEvent(stored))
}

func handleEventDelete(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	id := ParamString(req.Params, "id")
	if id == "" {
		w.RespondError(req.ID, "id is required")
		return
	}

	entEv, err := deps.Repo.GetEvent(ctx, id)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	if entEv.Edges.Calendar == nil {
		w.RespondError(req.ID, "event has no calendar")
		return
	}
	calendarID := entEv.Edges.Calendar.ID

	if raw := ParamString(req.Params, "occurrenceStart"); raw != "" {
		occStart, perr := parseOccurrenceStart(raw, entEv.AllDay)
		if perr != nil {
			w.RespondError(req.ID, perr.Error())
			return
		}
		deleteEventOccurrence(ctx, w, req, deps, entEv, calendarID, occStart)
		return
	}

	provider, domCal, err := providerForCalendar(ctx, deps, calendarID)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	defer provider.Close()

	if err := provider.DeleteEvent(ctx, domCal, domainEventFromEnt(entEv)); err != nil {
		w.RespondError(req.ID, fmt.Sprintf("delete event: %v", err))
		return
	}
	if err := deps.Repo.DeleteEvent(ctx, id); err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	publishEventsChanged(deps, calendarID)
	w.Respond(req.ID, map[string]any{"deleted": true})
}

// deleteEventOccurrence removes one instance of a recurring series by adding
// an EXDATE to the master and updating it in place.
func deleteEventOccurrence(ctx context.Context, w *ConnWriter, req Request, deps Deps, entEv *ent.Event, calendarID string, occStart time.Time) {
	ev := domainEventFromEnt(entEv)
	if ev.Recurrence == nil || len(ev.Recurrence.RRule)+len(ev.Recurrence.RDate) == 0 {
		w.RespondError(req.ID, "event is not recurring")
		return
	}

	ev.Recurrence.ExDate = append(ev.Recurrence.ExDate, exDateValue(occStart, ev.AllDay))

	provider, domCal, err := providerForCalendar(ctx, deps, calendarID)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}
	defer provider.Close()

	updated, err := provider.UpdateEvent(ctx, domCal, &ev)
	if err != nil {
		w.RespondError(req.ID, fmt.Sprintf("delete occurrence: %v", err))
		return
	}
	if _, err := persistEvent(ctx, deps, domCal.ID, updated); err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	publishEventsChanged(deps, calendarID)
	w.Respond(req.ID, map[string]any{"deleted": true})
}

func handleEventRSVP(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	id := ParamString(req.Params, "id")
	if id == "" {
		w.RespondError(req.ID, "id is required")
		return
	}
	response := ParamString(req.Params, "response")
	if response == "" {
		w.RespondError(req.ID, "response is required (accept|decline|tentative)")
		return
	}
	var occurrenceStart time.Time
	if raw := ParamString(req.Params, "occurrenceStart"); raw != "" {
		parsed, perr := time.Parse(time.RFC3339, raw)
		if perr != nil {
			w.RespondError(req.ID, fmt.Sprintf("occurrenceStart must be RFC3339: %v", perr))
			return
		}
		occurrenceStart = parsed
	}

	res, err := rsvp.Apply(ctx, rsvp.Stores{
		Repo:     deps.Repo,
		Registry: deps.Registry,
		Secrets:  deps.Secrets,
	}, id, response, occurrenceStart)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	publishEventsChanged(deps, res.CalendarID)

	stored, err := deps.Repo.GetEvent(ctx, res.EventID)
	if err != nil {
		w.Respond(req.ID, map[string]any{"id": res.EventID, "response": res.Response})
		return
	}
	w.Respond(req.ID, mapEvent(stored))
}

func handleCalendarSetHidden(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	id := ParamString(req.Params, "calendarId")
	if id == "" {
		w.RespondError(req.ID, "calendarId is required")
		return
	}
	if _, ok := req.Params["hidden"]; !ok {
		w.RespondError(req.ID, "hidden is required")
		return
	}

	if err := deps.Repo.SetCalendarHidden(ctx, id, ParamBool(req.Params, "hidden")); err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	if deps.Bus != nil {
		deps.Bus.Publish("calendars", map[string]any{"type": "changed", "calendarId": id})
	}
	w.Respond(req.ID, map[string]any{"calendarId": id, "hidden": ParamBool(req.Params, "hidden")})
}

func handleCalendarSetSyncDisabled(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	id := ParamString(req.Params, "calendarId")
	if id == "" {
		w.RespondError(req.ID, "calendarId is required")
		return
	}
	if _, ok := req.Params["disabled"]; !ok {
		w.RespondError(req.ID, "disabled is required")
		return
	}

	cal, err := deps.Repo.GetCalendar(ctx, id)
	if err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	disabled := ParamBool(req.Params, "disabled")
	if err := deps.Repo.SetCalendarSyncDisabled(ctx, id, disabled); err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	// Re-enabling resyncs in the background so the calendar's events come
	// back without waiting for the next scheduled pass; the response must
	// not block on a full account sync.
	if !disabled && deps.Sync != nil && cal.Edges.Account != nil {
		acc := cal.Edges.Account
		go func() {
			if err := deps.Sync.SyncAccount(context.Background(), acc); err != nil {
				log.Warnf("sync after calendar enable: %v", err)
			}
		}()
	}

	if deps.Bus != nil {
		deps.Bus.Publish("calendars", map[string]any{"type": "changed", "calendarId": id})
		deps.Bus.Publish("events", map[string]any{"type": "changed", "calendarId": id})
	}
	w.Respond(req.ID, map[string]any{"calendarId": id, "syncDisabled": disabled})
}

func handleCalendarRename(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	id := ParamString(req.Params, "calendarId")
	if id == "" {
		w.RespondError(req.ID, "calendarId is required")
		return
	}

	// Empty name clears the override, falling back to the provider name.
	name := strings.TrimSpace(ParamString(req.Params, "name"))
	if err := deps.Repo.SetCalendarNameOverride(ctx, id, name); err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	if deps.Bus != nil {
		deps.Bus.Publish("calendars", map[string]any{"type": "changed", "calendarId": id})
	}
	w.Respond(req.ID, map[string]any{"calendarId": id, "name": name})
}

func handleCalendarSetReminders(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	id := ParamString(req.Params, "calendarId")
	if id == "" {
		w.RespondError(req.ID, "calendarId is required")
		return
	}

	// A missing or empty overrides object clears all overrides, reverting
	// the calendar to the global reminder settings.
	override := reminderOverrideFromParam(req.Params["overrides"])
	if err := deps.Repo.SetCalendarReminders(ctx, id, override); err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	if deps.Bus != nil {
		deps.Bus.Publish("calendars", map[string]any{"type": "changed", "calendarId": id})
	}
	w.Respond(req.ID, map[string]any{"calendarId": id})
}

// reminderOverrideFromParam reads the override object: only the keys present
// become overrides, everything else inherits the global value.
func reminderOverrideFromParam(raw any) *settings.ReminderOverride {
	o := &settings.ReminderOverride{}
	m, ok := raw.(map[string]any)
	if !ok {
		return o
	}
	if v, ok := m["enabled"].(bool); ok {
		o.Enabled = &v
	}
	if v, ok := m["persist"].(bool); ok {
		o.Persist = &v
	}
	if v, ok := m["allDay"].(bool); ok {
		o.AllDay = &v
	}
	if v, ok := m["allDayTime"].(string); ok {
		o.AllDayTime = &v
	}
	if v, ok := intFromParam(m["allDayDaysBefore"]); ok {
		o.AllDayDaysBefore = &v
	}
	if v, ok := intFromParam(m["defaultReminderMinutes"]); ok {
		o.DefaultReminderMinutes = &v
	}
	if v, ok := intFromParam(m["snoozeMinutes"]); ok {
		o.SnoozeMinutes = &v
	}
	return o
}

func intFromParam(raw any) (int, bool) {
	switch v := raw.(type) {
	case float64:
		return int(v), true
	case int:
		return v, true
	case int64:
		return int(v), true
	}
	return 0, false
}

func handleCalendarDelete(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	id := ParamString(req.Params, "calendarId")
	if id == "" {
		w.RespondError(req.ID, "calendarId is required")
		return
	}

	if err := deps.Repo.DeleteCalendar(ctx, id); err != nil {
		w.RespondError(req.ID, err.Error())
		return
	}

	if deps.Bus != nil {
		deps.Bus.Publish("calendars", map[string]any{"type": "deleted", "calendarId": id})
		deps.Bus.Publish("events", map[string]any{"type": "changed", "calendarId": id})
	}
	w.Respond(req.ID, map[string]any{"deleted": true})
}

func providerForCalendar(ctx context.Context, deps Deps, calendarID string) (calendar.Provider, calendar.Calendar, error) {
	entCal, err := deps.Repo.GetCalendar(ctx, calendarID)
	if err != nil {
		return nil, calendar.Calendar{}, err
	}
	entAcc := entCal.Edges.Account
	if entAcc == nil {
		return nil, calendar.Calendar{}, errors.New("calendar has no account")
	}
	if entCal.ReadOnly {
		return nil, calendar.Calendar{}, fmt.Errorf("calendar %q is read-only", entCal.Name)
	}

	domAcc := calendar.Account{
		ID:          entAcc.ID,
		Kind:        calendar.AccountKind(entAcc.Kind),
		DisplayName: entAcc.DisplayName,
		Settings:    entAcc.Settings,
	}
	provider, err := deps.Registry.Build(ctx, domAcc, deps.Secrets)
	if err != nil {
		return nil, calendar.Calendar{}, err
	}

	domCal := calendar.Calendar{
		ID:                  entCal.ID,
		AccountID:           entAcc.ID,
		RemoteID:            entCal.RemoteID,
		Name:                entCal.Name,
		TimeZone:            entCal.TimeZone,
		ReadOnly:            entCal.ReadOnly,
		SupportedComponents: entCal.SupportedComponents,
	}
	return provider, domCal, nil
}

// exDateValue formats an occurrence start as an EXDATE property value in the
// UTC forms the expander compares against.
func exDateValue(occStart time.Time, allDay bool) string {
	if allDay {
		return occStart.UTC().Format("20060102")
	}
	return occStart.UTC().Format("20060102T150405Z")
}

// allDayDate pins an all-day instant to UTC midnight of the calendar date it
// was written with, so a client's local offset never shifts the day.
func allDayDate(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

func parseOccurrenceStart(raw string, allDay bool) (time.Time, error) {
	t, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		return time.Time{}, fmt.Errorf("occurrenceStart must be RFC3339: %v", err)
	}
	if allDay {
		return allDayDate(t), nil
	}
	return t, nil
}

func shiftSeriesTimes(ev calendar.Event, masterStart, occurrenceStart time.Time) calendar.Event {
	duration := ev.End.Sub(ev.Start)
	ev.Start = masterStart.Add(ev.Start.Sub(occurrenceStart))
	ev.End = ev.Start.Add(duration)
	return ev
}

// eventFromParams overlays request params onto base; only provided keys win.
func eventFromParams(base calendar.Event, p map[string]any) (calendar.Event, error) {
	if _, ok := p["summary"]; ok {
		base.Summary = ParamString(p, "summary")
	}
	if _, ok := p["description"]; ok {
		base.Description = ParamString(p, "description")
	}
	if _, ok := p["location"]; ok {
		base.Location = ParamString(p, "location")
	}
	if _, ok := p["allDay"]; ok {
		base.AllDay = ParamBool(p, "allDay")
	}
	if _, ok := p["status"]; ok {
		switch ParamString(p, "status") {
		case "tentative":
			base.Status = calendar.EventTentative
		case "cancelled":
			base.Status = calendar.EventCancelled
		default:
			base.Status = calendar.EventConfirmed
		}
	}
	if _, ok := p["transparency"]; ok {
		transparency, err := transparencyFromParam(ParamString(p, "transparency"))
		if err != nil {
			return base, err
		}
		base.Transparency = transparency
	}

	if raw, ok := p["reminders"]; ok {
		rems, err := remindersFromParam(raw)
		if err != nil {
			return base, err
		}
		base.Reminders = rems
	}

	if raw, ok := p["recurrence"]; ok {
		base.Recurrence = recurrenceFromParam(base.Recurrence, raw)
	}

	for key, dst := range map[string]*time.Time{"start": &base.Start, "end": &base.End} {
		raw := ParamString(p, key)
		if raw == "" {
			continue
		}
		t, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			return base, fmt.Errorf("%s must be RFC3339: %v", key, err)
		}
		if base.AllDay {
			t = allDayDate(t)
		}
		*dst = t
	}

	if base.End.Before(base.Start) {
		return base, errors.New("end must not be before start")
	}
	return base, nil
}

// transparencyFromParam reads the iCalendar TRANSP values, or the plainer
// busy/free. An empty value leaves the field unset, which providers treat
// as busy.
func transparencyFromParam(raw string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "":
		return "", nil
	case "opaque", "busy":
		return "opaque", nil
	case "transparent", "free":
		return "transparent", nil
	default:
		return "", fmt.Errorf("transparency must be opaque or transparent, got %q", raw)
	}
}

// remindersFromParam parses the wire form: an array of {method?, minutes}
// objects. An empty array clears the event's reminders.
func remindersFromParam(raw any) ([]calendar.Reminder, error) {
	switch v := raw.(type) {
	case nil:
		return nil, nil
	case []any:
		out := make([]calendar.Reminder, 0, len(v))
		for _, item := range v {
			entry, ok := item.(map[string]any)
			if !ok {
				return nil, errors.New("reminders entries must be objects")
			}
			minutes, ok := reminderMinutes(entry["minutes"])
			if !ok {
				return nil, errors.New("reminder minutes must be a number")
			}
			method, _ := entry["method"].(string)
			if method == "" {
				method = "popup"
			}
			related, _ := entry["related"].(string)
			out = append(out, calendar.Reminder{Method: method, Minutes: minutes, Related: related})
		}
		return out, nil
	default:
		return nil, errors.New("reminders must be an array")
	}
}

func reminderMinutes(raw any) (int, bool) {
	switch v := raw.(type) {
	case int:
		return v, true
	case int64:
		return int(v), true
	case float64:
		return int(v), true
	default:
		return 0, false
	}
}

func domainEventFromEnt(e *ent.Event) calendar.Event {
	ev := calendar.Event{
		ID:            e.ID,
		UID:           e.UID,
		RemoteID:      e.RemoteID,
		Etag:          e.Etag,
		Summary:       e.Summary,
		Description:   e.Description,
		Location:      e.Location,
		URL:           e.URL,
		MeetingURL:    e.MeetingURL,
		Status:        calendar.EventStatus(e.Status),
		Start:         e.Start,
		End:           e.End,
		AllDay:        e.AllDay,
		StartTimeZone: e.StartTz,
		EndTimeZone:   e.EndTz,
		Recurrence:    calendar.RecurrenceFromMap(e.Recurrence),
		RecurringID:   e.RecurringID,
		Reminders:     calendar.RemindersFromMaps(e.Reminders),
	}
	if e.OriginalStart != nil {
		ev.OriginalStart = *e.OriginalStart
	}
	return ev
}

func persistEvent(ctx context.Context, deps Deps, calendarID string, ev *calendar.Event) (*ent.Event, error) {
	return deps.Repo.UpsertEvent(ctx, eventconv.UpsertInput(calendarID, ev))
}

func publishEventsChanged(deps Deps, calendarID string) {
	if deps.Bus == nil {
		return
	}
	deps.Bus.Publish("events", map[string]any{"type": "changed", "calendarId": calendarID})
}
