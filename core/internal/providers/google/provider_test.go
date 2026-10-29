package google

import (
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"google.golang.org/api/googleapi"

	cal "github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
)

func TestGoogleInstanceID(t *testing.T) {
	start := time.Date(2026, 8, 17, 13, 30, 0, 0, time.FixedZone("CEST", 2*3600))

	if got := googleInstanceID("master", start, false); got != "master_20260817T113000Z" {
		t.Errorf("timed instance id = %q", got)
	}
	if got := googleInstanceID("master", time.Date(2026, 8, 17, 0, 0, 0, 0, time.UTC), true); got != "master_20260817" {
		t.Errorf("all-day instance id = %q", got)
	}
}

func TestGoogleRespondTargetID(t *testing.T) {
	original := time.Date(2026, 10, 12, 9, 0, 0, 0, time.UTC)
	cases := []struct {
		name string
		ev   cal.Event
		want string
	}{
		{
			name: "plain event",
			ev:   cal.Event{RemoteID: "_60q30c1g"},
			want: "_60q30c1g",
		},
		{
			name: "occurrence synthesized from master",
			ev:   cal.Event{RemoteID: "_60q30c1g", RecurringID: "_60q30c1g", OriginalStart: original},
			want: "_60q30c1g_20261012T090000Z",
		},
		{
			name: "synced exception row keeps its own id",
			ev:   cal.Event{RemoteID: "_60q30c1g_20261012T090000Z", RecurringID: "_60q30c1g", OriginalStart: original},
			want: "_60q30c1g_20261012T090000Z",
		},
		{
			name: "all-day occurrence synthesized from master",
			ev:   cal.Event{RemoteID: "m", RecurringID: "m", OriginalStart: original, AllDay: true},
			want: "m_20261012",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, googleRespondTargetID(&tc.ev))
		})
	}
}

func TestIsServiceDisabled(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{
			name: "access not configured reason",
			err:  &googleapi.Error{Code: http.StatusForbidden, Errors: []googleapi.ErrorItem{{Reason: "accessNotConfigured"}}},
			want: true,
		},
		{
			name: "disabled message",
			err:  &googleapi.Error{Code: http.StatusForbidden, Message: "Google Tasks API has not been used in project 123 before or it is disabled."},
			want: true,
		},
		{
			name: "wrapped disabled error",
			err:  fmt.Errorf("list google task lists: %w", &googleapi.Error{Code: http.StatusForbidden, Errors: []googleapi.ErrorItem{{Reason: "accessNotConfigured"}}}),
			want: true,
		},
		{
			name: "forbidden for another reason",
			err:  &googleapi.Error{Code: http.StatusForbidden, Errors: []googleapi.ErrorItem{{Reason: "insufficientPermissions"}}},
			want: false,
		},
		{
			name: "unauthorized is not a disabled service",
			err:  &googleapi.Error{Code: http.StatusUnauthorized},
			want: false,
		},
		{
			name: "plain error",
			err:  errors.New("boom"),
			want: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isServiceDisabled(tc.err); got != tc.want {
				t.Fatalf("isServiceDisabled = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestIsOptionalServiceUnavailable(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{
			name: "service disabled",
			err:  &googleapi.Error{Code: http.StatusForbidden, Errors: []googleapi.ErrorItem{{Reason: "accessNotConfigured"}}},
			want: true,
		},
		{
			name: "missing scope reason",
			err:  &googleapi.Error{Code: http.StatusForbidden, Errors: []googleapi.ErrorItem{{Reason: "insufficientPermissions"}}},
			want: true,
		},
		{
			name: "wrapped missing scope message",
			err:  fmt.Errorf("list task lists: %w", &googleapi.Error{Code: http.StatusForbidden, Message: "Request had insufficient authentication scopes."}),
			want: true,
		},
		{
			name: "another forbidden error",
			err:  &googleapi.Error{Code: http.StatusForbidden, Errors: []googleapi.ErrorItem{{Reason: "rateLimitExceeded"}}},
			want: false,
		},
		{
			name: "plain error",
			err:  errors.New("boom"),
			want: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isOptionalServiceUnavailable(tc.err); got != tc.want {
				t.Fatalf("isOptionalServiceUnavailable = %v, want %v", got, tc.want)
			}
		})
	}
}
