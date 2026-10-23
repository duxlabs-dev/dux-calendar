# Dux Calendar

<div align="center">
  <a href="https://duxlabs.dev">
    <img src="assets/danklogo.svg" alt="Dux Calendar" width="200">
  </a>

### Local, Google, Microsoft, CalDAV, and iCloud calendars in one standalone app

Built with [Quickshell](https://quickshell.org/) and [Go](https://go.dev/)

[![GitHub stars](https://img.shields.io/github/stars/duxlabs-dev/dux-calendar?style=for-the-badge&labelColor=101418&color=ffd700)](https://github.com/duxlabs-dev/dux-calendar/stargazers)
[![GitHub License](https://img.shields.io/github/license/duxlabs-dev/dux-calendar?style=for-the-badge&labelColor=101418&color=b9c8da)](https://github.com/duxlabs-dev/dux-calendar/blob/master/LICENSE)
[![AUR version (bin)](<https://img.shields.io/aur/version/dux-calendar-bin?style=for-the-badge&labelColor=101418&color=9ccbfb&label=AUR%20(bin)>)](https://aur.archlinux.org/packages/dux-calendar-bin)
[![AUR version (git)](<https://img.shields.io/aur/version/dux-calendar-git?style=for-the-badge&labelColor=101418&color=9ccbfb&label=AUR%20(git)>)](https://aur.archlinux.org/packages/dux-calendar-git)
[![Flathub version](https://img.shields.io/flathub/v/dev.duxlabs.calendar?style=for-the-badge&labelColor=101418&color=9ccbfb&label=Flathub)](https://flathub.org/apps/dev.duxlabs.calendar)
[![Discord](https://img.shields.io/badge/discord-join?style=for-the-badge&logo=discord&logoColor=ffffff&label=discord&labelColor=101418&color=5865f2)](https://discord.gg/ppWTpKmPgT)
[![Ko-Fi donate](https://img.shields.io/badge/donate-kofi?style=for-the-badge&logo=ko-fi&logoColor=ffffff&label=ko-fi&labelColor=101418&color=f16061&link=https%3A%2F%2Fko-fi.com%2Fduxlabs)](https://ko-fi.com/duxlabs)

</div>

Dux Calendar is a standalone calendar app that brings your Local, [Google](https://calendar.google.com/), [Microsoft](https://outlook.com/), [CalDAV](https://en.wikipedia.org/wiki/CalDAV), and [iCloud](https://www.icloud.com/calendar/) calendars together in one place. It runs as a lightweight daemon with a tray icon, keeps your accounts in sync, and reminds you about events — all with the look and feel of [Dux Shell](https://github.com/duxlabs-dev/dux-shell).

## Repository Structure

This is a monorepo containing both the calendar interface and the core backend services:

```
dankcalendar/
├── quickshell/         # QML-based calendar interface
│   ├── Modules/        # UI components (calendar views, sidebar, tray)
│   ├── Modals/         # Settings, account, event, and search dialogs
│   ├── Services/       # IPC bridge and shell-side state
│   ├── Widgets/        # Calendar-specific Dank UI controls
│   ├── Common/         # Shared resources, themes, and i18n
│   ├── DCommon/     # → symlink into the dux-qml-common submodule
│   └── translations/   # POEditor-managed string catalogs
├── dux-qml-common/    # Shared DMS widget library (git submodule)
├── core/               # Go backend, daemon, and CLI
│   ├── cmd/dcal/       # dcal CLI and daemon entrypoint
│   ├── internal/       # Providers, sync engine, reminders, IPC, OAuth
│   ├── api/            # HUMA + chi HTTP API
│   ├── ent/            # Ent ORM schema and generated code
│   └── repo/           # Repository-pattern data access
├── assets/             # Icons, desktop entry, systemd unit
└── Makefile            # Build, install, and dev targets
```

## See it in Action

<div align="center">

<!-- Screenshots / demo video coming soon -->

</div>

## Installation

### Flatpak

```bash
flatpak install flathub dev.duxlabs.calendar
flatpak run dev.duxlabs.calendar
```

### Arch Linux (AUR)

```bash
# Prebuilt binary
yay -S dux-calendar-bin

# Build from latest git
yay -S dux-calendar-git
```

### From Source

```bash
git clone --recurse-submodules https://github.com/duxlabs-dev/dux-calendar.git
cd dankcalendar
sudo make install
```

Already cloned without submodules? Run `git submodule update --init` first —
the shared widget library ([dux-qml-common](https://github.com/duxlabs-dev/dux-qml-common))
is vendored as a submodule and the build fails without it.

This installs:

- `dcal` binary to `/usr/local/bin` (the Quickshell UI is embedded in the binary)
- Desktop entry + icon

Override the prefix with `PREFIX=/usr sudo make install`.

Release archives for Linux and FreeBSD include the same desktop integration.
After extracting the platform tarball, install its binary and file associations
with `sudo sh scripts/install-release.sh ./dcal-<os>-<arch>`. Set `PREFIX` to
install somewhere other than `/usr/local`.

At launch the embedded UI is unpacked read-only into the session runtime dir
(`$XDG_RUNTIME_DIR/dankcal-shell/`, tmpfs) and verified against the binary on
every start, so editing the unpacked files has no effect. To run a modified
copy of the UI, point dcal at any directory containing a `shell.qml` with
`dcal -c <dir>` or the `DANKCAL_SHELL_DIR` environment variable — there is no
implicit filesystem lookup otherwise.

Optional session service (starts the daemon at login, restarts on failure):

```bash
make install-systemd
systemctl --user enable --now dcal
```

You can also toggle **Start at login** from Settings → General, which manages
an XDG autostart entry that launches `dcal run -d --hidden`.

### Requirements

- [Quickshell](https://quickshell.org) (`qs`)
- Qt 6 declarative (including `Qt.labs.platform` for the tray icon)
- Go 1.25+ (build only — the binary is pure Go, no CGO)

## Features

**Multiple Providers**
Connect Local, Google, Microsoft, CalDAV, and iCloud accounts and view every
calendar in a single unified agenda.

**Background Sync**
A lightweight daemon keeps your accounts in sync and serves the UI over IPC.
Closing the window only hides it — sync and reminders keep running.

**Event Reminders**
Native desktop notifications for upcoming events, with per-event and
per-calendar reminder configuration.

**Tray Integration**
A system tray icon to show, hide, and quit the app, plus quick access to
upcoming events.

**Secure Credentials**
OAuth tokens and account secrets are stored in your system keyring, never in
plaintext.

**Keyboard Navigation**
Full keyboard-driven navigation with a shortcuts overlay, plus spotlight-style
search across your events.

**Localized**
User-facing strings are translatable and managed through POEditor.

## Usage

```bash
dcal           # launch, or show/focus the window if already running
dcal show      # same as above
dcal show --view day   # open (or focus) directly on a view: month|week|day|agenda
dcal toggle    # toggle window visibility
dcal run       # run in the foreground (logs to the terminal)
dcal run -d    # run as a background daemon
dcal restart   # restart the running shell
dcal kill      # stop everything
```

Closing the window only hides it — the daemon and tray icon keep running.
Reopen from the tray icon, the desktop entry, or `dcal show`. Quit entirely
from the tray menu or `dcal kill`.

Manage accounts and sync from the command line:

```bash
dcal account list                 # list connected accounts
dcal account add local ~/cal      # add a local calendar directory
dcal account add caldav           # add a CalDAV / iCloud account
dcal account add google           # sign in with Google (opens your browser)
dcal account add microsoft        # sign in with Microsoft (opens your browser)
dcal account setup google         # optional: use your own Google OAuth client
dcal account setup microsoft      # optional: use your own Microsoft app registration
dcal account remove <account-id>  # remove an account
dcal sync [account-id]            # force a sync
dcal reminders                    # list upcoming reminders
```

Open an `.ics` file, such as a meeting invitation attached to an email, to
preview and import it. The desktop entry registers `dcal` as a `text/calendar`
handler, so opening the attachment from your mail client does the same:

```bash
dcal open invite.ics                          # preview in the import dialog
dcal events import invite.ics --calendar <id> # import from the terminal
dcal events rsvp <event-id> accept            # reply to an imported invitation
```

## Calendar files

Open `.ics` and `.vcs` files with Dux Calendar, or run
`dcal open invitation.ics appointment.vcs`. Event files show a destination calendar
picker and a preview of overlapping events before import. Subscription links and
files carrying a refreshable calendar source open subscription setup instead.

See [calendar file imports](docs/calendar-file-import.md) for supported formats,
conflict-preview behavior, and legacy compatibility.

## Matugen colors

In **Settings → Appearance → Color source**, select **Matugen** to read
`$XDG_CONFIG_HOME/dankcal/matugen-theme.json` (normally
`~/.config/dankcal/matugen-theme.json`). Dux Calendar reloads this file when
it changes. Matugen is optional and runs independently of the app.

Copy the included [template](assets/matugen/dankcalendar.json.template) from
the repository into your Matugen configuration:

```bash
mkdir -p ~/.config/matugen/templates ~/.config/dankcal
cp assets/matugen/dankcalendar.json.template ~/.config/matugen/templates/dankcalendar.json.template
```

Add this entry to `~/.config/matugen/config.toml`:

```toml
[templates.dankcalendar]
input_path = "~/.config/matugen/templates/dankcalendar.json.template"
output_path = "~/.config/dankcal/matugen-theme.json"
```

If you use a custom `XDG_CONFIG_HOME`, adjust these paths to match it. Then
generate your colors:

```bash
matugen image /path/to/wallpaper.png
```

No reload hook is needed. The template generates both `dark` and `light`
palettes; Dux Calendar's light/dark/automatic setting selects the palette.
Its [Matugen template syntax](https://github.com/InioX/matugen-themes) maps
Material colors to the app's existing theme roles.

The theme file is separate from `ui-settings.json`. It accepts either a
flat object of theme roles or `dark`/`light` objects, with colors encoded as
`#RRGGBB`. Partial palettes override only the supplied roles; the selected
preset supplies the remaining colors. Missing, empty, or invalid theme
files fall back to the preset. Select **Auto** to follow Dux Shell
again, or **Custom** to load a theme from another path.

For **Flatpak**, set the Matugen entry's `output_path` to
`~/.var/app/dev.duxlabs.calendar/config/dankcal/matugen-theme.json`
and create its parent directory first. This writes directly to the app's
configuration directory without requiring extra sandbox permissions.

## IPC

The daemon exposes a scriptable IPC surface — handy for keybinds and automation:

```bash
dcal ipc ui.toggle
dcal ipc ui.show
dcal ipc ui.show view=day          # open on a specific view: month|week|day|agenda
dcal ipc ui.openEvent uid=<uid>    # open a specific event's details window
dcal ipc events.list from=2026-06-01 to=2026-06-30
dcal ipc accounts.list
dcal ipc reminders.upcoming
dcal ipc system.autostart
```

## Development

```bash
git submodule update --init   # once after clone (or clone with --recurse-submodules)

make run            # build and run against the in-repo quickshell config
make test           # run the Go test suite
make fmt            # format Go code
make update-common  # bump the dux-qml-common submodule + nix flake input together
```

Shared widgets (`quickshell/DCommon/`) live in the
[dux-qml-common](https://github.com/duxlabs-dev/dux-qml-common) submodule —
edit them in place, they hot-reload like any other QML, but they are committed
and PR'd in that repo. See CONTRIBUTING for the workflow.

> **Tip:** Run with hot reload to pick up QML changes without restarting:
>
> ```bash
> # from core/
> DCAL_ENABLE_HOTRELOAD=1 go run ./cmd/dcal run -c ../quickshell
> ```

Install [prek](https://prek.j178.dev/) and activate the hooks:

```bash
prek install
```

The hooks run `gofmt -s`, `go vet`, `go mod tidy`, and the Go test suite for
changes under `core/`, plus generic whitespace/YAML checks.

See [CONTRIBUTING.md](CONTRIBUTING.md) for editor setup, the i18n workflow, and
Go style guidelines.

## Contributing

Contributions welcome. Bug fixes, widgets, features, providers, and translations
all help.

1. Fork the repository
2. Make your changes
3. Test thoroughly (`make test`)
4. Open a pull request

Include screenshots or video in your PR when the change is user-facing.

## Credits

- [Quickshell](https://quickshell.org/) - Shell framework
- [Dux Shell](https://github.com/duxlabs-dev/dux-shell) - Design language and widgets
- [Ent](https://entgo.io/) - Go ORM
- [HUMA](https://huma.rocks/) - HTTP API framework

## License

MIT License - See [LICENSE](LICENSE) for details.

### OAuth client credentials

This repository includes a Google OAuth client and a Microsoft app registration so
`dcal account add google` and `dcal account add microsoft` work out of the box.
Distribution packages built from this repository (AUR, Flathub, Fedora, Debian, Nix,
and the like) are welcome to ship them unchanged — no special permission is needed to
package or redistribute Dux Calendar.

These credential strings identify the upstream Dux Calendar application to Google and
Microsoft. They are not authorized for use by forks, rebranded builds, or unrelated
applications — under [Google's API Services Terms](https://developers.google.com/terms)
and Microsoft's identity platform terms, such projects must register their own OAuth
clients and supply them at build time via `-ldflags -X`, at runtime via
`DANKCAL_GOOGLE_CLIENT_ID` / `DANKCAL_GOOGLE_CLIENT_SECRET` /
`DANKCAL_MICROSOFT_CLIENT_ID`, or in-app via the custom OAuth client option.
