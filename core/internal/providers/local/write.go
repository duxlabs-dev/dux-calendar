package local

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	ical "github.com/emersion/go-ical"
	"github.com/google/uuid"

	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/icalconv"
)

// emptyCalendar is written when a file calendar loses its last event: the file
// is the calendar, so it must survive, but the encoder rejects a childless one.
const emptyCalendar = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//dankcalendar//dankcalendar//EN\r\nEND:VCALENDAR\r\n"

var filenameSanitizer = strings.NewReplacer(
	"/", "_", "\\", "_", ":", "_", "*", "_", "?", "_",
	"\"", "_", "<", "_", ">", "_", "|", "_", "\x00", "_",
)

func (p *Provider) CreateEvent(ctx context.Context, cal calendar.Calendar, ev *calendar.Event) (*calendar.Event, error) {
	source, err := p.calendarPath(cal)
	if err != nil {
		return nil, err
	}

	uid := ev.UID
	if uid == "" {
		uid = uuid.NewString()
	}

	switch {
	case strings.HasPrefix(cal.RemoteID, "dir:"):
		err = createInDirectory(source, uid, ev)
	default:
		err = createInFile(source, uid, ev)
	}
	if err != nil {
		return nil, err
	}
	return storedEvent(cal, uid, ev), nil
}

func (p *Provider) ImportEvent(ctx context.Context, cal calendar.Calendar, ev *calendar.Event) (*calendar.Event, error) {
	return p.CreateEvent(ctx, cal, ev)
}

func (p *Provider) UpdateEvent(ctx context.Context, cal calendar.Calendar, ev *calendar.Event) (*calendar.Event, error) {
	if ev.UID == "" && ev.RecurringID == "" {
		return nil, fmt.Errorf("event missing UID")
	}
	source, err := p.calendarPath(cal)
	if err != nil {
		return nil, err
	}

	lookupUID := ev.UID
	if ev.RecurringID != "" {
		lookupUID = ev.RecurringID
	}

	path := source
	var doc *ical.Calendar
	switch {
	case strings.HasPrefix(cal.RemoteID, "dir:"):
		path, doc, err = findComponentFile(source, ical.CompEvent, lookupUID)
	default:
		doc, err = loadCalendarDoc(source)
	}
	if err != nil {
		return nil, err
	}

	if ev.RecurringID != "" && !ev.OriginalStart.IsZero() {
		rid, err := icalconv.ApplyEventOverride(doc, ev)
		if err != nil {
			return nil, err
		}
		if err := writeAtomic(path, doc); err != nil {
			return nil, err
		}
		return storedOverride(cal, ev, rid), nil
	}

	if !replaceComponent(doc, ical.CompEvent, ev.UID, icalconv.BuildEvent(ev, ev.UID).Component) {
		return nil, fmt.Errorf("event not found")
	}
	if err := writeAtomic(path, doc); err != nil {
		return nil, err
	}
	return storedEvent(cal, ev.UID, ev), nil
}

func storedOverride(cal calendar.Calendar, ev *calendar.Event, rid string) *calendar.Event {
	out := *ev
	out.CalendarID = cal.ID
	out.UID = ev.RecurringID + "/" + rid
	out.RemoteID = ev.RecurringID
	return &out
}

func (p *Provider) DeleteEvent(ctx context.Context, cal calendar.Calendar, ev calendar.Event) error {
	if ev.UID == "" {
		return fmt.Errorf("event missing UID")
	}
	source, err := p.calendarPath(cal)
	if err != nil {
		return err
	}

	switch {
	case strings.HasPrefix(cal.RemoteID, "dir:"):
		return deleteInDirectory(source, ev.UID)
	default:
		return deleteInFile(source, ev.UID)
	}
}

