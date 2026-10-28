package caldav

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/mocks"
)

const principalXML = `<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/</d:href>
    <d:propstat>
      <d:prop>
        <d:current-user-principal><d:href>/dav/principals/user/</d:href></d:current-user-principal>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>`

const homeSetXML = `<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:response>
    <d:href>/dav/principals/user/</d:href>
    <d:propstat>
      <d:prop>
        <c:calendar-home-set><d:href>/dav/calendars/user/</d:href></c:calendar-home-set>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>`

func newSecrets(t *testing.T) cal.SecretStore {
	secrets := mocks.NewMockSecretStore(t)
	secrets.EXPECT().Get(context.Background(), "acc", SecretKeyPassword).Return([]byte("pw"), nil)
	return secrets
}

func writeMultiStatus(w http.ResponseWriter, body string) {
	w.Header().Set("Content-Type", "text/xml; charset=utf-8")
	w.WriteHeader(http.StatusMultiStatus)
	w.Write([]byte(body))
}

// OpenCloud-style server (#38): PROPFIND at the bare host is 405, but the RFC
// 6764 well-known URI redirects to the CalDAV root.
func TestNewFallsBackToWellKnown(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimSuffix(r.URL.Path, "/")
		switch {
		case path == "/.well-known/caldav":
			http.Redirect(w, r, "/dav/", http.StatusMovedPermanently)
		case r.Method == "PROPFIND" && path == "/dav":
			writeMultiStatus(w, principalXML)
		case r.Method == "PROPFIND" && path == "/dav/principals/user":
			writeMultiStatus(w, homeSetXML)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.NoError(t, err)
	assert.Equal(t, "/dav/calendars/user/", p.homeSet)
}

// Synology DSM (#91): nginx answers PROPFIND outside /caldav/<user>/ with a
// static 405, and serves /.well-known/caldav in place instead of redirecting.
func TestNewDiscoversWellKnownServedInPlace(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method != "PROPFIND":
			w.WriteHeader(http.StatusMethodNotAllowed)
		case r.URL.Path == "/.well-known/caldav", r.URL.Path == "/caldav/user/":
			writeMultiStatus(w, principalXML)
		case r.URL.Path == "/dav/principals/user/":
			writeMultiStatus(w, homeSetXML)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.NoError(t, err)
	assert.Equal(t, "/dav/calendars/user/", p.homeSet)

	p, err = New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL+"/caldav/user/", "user")
	require.NoError(t, err)
	assert.Equal(t, "/dav/calendars/user/", p.homeSet)
}

func TestNewFollowsRedirectsKeepingMethod(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		switch {
		case r.Method != "PROPFIND" || len(body) == 0:
			w.WriteHeader(http.StatusMethodNotAllowed)
		case r.URL.Path == "/caldav/user":
			http.Redirect(w, r, "/caldav/user/", http.StatusMovedPermanently)
		case r.URL.Path == "/caldav/user/":
			writeMultiStatus(w, principalXML)
		case r.URL.Path == "/dav/principals/user/":
			writeMultiStatus(w, homeSetXML)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL+"/caldav/user", "user")
	require.NoError(t, err)
	assert.Equal(t, "/dav/calendars/user/", p.homeSet)
}

func TestNewFallsBackToHomeSetWithoutPrincipal(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == "PROPFIND" && r.URL.Path == "/dav/":
			writeMultiStatus(w, homeSetXML)
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL+"/dav/", "user")
	require.NoError(t, err)
	assert.Equal(t, "/dav/calendars/user/", p.homeSet)
}

// A self-signed TLS server stands in for a Nextcloud/self-hosted instance (#50):
// verification fails by default, and SettingInsecureSkipVerify opts out of it.
func TestNewSkipsCertificateVerification(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimSuffix(r.URL.Path, "/")
		switch {
		case r.Method == "PROPFIND" && path == "":
			writeMultiStatus(w, principalXML)
		case r.Method == "PROPFIND" && path == "/dav/principals/user":
			writeMultiStatus(w, homeSetXML)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	_, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "certificate")

	insecure := cal.Account{ID: "acc", Settings: map[string]any{SettingInsecureSkipVerify: true}}
	p, err := New(context.Background(), insecure, newSecrets(t), server.URL, "user")
	require.NoError(t, err)
	assert.Equal(t, "/dav/calendars/user/", p.homeSet)
}

const calendarsXML = `<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:response>
    <d:href>/dav/calendars/user/</d:href>
    <d:propstat>
      <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/calendars/user/personal/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
        <d:displayname>Personal</d:displayname>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/calendars/user/work/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
        <d:displayname>Work</d:displayname>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>`

