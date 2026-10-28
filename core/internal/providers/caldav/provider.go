package caldav

import (
	"context"
	"crypto/tls"
	"encoding/xml"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	ical "github.com/emersion/go-ical"
	"github.com/emersion/go-webdav"
	"github.com/emersion/go-webdav/caldav"
	"github.com/google/uuid"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/httpauth"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/icalconv"
	"github.com/duxlabs-dev/dux-go/log"
)

type Provider struct {
	account    cal.Account
	client     *caldav.Client
	httpClient webdav.HTTPClient
	endpoint   *url.URL
	homeSet    string
	username   string
	notices    []string
}

func (p *Provider) Notices() []string { return p.notices }

func New(ctx context.Context, account cal.Account, secrets cal.SecretStore, baseURL, username string) (*Provider, error) {
	password, err := secrets.Get(ctx, account.ID, SecretKeyPassword)
	if err != nil {
		return nil, fmt.Errorf("caldav password not stored for %q: %w", account.ID, err)
	}

	endpoint, err := url.Parse(baseURL)
	if err != nil {
		return nil, fmt.Errorf("parse caldav url: %w", err)
	}

	httpClient := newHTTPClient(account, username, string(password))
	client, endpoint, homeSet, err := discover(ctx, httpClient, endpoint)
	if err != nil {
		return nil, err
	}

	return &Provider{
		account:    account,
		client:     client,
		httpClient: httpClient,
		endpoint:   endpoint,
		homeSet:    homeSet,
		username:   username,
	}, nil
}

// discover walks the RFC 6764 §6 bootstrap order: the URL as entered, then
// /.well-known/caldav, then the server root. OpenCloud (#38) only answers at
// the well-known URI via redirect, Synology DSM (#91) answers it in place.
// Servers without current-user-principal still expose calendar-home-set on
// the entered URL, which Thunderbird's detector also falls back to.
func discover(ctx context.Context, hc webdav.HTTPClient, endpoint *url.URL) (*caldav.Client, *url.URL, string, error) {
	var errs []error
	for _, candidate := range discoveryCandidates(endpoint) {
		client, err := caldav.NewClient(hc, candidate.String())
		if err != nil {
			return nil, nil, "", fmt.Errorf("init caldav client: %w", err)
		}
		principal, err := client.FindCurrentUserPrincipal(ctx)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", candidate.Path, err))
			continue
		}
		homeSet, err := client.FindCalendarHomeSet(ctx, principal)
		if err != nil {
			return nil, nil, "", fmt.Errorf("find caldav home set: %w", err)
		}
		if candidate != endpoint {
			log.Debugf("caldav: principal for %q discovered at %q", endpoint, candidate)
		}
		return client, candidate, homeSet, nil
	}

	client, err := caldav.NewClient(hc, endpoint.String())
	if err != nil {
		return nil, nil, "", fmt.Errorf("init caldav client: %w", err)
	}
	homeSet, err := client.FindCalendarHomeSet(ctx, "")
	if err == nil {
		return client, endpoint, homeSet, nil
	}
	errs = append(errs, fmt.Errorf("%s calendar-home-set: %w", endpoint.Path, err))
	return nil, nil, "", fmt.Errorf("find caldav principal: %w", errors.Join(errs...))
}

func discoveryCandidates(endpoint *url.URL) []*url.URL {
	candidates := []*url.URL{endpoint}
	for _, path := range []string{"/.well-known/caldav", "/"} {
		if strings.Trim(endpoint.Path, "/") == strings.Trim(path, "/") {
			continue
		}
		candidates = append(candidates, &url.URL{Scheme: endpoint.Scheme, Host: endpoint.Host, Path: path})
	}
	return candidates
}

