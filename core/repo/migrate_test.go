package repo

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	"github.com/pressly/goose/v3"
	_ "modernc.org/sqlite"
)

func openRaw(t *testing.T, name string) (*sql.DB, string) {
	t.Helper()
	dsn := "file:" + filepath.Join(t.TempDir(), name) + "?_pragma=foreign_keys(ON)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		t.Fatal(err)
	}
	return db, dsn
}

// A database created by the old auto-migration has the pre-reauth schema and no
// goose history; it must be baselined and then upgraded without losing rows.
func TestMigrateBaselinesLegacyDatabase(t *testing.T) {
	ctx := context.Background()
	db, dsn := openRaw(t, "legacy.db")
	defer db.Close()

	_, err := db.ExecContext(ctx, `CREATE TABLE accounts (
		id text NOT NULL, kind text NOT NULL, display_name text NOT NULL,
		settings json NULL, created_at datetime NOT NULL, updated_at datetime NOT NULL,
		PRIMARY KEY (id));
		INSERT INTO accounts (id, kind, display_name, created_at, updated_at)
		VALUES ('a@b.com','google','A','2026-01-01','2026-01-01');
		CREATE TABLE calendars (
		id text NOT NULL, remote_id text NOT NULL, name text NOT NULL,
		name_override text NULL, description text NULL, color text NULL,
		time_zone text NULL, read_only bool NOT NULL DEFAULT (false),
		hidden bool NOT NULL DEFAULT (false), sync_token text NULL,
		created_at datetime NOT NULL, updated_at datetime NOT NULL,
		account_calendars text NOT NULL, PRIMARY KEY (id));
		CREATE TABLE events (
		id text NOT NULL, uid text NOT NULL, summary text NOT NULL,
		status text NOT NULL DEFAULT ('confirmed'), start datetime NOT NULL,
		end datetime NOT NULL, all_day bool NOT NULL DEFAULT (false),
		recurrence json NULL, recurring_id text NULL,
		created datetime NOT NULL, updated datetime NOT NULL,
		calendar_events text NOT NULL, PRIMARY KEY (id));
		CREATE INDEX event_recurring_id ON events (recurring_id);
		CREATE TABLE reminder_states (
		id integer NOT NULL PRIMARY KEY AUTOINCREMENT, calendar_id text NOT NULL,
		uid text NOT NULL, occurrence_start datetime NOT NULL, minutes integer NOT NULL,
		fired_at datetime NOT NULL, snoozed_until datetime NULL);
		CREATE INDEX reminderstate_snoozed_until ON reminder_states (snoozed_until);`)
	if err != nil {
		t.Fatal(err)
	}

	if err := migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate legacy: %v", err)
	}

	ok, err := columnExists(ctx, db, "accounts", "needs_reauth")
	if err != nil || !ok {
		t.Fatalf("needs_reauth missing after upgrade: ok=%v err=%v", ok, err)
	}
	var n int
	if err := db.QueryRowContext(ctx, "SELECT count(*) FROM accounts WHERE id = 'a@b.com';").Scan(&n); err != nil || n != 1 {
		t.Fatalf("existing row not preserved: n=%d err=%v", n, err)
	}
}

func TestMigrateIsIdempotent(t *testing.T) {
	ctx := context.Background()
	db, dsn := openRaw(t, "idem.db")
	defer db.Close()

	for i := 0; i < 3; i++ {
		if err := migrate(ctx, dsn); err != nil {
			t.Fatalf("migrate run %d: %v", i, err)
		}
	}
}