// Fastmail-style color response: one calendar carries the Apple extension with
// an alpha suffix, the other reports the property as 404.
const colorsXML = `<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:a="http://apple.com/ns/ical/">
  <d:response>
    <d:href>/dav/calendars/user/personal/</d:href>
    <d:propstat>
      <d:prop><a:calendar-color>#3A429CFF</a:calendar-color></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/calendars/user/work/</d:href>
    <d:propstat>
      <d:prop><a:calendar-color/></d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>`

func TestListCalendarsReadsAppleColor(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		path := strings.TrimSuffix(r.URL.Path, "/")
		switch {
		case r.Method == "PROPFIND" && path == "":
			writeMultiStatus(w, principalXML)
		case r.Method == "PROPFIND" && path == "/dav/principals/user":
			writeMultiStatus(w, homeSetXML)
		case r.Method == "PROPFIND" && path == "/dav/calendars/user" && strings.Contains(string(body), "calendar-color"):
			writeMultiStatus(w, colorsXML)
		case r.Method == "PROPFIND" && path == "/dav/calendars/user":
			writeMultiStatus(w, calendarsXML)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.NoError(t, err)

	cals, err := p.ListCalendars(context.Background())
	require.NoError(t, err)
	require.Len(t, cals, 2)

	byName := map[string]cal.Calendar{}
	for _, c := range cals {
		byName[c.Name] = c
	}
	assert.Equal(t, "#3A429CFF", byName["Personal"].Color)
	assert.Empty(t, byName["Work"].Color)
}

func TestNewReportsPrincipalErrorWithoutWellKnown(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/caldav":
			http.NotFound(w, r)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()

	_, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "find caldav principal")
	assert.Contains(t, err.Error(), "405")
}

// Baïkal behind nginx (#98): PROPFIND on the entered URL and the root are
// 405 from nginx, the well-known URI redirects into sabre/dav, and sabre only
// accepts Digest credentials.
func TestNewAuthenticatesWithDigest(t *testing.T) {
	const nonce = "nonce-1"
	fieldRe := regexp.MustCompile(`(\w+)=(?:"([^"]*)"|([^\s,]+))`)
	md5hex := func(s string) string {
		sum := md5.Sum([]byte(s))
		return hex.EncodeToString(sum[:])
	}
	authorized := func(r *http.Request) bool {
		parts := map[string]string{}
		for _, m := range fieldRe.FindAllStringSubmatch(strings.TrimPrefix(r.Header.Get("Authorization"), "Digest "), -1) {
			parts[m[1]] = m[2] + m[3]
		}
		a1 := md5hex(parts["username"] + ":BaikalDAV:pw")
		a2 := md5hex(r.Method + ":" + parts["uri"])
		expected := md5hex(strings.Join([]string{a1, nonce, parts["nc"], parts["cnonce"], parts["qop"], a2}, ":"))
		return parts["response"] == expected
	}
	var challenges, basicAttempts int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.Header.Get("Authorization"), "Basic ") {
			basicAttempts++
		}
		switch {
		case r.URL.Path == "/" || r.URL.Path == "/baikal/":
			w.WriteHeader(http.StatusMethodNotAllowed)
		case r.URL.Path == "/.well-known/caldav":
			http.Redirect(w, r, "/dav.php/", http.StatusFound)
		case !authorized(r):
			challenges++
			w.Header().Set("WWW-Authenticate", `Digest realm="BaikalDAV", qop="auth", nonce="`+nonce+`", opaque="op"`)
			w.WriteHeader(http.StatusUnauthorized)
		case r.Method == "PROPFIND" && r.URL.Path == "/dav.php/":
			writeMultiStatus(w, principalXML)
		case r.Method == "PROPFIND" && r.URL.Path == "/dav/principals/user/":
			writeMultiStatus(w, homeSetXML)
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL+"/baikal/", "user")
	require.NoError(t, err)
	assert.Equal(t, "/dav/calendars/user/", p.homeSet)
	assert.Equal(t, 1, challenges)
	assert.Equal(t, 3, basicAttempts)
}

func TestNoticeUpgradedReminders(t *testing.T) {
	placeholder := cal.Task{
		Summary:     "The creator of this list has upgraded these reminders.",
		Description: "Learn more here: https://support.apple.com/HT210220",
	}

	icloud, err := url.Parse("https://p147-caldav.icloud.com")
	require.NoError(t, err)
	p := &Provider{endpoint: icloud}

	p.noticeUpgradedReminders(cal.Task{Summary: "Buy milk"})
	assert.Empty(t, p.Notices())

	p.noticeUpgradedReminders(placeholder)
	p.noticeUpgradedReminders(placeholder)
	assert.Equal(t, []string{cal.NoticeICloudRemindersUpgraded}, p.Notices())

	other, err := url.Parse("https://dav.example.com")
	require.NoError(t, err)
	p = &Provider{endpoint: other}
	p.noticeUpgradedReminders(placeholder)
	assert.Empty(t, p.Notices())
}