func createInDirectory(dir, uid string, ev *calendar.Event) error {
	path := filepath.Join(dir, filenameSanitizer.Replace(uid)+".ics")
	switch _, err := os.Stat(path); {
	case err == nil:
		return fmt.Errorf("event %q already exists", uid)
	case !errors.Is(err, os.ErrNotExist):
		return fmt.Errorf("stat %q: %w", path, err)
	}

	doc := icalconv.NewCalendar()
	doc.Children = append(doc.Children, icalconv.BuildEvent(ev, uid).Component)
	return writeAtomic(path, doc)
}

func createInFile(path, uid string, ev *calendar.Event) error {
	doc, err := loadCalendarDoc(path)
	switch {
	case errors.Is(err, os.ErrNotExist):
		doc = icalconv.NewCalendar()
	case err != nil:
		return err
	}

	if findComponent(doc, ical.CompEvent, uid) != nil {
		return fmt.Errorf("event %q already exists", uid)
	}
	doc.Children = append(doc.Children, icalconv.BuildEvent(ev, uid).Component)
	return writeAtomic(path, doc)
}

func deleteInDirectory(dir, uid string) error {
	path, doc, err := findComponentFile(dir, ical.CompEvent, uid)
	if err != nil {
		return err
	}

	removeComponent(doc, ical.CompEvent, uid)
	if len(doc.Children) == 0 {
		return os.Remove(path)
	}
	return writeAtomic(path, doc)
}

func deleteInFile(path, uid string) error {
	doc, err := loadCalendarDoc(path)
	if err != nil {
		return err
	}
	if !removeComponent(doc, ical.CompEvent, uid) {
		return fmt.Errorf("event not found")
	}
	return writeAtomic(path, doc)
}

func findComponentFile(dir, name, uid string) (string, *ical.Calendar, error) {
	fast := filepath.Join(dir, filenameSanitizer.Replace(uid)+".ics")
	if doc, err := loadCalendarDoc(fast); err == nil && findComponent(doc, name, uid) != nil {
		return fast, doc, nil
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", nil, err
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(strings.ToLower(entry.Name()), ".ics") {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		doc, err := loadCalendarDoc(path)
		if err != nil {
			return "", nil, err
		}
		if findComponent(doc, name, uid) != nil {
			return path, doc, nil
		}
	}
	return "", nil, fmt.Errorf("%s not found", strings.ToLower(name))
}

func loadCalendarDoc(path string) (*ical.Calendar, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	doc, err := ical.NewDecoder(f).Decode()
	if err != nil {
		return nil, fmt.Errorf("parse %q: %w", path, err)
	}
	return doc, nil
}

func findComponent(doc *ical.Calendar, name, uid string) *ical.Component {
	for _, child := range doc.Children {
		if child.Name == name && icalconv.ComponentUID(child) == uid {
			return child
		}
	}
	return nil
}

func replaceComponent(doc *ical.Calendar, name, uid string, newChild *ical.Component) bool {
	for i, child := range doc.Children {
		if child.Name != name || icalconv.ComponentUID(child) != uid {
			continue
		}
		doc.Children[i] = newChild
		return true
	}
	return false
}

func removeComponent(doc *ical.Calendar, name, uid string) bool {
	for i, child := range doc.Children {
		if child.Name != name || icalconv.ComponentUID(child) != uid {
			continue
		}
		doc.Children = append(doc.Children[:i], doc.Children[i+1:]...)
		return true
	}
	return false
}

func storedEvent(cal calendar.Calendar, uid string, ev *calendar.Event) *calendar.Event {
	out := *ev
	out.CalendarID = cal.ID
	out.UID = uid
	out.RemoteID = uid
	return &out
}

func writeAtomic(path string, doc *ical.Calendar) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, ".dankcal-*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())

	if err := encodeCalendar(tmp, doc); err != nil {
		tmp.Close()
		return fmt.Errorf("serialize %q: %w", path, err)
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

func encodeCalendar(w io.Writer, doc *ical.Calendar) error {
	if len(doc.Children) == 0 {
		_, err := io.WriteString(w, emptyCalendar)
		return err
	}
	return ical.NewEncoder(w).Encode(doc)
}
