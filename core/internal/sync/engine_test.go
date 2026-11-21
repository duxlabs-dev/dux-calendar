package sync_test

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/duxlabs-dev/dux-calendar/core/ent"
	"github.com/duxlabs-dev/dux-calendar/core/ent/account"
	"github.com/duxlabs-dev/dux-calendar/core/ent/event"
	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/mocks"
	"github.com/duxlabs-dev/dux-calendar/core/internal/notify"
	enginesync "github.com/duxlabs-dev/dux-calendar/core/internal/sync"
	"github.com/duxlabs-dev/dux-calendar/core/repo"
)

// fakeSender records notifications instead of touching D-Bus.
type fakeSender struct {
	sent []notify.Notification
}

func (f *fakeSender) Send(n notify.Notification) (uint32, error) {
	f.sent = append(f.sent, n)
	return uint32(len(f.sent)), nil
}

type EngineSuite struct {
	suite.Suite
	ctx      context.Context
	repo     *repo.Repo
	registry *calendar.Registry
	engine   *enginesync.Engine
	account  *ent.Account
}

func TestEngineSuite(t *testing.T) {
	suite.Run(t, new(EngineSuite))
}

func (s *EngineSuite) SetupTest() {
	s.ctx = context.Background()

	client, err := repo.OpenMemory(s.ctx)
	s.Require().NoError(err)
	s.repo = repo.New(client)
	s.T().Cleanup(func() { _ = s.repo.Close() })

	s.registry = calendar.NewRegistry()
	s.engine = enginesync.NewEngine(s.repo, s.registry, nil, time.Minute)

	s.account, err = s.repo.CreateAccount(s.ctx, repo.CreateAccountInput{
		ID:          "acc",
		Kind:        account.KindLocal,
		DisplayName: "Acc",
	})
	s.Require().NoError(err)
}

func (s *EngineSuite) registerProvider() *mocks.MockProvider {
	provider := mocks.NewMockProvider(s.T())
	factory := mocks.NewMockProviderFactory(s.T())
	factory.EXPECT().Kind().Return(calendar.AccountLocal)
	factory.EXPECT().Build(mock.Anything, mock.Anything, mock.Anything).Return(provider, nil)
	s.registry.Register(factory)
	return provider
}

func (s *EngineSuite) seedCalendar(remoteID string) *ent.Calendar {
	cal, err := s.repo.UpsertCalendar(s.ctx, repo.UpsertCalendarInput{
		AccountID: s.account.ID,
		RemoteID:  remoteID,
		Name:      "Main",
	})
	s.Require().NoError(err)
	return cal
}

func (s *EngineSuite) seedEvent(calendarID, uid string) {
	start := time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC)
	_, err := s.repo.UpsertEvent(s.ctx, repo.UpsertEventInput{
		CalendarID: calendarID,
		UID:        uid,
		Summary:    uid,
		Start:      start,
		End:        start.Add(time.Hour),
	})
	s.Require().NoError(err)
}

func (s *EngineSuite) listUIDs() []string {
	events, _, err := s.repo.ListEvents(s.ctx, repo.ListEventsParams{})
	s.Require().NoError(err)
	uids := make([]string, 0, len(events))
	for _, ev := range events {
		uids = append(uids, ev.UID)
	}
	return uids
}

func upsertChange(uid string, status calendar.EventStatus) calendar.EventChange {
	start := time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC)
	return calendar.EventChange{
		Type: calendar.ChangeUpsert,
		Event: &calendar.Event{
			UID:     uid,
			Summary: uid,
			Status:  status,
			Start:   start,
			End:     start.Add(time.Hour),
		},
	}
}

func (s *EngineSuite) TestSyncAccountStoresCalendarsAndEvents() {
	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main", Color: "#ff0000"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Cursor:  calendar.SyncCursor{Token: "tok-1"},
		Changes: []calendar.EventChange{upsertChange("ev-1", calendar.EventConfirmed)},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	calendars, err := s.repo.ListCalendars(s.ctx)
	s.Require().NoError(err)
	s.Require().Len(calendars, 1)
	s.Equal("Main", calendars[0].Name)
	s.Equal("tok-1", calendars[0].SyncToken)
	s.Equal("#ff0000", calendars[0].Color)

	s.Equal([]string{"ev-1"}, s.listUIDs())
}