const objectListingXML = `<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/calendars/user/cal/</d:href><d:propstat><d:prop/><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/calendars/user/cal/good.ics</d:href><d:propstat><d:prop><d:getetag>"1"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/calendars/user/cal/-963706995%40logmeincom.ics</d:href><d:propstat><d:prop><d:getetag>"2"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</d:multistatus>`

const goodObjectResponseXML = `<d:response>
    <d:href>/dav/calendars/user/cal/good.ics</d:href>
    <d:propstat>
      <d:prop>
        <d:getetag>"1"</d:getetag>
        <c:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:good
DTSTAMP:20260101T000000Z
DTSTART:20260501T100000Z
DTEND:20260501T110000Z
SUMMARY:Good
END:VEVENT
END:VCALENDAR
</c:calendar-data>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>`

const staleObjectResponseXML = `<d:response>
    <d:href>/dav/calendars/user/cal/-963706995%40logmeincom.ics</d:href>
    <d:status>HTTP/1.1 404 Not Found</d:status>
  </d:response>`

func multiStatusXML(responses ...string) string {
	return `<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">` + strings.Join(responses, "\n") + `</d:multistatus>`
}

// iCloud-style server (#108): calendar-query is refused, the multiget answers
// one stale invite with a per-response 404 next to a good object.
func newMultiGetServer(t *testing.T, multiGetBody string) *httptest.Server {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		path := strings.TrimSuffix(r.URL.Path, "/")
		switch {
		case r.Method == "PROPFIND" && path == "":
			writeMultiStatus(w, principalXML)
		case r.Method == "PROPFIND" && path == "/dav/principals/user":
			writeMultiStatus(w, homeSetXML)
		case r.Method == "PROPFIND" && path == "/dav/calendars/user/cal":
			writeMultiStatus(w, objectListingXML)
		case r.Method == "REPORT" && strings.Contains(string(body), "calendar-query"):
			w.WriteHeader(http.StatusForbidden)
		case r.Method == "REPORT" && strings.Contains(string(body), "calendar-multiget"):
			writeMultiStatus(w, multiGetBody)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	t.Cleanup(server.Close)
	return server
}

func TestSyncKeepsObjectsNextToRefusedOnes(t *testing.T) {
	server := newMultiGetServer(t, multiStatusXML(goodObjectResponseXML, staleObjectResponseXML))

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.NoError(t, err)

	result, err := p.Sync(context.Background(), cal.Calendar{RemoteID: "/dav/calendars/user/cal/"}, cal.SyncCursor{})
	require.NoError(t, err)
	require.Len(t, result.Changes, 1)
	assert.Equal(t, "good", result.Changes[0].Event.UID)
	assert.Equal(t, []string{cal.NoticeItemsSkipped}, p.Notices())
}

func TestSyncFailsWhenEveryObjectIsRefused(t *testing.T) {
	server := newMultiGetServer(t, multiStatusXML(staleObjectResponseXML))

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.NoError(t, err)

	_, err = p.Sync(context.Background(), cal.Calendar{RemoteID: "/dav/calendars/user/cal/"}, cal.SyncCursor{})
	require.ErrorContains(t, err, "404")
	assert.Empty(t, p.Notices())
}

const encodedObjectHref = "/dav/calendars/user/cal/abc%40client.ics"

const encodedListingXML = `<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/calendars/user/cal/</d:href><d:propstat><d:prop/><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/calendars/user/cal/abc%40client.ics</d:href><d:propstat><d:prop><d:getetag>"1"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</d:multistatus>`

const encodedObjectResponseXML = `<d:response>
    <d:href>/dav/calendars/user/cal/abc%40client.ics</d:href>
    <d:propstat>
      <d:prop>
        <d:getetag>"1"</d:getetag>
        <c:calendar-data>BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:abc@client
DTSTAMP:20260101T000000Z
DTSTART:20260501T100000Z
DTEND:20260501T110000Z
SUMMARY:Encoded
END:VEVENT
END:VCALENDAR
</c:calendar-data>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>`

const encodedMissingResponseXML = `<d:response>
    <d:href>/dav/calendars/user/cal/abc@client.ics</d:href>
    <d:status>HTTP/1.1 404 Not Found</d:status>
  </d:response>`

const noUIDConflictXML = `<error xmlns="DAV:"><no-uid-conflict xmlns="urn:ietf:params:xml:ns:caldav"><href xmlns="DAV:">/dav/calendars/user/cal/abc%40client.ics</href></no-uid-conflict></error>`

// Stalwart-style server (#141): resource names keep their percent-encoding, so
// "abc@client.ics" and "abc%40client.ics" are different objects.
func newEncodedHrefServer(t *testing.T) *httptest.Server {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		path := strings.TrimSuffix(r.URL.Path, "/")
		switch {
		case r.Method == "PROPFIND" && path == "":
			writeMultiStatus(w, principalXML)
		case r.Method == "PROPFIND" && path == "/dav/principals/user":
			writeMultiStatus(w, homeSetXML)
		case r.Method == "PROPFIND" && path == "/dav/calendars/user/cal":
			writeMultiStatus(w, encodedListingXML)
		case r.Method == "REPORT" && strings.Contains(string(body), "calendar-query"):
			w.WriteHeader(http.StatusForbidden)
		case r.Method == "REPORT" && strings.Contains(string(body), "<d:href>"+encodedObjectHref+"</d:href>"):
			writeMultiStatus(w, multiStatusXML(encodedObjectResponseXML))
		case r.Method == "REPORT":
			writeMultiStatus(w, multiStatusXML(encodedMissingResponseXML))
		case r.URL.EscapedPath() != encodedObjectHref:
			w.Header().Set("Content-Type", "text/xml")
			w.WriteHeader(http.StatusPreconditionFailed)
			w.Write([]byte(noUIDConflictXML))
		case r.Method == "PUT":
			w.Header().Set("ETag", `"2"`)
			w.WriteHeader(http.StatusNoContent)
		case r.Method == "DELETE":
			w.WriteHeader(http.StatusNoContent)
		default:
			w.WriteHeader(http.StatusMethodNotAllowed)
		}
	}))
	t.Cleanup(server.Close)
	return server
}

