package accounts_test

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/duxlabs-dev/dux-calendar/core/ent"
	"github.com/duxlabs-dev/dux-calendar/core/ent/account"
	"github.com/duxlabs-dev/dux-calendar/core/internal/accounts"
	"github.com/duxlabs-dev/dux-calendar/core/internal/keyring"
	"github.com/duxlabs-dev/dux-calendar/core/internal/mocks"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/google"
	"github.com/duxlabs-dev/dux-calendar/core/repo"
)

func TestFlavor(t *testing.T) {
	tests := []struct {
		name     string
		kind     string
		settings map[string]any
		want     string
	}{
		{"google passes through", "google", nil, "google"},
		{"plain caldav", "caldav", map[string]any{"url": "https://dav.example.com"}, "caldav"},
		{"icloud preset", "caldav", map[string]any{"preset": "icloud"}, "icloud"},
		{"icloud url", "caldav", map[string]any{"url": "https://caldav.icloud.com"}, "icloud"},
		{"caldav without settings", "caldav", nil, "caldav"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, accounts.Flavor(tc.kind, tc.settings))
		})
	}
}

func TestProviderName(t *testing.T) {
	assert.Equal(t, "Google", accounts.ProviderName("google"))
	assert.Equal(t, "iCloud", accounts.ProviderName("icloud"))
	assert.Equal(t, "iCalendar subscription", accounts.ProviderName("ical"))
	assert.Equal(t, "mystery", accounts.ProviderName("mystery"))
}

func TestCheckCredentials(t *testing.T) {
	ctx := context.Background()

	t.Run("local accounts need no credentials", func(t *testing.T) {
		secrets := mocks.NewMockSecretStore(t)
		acc := &ent.Account{ID: "loc", Kind: account.KindLocal}
		assert.Equal(t, accounts.CredentialsPresent, accounts.CheckCredentials(ctx, secrets, acc))
	})

	t.Run("google with stored credentials", func(t *testing.T) {
		secrets := mocks.NewMockSecretStore(t)
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyApp).Return([]byte("app"), nil)
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyToken).Return([]byte("tok"), nil)
		acc := &ent.Account{ID: "g", Kind: account.KindGoogle}
		assert.Equal(t, accounts.CredentialsPresent, accounts.CheckCredentials(ctx, secrets, acc))
	})

	t.Run("google without token", func(t *testing.T) {
		secrets := mocks.NewMockSecretStore(t)
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyApp).Return([]byte("app"), nil)
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyToken).Return(nil, errors.New("not found"))
		acc := &ent.Account{ID: "g", Kind: account.KindGoogle}
		assert.Equal(t, accounts.CredentialsMissing, accounts.CheckCredentials(ctx, secrets, acc))
	})

	t.Run("google without app credentials is missing even with a token", func(t *testing.T) {
		secrets := mocks.NewMockSecretStore(t)
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyApp).Return(nil, errors.New("not found"))
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyToken).Return([]byte("tok"), nil)
		acc := &ent.Account{ID: "g", Kind: account.KindGoogle}
		assert.Equal(t, accounts.CredentialsMissing, accounts.CheckCredentials(ctx, secrets, acc))
	})

	t.Run("google behind a locked keyring", func(t *testing.T) {
		secrets := mocks.NewMockSecretStore(t)
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyApp).Return(nil, fmt.Errorf("keyring get: %w", keyring.ErrLocked))
		acc := &ent.Account{ID: "g", Kind: account.KindGoogle}
		assert.Equal(t, accounts.CredentialsLocked, accounts.CheckCredentials(ctx, secrets, acc))
	})

	t.Run("locked token wins over missing app", func(t *testing.T) {
		secrets := mocks.NewMockSecretStore(t)
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyApp).Return(nil, errors.New("not found"))
		secrets.EXPECT().Get(mock.Anything, "g", google.SecretKeyToken).Return(nil, fmt.Errorf("keyring get: %w", keyring.ErrLocked))
		acc := &ent.Account{ID: "g", Kind: account.KindGoogle}
		assert.Equal(t, accounts.CredentialsLocked, accounts.CheckCredentials(ctx, secrets, acc))
	})
}

type AccountsSuite struct {
	suite.Suite
	ctx  context.Context
	repo *repo.Repo
}

func TestAccountsSuite(t *testing.T) {
	suite.Run(t, new(AccountsSuite))
}

func (s *AccountsSuite) SetupTest() {
	s.ctx = context.Background()
	client, err := repo.OpenMemory(s.ctx)
	s.Require().NoError(err)
	s.repo = repo.New(client)
	s.T().Cleanup(func() { _ = s.repo.Close() })
}