func (s *EngineSuite) TestSyncPersistsColorDiscoveredDuringSync() {
	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Color: "#FF2968FF",
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	calendars, err := s.repo.ListCalendars(s.ctx)
	s.Require().NoError(err)
	s.Require().Len(calendars, 1)
	s.Equal("#ff2968", calendars[0].Color)
}

func (s *EngineSuite) TestSyncKeepsStoredColorWhenListingReportsNone() {
	_, err := s.repo.UpsertCalendar(s.ctx, repo.UpsertCalendarInput{
		AccountID: s.account.ID,
		RemoteID:  "cal-1",
		Name:      "Main",
		Color:     "#ff2968",
	})
	s.Require().NoError(err)

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	calendars, err := s.repo.ListCalendars(s.ctx)
	s.Require().NoError(err)
	s.Require().Len(calendars, 1)
	s.Equal("#ff2968", calendars[0].Color)
}

func (s *EngineSuite) TestSyncSkipsDisabledCalendar() {
	cal := s.seedCalendar("cal-1")
	s.Require().NoError(s.repo.SetCalendarSyncDisabled(s.ctx, cal.ID, true))

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.Empty(s.listUIDs())
	stored, err := s.repo.GetCalendar(s.ctx, cal.ID)
	s.Require().NoError(err)
	s.True(stored.SyncDisabled)
}

func (s *EngineSuite) TestDisableDuringSyncDropsFetchedChanges() {
	cal := s.seedCalendar("cal-1")

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).
		RunAndReturn(func(ctx context.Context, _ calendar.Calendar, _ calendar.SyncCursor) (*calendar.SyncResult, error) {
			s.Require().NoError(s.repo.SetCalendarSyncDisabled(ctx, cal.ID, true))
			return &calendar.SyncResult{
				FullSnapshot: true,
				Cursor:       calendar.SyncCursor{Token: "delta-1"},
				Changes:      []calendar.EventChange{upsertChange("late-1", calendar.EventConfirmed)},
			}, nil
		})
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.Empty(s.listUIDs())
	stored, err := s.repo.GetCalendar(s.ctx, cal.ID)
	s.Require().NoError(err)
	s.True(stored.SyncDisabled)
	s.Empty(stored.SyncToken)
}

func (s *EngineSuite) TestSyncMapsEventStatus() {
	s.seedCalendar("cal-1")
	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Changes: []calendar.EventChange{upsertChange("ev-tentative", calendar.EventTentative)},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	events, _, err := s.repo.ListEvents(s.ctx, repo.ListEventsParams{})
	s.Require().NoError(err)
	s.Require().Len(events, 1)
	s.Equal(event.StatusTentative, events[0].Status)
}

func (s *EngineSuite) TestFullSnapshotPrunesMissingEvents() {
	cal := s.seedCalendar("cal-1")
	s.seedEvent(cal.ID, "stale-1")
	s.seedEvent(cal.ID, "keep-1")

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		FullSnapshot: true,
		Cursor:       calendar.SyncCursor{Token: "snap-1"},
		Changes:      []calendar.EventChange{upsertChange("keep-1", calendar.EventConfirmed)},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.Equal([]string{"keep-1"}, s.listUIDs())
}

func (s *EngineSuite) seedOccurrence(calendarID, uid, recurringID string) {
	start := time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC)
	_, err := s.repo.UpsertEvent(s.ctx, repo.UpsertEventInput{
		CalendarID:  calendarID,
		UID:         uid,
		Summary:     uid,
		RecurringID: recurringID,
		Start:       start,
		End:         start.Add(time.Hour),
	})
	s.Require().NoError(err)
}

func upsertSeriesChange(uid, recurringID string) calendar.EventChange {
	ch := upsertChange(uid, calendar.EventConfirmed)
	ch.Event.RecurringID = recurringID
	return ch
}