func TestSyncKeepsHrefEncoding(t *testing.T) {
	server := newEncodedHrefServer(t)

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.NoError(t, err)

	result, err := p.Sync(context.Background(), cal.Calendar{RemoteID: "/dav/calendars/user/cal/"}, cal.SyncCursor{})
	require.NoError(t, err)
	require.Len(t, result.Changes, 1)
	assert.Equal(t, "abc@client", result.Changes[0].Event.UID)
	assert.Equal(t, encodedObjectHref, result.Changes[0].Event.RemoteID)
	assert.Equal(t, "1", result.Changes[0].Event.Etag)
	assert.Empty(t, p.Notices())
}

func TestUpdateEventSendsHrefAsServed(t *testing.T) {
	server := newEncodedHrefServer(t)

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.NoError(t, err)

	start := time.Date(2026, 5, 1, 10, 0, 0, 0, time.UTC)
	ev := &cal.Event{UID: "abc@client", RemoteID: encodedObjectHref, Summary: "Encoded", Start: start, End: start.Add(time.Hour)}
	updated, err := p.UpdateEvent(context.Background(), cal.Calendar{RemoteID: "/dav/calendars/user/cal/"}, ev)
	require.NoError(t, err)
	assert.Equal(t, "2", updated.Etag)

	ev.RemoteID = "/dav/calendars/user/cal/abc@client.ics"
	_, err = p.UpdateEvent(context.Background(), cal.Calendar{RemoteID: "/dav/calendars/user/cal/"}, ev)
	require.ErrorContains(t, err, "412 Precondition Failed")
	require.ErrorContains(t, err, "no-uid-conflict")
}

func TestDeleteEventSendsHrefAsServed(t *testing.T) {
	server := newEncodedHrefServer(t)

	p, err := New(context.Background(), cal.Account{ID: "acc"}, newSecrets(t), server.URL, "user")
	require.NoError(t, err)

	err = p.DeleteEvent(context.Background(), cal.Calendar{RemoteID: "/dav/calendars/user/cal/"}, cal.Event{RemoteID: encodedObjectHref})
	require.NoError(t, err)
}

func TestObjectPathEscapesSegments(t *testing.T) {
	assert.Equal(t, "/dav/calendars/user/cal/abc@client.ics", objectPath("/dav/calendars/user/cal", "abc@client"))
	assert.Equal(t, "/dav/calendars/user/cal/a%2Fb.ics", objectPath("/dav/calendars/user/cal/", "a/b"))
	assert.Equal(t, "/dav/calendars/user/M%C3%B6j/x.ics", objectPath("/dav/calendars/user/Möj/", "x"))
}
