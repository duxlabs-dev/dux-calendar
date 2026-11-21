package calendar_handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/humatest"
	"github.com/stretchr/testify/suite"

	calendar_handler "github.com/duxlabs-dev/dux-calendar/core/api/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/api/server"
	"github.com/duxlabs-dev/dux-calendar/core/ent"
	"github.com/duxlabs-dev/dux-calendar/core/ent/account"
	"github.com/duxlabs-dev/dux-calendar/core/models"
	"github.com/duxlabs-dev/dux-calendar/core/repo"
	"github.com/duxlabs-dev/dux-go/errdefs/humaerr"
)

type HandlersSuite struct {
	suite.Suite
	ctx  context.Context
	repo *repo.Repo
	api  humatest.TestAPI
}

func TestHandlersSuite(t *testing.T) {
	suite.Run(t, new(HandlersSuite))
}

func (s *HandlersSuite) SetupTest() {
	s.ctx = context.Background()

	client, err := repo.OpenMemory(s.ctx)
	s.Require().NoError(err)
	s.repo = repo.New(client)
	s.T().Cleanup(func() { _ = s.repo.Close() })

	huma.NewError = humaerr.HumaErrorFunc
	_, s.api = humatest.New(s.T())
	calendar_handler.RegisterHandlers(&server.Server{Repo: s.repo}, huma.NewGroup(s.api))
}

func (s *HandlersSuite) seedAccount(id string) {
	_, err := s.repo.CreateAccount(s.ctx, repo.CreateAccountInput{
		ID:          id,
		Kind:        account.KindLocal,
		DisplayName: id,
	})
	s.Require().NoError(err)
}

func (s *HandlersSuite) seedCalendar(accountID, remoteID string) *ent.Calendar {
	cal, err := s.repo.UpsertCalendar(s.ctx, repo.UpsertCalendarInput{
		AccountID: accountID,
		RemoteID:  remoteID,
		Name:      remoteID,
	})
	s.Require().NoError(err)
	return cal
}

func (s *HandlersSuite) seedEvent(calendarID, uid string, start time.Time) *ent.Event {
	ev, err := s.repo.UpsertEvent(s.ctx, repo.UpsertEventInput{
		CalendarID: calendarID,
		UID:        uid,
		Summary:    uid,
		Start:      start,
		End:        start.Add(time.Hour),
	})
	s.Require().NoError(err)
	return ev
}

func (s *HandlersSuite) decode(body []byte, out any) {
	s.Require().NoError(json.Unmarshal(body, out))
}

func (s *HandlersSuite) TestListCalendarsFiltersByAccount() {
	s.seedAccount("personal")
	s.seedAccount("work")
	s.seedCalendar("personal", "cal-personal")
	s.seedCalendar("work", "cal-work")

	res := s.api.Get("/calendars?accountId=work")
	s.Require().Equal(http.StatusOK, res.Code)

	var body struct {
		Calendars []models.Calendar `json:"calendars"`
	}
	s.decode(res.Body.Bytes(), &body)
	s.Require().Len(body.Calendars, 1)
	s.Equal("cal-work", body.Calendars[0].Name)
	s.Equal("work", body.Calendars[0].AccountID)

	res = s.api.Get("/calendars")
	s.Require().Equal(http.StatusOK, res.Code)
	s.decode(res.Body.Bytes(), &body)
	s.Len(body.Calendars, 2)
}

func (s *HandlersSuite) TestListEventsTimeWindow() {
	s.seedAccount("personal")
	cal := s.seedCalendar("personal", "main")
	s.seedEvent(cal.ID, "inside", time.Date(2026, 5, 7, 14, 0, 0, 0, time.UTC))
	s.seedEvent(cal.ID, "outside", time.Date(2026, 6, 1, 14, 0, 0, 0, time.UTC))

	res := s.api.Get("/events?from=2026-05-07T00:00:00Z&to=2026-05-08T00:00:00Z")
	s.Require().Equal(http.StatusOK, res.Code)

	var body models.EventList
	s.decode(res.Body.Bytes(), &body)
	s.Require().Equal(1, body.Total)
	s.Equal("inside", body.Events[0].Summary)
	s.Equal(cal.ID, body.Events[0].CalendarID)
}

func (s *HandlersSuite) TestListEventsInvalidTimestamp() {
	res := s.api.Get("/events?from=yesterday")
	s.Equal(http.StatusBadRequest, res.Code)

	res = s.api.Get("/events?to=tomorrow")
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *HandlersSuite) TestGetEventNotFound() {
	res := s.api.Get("/events/does-not-exist")
	s.Equal(http.StatusNotFound, res.Code)
}