func (s *EngineSuite) TestSeriesTouchedReconcilesStaleOccurrences() {
	cal := s.seedCalendar("cal-1")
	s.seedOccurrence(cal.ID, "old-1", "master-1")
	s.seedOccurrence(cal.ID, "old-2", "master-1")
	s.seedOccurrence(cal.ID, "other-1", "master-2")
	s.seedEvent(cal.ID, "single-1")

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Cursor:        calendar.SyncCursor{Token: "delta-1"},
		SeriesTouched: []string{"master-1"},
		Changes: []calendar.EventChange{
			upsertSeriesChange("new-1", "master-1"),
			upsertSeriesChange("new-2", "master-1"),
		},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.ElementsMatch([]string{"new-1", "new-2", "other-1", "single-1"}, s.listUIDs())
}

func (s *EngineSuite) TestSeriesTouchedAccumulatesAcrossPages() {
	cal := s.seedCalendar("cal-1")
	s.seedOccurrence(cal.ID, "old-1", "master-1")

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	tokenMatch := func(token string) any {
		return mock.MatchedBy(func(c calendar.SyncCursor) bool { return c.Token == token })
	}
	provider.EXPECT().Sync(mock.Anything, mock.Anything, tokenMatch("")).Return(&calendar.SyncResult{
		Cursor:        calendar.SyncCursor{Token: "page-1"},
		SeriesTouched: []string{"master-1"},
		Changes:       []calendar.EventChange{upsertSeriesChange("new-1", "master-1")},
		More:          true,
	}, nil).Once()
	provider.EXPECT().Sync(mock.Anything, mock.Anything, tokenMatch("page-1")).Return(&calendar.SyncResult{
		Cursor:  calendar.SyncCursor{Token: "delta-1"},
		Changes: []calendar.EventChange{upsertSeriesChange("new-2", "master-1")},
	}, nil).Once()
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.ElementsMatch([]string{"new-1", "new-2"}, s.listUIDs())
}

func (s *EngineSuite) TestSeriesTouchedWithNoOccurrencesRemovesSeries() {
	cal := s.seedCalendar("cal-1")
	s.seedOccurrence(cal.ID, "old-1", "master-1")
	s.seedEvent(cal.ID, "single-1")

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Cursor:        calendar.SyncCursor{Token: "delta-1"},
		SeriesTouched: []string{"master-1"},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.Equal([]string{"single-1"}, s.listUIDs())
}

func (s *EngineSuite) TestSeriesUntouchedKeepsOccurrences() {
	cal := s.seedCalendar("cal-1")
	s.seedOccurrence(cal.ID, "old-1", "master-1")
	s.seedOccurrence(cal.ID, "old-2", "master-1")

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Cursor:  calendar.SyncCursor{Token: "delta-1"},
		Changes: []calendar.EventChange{upsertSeriesChange("old-1", "master-1")},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.ElementsMatch([]string{"old-1", "old-2"}, s.listUIDs())
}

func upsertTaskChange(uid string) calendar.TaskChange {
	return calendar.TaskChange{
		Type: calendar.ChangeUpsert,
		Task: &calendar.Task{UID: uid, Summary: uid, Status: calendar.TaskNeedsAction},
	}
}

func (s *EngineSuite) listTaskUIDs() []string {
	tasks, _, err := s.repo.ListTasks(s.ctx, repo.ListTasksParams{
		Filter: repo.TaskFilter{IncludeCompleted: true},
	})
	s.Require().NoError(err)
	uids := make([]string, 0, len(tasks))
	for _, t := range tasks {
		uids = append(uids, t.UID)
	}
	return uids
}

func (s *EngineSuite) TestSyncStoresTasksForTaskCalendar() {
	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "tasks-1", Name: "Reminders", SupportedComponents: []string{calendar.ComponentVTodo}},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Cursor:       calendar.SyncCursor{Token: "tok-1"},
		FullSnapshot: true,
		TaskChanges:  []calendar.TaskChange{upsertTaskChange("todo-1")},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.Equal([]string{"todo-1"}, s.listTaskUIDs())
	// A task-only calendar holds no events, so none are touched.
	s.Empty(s.listUIDs())
}

