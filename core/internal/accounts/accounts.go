package accounts

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/duxlabs-dev/dux-calendar/core/ent"
	"github.com/duxlabs-dev/dux-calendar/core/ent/account"
	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/keyring"
	caldavprovider "github.com/duxlabs-dev/dux-calendar/core/internal/providers/caldav"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/evolution/eds"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/google"
	icalprovider "github.com/duxlabs-dev/dux-calendar/core/internal/providers/ical"
	"github.com/duxlabs-dev/dux-calendar/core/internal/providers/microsoft"
	"github.com/duxlabs-dev/dux-calendar/core/repo"
)

const ICloudCalDAVURL = "https://caldav.icloud.com"

type Provider struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Description  string   `json:"description"`
	Implemented  bool     `json:"implemented"`
	Capabilities []string `json:"capabilities"`
}

func Providers() []Provider {
	return []Provider{
		{
			ID:           "google",
			Name:         "Google",
			Description:  "Sign in with your Google account.",
			Implemented:  true,
			Capabilities: []string{"oauth", "events", "calendars"},
		},
		{
			ID:           "microsoft",
			Name:         "Microsoft",
			Description:  "Outlook, Office 365 and Exchange Online calendars.",
			Implemented:  true,
			Capabilities: []string{"oauth", "events", "calendars"},
		},
		{
			ID:           "caldav",
			Name:         "CalDAV",
			Description:  "Connect any CalDAV-compatible server.",
			Implemented:  true,
			Capabilities: []string{"events", "calendars"},
		},
		{
			ID:           "icloud",
			Name:         "iCloud",
			Description:  "Apple iCloud calendars via app-specific password.",
			Implemented:  true,
			Capabilities: []string{"events", "calendars"},
		},
		{
			ID:           "ical",
			Name:         "iCalendar subscription",
			Description:  "Subscribe to an external calendar by URL (webcal/https).",
			Implemented:  true,
			Capabilities: []string{"events", "calendars", "readonly"},
		},
		{
			ID:           "local",
			Name:         "Local",
			Description:  "A folder of .ics files on this machine.",
			Implemented:  true,
			Capabilities: []string{"events", "calendars"},
		},
		{
			ID:           "evolution",
			Name:         "Evolution",
			Description:  "Calendars managed by Evolution Data Server on this machine.",
			Implemented:  true,
			Capabilities: []string{"events", "calendars"},
		},
	}
}

// AvailableProviders is the provider list for the add-account UI, dropping
// providers whose backing service is not present on this machine (Evolution
// Data Server).
func AvailableProviders() []Provider {
	all := Providers()
	if eds.Available() {
		return all
	}

	out := make([]Provider, 0, len(all))
	for _, p := range all {
		if p.ID == "evolution" {
			continue
		}
		out = append(out, p)
	}
	return out
}

func ProviderName(id string) string {
	for _, p := range Providers() {
		if p.ID == id {
			return p.Name
		}
	}
	return id
}

// Flavor maps a stored account kind to the provider the user picked: iCloud
// accounts are stored as caldav with a preset marker.
func Flavor(kind string, settings map[string]any) string {
	if kind != string(account.KindCaldav) {
		return kind
	}

	preset, _ := settings["preset"].(string)
	serverURL, _ := settings["url"].(string)
	switch {
	case preset == "icloud", strings.Contains(serverURL, "icloud.com"):
		return "icloud"
	}
	return kind
}

type CredentialState int

const (
	CredentialsPresent CredentialState = iota
	CredentialsMissing
	CredentialsLocked
)

// CheckCredentials reports whether the provider's credentials are stored,
// missing, or behind a locked keyring; it does not probe the provider.
// OAuth providers need both the app credentials and the user token: sync
// fails on either, so a status that only probes the token reports a false
// "ok" while sync errors with a missing app secret (issue #105).
func CheckCredentials(ctx context.Context, secrets calendar.SecretStore, acc *ent.Account) CredentialState {
	var keys []string
	switch acc.Kind {
	case account.KindGoogle:
		keys = []string{google.SecretKeyApp, google.SecretKeyToken}
	case account.KindMicrosoft:
		keys = []string{microsoft.SecretKeyApp, microsoft.SecretKeyToken}
	case account.KindCaldav:
		keys = []string{caldavprovider.SecretKeyPassword}
	case account.KindIcal:
		user, _ := acc.Settings["username"].(string)
		if user == "" {
			return CredentialsPresent
		}
		keys = []string{icalprovider.SecretKeyPassword}
	default:
		return CredentialsPresent
	}

	return checkKeys(ctx, secrets, acc.ID, keys)
}

// checkKeys requires every key to be present. A locked keyring cannot prove
// absence, so any locked key wins over a missing one: the caller should
// retry after unlock instead of reporting the account as unauthenticated.
func checkKeys(ctx context.Context, secrets calendar.SecretStore, accountID string, keys []string) CredentialState {
	missing := false
	for _, key := range keys {
		_, err := secrets.Get(ctx, accountID, key)
		switch {
		case err == nil:
			continue
		case errors.Is(err, keyring.ErrLocked):
			return CredentialsLocked
		default:
			missing = true
		}
	}
	if missing {
		return CredentialsMissing
	}
	return CredentialsPresent
}

func Ensure(ctx context.Context, r *repo.Repo, id string, kind account.Kind, displayName string, settings map[string]any) error {
	_, err := r.GetAccount(ctx, id)
	switch {
	case err == nil:
		return nil
	case !repo.IsNotFound(err):
		return err
	}

	if _, err := r.CreateAccount(ctx, repo.CreateAccountInput{
		ID:          id,
		Kind:        kind,
		DisplayName: displayName,
		Settings:    settings,
	}); err != nil {
		return fmt.Errorf("create account: %w", err)
	}
	return nil
}

func Delete(ctx context.Context, r *repo.Repo, secrets calendar.SecretStore, accountID string) error {
	for _, key := range []string{
		google.SecretKeyToken,
		google.SecretKeyApp,
		microsoft.SecretKeyToken,
		microsoft.SecretKeyApp,
		caldavprovider.SecretKeyPassword,
		icalprovider.SecretKeyPassword,
	} {
		_ = secrets.Delete(ctx, accountID, key)
	}
	return r.DeleteAccount(ctx, accountID)
}

const maxAccountIDLen = 64

func truncateID(id string) string {
	if len(id) > maxAccountIDLen {
		return id[:maxAccountIDLen]
	}
	return id
}