func (s *AccountsSuite) TestEnsureCreatesMissingAccount() {
	err := accounts.Ensure(s.ctx, s.repo, "personal", account.KindLocal, "Personal", map[string]any{"root": "/tmp"})
	s.Require().NoError(err)

	acc, err := s.repo.GetAccount(s.ctx, "personal")
	s.Require().NoError(err)
	s.Equal("Personal", acc.DisplayName)
}

func (s *AccountsSuite) TestEnsureIsIdempotent() {
	s.Require().NoError(accounts.Ensure(s.ctx, s.repo, "personal", account.KindLocal, "Personal", nil))
	s.Require().NoError(accounts.Ensure(s.ctx, s.repo, "personal", account.KindLocal, "Renamed", nil))

	acc, err := s.repo.GetAccount(s.ctx, "personal")
	s.Require().NoError(err)
	s.Equal("Personal", acc.DisplayName, "existing account should not be overwritten")

	all, err := s.repo.ListAccounts(s.ctx)
	s.Require().NoError(err)
	s.Len(all, 1)
}

const icalFeed = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\nBEGIN:VEVENT\r\nUID:evt-1@test\r\nDTSTART:20260507T140000Z\r\nDTEND:20260507T150000Z\r\nSUMMARY:Hello\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

func (s *AccountsSuite) feedServer() string {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(icalFeed))
	}))
	s.T().Cleanup(server.Close)
	return server.URL + "/owa/calendar/" + strings.Repeat("a", 60) + "/"
}

func (s *AccountsSuite) TestAddICalKeepsFeedsWithLongSharedPrefixApart() {
	prefix := s.feedServer()

	first, err := accounts.AddICal(s.ctx, s.repo, nil, accounts.ICalInput{URL: prefix + "token-one/calendar.ics"})
	s.Require().NoError(err)
	second, err := accounts.AddICal(s.ctx, s.repo, nil, accounts.ICalInput{URL: prefix + "token-two/calendar.ics"})
	s.Require().NoError(err)
	s.NotEqual(first.AccountID, second.AccountID)

	again, err := accounts.AddICal(s.ctx, s.repo, nil, accounts.ICalInput{URL: prefix + "token-one/calendar.ics"})
	s.Require().NoError(err)
	s.Equal(first.AccountID, again.AccountID, "re-adding the same feed must stay idempotent")

	all, err := s.repo.ListAccountsByKind(s.ctx, account.KindIcal)
	s.Require().NoError(err)
	s.Len(all, 2)
	for _, acc := range all {
		s.LessOrEqual(len(acc.ID), 64)
		s.Contains([]string{first.AccountID, second.AccountID}, acc.ID)
	}
}

func (s *AccountsSuite) TestAddICalReusesLegacyTruncatedID() {
	feedURL := s.feedServer() + "token-one/calendar.ics"
	parsed, err := url.Parse(feedURL)
	s.Require().NoError(err)
	legacyID := ("ical:" + parsed.Host + parsed.Path)[:64]
	_, err = s.repo.CreateAccount(s.ctx, repo.CreateAccountInput{
		ID:          legacyID,
		Kind:        account.KindIcal,
		DisplayName: "Legacy",
		Settings:    map[string]any{"url": feedURL},
	})
	s.Require().NoError(err)

	res, err := accounts.AddICal(s.ctx, s.repo, nil, accounts.ICalInput{URL: feedURL})
	s.Require().NoError(err)
	s.Equal(legacyID, res.AccountID)

	all, err := s.repo.ListAccountsByKind(s.ctx, account.KindIcal)
	s.Require().NoError(err)
	s.Len(all, 1)
}

func (s *AccountsSuite) TestAddICalShortFeedKeepsReadableID() {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(icalFeed))
	}))
	s.T().Cleanup(server.Close)
	parsed, err := url.Parse(server.URL)
	s.Require().NoError(err)

	res, err := accounts.AddICal(s.ctx, s.repo, nil, accounts.ICalInput{URL: server.URL + "/team.ics"})
	s.Require().NoError(err)
	s.Equal("ical:"+parsed.Host+"/team.ics", res.AccountID)
}

func (s *AccountsSuite) TestDeleteRemovesAccountAndSecrets() {
	_, err := s.repo.CreateAccount(s.ctx, repo.CreateAccountInput{
		ID:          "g",
		Kind:        account.KindGoogle,
		DisplayName: "Google",
	})
	s.Require().NoError(err)

	secrets := repo.NewSecretStore(s.repo)
	s.Require().NoError(secrets.Set(s.ctx, "g", google.SecretKeyToken, []byte("tok")))

	s.Require().NoError(accounts.Delete(s.ctx, s.repo, secrets, "g"))

	_, err = s.repo.GetAccount(s.ctx, "g")
	s.True(repo.IsNotFound(err))

	_, err = secrets.Get(s.ctx, "g", google.SecretKeyToken)
	s.Error(err)
}
