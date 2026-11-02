package repo

import (
	"context"
	"sort"
	"time"

	"entgo.io/ent/dialect/sql"

	"github.com/duxlabs-dev/dux-calendar/core/ent"
	"github.com/duxlabs-dev/dux-calendar/core/ent/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/ent/event"
	"github.com/duxlabs-dev/dux-calendar/core/ent/predicate"
	"github.com/duxlabs-dev/dux-calendar/core/internal/recurrence"
	"github.com/duxlabs-dev/dux-go/errdefs"
)

type EventFilter struct {
	CalendarIDs      []string
	From             *time.Time
	To               *time.Time
	Query            string
	IncludeRecurring bool
}

type ListEventsParams struct {
	Filter EventFilter
	Limit  int
	Offset int
}

func (r *Repo) GetEvent(ctx context.Context, id string) (*ent.Event, error) {
	e, err := r.client.Event.Query().Where(event.IDEQ(id)).WithCalendar().Only(ctx)
	switch {
	case ent.IsNotFound(err):
		return nil, errdefs.NewCustomError(errdefs.ErrTypeNotFound, "event not found")
	case err != nil:
		return nil, err
	}
	return e, nil
}

func (r *Repo) ListEvents(ctx context.Context, p ListEventsParams) ([]*ent.Event, int, error) {
	if p.Filter.IncludeRecurring && p.Filter.From != nil && p.Filter.To != nil {
		return r.listEventsExpanded(ctx, p)
	}

	q := r.client.Event.Query().Where(baseEventPredicates(p.Filter)...)

	total, err := q.Clone().Count(ctx)
	if err != nil {
		return nil, 0, err
	}

	q = q.WithCalendar().Order(ent.Asc(event.FieldStart))

	if p.Limit > 0 {
		q = q.Limit(p.Limit)
	}
	if p.Offset > 0 {
		q = q.Offset(p.Offset)
	}

	events, err := q.All(ctx)
	if err != nil {
		return nil, 0, err
	}
	return events, total, nil
}

// listEventsExpanded materializes recurring series into per-occurrence events
// within the requested window. Recurring masters never match a future window
// by their stored start/end, so they are expanded here instead of returned
// directly; rows overriding an occurrence (recurring_id set) come back from
// the concrete query and suppress the generated occurrence they replace.
func (r *Repo) listEventsExpanded(ctx context.Context, p ListEventsParams) ([]*ent.Event, int, error) {
	from, to := p.Filter.From.UTC(), p.Filter.To.UTC()

	concrete, err := r.client.Event.Query().
		Where(baseEventPredicates(p.Filter)...).
		Where(event.StatusNEQ(event.StatusCancelled), recurrenceIsNil()).
		WithCalendar().
		All(ctx)
	if err != nil {
		return nil, 0, err
	}

	masters, err := r.client.Event.Query().
		Where(scopeEventPredicates(p.Filter)...).
		Where(event.StartLTE(to), recurrenceNotNil()).
		WithCalendar().
		All(ctx)
	if err != nil {
		return nil, 0, err
	}

	suppressed, err := r.overriddenOccurrences(ctx, p.Filter)
	if err != nil {
		return nil, 0, err
	}

	out := concrete
	for _, master := range masters {
		out = append(out, expandMaster(master, from, to, suppressed)...)
	}

	sort.Slice(out, func(i, j int) bool { return out[i].Start.Before(out[j].Start) })

	total := len(out)
	if p.Offset > 0 {
		if p.Offset >= total {
			return nil, total, nil
		}
		out = out[p.Offset:]
	}
	if p.Limit > 0 && len(out) > p.Limit {
		out = out[:p.Limit]
	}
	return out, total, nil
}

func expandMaster(master *ent.Event, from, to time.Time, suppressed map[string]struct{}) []*ent.Event {
	tz := master.StartTz
	if tz == "" && master.Edges.Calendar != nil {
		tz = master.Edges.Calendar.TimeZone
	}

	series := recurrence.Series{
		Start:    master.Start,
		AllDay:   master.AllDay,
		TimeZone: tz,
		RRule:    recurrenceStrings(master.Recurrence, "rrule"),
		RDate:    recurrenceStrings(master.Recurrence, "rdate"),
		ExDate:   recurrenceStrings(master.Recurrence, "exdate"),
	}

	duration := master.End.Sub(master.Start)
	starts, err := recurrence.Expand(series, from.Add(-duration), to)
	if err != nil {
		// Unexpandable series: fall back to the stored row when it overlaps.
		if master.End.After(from) && master.Start.Before(to) {
			return []*ent.Event{master}
		}
		return nil
	}

	calID := ""
	if master.Edges.Calendar != nil {
		calID = master.Edges.Calendar.ID
	}

	out := make([]*ent.Event, 0, len(starts))
	for _, start := range starts {
		if !start.Add(duration).After(from) || !start.Before(to) {
			continue
		}
		if _, ok := suppressed[occurrenceKey(calID, master.UID, start)]; ok {
			continue
		}
		if start.Equal(master.Start) {
			out = append(out, master)
			continue
		}
		occ := *master
		occ.RecurringID = master.UID
		occ.Start = start.UTC()
		occ.End = start.Add(duration).UTC()
		out = append(out, &occ)
	}
	return out
}

