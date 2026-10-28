package caldav

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	ical "github.com/emersion/go-ical"
	"github.com/emersion/go-webdav/caldav"
)

// Hrefs travel as served: RFC 3986 §2.2 keeps "@" and "%40" distinct, Stalwart (#141) matches raw names, go-webdav decodes them.

func escapedPath(href string) (string, bool) {
	u, err := url.Parse(strings.TrimSpace(href))
	if err != nil || u.Path == "" {
		return "", false
	}
	return u.EscapedPath(), true
}

func objectPath(calendarPath, uid string) string {
	collection := (&url.URL{Path: strings.TrimSuffix(calendarPath, "/") + "/"}).EscapedPath()
	return collection + url.PathEscape(uid) + ".ics"
}

func (p *Provider) objectURL(href string) (string, error) {
	ref, err := url.Parse(href)
	if err != nil {
		return "", err
	}
	return p.endpoint.ResolveReference(&url.URL{Path: ref.Path, RawPath: ref.RawPath}).String(), nil
}

func (p *Provider) doObject(ctx context.Context, method, href string, body []byte, contentType string) (*http.Response, error) {
	target, err := p.objectURL(href)
	if err != nil {
		return nil, err
	}
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, target, reader)
	if err != nil {
		return nil, err
	}
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode/100 == 2 {
		return resp, nil
	}
	defer resp.Body.Close()
	return nil, responseError(resp)
}

func responseError(resp *http.Response) error {
	detail, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	text := strings.TrimSpace(string(detail))
	if text == "" {
		return errors.New(resp.Status)
	}
	return fmt.Errorf("%s: %s", resp.Status, text)
}

func (p *Provider) putObject(ctx context.Context, href string, doc *ical.Calendar) (string, error) {
	var body bytes.Buffer
	if err := ical.NewEncoder(&body).Encode(doc); err != nil {
		return "", err
	}
	resp, err := p.doObject(ctx, http.MethodPut, href, body.Bytes(), ical.MIMEType)
	if err != nil {
		return "", err
	}
	resp.Body.Close()
	return unquoteETag(resp.Header.Get("ETag")), nil
}

func (p *Provider) getObject(ctx context.Context, href string) (*ical.Calendar, error) {
	resp, err := p.doObject(ctx, http.MethodGet, href, nil, "")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return ical.NewDecoder(resp.Body).Decode()
}

func (p *Provider) deleteObject(ctx context.Context, href string) error {
	resp, err := p.doObject(ctx, http.MethodDelete, href, nil, "")
	if err != nil {
		return err
	}
	resp.Body.Close()
	return nil
}

const multiGetHead = `<?xml version="1.0" encoding="UTF-8"?>
<c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:getetag/><c:calendar-data/></d:prop>`

func multiGetBody(hrefs []string) string {
	var b strings.Builder
	b.WriteString(multiGetHead)
	for _, href := range hrefs {
		b.WriteString("<d:href>")
		_ = xml.EscapeText(&b, []byte(href))
		b.WriteString("</d:href>")
	}
	b.WriteString("</c:calendar-multiget>")
	return b.String()
}

func (p *Provider) multiGet(ctx context.Context, calendarPath string, hrefs []string) ([]caldav.CalendarObject, error) {
	target := p.endpoint.ResolveReference(&url.URL{Path: calendarPath})
	req, err := http.NewRequestWithContext(ctx, "REPORT", target.String(), strings.NewReader(multiGetBody(hrefs)))
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
		return nil, responseError(resp)
	}
	return decodeMultiGet(resp.Body)
}

type multiGetResponse struct {
	Href      string `xml:"DAV: href"`
	Status    string `xml:"DAV: status"`
	PropStats []struct {
		Status string `xml:"DAV: status"`
		Prop   struct {
			ETag string `xml:"DAV: getetag"`
			Data string `xml:"urn:ietf:params:xml:ns:caldav calendar-data"`
		} `xml:"DAV: prop"`
	} `xml:"DAV: propstat"`
}

func (r multiGetResponse) calendarData() (data, etag string, err error) {
	if r.Status != "" && statusCode(r.Status)/100 != 2 {
		return "", "", errors.New(strings.TrimSpace(r.Status))
	}
	for _, ps := range r.PropStats {
		if statusCode(ps.Status)/100 != 2 || ps.Prop.Data == "" {
			continue
		}
		return ps.Prop.Data, unquoteETag(ps.Prop.ETag), nil
	}
	return "", "", errors.New("404 Not Found: missing calendar-data")
}

func decodeMultiGet(body io.Reader) ([]caldav.CalendarObject, error) {
	var ms struct {
		Responses []multiGetResponse `xml:"DAV: response"`
	}
	if err := xml.NewDecoder(body).Decode(&ms); err != nil {
		return nil, fmt.Errorf("decode multiget response: %w", err)
	}

	var objects []caldav.CalendarObject
	var refused []error
	for _, r := range ms.Responses {
		href, ok := escapedPath(r.Href)
		if !ok {
			continue
		}
		data, etag, err := r.calendarData()
		if err != nil {
			refused = append(refused, fmt.Errorf("%s: %w", href, err))
			continue
		}
		doc, err := ical.NewDecoder(strings.NewReader(data)).Decode()
		if err != nil {
			return nil, fmt.Errorf("decode %s: %w", href, err)
		}
		objects = append(objects, caldav.CalendarObject{Path: href, ETag: etag, Data: doc})
	}
	return objects, errors.Join(refused...)
}

func statusCode(status string) int {
	fields := strings.Fields(status)
	if len(fields) < 2 {
		return 0
	}
	code, _ := strconv.Atoi(fields[1])
	return code
}

func unquoteETag(etag string) string {
	trimmed := strings.TrimSpace(etag)
	if unquoted, err := strconv.Unquote(trimmed); err == nil {
		return unquoted
	}
	return trimmed
}
