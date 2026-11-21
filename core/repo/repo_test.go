package repo_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/duxlabs-dev/dux-calendar/core/ent/account"
	"github.com/duxlabs-dev/dux-calendar/core/ent/event"
	"github.com/duxlabs-dev/dux-calendar/core/repo"
)

func newTestRepo(t *testing.T) (*repo.Repo, context.Context) {
	t.Helper()
	ctx := context.Background()
	client, err := repo.OpenMemory(ctx)
	require.NoError(t, err)

	r := repo.New(client)
	t.Cleanup(func() { _ = r.Close() })
	return r, ctx
}

// Account timestamps default to time.Now in the daemon's local zone; a zone
// whose offset has minutes broke every later read of the row (issue #79).
func TestAccountRoundTripInMinuteOffsetZone(t *testing.T) {
	loc, err := time.LoadLocation("Asia/Kathmandu")
	require.NoError(t, err)
	original := time.Local
	time.Local = loc
	t.Cleanup(func() { time.Local = original })

	r, ctx := newTestRepo(t)

	_, err = r.CreateAccount(ctx, repo.CreateAccountInput{
		ID:          "nepal",
		Kind:        account.KindGoogle,
		DisplayName: "Nepal",
	})
	require.NoError(t, err)

	require.NoError(t, r.SetAccountAuthState(ctx, "nepal", false, ""))

	_, err = r.GetAccount(ctx, "nepal")
	require.NoError(t, err)
}

func TestUpsertCalendarAndEvents(t *testing.T) {
	r, ctx := newTestRepo(t)

	_, err := r.CreateAccount(ctx, repo.CreateAccountInput{
		ID:          "personal",
		Kind:        account.KindLocal,
		DisplayName: "Personal",
	})
	require.NoError(t, err)

	cal, err := r.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		AccountID: "personal",
		RemoteID:  "file:work.ics",
		Name:      "Work",
	})
	require.NoError(t, err)
	require.NotEmpty(t, cal.ID)

	again, err := r.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		AccountID: "personal",
		RemoteID:  "file:work.ics",
		Name:      "Work (renamed)",
	})
	require.NoError(t, err)
	require.Equal(t, cal.ID, again.ID)
	require.Equal(t, "Work (renamed)", again.Name)

	now := time.Now().UTC().Truncate(time.Second)
	created, err := r.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: cal.ID,
		UID:        "evt-1",
		Summary:    "Standup",
		Start:      now,
		End:        now.Add(30 * time.Minute),
		Status:     event.StatusConfirmed,
	})
	require.NoError(t, err)
	require.Equal(t, "Standup", created.Summary)

	from := now.Add(-time.Hour)
	to := now.Add(2 * time.Hour)
	events, total, err := r.ListEvents(ctx, repo.ListEventsParams{
		Filter: repo.EventFilter{
			CalendarIDs: []string{cal.ID},
			From:        &from,
			To:          &to,
		},
	})
	require.NoError(t, err)
	require.Equal(t, 1, total)
	require.Len(t, events, 1)
	require.Equal(t, "Standup", events[0].Summary)
}

func TestCalendarNameOverrideSurvivesSync(t *testing.T) {
	r, ctx := newTestRepo(t)

	_, err := r.CreateAccount(ctx, repo.CreateAccountInput{
		ID:          "personal",
		Kind:        account.KindLocal,
		DisplayName: "Personal",
	})
	require.NoError(t, err)

	cal, err := r.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		AccountID: "personal",
		RemoteID:  "file:work.ics",
		Name:      "Work",
	})
	require.NoError(t, err)

	require.NoError(t, r.SetCalendarNameOverride(ctx, cal.ID, "Job stuff"))

	synced, err := r.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		AccountID: "personal",
		RemoteID:  "file:work.ics",
		Name:      "Work (provider rename)",
	})
	require.NoError(t, err)
	require.Equal(t, "Work (provider rename)", synced.Name)
	require.Equal(t, "Job stuff", synced.NameOverride)

	require.NoError(t, r.SetCalendarNameOverride(ctx, cal.ID, ""))
	cleared, err := r.GetCalendar(ctx, cal.ID)
	require.NoError(t, err)
	require.Empty(t, cleared.NameOverride)
}

