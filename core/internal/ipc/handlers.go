package ipc

import (
	"context"
	"slices"
	"time"

	"github.com/duxlabs-dev/dux-calendar/core/ent"
	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/repo"
)

func HandleCalendars(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	switch req.Method {
	case "calendars.list":
		calendars, err := deps.Repo.ListCalendars(ctx)
		if err != nil {
			w.RespondError(req.ID, err.Error())
			return
		}
		w.Respond(req.ID, mapCalendars(calendars))
	case "calendars.create":
		handleCalendarCreate(ctx, w, req, deps)
	case "calendars.setHidden":
		handleCalendarSetHidden(ctx, w, req, deps)
	case "calendars.setSyncDisabled":
		handleCalendarSetSyncDisabled(ctx, w, req, deps)
	case "calendars.rename":
		handleCalendarRename(ctx, w, req, deps)
	case "calendars.setReminders":
		handleCalendarSetReminders(ctx, w, req, deps)
	case "calendars.delete":
		handleCalendarDelete(ctx, w, req, deps)
	default:
		w.RespondError(req.ID, "unknown calendars method: "+req.Method)
	}
}

func HandleEvents(ctx context.Context, w *ConnWriter, req Request, deps Deps) {
	switch req.Method {
	case "events.list":
		filter := repo.EventFilter{
			Query:            ParamString(req.Params, "query"),
			IncludeRecurring: true,
		}
		if from := ParamString(req.Params, "from"); from != "" {
			if t, err := time.Parse(time.RFC3339, from); err == nil {
				filter.From = &t
			}
		}
		if to := ParamString(req.Params, "to"); to != "" {
			if t, err := time.Parse(time.RFC3339, to); err == nil {
				filter.To = &t
			}
		}

		events, total, err := deps.Repo.ListEvents(ctx, repo.ListEventsParams{
			Filter: filter,
			Limit:  ParamInt(req.Params, "limit"),
			Offset: ParamInt(req.Params, "offset"),
		})
		if err != nil {
			w.RespondError(req.ID, err.Error())
			return
		}
		w.Respond(req.ID, map[string]any{"events": mapEvents(events), "total": total})
	case "events.get":
		uid := ParamString(req.Params, "uid")
		if uid == "" {
			w.RespondError(req.ID, "events.get requires a uid")
			return
		}
		e, err := deps.Repo.GetEventByUID(ctx, uid, ParamString(req.Params, "calendarId"))
		if err != nil {
			w.RespondError(req.ID, err.Error())
			return
		}
		if start := ParamString(req.Params, "start"); start != "" && len(e.Recurrence) > 0 {
			if t, perr := time.Parse(time.RFC3339, start); perr == nil {
				e.End = t.Add(e.End.Sub(e.Start))
				e.Start = t
			}
		}
		w.Respond(req.ID, mapEvent(e))
	case "events.create":
		handleEventCreate(ctx, w, req, deps)
	case "events.update":
		handleEventUpdate(ctx, w, req, deps)
	case "events.delete":
		handleEventDelete(ctx, w, req, deps)
	case "events.rsvp":
		handleEventRSVP(ctx, w, req, deps)
	case "events.parseIcs":
		handleEventsParseIcs(ctx, w, req, deps)
	case "events.importIcs":
		handleEventsImportIcs(ctx, w, req, deps)
	default:
		w.RespondError(req.ID, "unknown events method: "+req.Method)
	}
}

func mapAccounts(items []*ent.Account) []map[string]any {
	out := make([]map[string]any, 0, len(items))
	for _, a := range items {
		out = append(out, mapAccount(a))
	}
	return out
}

func mapAccount(a *ent.Account) map[string]any {
	return map[string]any{
		"id":          a.ID,
		"kind":        string(a.Kind),
		"displayName": a.DisplayName,
		"settings":    a.Settings,
		"needsReauth": a.NeedsReauth,
		"authError":   a.AuthError,
		"notice":      a.SyncNotice,
		"createdAt":   a.CreatedAt,
		"updatedAt":   a.UpdatedAt,
	}
}

func mapCalendars(items []*ent.Calendar) []map[string]any {
	out := make([]map[string]any, 0, len(items))
	for _, c := range items {
		name := c.Name
		if c.NameOverride != "" {
			name = c.NameOverride
		}
		entry := map[string]any{
			"id":                  c.ID,
			"remoteId":            c.RemoteID,
			"name":                name,
			"providerName":        c.Name,
			"description":         c.Description,
			"color":               c.Color,
			"timeZone":            c.TimeZone,
			"readOnly":            c.ReadOnly,
			"hidden":              c.Hidden,
			"syncDisabled":        c.SyncDisabled,
			"reminders":           c.ReminderOverrides,
			"supportedComponents": c.SupportedComponents,
			"holdsTasks":          slices.Contains(c.SupportedComponents, calendar.ComponentVTodo),
			"updatedAt":           c.UpdatedAt,
		}
		if acc := c.Edges.Account; acc != nil {
			entry["accountId"] = acc.ID
			entry["accountKind"] = string(acc.Kind)
			entry["accountName"] = acc.DisplayName
		}
		out = append(out, entry)
	}
	return out
}

func mapEvents(items []*ent.Event) []map[string]any {
	out := make([]map[string]any, 0, len(items))
	for _, e := range items {
		out = append(out, mapEvent(e))
	}
	return out
}

func mapEvent(e *ent.Event) map[string]any {
	entry := map[string]any{
		"id":          e.ID,
		"uid":         e.UID,
		"summary":     e.Summary,
		"description": e.Description,
		"location":    e.Location,
		"url":         e.URL,
		"meetingUrl":  e.MeetingURL,
		"start":       e.Start,
		"end":         e.End,
		"allDay":      e.AllDay,
		"status":      string(e.Status),
		"recurringId": e.RecurringID,
		"visibility":  e.Visibility,
	}
	if cal := e.Edges.Calendar; cal != nil {
		entry["calendarId"] = cal.ID
	}
	if len(e.Attendees) > 0 {
		entry["attendees"] = e.Attendees
	}
	if len(e.Organizer) > 0 {
		entry["organizer"] = e.Organizer
	}
	if len(e.Recurrence) > 0 {
		entry["recurrence"] = e.Recurrence
	}
	if len(e.Reminders) > 0 {
		entry["reminders"] = e.Reminders
	}
	if e.OriginalStart != nil {
		entry["originalStart"] = e.OriginalStart
	}
	return entry
}
