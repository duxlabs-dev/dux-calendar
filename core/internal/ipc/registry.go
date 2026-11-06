package ipc

import "sort"

type ParamSpec struct {
	Name     string `json:"name"`
	Required bool   `json:"required"`
	Desc     string `json:"desc,omitempty"`
}

type MethodSpec struct {
	Name   string      `json:"name"`
	Group  string      `json:"group"`
	Desc   string      `json:"desc,omitempty"`
	Params []ParamSpec `json:"params,omitempty"`
}

func req(name, desc string) ParamSpec { return ParamSpec{Name: name, Required: true, Desc: desc} }
func opt(name, desc string) ParamSpec { return ParamSpec{Name: name, Desc: desc} }

// Methods is the authoritative catalog of IPC methods. It drives shell
// completion, the `ipc list` help, and the `describe` introspection method.
var Methods = []MethodSpec{
	{Name: "ping", Group: "core", Desc: "Liveness check"},
	{Name: "version", Group: "core", Desc: "Daemon and API version"},
	{Name: "describe", Group: "core", Desc: "List all IPC methods and their params"},
	{Name: "subscribe", Group: "core", Desc: "Subscribe to event topics", Params: []ParamSpec{opt("topics", "accounts,calendars,events,sync")}},
	{Name: "unsubscribe", Group: "core", Desc: "Unsubscribe from event topics", Params: []ParamSpec{opt("topics", "topics to drop")}},

	{Name: "accounts.list", Group: "accounts", Desc: "List configured accounts"},
	{Name: "accounts.providers", Group: "accounts", Desc: "List available account providers"},
	{Name: "accounts.google.setupGuide", Group: "accounts", Desc: "Google OAuth setup steps"},
	{Name: "accounts.google.start", Group: "accounts", Desc: "Begin Google OAuth flow", Params: []ParamSpec{opt("clientId", "defaults to the built-in client"), opt("clientSecret", "defaults to the built-in client"), opt("displayName", "")}},
	{Name: "accounts.google.complete", Group: "accounts", Desc: "Finish a pending Google flow", Params: []ParamSpec{req("state", "flow state token")}},
	{Name: "accounts.google.reauth", Group: "accounts", Desc: "Re-authorize a Google account", Params: []ParamSpec{req("accountId", "")}},
	{Name: "accounts.google.cancel", Group: "accounts", Desc: "Cancel a pending Google flow", Params: []ParamSpec{req("state", "flow state token")}},
	{Name: "accounts.microsoft.setupGuide", Group: "accounts", Desc: "Microsoft OAuth setup steps"},
	{Name: "accounts.microsoft.start", Group: "accounts", Desc: "Begin Microsoft OAuth flow", Params: []ParamSpec{opt("clientId", "defaults to the built-in client"), opt("tenant", "")}},
	{Name: "accounts.microsoft.complete", Group: "accounts", Desc: "Finish a pending Microsoft flow", Params: []ParamSpec{req("state", "flow state token")}},
	{Name: "accounts.microsoft.reauth", Group: "accounts", Desc: "Re-authorize a Microsoft account", Params: []ParamSpec{req("accountId", "")}},
	{Name: "accounts.microsoft.cancel", Group: "accounts", Desc: "Cancel a pending Microsoft flow", Params: []ParamSpec{req("state", "flow state token")}},
	{Name: "accounts.caldav.add", Group: "accounts", Desc: "Add a CalDAV account", Params: []ParamSpec{req("url", ""), opt("username", ""), opt("password", ""), opt("displayName", "")}},
	{Name: "accounts.ical.add", Group: "accounts", Desc: "Subscribe to an iCal feed by URL", Params: []ParamSpec{req("url", "webcal or https feed URL"), opt("username", "basic-auth user"), opt("password", "basic-auth password"), opt("displayName", "")}},
	{Name: "accounts.local.add", Group: "accounts", Desc: "Add a local calendar store", Params: []ParamSpec{opt("root", "storage directory"), opt("displayName", "")}},
	{Name: "accounts.delete", Group: "accounts", Desc: "Delete an account", Params: []ParamSpec{req("accountId", "")}},
	{Name: "accounts.refresh", Group: "accounts", Desc: "Sync one account, or all if omitted", Params: []ParamSpec{opt("accountId", "empty syncs all")}},
	{Name: "accounts.changed", Group: "accounts", Desc: "Publish an accounts-changed event", Params: []ParamSpec{opt("accountId", "")}},

	{Name: "calendars.list", Group: "calendars", Desc: "List calendars"},
	{Name: "calendars.create", Group: "calendars", Desc: "Create a calendar in a local account", Params: []ParamSpec{req("accountId", ""), req("name", "")}},
	{Name: "calendars.setHidden", Group: "calendars", Desc: "Show or hide a calendar", Params: []ParamSpec{req("calendarId", ""), req("hidden", "true|false")}},
	{Name: "calendars.setSyncDisabled", Group: "calendars", Desc: "Exclude a calendar from provider sync (purges the local copy)", Params: []ParamSpec{req("calendarId", ""), req("disabled", "true|false")}},
	{Name: "calendars.rename", Group: "calendars", Desc: "Override a calendar name (empty clears)", Params: []ParamSpec{req("calendarId", ""), opt("name", "")}},
	{Name: "calendars.setReminders", Group: "calendars", Desc: "Set per-calendar reminder overrides (empty clears)", Params: []ParamSpec{req("calendarId", ""), opt("overrides", "override object; omit to inherit")}},
	{Name: "calendars.delete", Group: "calendars", Desc: "Delete a calendar", Params: []ParamSpec{req("calendarId", "")}},

	{Name: "events.list", Group: "events", Desc: "List events", Params: []ParamSpec{opt("query", "text filter"), opt("from", "RFC3339"), opt("to", "RFC3339"), opt("limit", ""), opt("offset", "")}},
	{Name: "events.get", Group: "events", Desc: "Get an event by iCal UID", Params: []ParamSpec{req("uid", "event iCal UID"), opt("calendarId", "limit to one calendar"), opt("start", "occurrence start RFC3339 for recurring events")}},
	{Name: "events.create", Group: "events", Desc: "Create an event", Params: []ParamSpec{req("calendarId", ""), req("summary", ""), req("start", "RFC3339"), req("end", "RFC3339"), opt("description", ""), opt("location", ""), opt("allDay", "true|false"), opt("status", "confirmed|tentative|cancelled"), opt("transparency", "opaque|transparent (busy|free); shown as busy when unset"), opt("reminders", ""), opt("recurrence", "RRULE list")}},
	{Name: "events.update", Group: "events", Desc: "Update an event", Params: []ParamSpec{req("id", ""), opt("summary", ""), opt("start", "RFC3339"), opt("end", "RFC3339"), opt("description", ""), opt("location", ""), opt("allDay", "true|false"), opt("status", "confirmed|tentative|cancelled"), opt("transparency", "opaque|transparent (busy|free)"), opt("reminders", ""), opt("recurrence", "RRULE list"), opt("scope", "series (default) or occurrence; occurrence writes a RECURRENCE-ID exception"), opt("occurrenceStart", "RFC3339 start of the edited occurrence; required for scope=occurrence, shifts the series for scope=series")}},
	{Name: "events.delete", Group: "events", Desc: "Delete an event", Params: []ParamSpec{req("id", ""), opt("occurrenceStart", "RFC3339 start of one occurrence; excludes it via EXDATE instead of deleting the series")}},
	{Name: "events.rsvp", Group: "events", Desc: "Respond to a meeting invitation", Params: []ParamSpec{req("id", ""), req("response", "accept|decline|tentative"), opt("occurrenceStart", "RFC3339; reply for this single occurrence of a recurring event")}},
	{Name: "events.parseIcs", Group: "events", Desc: "Preview calendar events, duplicates and busy overlaps", Params: []ParamSpec{req("ics", "iCalendar or vCalendar text"), opt("calendarId", "destination calendar for duplicate detection")}},
	{Name: "events.importIcs", Group: "events", Desc: "Import events from iCalendar data into a calendar", Params: []ParamSpec{req("ics", "iCalendar text"), req("calendarId", ""), opt("uids", "only import these event UIDs")}},

	{Name: "tasks.list", Group: "tasks", Desc: "List tasks", Params: []ParamSpec{opt("query", "text filter"), opt("calendarId", "limit to one task list"), opt("includeCompleted", "true|false, default true"), opt("limit", ""), opt("offset", "")}},
	{Name: "tasks.get", Group: "tasks", Desc: "Get a task by id", Params: []ParamSpec{req("id", "")}},
	{Name: "tasks.create", Group: "tasks", Desc: "Create a task", Params: []ParamSpec{req("calendarId", ""), req("summary", ""), opt("description", ""), opt("location", ""), opt("due", "RFC3339"), opt("start", "RFC3339"), opt("allDay", "true|false"), opt("priority", "0-9"), opt("status", "needs_action|in_process|completed|cancelled"), opt("parentUid", ""), opt("reminders", ""), opt("recurrence", "RRULE list")}},
	{Name: "tasks.update", Group: "tasks", Desc: "Update a task", Params: []ParamSpec{req("id", ""), opt("summary", ""), opt("description", ""), opt("location", ""), opt("due", "RFC3339"), opt("start", "RFC3339"), opt("allDay", "true|false"), opt("priority", "0-9"), opt("percentComplete", "0-100"), opt("status", "needs_action|in_process|completed|cancelled"), opt("parentUid", ""), opt("reminders", ""), opt("recurrence", "RRULE list")}},
	{Name: "tasks.complete", Group: "tasks", Desc: "Mark a task complete or reopen it", Params: []ParamSpec{req("id", ""), opt("completed", "true|false, default true")}},
	{Name: "tasks.delete", Group: "tasks", Desc: "Delete a task", Params: []ParamSpec{req("id", "")}},

	{Name: "reminders.upcoming", Group: "reminders", Desc: "List upcoming reminders", Params: []ParamSpec{opt("limit", "default 20")}},
	{Name: "reminders.test", Group: "reminders", Desc: "Fire a test reminder notification"},

	{Name: "files.list", Group: "files", Desc: "List a directory, or page a live watch when watchId is given", Params: []ParamSpec{req("path", "absolute directory path"), opt("watchId", "page from this watch instead of re-reading"), opt("includeHidden", "include dot-prefixed and .hidden entries"), opt("sort", "name|size|mtime|type"), opt("desc", "reverse the sort"), opt("dirsFirst", "directories before files (default true)"), opt("limit", "page size (default 500)"), opt("cursor", "cursor from the previous page"), opt("filters", "file name globs, case-insensitive; directories always pass")}},
	{Name: "files.watch", Group: "files", Desc: "List a directory and stream changes on files:<watchId>", Params: []ParamSpec{req("path", "absolute directory path"), opt("includeHidden", "include dot-prefixed and .hidden entries"), opt("sort", "name|size|mtime|type"), opt("desc", "reverse the sort"), opt("dirsFirst", "directories before files (default true)"), opt("limit", "page size (default 500)"), opt("filters", "file name globs, case-insensitive; directories always pass")}},
	{Name: "files.unwatch", Group: "files", Desc: "Close a watch and its event topic", Params: []ParamSpec{req("watchId", "id from files.watch")}},
	{Name: "files.stat", Group: "files", Desc: "Metadata for a single path", Params: []ParamSpec{req("path", "absolute path")}},
	{Name: "files.count", Group: "files", Desc: "Child counts for directories, capped at 10000", Params: []ParamSpec{req("paths", "absolute directory paths"), opt("includeHidden", "count dot-prefixed entries")}},
	{Name: "files.thumbnail", Group: "files", Desc: "Thumbnail cache paths, generating what is missing", Params: []ParamSpec{req("paths", "absolute file paths"), opt("size", "normal|large|x-large|xx-large"), opt("watchId", "deliver late results on this watch topic")}},
	{Name: "files.userDirs", Group: "files", Desc: "XDG user directories, home first"},
	{Name: "files.icon", Group: "files", Desc: "Icon name ladders for paths or mime types", Params: []ParamSpec{opt("paths", "absolute paths"), opt("mimes", "mime types")}},
	{Name: "files.size", Group: "files", Desc: "Scan paths recursively, streaming totals on the sizes topic", Params: []ParamSpec{req("paths", "absolute paths")}},
	{Name: "files.sizeCancel", Group: "files", Desc: "Stop a running recursive scan", Params: []ParamSpec{req("scanId", "id from files.size")}},
	{Name: "files.mkdir", Group: "files", Desc: "Create a directory whose parent exists, without undo", Params: []ParamSpec{req("path", "absolute path of the new directory")}},
	{Name: "files.rename", Group: "files", Desc: "Rename a path in place, refusing an existing target, without undo", Params: []ParamSpec{req("path", "absolute path"), req("name", "new name")}},
	{Name: "files.trash", Group: "files", Desc: "Move paths to the trash, reporting each failure, without undo", Params: []ParamSpec{req("paths", "absolute paths")}},

	{Name: "ui.show", Group: "ui", Desc: "Show the calendar window", Params: []ParamSpec{opt("view", "month|week|day|agenda")}},
	{Name: "ui.open", Group: "ui", Desc: "Open a webcal/ICS subscription link in the UI", Params: []ParamSpec{req("url", "webcal:// or https ICS URL")}},
	{Name: "ui.openIcs", Group: "ui", Desc: "Open iCalendar data in the import dialog", Params: []ParamSpec{req("ics", "iCalendar text"), opt("name", "file name shown in the dialog")}},
	{Name: "ui.openEvent", Group: "ui", Desc: "Open a specific event's details window", Params: []ParamSpec{req("uid", "event iCal UID"), opt("start", "occurrence start RFC3339 for recurring events")}},
	{Name: "ui.newEvent", Group: "ui", Desc: "Open the new-event editor", Params: []ParamSpec{opt("start", "prefill start RFC3339 (defaults to the next half-hour slot)")}},
	{Name: "ui.hide", Group: "ui", Desc: "Hide the calendar window"},
	{Name: "ui.toggle", Group: "ui", Desc: "Toggle the calendar window", Params: []ParamSpec{opt("view", "month|week|day|agenda")}},
	{Name: "ui.quit", Group: "ui", Desc: "Quit the running daemon"},
	{Name: "ui.restart", Group: "ui", Desc: "Restart the running daemon and reopen the window"},

	{Name: "system.autostart.get", Group: "system", Desc: "Report autostart status"},
	{Name: "system.autostart.set", Group: "system", Desc: "Enable or disable autostart", Params: []ParamSpec{req("enabled", "true|false")}},
	{Name: "system.colorScheme.get", Group: "system", Desc: "Current portal color scheme (0 no-preference, 1 dark, 2 light)"},
	{Name: "system.openUri", Group: "system", Desc: "Open a URI with the default handler via the desktop portal", Params: []ParamSpec{req("uri", "")}},
}

func MethodNames() []string {
	names := make([]string, len(Methods))
	for i, m := range Methods {
		names[i] = m.Name
	}
	sort.Strings(names)
	return names
}

func FindMethod(name string) (MethodSpec, bool) {
	for _, m := range Methods {
		if m.Name == name {
			return m, true
		}
	}
	return MethodSpec{}, false
}