func (s *EngineSuite) TestFullSnapshotPrunesMissingTasks() {
	cal, err := s.repo.UpsertCalendar(s.ctx, repo.UpsertCalendarInput{
		AccountID:           s.account.ID,
		RemoteID:            "tasks-1",
		Name:                "Reminders",
		SupportedComponents: []string{calendar.ComponentVTodo},
	})
	s.Require().NoError(err)
	for _, uid := range []string{"stale-1", "keep-1"} {
		_, err := s.repo.UpsertTask(s.ctx, repo.UpsertTaskInput{CalendarID: cal.ID, UID: uid, Summary: uid})
		s.Require().NoError(err)
	}

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "tasks-1", Name: "Reminders", SupportedComponents: []string{calendar.ComponentVTodo}},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		FullSnapshot: true,
		Cursor:       calendar.SyncCursor{Token: "snap-1"},
		TaskChanges:  []calendar.TaskChange{upsertTaskChange("keep-1")},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.Equal([]string{"keep-1"}, s.listTaskUIDs())
}

func (s *EngineSuite) TestDeleteChangeRemovesEvent() {
	cal := s.seedCalendar("cal-1")
	s.seedEvent(cal.ID, "ev-del")
	s.seedEvent(cal.ID, "ev-keep")

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Changes: []calendar.EventChange{{Type: calendar.ChangeDelete, RemoteID: "ev-del"}},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.Equal([]string{"ev-keep"}, s.listUIDs())
}

func (s *EngineSuite) TestSyncFollowsPagination() {
	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)

	tokenMatch := func(token string) any {
		return mock.MatchedBy(func(c calendar.SyncCursor) bool { return c.Token == token })
	}
	provider.EXPECT().Sync(mock.Anything, mock.Anything, tokenMatch("")).Return(&calendar.SyncResult{
		Cursor:  calendar.SyncCursor{Token: "page-1"},
		Changes: []calendar.EventChange{upsertChange("ev-1", calendar.EventConfirmed)},
		More:    true,
	}, nil).Once()
	provider.EXPECT().Sync(mock.Anything, mock.Anything, tokenMatch("page-1")).Return(&calendar.SyncResult{
		Cursor:  calendar.SyncCursor{Token: "page-2"},
		Changes: []calendar.EventChange{upsertChange("ev-2", calendar.EventConfirmed)},
	}, nil).Once()
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.ElementsMatch([]string{"ev-1", "ev-2"}, s.listUIDs())

	calendars, err := s.repo.ListCalendars(s.ctx)
	s.Require().NoError(err)
	s.Require().Len(calendars, 1)
	s.Equal("page-2", calendars[0].SyncToken)
}

func (s *EngineSuite) TestSyncAccountPublishesNotifications() {
	var topics []string
	s.engine.SetNotifier(func(topic string, _ any) { topics = append(topics, topic) })

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Changes: []calendar.EventChange{upsertChange("ev-1", calendar.EventConfirmed)},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.Contains(topics, "events")
	s.Contains(topics, "sync")
}

func (s *EngineSuite) TestSyncAccountNoEventsTopicWithoutChanges() {
	var topics []string
	s.engine.SetNotifier(func(topic string, _ any) { topics = append(topics, topic) })

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	s.NotContains(topics, "events")
	s.Contains(topics, "sync")
}

func (s *EngineSuite) TestSyncAccountListCalendarsError() {
	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return(nil, errors.New("upstream down"))
	provider.EXPECT().Close().Return(nil)

	err := s.engine.SyncAccount(s.ctx, s.account)
	s.Require().ErrorContains(err, "list calendars")
}

func (s *EngineSuite) TestSyncAccountFlagsReauthOnAuthError() {
	var topics []string
	s.engine.SetNotifier(func(topic string, _ any) { topics = append(topics, topic) })

	provider := s.registerProvider()
	authErr := fmt.Errorf("list google calendars: %w", calendar.ErrReauthRequired)
	provider.EXPECT().ListCalendars(mock.Anything).Return(nil, authErr)
	provider.EXPECT().Close().Return(nil)

	err := s.engine.SyncAccount(s.ctx, s.account)
	s.Require().Error(err)

	acc, err := s.repo.GetAccount(s.ctx, s.account.ID)
	s.Require().NoError(err)
	s.True(acc.NeedsReauth)
	s.NotEmpty(acc.AuthError)
	s.Contains(topics, "accounts")
}