// The sync_disabled migration rebuilds the calendars table. Run with foreign
// keys enforced, its DROP TABLE would cascade-delete every event and task
// (issue #76); this pins the fix that migrations run on a keys-off connection.
func TestCalendarRebuildPreservesChildRows(t *testing.T) {
	ctx := context.Background()
	db, dsn := openRaw(t, "rebuild.db")
	defer db.Close()

	configureGoose()
	const beforeRebuild = 20260630202500
	if err := goose.UpToContext(ctx, db, migrationsDir, beforeRebuild); err != nil {
		t.Fatalf("migrate to pre-rebuild version: %v", err)
	}

	_, err := db.ExecContext(ctx, `INSERT INTO accounts
		(id, kind, display_name, created_at, updated_at)
		VALUES ('account-1', 'ical', 'Feed', '2026-01-01', '2026-01-01');
		INSERT INTO calendars
		(id, remote_id, name, sync_token, created_at, updated_at, account_calendars)
		VALUES ('calendar-1', 'feed', 'Feed', 'cursor-1', '2026-01-01', '2026-01-01', 'account-1');
		INSERT INTO events
		(id, uid, summary, start, end, created, updated, calendar_events)
		VALUES ('event-1', 'uid-1', 'Holiday', '2026-01-01', '2026-01-02', '2026-01-01', '2026-01-01', 'calendar-1');
		INSERT INTO tasks
		(id, uid, summary, created, updated, calendar_tasks)
		VALUES ('task-1', 'uid-2', 'Todo', '2026-01-01', '2026-01-01', 'calendar-1');`)
	if err != nil {
		t.Fatal(err)
	}

	if err := migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	for _, table := range []string{"events", "tasks"} {
		var n int
		if err := db.QueryRowContext(ctx, "SELECT count(*) FROM "+table+";").Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 1 {
			t.Fatalf("%s rows lost during calendars rebuild: got %d, want 1", table, n)
		}
	}

	var token sql.NullString
	if err := db.QueryRowContext(ctx, "SELECT sync_token FROM calendars WHERE id = 'calendar-1';").Scan(&token); err != nil {
		t.Fatal(err)
	}
	if token.Valid {
		t.Fatalf("sync token should be invalidated for a full refetch: %q", token.String)
	}
}

// Timestamps written before _time_format=sqlite was set used time.Time's
// String() format, which the driver cannot read back in zones whose offset has
// minutes, e.g. +0545 (issue #79). migrate rewrites them on every run.
func TestMigrateRepairsLocalizedTimestamps(t *testing.T) {
	ctx := context.Background()
	db, dsn := openRaw(t, "timestamps.db")
	defer db.Close()

	if err := migrate(ctx, dsn); err != nil {
		t.Fatalf("initial migrate: %v", err)
	}

	_, err := db.ExecContext(ctx, `INSERT INTO accounts
		(id, kind, display_name, created_at, updated_at) VALUES
		('kathmandu', 'google', 'Broken',
			'2026-08-16 12:34:56.789012345 +0545 +0545 m=+0.001234567',
			'2026-08-16 07:04:56 +0000 UTC'),
		('normal', 'google', 'Fine',
			'2026-01-01',
			'2026-04-01 08:00:00.5 -0400 EDT');`)
	if err != nil {
		t.Fatal(err)
	}

	if err := migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	cases := []struct {
		id      string
		created time.Time
		updated time.Time
	}{
		{
			id:      "kathmandu",
			created: time.Date(2026, 8, 16, 12, 34, 56, 789012345, time.FixedZone("", 5*3600+45*60)),
			updated: time.Date(2026, 8, 16, 7, 4, 56, 0, time.UTC),
		},
		{
			id:      "normal",
			created: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC),
			updated: time.Date(2026, 4, 1, 8, 0, 0, 500000000, time.FixedZone("", -4*3600)),
		},
	}
	for _, tc := range cases {
		var created, updated time.Time
		err := db.QueryRowContext(ctx,
			"SELECT created_at, updated_at FROM accounts WHERE id = ?;", tc.id).Scan(&created, &updated)
		if err != nil {
			t.Fatalf("scan %q timestamps: %v", tc.id, err)
		}
		if !created.Equal(tc.created) {
			t.Errorf("%q created_at = %v, want %v", tc.id, created, tc.created)
		}
		if !updated.Equal(tc.updated) {
			t.Errorf("%q updated_at = %v, want %v", tc.id, updated, tc.updated)
		}
	}
}

func TestMeetingURLMigrationInvalidatesSyncTokens(t *testing.T) {
	ctx := context.Background()
	db, dsn := openRaw(t, "meeting-urls.db")
	defer db.Close()

	configureGoose()
	const previousVersion = 20260629125249
	if err := goose.UpToContext(ctx, db, migrationsDir, previousVersion); err != nil {
		t.Fatalf("migrate to previous version: %v", err)
	}

	_, err := db.ExecContext(ctx, `INSERT INTO accounts
		(id, kind, display_name, created_at, updated_at)
		VALUES ('account-1', 'google', 'Test', '2026-01-01', '2026-01-01');
		INSERT INTO calendars
		(id, remote_id, name, sync_token, created_at, updated_at, account_calendars)
		VALUES ('calendar-1', 'remote-1', 'Test', 'cursor-1', '2026-01-01', '2026-01-01', 'account-1');`)
	if err != nil {
		t.Fatal(err)
	}

	if err := migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	var token sql.NullString
	if err := db.QueryRowContext(ctx, "SELECT sync_token FROM calendars WHERE id = 'calendar-1';").Scan(&token); err != nil {
		t.Fatal(err)
	}
	if token.Valid {
		t.Fatalf("sync token was not invalidated: %q", token.String)
	}
}