func TestSetCalendarSyncDisabled(t *testing.T) {
	r, ctx := newTestRepo(t)

	_, err := r.CreateAccount(ctx, repo.CreateAccountInput{
		ID:          "personal",
		Kind:        account.KindLocal,
		DisplayName: "Personal",
	})
	require.NoError(t, err)

	cal, err := r.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		AccountID: "personal",
		RemoteID:  "file:work.ics",
		Name:      "Work",
		SyncToken: "tok-1",
	})
	require.NoError(t, err)

	now := time.Now().UTC().Truncate(time.Second)
	_, err = r.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: cal.ID,
		UID:        "evt-1",
		Summary:    "Standup",
		Start:      now,
		End:        now.Add(30 * time.Minute),
		Status:     event.StatusConfirmed,
	})
	require.NoError(t, err)
	_, err = r.UpsertTask(ctx, repo.UpsertTaskInput{
		CalendarID: cal.ID,
		UID:        "task-1",
		Summary:    "Prep notes",
	})
	require.NoError(t, err)

	require.NoError(t, r.SetCalendarSyncDisabled(ctx, cal.ID, true))

	disabled, err := r.GetCalendar(ctx, cal.ID)
	require.NoError(t, err)
	require.True(t, disabled.SyncDisabled)
	require.Empty(t, disabled.SyncToken)

	_, total, err := r.ListEvents(ctx, repo.ListEventsParams{
		Filter: repo.EventFilter{CalendarIDs: []string{cal.ID}},
	})
	require.NoError(t, err)
	require.Zero(t, total)

	_, taskTotal, err := r.ListTasks(ctx, repo.ListTasksParams{
		Filter: repo.TaskFilter{CalendarIDs: []string{cal.ID}},
	})
	require.NoError(t, err)
	require.Zero(t, taskTotal)

	synced, err := r.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		AccountID: "personal",
		RemoteID:  "file:work.ics",
		Name:      "Work",
	})
	require.NoError(t, err)
	require.True(t, synced.SyncDisabled)

	require.NoError(t, r.SetCalendarSyncToken(ctx, cal.ID, "tok-stale"))
	stillDisabled, err := r.GetCalendar(ctx, cal.ID)
	require.NoError(t, err)
	require.Empty(t, stillDisabled.SyncToken)

	require.NoError(t, r.SetCalendarSyncDisabled(ctx, cal.ID, false))
	enabled, err := r.GetCalendar(ctx, cal.ID)
	require.NoError(t, err)
	require.False(t, enabled.SyncDisabled)
	require.Empty(t, enabled.SyncToken)

	require.NoError(t, r.SetCalendarSyncToken(ctx, cal.ID, "tok-2"))
	resynced, err := r.GetCalendar(ctx, cal.ID)
	require.NoError(t, err)
	require.Equal(t, "tok-2", resynced.SyncToken)
}

func TestSecrets(t *testing.T) {
	r, ctx := newTestRepo(t)

	_, err := r.CreateAccount(ctx, repo.CreateAccountInput{
		ID:          "google",
		Kind:        account.KindGoogle,
		DisplayName: "Google",
	})
	require.NoError(t, err)

	require.NoError(t, r.SetSecret(ctx, "google", "google.token", []byte("first")))

	value, err := r.GetSecret(ctx, "google", "google.token")
	require.NoError(t, err)
	require.Equal(t, []byte("first"), value)

	require.NoError(t, r.SetSecret(ctx, "google", "google.token", []byte("second")))

	value, err = r.GetSecret(ctx, "google", "google.token")
	require.NoError(t, err)
	require.Equal(t, []byte("second"), value)

	require.NoError(t, r.DeleteSecret(ctx, "google", "google.token"))

	_, err = r.GetSecret(ctx, "google", "google.token")
	require.True(t, repo.IsNotFound(err))
}

func TestDeleteAccountCascades(t *testing.T) {
	r, ctx := newTestRepo(t)

	_, err := r.CreateAccount(ctx, repo.CreateAccountInput{
		ID:          "acc",
		Kind:        account.KindLocal,
		DisplayName: "Acc",
	})
	require.NoError(t, err)

	cal, err := r.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		AccountID: "acc",
		RemoteID:  "dir:main",
		Name:      "Main",
	})
	require.NoError(t, err)

	_, err = r.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: cal.ID,
		UID:        "ev-1",
		Summary:    "Event",
		Start:      time.Now(),
		End:        time.Now().Add(time.Hour),
	})
	require.NoError(t, err)

	secrets := repo.NewSecretStore(r)
	require.NoError(t, secrets.Set(ctx, "acc", "test.token", []byte("tok")))

	require.NoError(t, r.DeleteAccount(ctx, "acc"))

	_, err = r.GetAccount(ctx, "acc")
	require.True(t, repo.IsNotFound(err))

	cals, err := r.ListCalendars(ctx)
	require.NoError(t, err)
	require.Empty(t, cals)

	events, total, err := r.ListEvents(ctx, repo.ListEventsParams{})
	require.NoError(t, err)
	require.Zero(t, total)
	require.Empty(t, events)
}

func TestDeleteCalendarCascades(t *testing.T) {
	r, ctx := newTestRepo(t)

	_, err := r.CreateAccount(ctx, repo.CreateAccountInput{
		ID:          "acc",
		Kind:        account.KindLocal,
		DisplayName: "Acc",
	})
	require.NoError(t, err)

	cal, err := r.UpsertCalendar(ctx, repo.UpsertCalendarInput{
		AccountID: "acc",
		RemoteID:  "dir:main",
		Name:      "Main",
	})
	require.NoError(t, err)

	_, err = r.UpsertEvent(ctx, repo.UpsertEventInput{
		CalendarID: cal.ID,
		UID:        "ev-1",
		Summary:    "Event",
		Start:      time.Now(),
		End:        time.Now().Add(time.Hour),
	})
	require.NoError(t, err)

	require.NoError(t, r.DeleteCalendar(ctx, cal.ID))

	_, total, err := r.ListEvents(ctx, repo.ListEventsParams{})
	require.NoError(t, err)
	require.Zero(t, total)
}