func (s *EngineSuite) TestSyncAccountLeavesReauthClearOnGenericError() {
	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return(nil, errors.New("upstream down"))
	provider.EXPECT().Close().Return(nil)

	s.Require().Error(s.engine.SyncAccount(s.ctx, s.account))

	acc, err := s.repo.GetAccount(s.ctx, s.account.ID)
	s.Require().NoError(err)
	s.False(acc.NeedsReauth)
}

func (s *EngineSuite) TestSyncAccountNotifiesOnReauthTransition() {
	sender := &fakeSender{}
	s.engine.SetSender(sender)

	provider := s.registerProvider()
	authErr := fmt.Errorf("list google calendars: %w", calendar.ErrReauthRequired)
	provider.EXPECT().ListCalendars(mock.Anything).Return(nil, authErr)
	provider.EXPECT().Close().Return(nil)

	s.Require().Error(s.engine.SyncAccount(s.ctx, s.account))
	s.Require().Len(sender.sent, 1)
	s.Contains(sender.sent[0].Body, s.account.DisplayName)
}

func (s *EngineSuite) TestSyncAccountDoesNotRenotifyOnRepeatedReauthFailure() {
	sender := &fakeSender{}
	s.engine.SetSender(sender)

	provider := s.registerProvider()
	authErr := fmt.Errorf("list google calendars: %w", calendar.ErrReauthRequired)
	provider.EXPECT().ListCalendars(mock.Anything).Return(nil, authErr).Twice()
	provider.EXPECT().Close().Return(nil).Twice()

	acc, err := s.repo.GetAccount(s.ctx, s.account.ID)
	s.Require().NoError(err)

	s.Require().Error(s.engine.SyncAccount(s.ctx, acc))
	s.Require().Error(s.engine.SyncAccount(s.ctx, acc))
	s.Require().Len(sender.sent, 1)
}

func (s *EngineSuite) TestSyncAccountDoesNotNotifyOnGenericError() {
	sender := &fakeSender{}
	s.engine.SetSender(sender)

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return(nil, errors.New("upstream down"))
	provider.EXPECT().Close().Return(nil)

	s.Require().Error(s.engine.SyncAccount(s.ctx, s.account))
	s.Empty(sender.sent)
}

func (s *EngineSuite) TestSyncAccountClearsReauthOnSuccess() {
	s.Require().NoError(s.repo.SetAccountAuthState(s.ctx, s.account.ID, true, "stale"))
	var err error
	s.account, err = s.repo.GetAccount(s.ctx, s.account.ID)
	s.Require().NoError(err)

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))

	acc, err := s.repo.GetAccount(s.ctx, s.account.ID)
	s.Require().NoError(err)
	s.False(acc.NeedsReauth)
	s.Empty(acc.AuthError)
}

func (s *EngineSuite) TestSyncAllContinuesPastFailingAccount() {
	_, err := s.repo.CreateAccount(s.ctx, repo.CreateAccountInput{
		ID:          "broken",
		Kind:        account.KindGoogle,
		DisplayName: "Broken",
	})
	s.Require().NoError(err)

	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{
		Changes: []calendar.EventChange{upsertChange("ev-1", calendar.EventConfirmed)},
	}, nil)
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAll(s.ctx))

	s.Equal([]string{"ev-1"}, s.listUIDs())
}

func (s *EngineSuite) TestCalendarFailureRecordsNoticeUntilRecovered() {
	s.seedCalendar("cal-1")
	provider := s.registerProvider()
	provider.EXPECT().ListCalendars(mock.Anything).Return([]calendar.Calendar{
		{RemoteID: "cal-1", Name: "Main"},
	}, nil)
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(nil, errors.New("multiget: 404")).Once()
	provider.EXPECT().Sync(mock.Anything, mock.Anything, mock.Anything).Return(&calendar.SyncResult{FullSnapshot: true}, nil).Once()
	provider.EXPECT().Close().Return(nil)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))
	stored, err := s.repo.GetAccount(s.ctx, s.account.ID)
	s.Require().NoError(err)
	s.Equal(calendar.NoticeCalendarSyncFailed, stored.SyncNotice)

	s.Require().NoError(s.engine.SyncAccount(s.ctx, s.account))
	stored, err = s.repo.GetAccount(s.ctx, s.account.ID)
	s.Require().NoError(err)
	s.Empty(stored.SyncNotice)
}