// newHTTPClient returns the HTTP client the caldav client is built on,
// wrapped so redirects keep their method and non-compliant ETags and
// getlastmodified dates get repaired before go-webdav parses them.
// Authentication sits innermost so every redirect hop signs its own URI;
// Baïkal (#98) only accepts Digest.
// Servers with self-signed certificates opt out of TLS verification via the
// SettingInsecureSkipVerify account setting.
func newHTTPClient(account cal.Account, username, password string) *http.Client {
	var base = http.DefaultTransport
	if insecure, _ := account.Settings[SettingInsecureSkipVerify].(bool); insecure {
		transport := http.DefaultTransport.(*http.Transport).Clone()
		transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
		base = transport
	}
	auth := &httpauth.Transport{Base: base, Username: username, Password: password}
	return &http.Client{
		Transport: normalizingTransport{base: redirectFollowingTransport{base: auth}},
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
}

func (p *Provider) Kind() cal.AccountKind { return cal.AccountCalDAV }
func (p *Provider) Account() cal.Account  { return p.account }

func (p *Provider) ListCalendars(ctx context.Context) ([]cal.Calendar, error) {
	p.notices = nil
	calendars, err := p.client.FindCalendars(ctx, p.homeSet)
	if err != nil {
		return nil, fmt.Errorf("find caldav calendars: %w", err)
	}

	colors, err := p.calendarColors(ctx)
	if err != nil {
		log.Debugf("caldav: calendar-color lookup on %q failed: %v", p.homeSet, err)
	}

	out := make([]cal.Calendar, 0, len(calendars))
	for _, c := range calendars {
		out = append(out, cal.Calendar{
			AccountID:           p.account.ID,
			RemoteID:            c.Path,
			Name:                c.Name,
			Description:         c.Description,
			Color:               colors[strings.TrimSuffix(c.Path, "/")],
			SupportedComponents: c.SupportedComponentSet,
		})
	}
	return out, nil
}

// go-webdav's FindCalendars has no notion of the Apple calendar-color
// extension (emersion/go-webdav#150), so colors come from a separate raw
// PROPFIND. Servers without the property answer with 404 propstats, which
// simply yield no map entry.
const calendarColorsBody = `<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:a="http://apple.com/ns/ical/"><d:prop><a:calendar-color/></d:prop></d:propfind>`

func (p *Provider) calendarColors(ctx context.Context) (map[string]string, error) {
	target := p.endpoint.ResolveReference(&url.URL{Path: p.homeSet})
	req, err := http.NewRequestWithContext(ctx, "PROPFIND", target.String(), strings.NewReader(calendarColorsBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Depth", "1")
	req.Header.Set("Content-Type", "text/xml; charset=utf-8")

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusMultiStatus {
		return nil, fmt.Errorf("propfind %q: %s", p.homeSet, resp.Status)
	}

	var ms struct {
		Responses []struct {
			Href  string `xml:"DAV: href"`
			Props []struct {
				Color string `xml:"http://apple.com/ns/ical/ calendar-color"`
			} `xml:"DAV: propstat>prop"`
		} `xml:"DAV: response"`
	}
	if err := xml.NewDecoder(resp.Body).Decode(&ms); err != nil {
		return nil, fmt.Errorf("decode propfind response: %w", err)
	}

	colors := make(map[string]string, len(ms.Responses))
	for _, r := range ms.Responses {
		href := strings.TrimSpace(r.Href)
		if href == "" {
			continue
		}
		if u, err := url.Parse(href); err == nil {
			href = u.Path
		}
		if unescaped, err := url.PathUnescape(href); err == nil {
			href = unescaped
		}
		for _, prop := range r.Props {
			color := strings.TrimSpace(prop.Color)
			if color == "" {
				continue
			}
			colors[strings.TrimSuffix(href, "/")] = color
			break
		}
	}
	return colors, nil
}

func (p *Provider) Sync(ctx context.Context, c cal.Calendar, cursor cal.SyncCursor) (*cal.SyncResult, error) {
	result := &cal.SyncResult{
		Cursor:       cal.SyncCursor{CalendarID: cursor.CalendarID},
		FullSnapshot: true,
	}

	if c.HoldsEvents() {
		objects, err := p.queryComponents(ctx, c.RemoteID, ical.CompEvent, time.Time{}, time.Time{})
		if err != nil {
			return nil, fmt.Errorf("query caldav events %q: %w", c.RemoteID, err)
		}
		for _, obj := range objects {
			for _, ev := range eventsFromObject(c, obj) {
				result.Changes = append(result.Changes, cal.EventChange{Type: cal.ChangeUpsert, Event: &ev})
			}
		}
	}

	if c.HoldsTasks() {
		objects, err := p.queryComponents(ctx, c.RemoteID, ical.CompToDo, time.Time{}, time.Time{})
		if err != nil {
			return nil, fmt.Errorf("query caldav tasks %q: %w", c.RemoteID, err)
		}
		for _, obj := range objects {
			for _, t := range tasksFromObject(c, obj) {
				p.noticeUpgradedReminders(t)
				result.TaskChanges = append(result.TaskChanges, cal.TaskChange{Type: cal.ChangeUpsert, Task: &t})
			}
		}
	}

	return result, nil
}

// noticeUpgradedReminders flags Apple's placeholder VTODO ("The creator of
// this list has upgraded these reminders.") that iCloud serves instead of
// Reminders lists upgraded past CalDAV access. The support URL in the
// description is the locale-independent marker.
func (p *Provider) noticeUpgradedReminders(t cal.Task) {
	switch {
	case !strings.HasSuffix(p.endpoint.Hostname(), "icloud.com"):
		return
	case !strings.Contains(t.Description, "support.apple.com/HT210220"):
		return
	case slices.Contains(p.notices, cal.NoticeICloudRemindersUpgraded):
		return
	}
	p.notices = append(p.notices, cal.NoticeICloudRemindersUpgraded)
}

func (p *Provider) ListEvents(ctx context.Context, c cal.Calendar, opts cal.ListEventsOptions) ([]cal.Event, error) {
	objects, err := p.queryComponents(ctx, c.RemoteID, ical.CompEvent, opts.Start, opts.End)
	if err != nil {
		return nil, fmt.Errorf("query caldav calendar %q: %w", c.RemoteID, err)
	}

	var events []cal.Event
	for _, obj := range objects {
		events = append(events, eventsFromObject(c, obj)...)
	}
	if opts.Limit > 0 && len(events) > opts.Limit {
		events = events[:opts.Limit]
	}
	return events, nil
}

func (p *Provider) CreateEvent(ctx context.Context, c cal.Calendar, ev *cal.Event) (*cal.Event, error) {
	uid := ev.UID
	if uid == "" {
		uid = uuid.NewString()
	}

	path := objectPath(c.RemoteID, uid)
	etag, err := p.putObject(ctx, path, icalconv.CalendarFromEvent(ev, uid))
	if err != nil {
		return nil, fmt.Errorf("put caldav object %q: %w", path, err)
	}

	out := *ev
	out.UID = uid
	out.RemoteID = path
	out.Etag = etag
	return &out, nil
}

func (p *Provider) ImportEvent(ctx context.Context, c cal.Calendar, ev *cal.Event) (*cal.Event, error) {
	return p.CreateEvent(ctx, c, ev)
}

func (p *Provider) UpdateEvent(ctx context.Context, c cal.Calendar, ev *cal.Event) (*cal.Event, error) {
	if ev.RemoteID == "" {
		return nil, errors.New("caldav update requires remote id")
	}

	etag, err := p.putObject(ctx, ev.RemoteID, icalconv.CalendarFromEvent(ev, ev.UID))
	if err != nil {
		return nil, fmt.Errorf("put caldav object %q: %w", ev.RemoteID, err)
	}

	out := *ev
	out.Etag = etag
	return &out, nil
}

// RespondToEvent patches the user's PARTSTAT inside the stored resource rather
// than rewriting it from the domain event, preserving exception components the
// local model does not carry. Occurrence replies (ev.OriginalStart set) land on
// the matching exception VEVENT, created from the master when needed.
func (p *Provider) RespondToEvent(ctx context.Context, c cal.Calendar, ev *cal.Event, response string) (*cal.Event, error) {
	if ev.RemoteID == "" {
		return nil, errors.New("caldav respond requires remote id")
	}

	doc, err := p.getObject(ctx, ev.RemoteID)
	if err != nil {
		return nil, fmt.Errorf("get caldav object %q: %w", ev.RemoteID, err)
	}

	rid, err := icalconv.ApplyParticipation(doc, ev, p.account.SelfEmail(), response)
	if err != nil {
		return nil, err
	}

	etag, err := p.putObject(ctx, ev.RemoteID, doc)
	if err != nil {
		return nil, fmt.Errorf("put caldav object %q: %w", ev.RemoteID, err)
	}

	out := *ev
	out.Etag = etag
	if rid != "" {
		out.UID = out.RecurringID + "/" + rid
	}
	return &out, nil
}

func (p *Provider) DeleteEvent(ctx context.Context, c cal.Calendar, ev cal.Event) error {
	if ev.RemoteID == "" {
		return errors.New("caldav delete requires remote id")
	}
	if err := p.deleteObject(ctx, ev.RemoteID); err != nil {
		return fmt.Errorf("delete caldav object %q: %w", ev.RemoteID, err)
	}
	return nil
}

func (p *Provider) CreateTask(ctx context.Context, c cal.Calendar, t *cal.Task) (*cal.Task, error) {
	uid := t.UID
	if uid == "" {
		uid = uuid.NewString()
	}

	path := objectPath(c.RemoteID, uid)
	etag, err := p.putObject(ctx, path, icalconv.CalendarFromTask(t, uid))
	if err != nil {
		return nil, fmt.Errorf("put caldav task %q: %w", path, err)
	}

	out := *t
	out.UID = uid
	out.RemoteID = path
	out.Etag = etag
	return &out, nil
}

func (p *Provider) UpdateTask(ctx context.Context, c cal.Calendar, t *cal.Task) (*cal.Task, error) {
	if t.RemoteID == "" {
		return nil, errors.New("caldav update requires remote id")
	}

	etag, err := p.putObject(ctx, t.RemoteID, icalconv.CalendarFromTask(t, t.UID))
	if err != nil {
		return nil, fmt.Errorf("put caldav task %q: %w", t.RemoteID, err)
	}

	out := *t
	out.Etag = etag
	return &out, nil
}

func (p *Provider) DeleteTask(ctx context.Context, c cal.Calendar, t cal.Task) error {
	if t.RemoteID == "" {
		return errors.New("caldav delete requires remote id")
	}
	if err := p.deleteObject(ctx, t.RemoteID); err != nil {
		return fmt.Errorf("delete caldav task %q: %w", t.RemoteID, err)
	}
	return nil
}

func (p *Provider) queryComponents(ctx context.Context, calendarPath, comp string, start, end time.Time) ([]caldav.CalendarObject, error) {
	compFilter := caldav.CompFilter{Name: comp}
	if !start.IsZero() {
		compFilter.Start = start
	}
	if !end.IsZero() {
		compFilter.End = end
	}

	query := &caldav.CalendarQuery{
		CompRequest: caldav.CalendarCompRequest{Name: ical.CompCalendar, AllProps: true, AllComps: true},
		CompFilter:  caldav.CompFilter{Name: ical.CompCalendar, Comps: []caldav.CompFilter{compFilter}},
	}

	// A query is time-bounded when either end of the range is set; a full
	// sync passes neither. Some servers answer a calendar-query without a
	// time-range with only the recurring masters, so an unbounded query
	// skips it and enumerates the collection instead.
	timeBounded := !start.IsZero() || !end.IsZero()

	var queryErr error
	if timeBounded {
		objects, err := p.client.QueryCalendar(ctx, calendarPath, query)
		if err == nil {
			return objects, nil
		}
		queryErr = err
	}

	// Some servers (notably iCloud) refuse to return calendar-data from a
	// calendar-query REPORT; list the collection and multiget instead.
	objects, err := p.multiGetAll(ctx, calendarPath)
	if err != nil {
		return nil, errors.Join(queryErr, err)
	}

	filtered, err := caldav.Filter(query, objects)
	if err != nil {
		return objects, nil
	}
	return filtered, nil
}

func (p *Provider) multiGetAll(ctx context.Context, calendarPath string) ([]caldav.CalendarObject, error) {
	paths, err := p.listObjectPaths(ctx, calendarPath)
	if err != nil {
		return nil, fmt.Errorf("list caldav objects: %w", err)
	}
	if len(paths) == 0 {
		return nil, nil
	}

	var out []caldav.CalendarObject
	for chunk := range slices.Chunk(paths, 50) {
		objs, err := p.multiGet(ctx, calendarPath, chunk)
		switch {
		case err == nil:
		case len(objs) == 0:
			return nil, fmt.Errorf("multiget caldav objects: %w", err)
		default:
			p.noticeItemsSkipped(calendarPath, err)
		}
		out = append(out, objs...)
	}
	return out, nil
}

// multiGet returns the objects it could decode alongside a joined error for
// responses the server refused (iCloud answers 404 for stale invites, #108).
func (p *Provider) noticeItemsSkipped(calendarPath string, err error) {
	log.Warnf("caldav: skipped unreadable objects in %q: %v", calendarPath, err)
	if slices.Contains(p.notices, cal.NoticeItemsSkipped) {
		return
	}
	p.notices = append(p.notices, cal.NoticeItemsSkipped)
}

// Raw PROPFIND asking only for hrefs: go-webdav's higher-level helpers error
// on iCloud's 404 propstats for props we don't even need. Hrefs stay in the
// server's own encoding, see objects.go.
const listObjectsBody = `<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/></d:prop></d:propfind>`

func (p *Provider) listObjectPaths(ctx context.Context, calendarPath string) ([]string, error) {
	target := p.endpoint.ResolveReference(&url.URL{Path: calendarPath})
	req, err := http.NewRequestWithContext(ctx, "PROPFIND", target.String(), strings.NewReader(listObjectsBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Depth", "1")
	req.Header.Set("Content-Type", "text/xml; charset=utf-8")

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusMultiStatus {
		return nil, fmt.Errorf("propfind %q: %s", calendarPath, resp.Status)
	}

	var ms struct {
		Responses []struct {
			Href string `xml:"DAV: href"`
		} `xml:"DAV: response"`
	}
	if err := xml.NewDecoder(resp.Body).Decode(&ms); err != nil {
		return nil, fmt.Errorf("decode propfind response: %w", err)
	}

	normalizedCal := strings.TrimSuffix(calendarPath, "/")
	paths := make([]string, 0, len(ms.Responses))
	for _, r := range ms.Responses {
		u, err := url.Parse(strings.TrimSpace(r.Href))
		if err != nil || u.Path == "" || strings.HasSuffix(u.Path, "/") || strings.TrimSuffix(u.Path, "/") == normalizedCal {
			continue
		}
		paths = append(paths, u.EscapedPath())
	}
	return paths, nil
}

func (p *Provider) Close() error { return nil }