// overriddenOccurrences keys every stored recurrence exception by the
// occurrence it replaces, so expansion can skip moved or cancelled instances.
func (r *Repo) overriddenOccurrences(ctx context.Context, f EventFilter) (map[string]struct{}, error) {
	exceptions, err := r.client.Event.Query().
		Where(scopeEventPredicates(f)...).
		Where(event.RecurringIDNEQ("")).
		WithCalendar().
		All(ctx)
	if err != nil {
		return nil, err
	}

	out := make(map[string]struct{}, len(exceptions))
	for _, e := range exceptions {
		calID := ""
		if e.Edges.Calendar != nil {
			calID = e.Edges.Calendar.ID
		}
		original := e.Start
		if e.OriginalStart != nil {
			original = *e.OriginalStart
		}
		out[occurrenceKey(calID, e.RecurringID, original)] = struct{}{}
	}
	return out, nil
}

func occurrenceKey(calendarID, seriesUID string, start time.Time) string {
	return calendarID + "\x00" + seriesUID + "\x00" + start.UTC().Format(time.RFC3339)
}

// baseEventPredicates applies the full filter, including the time window.
func baseEventPredicates(f EventFilter) []predicate.Event {
	preds := scopeEventPredicates(f)
	switch {
	case f.From != nil && f.To != nil:
		preds = append(preds, event.EndGTE(*f.From), event.StartLTE(*f.To))
	case f.From != nil:
		preds = append(preds, event.EndGTE(*f.From))
	case f.To != nil:
		preds = append(preds, event.StartLTE(*f.To))
	}
	return preds
}

// scopeEventPredicates applies calendar and text filters only.
func scopeEventPredicates(f EventFilter) []predicate.Event {
	var preds []predicate.Event
	if len(f.CalendarIDs) > 0 {
		preds = append(preds, event.HasCalendarWith(calendar.IDIn(f.CalendarIDs...)))
	}
	if f.Query != "" {
		preds = append(preds, event.Or(
			event.SummaryContainsFold(f.Query),
			event.DescriptionContainsFold(f.Query),
			event.LocationContainsFold(f.Query),
		))
	}
	return preds
}

func recurrenceIsNil() predicate.Event {
	return func(s *sql.Selector) { s.Where(sql.IsNull(s.C(event.FieldRecurrence))) }
}

func recurrenceNotNil() predicate.Event {
	return func(s *sql.Selector) { s.Where(sql.NotNull(s.C(event.FieldRecurrence))) }
}

func recurrenceStrings(rec map[string]any, key string) []string {
	raw, ok := rec[key]
	if !ok {
		return nil
	}

	switch v := raw.(type) {
	case []string:
		return v
	case []any:
		out := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				out = append(out, s)
			}
		}
		return out
	default:
		return nil
	}
}

// ListEventOverrides returns every stored exception of a recurring series.
func (r *Repo) ListEventOverrides(ctx context.Context, calendarID, recurringID string) ([]*ent.Event, error) {
	return r.client.Event.Query().
		Where(
			event.HasCalendarWith(calendar.IDEQ(calendarID)),
			event.RecurringIDEQ(recurringID),
		).
		Order(ent.Asc(event.FieldStart)).
		All(ctx)
}

// GetEventByUID resolves a single event by its iCal UID, optionally scoped to a
// calendar. Recurring occurrences share their master's UID, so callers pass the
// occurrence start to pin the returned row to that instance.
func (r *Repo) GetEventByUID(ctx context.Context, uid, calendarID string) (*ent.Event, error) {
	q := r.client.Event.Query().Where(event.UIDEQ(uid))
	if calendarID != "" {
		q = q.Where(event.HasCalendarWith(calendar.IDEQ(calendarID)))
	}
	e, err := q.WithCalendar().Order(ent.Asc(event.FieldStart)).First(ctx)
	switch {
	case ent.IsNotFound(err):
		return nil, errdefs.NewCustomError(errdefs.ErrTypeNotFound, "event not found")
	case err != nil:
		return nil, err
	}
	return e, nil
}

func (r *Repo) FindEventByUID(ctx context.Context, calendarID, uid string) (*ent.Event, error) {
	e, err := r.client.Event.Query().
		Where(
			event.HasCalendarWith(calendar.IDEQ(calendarID)),
			event.UIDEQ(uid),
		).
		Only(ctx)
	switch {
	case ent.IsNotFound(err):
		return nil, errdefs.NewCustomError(errdefs.ErrTypeNotFound, "event not found")
	case err != nil:
		return nil, err
	}
	return e, nil
}
