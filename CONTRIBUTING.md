# Contributing

Contributions are welcome and encouraged.

To contribute fork this repository, make your changes, and open a pull request.

## Setup

Clone with submodules — the shared widget library ([dux-qml-common](https://github.com/duxlabs-dev/dux-qml-common)) is vendored at `dux-qml-common/` and symlinked into `quickshell/DCommon`:

```bash
git clone --recurse-submodules https://github.com/duxlabs-dev/dux-calendar.git
# or, in an existing clone:
git submodule update --init
```

Install [prek](https://prek.j178.dev/) then activate pre-commit hooks:

```bash
prek install
```

The hooks run `gofmt -s`, `go vet`, `go mod tidy`, and the Go test suite for changes under `core/`, plus generic whitespace/YAML checks.

## Shared widgets (dux-qml-common)

Everything under `quickshell/DCommon/` (core widgets, the file browser, scroll physics) is shared across the DMS suite and lives in the `dux-qml-common` submodule. It is a normal git worktree:

1. Edit files under `dux-qml-common/` (or through the `quickshell/DCommon` symlink — same files) and test in the running app; hot reload works as usual. For isolated widget work, the library is its own runnable config with a gallery: `qs -c dux-qml-common`.
2. Commit and PR those changes in the `dux-qml-common` repo: `cd dux-qml-common && git switch -c my-change`, push, open the PR there.
3. Once merged, bump the pointer here: `make update-common` (updates the submodule and the nix flake input together), then commit alongside any dankcalendar-side changes. If you only bump the submodule, CI syncs `flake.lock` to it automatically on master.

Shared widgets read app-provided singletons (`Theme`, `SettingsData`, ...) through a documented contract — see the dux-qml-common README. If your change needs a new contract property, add it to the library's stub singletons in the same PR, then to `quickshell/Common/` here when you bump.

## VSCode Setup

This is a monorepo, the easiest thing to do is to open an editor in either `quickshell`, `core`, or both depending on which part of the project you are working on.

### QML (`quickshell` directory)

1. Install the [QML Extension](https://doc.qt.io/vscodeext/)
2. Configure `ctrl+shift+p` -> user preferences (json) with qmlls path

**Note:** Paths may vary by distribution. Below are examples for Arch Linux and Fedora.

**Arch Linux:**

```json
{
  "[qml]": {
    "editor.defaultFormatter": "qt-project.qmlls",
    "editor.formatOnSave": true
  },
  "qt-qml.doNotAskForQmllsDownload": true,
  "qt-qml.qmlls.customExePath": "/usr/lib/qt6/bin/qmlls",
  "qt-core.additionalQtPaths": [
    {
      "name": "Qt-6.x-linux-g++",
      "path": "/usr/bin/qmake"
    }
  ]
}
```

**Fedora:**

```json
{
  "[qml]": {
    "editor.defaultFormatter": "qt-project.qmlls",
    "editor.formatOnSave": true
  },
  "qt-qml.doNotAskForQmllsDownload": true,
  "qt-qml.qmlls.customExePath": "/usr/bin/qmlls",
  "qt-core.additionalQtPaths": [
    {
      "name": "Qt-6.x-Fedora-linux-g++",
      "path": "/usr/bin/qmake6"
    }
  ]
}
```

3. Generate `quickshell/.qmlls.ini` so qmlls can resolve `qs.*` and `Quickshell` imports. You don't need to create the file first; this command creates it:

```bash
dcal qs tooling -p quickshell
```

It does not start the app. The generated file is a symlink into `/run/user/<uid>`, so run it again after a reboot. If your dux-qt-base predates the `tooling` command, `rm -f quickshell/.qmlls.ini && touch quickshell/.qmlls.ini` and run the app from `quickshell/` once instead.

4. Make your changes, test, and open a pull request.

**Tip:** Run with hot reload to pick up QML changes without restarting the app:

```bash
# from core/
DCAL_ENABLE_HOTRELOAD=1 go run ./cmd/dcal run -c ../quickshell
```

### I18n/Localization

When adding user-facing strings, ensure they are wrapped in `I18n.tr()` with context, for example.

```qml
import qs.Common

Text {
  text: I18n.tr("Hello World", "<This is context for the translators, example> Hello world greeting shown on the calendar header")
}
```

Preferably, try to keep new terms to a minimum and re-use existing terms where possible. See `quickshell/translations/en.json` for the list of existing terms. (This isn't always possible obviously, but instead of using `Auto-connect` you would use `Autoconnect` since it's already translated)

After adding or changing strings, regenerate the translation template from the repo root:

```bash
make i18n-extract
```

Strings inside `quickshell/DCommon/` are owned by the dux-qml-common repo and synced through the DMS POEditor project, not this one — extraction here deliberately skips them. At runtime `I18n` merges both catalogs (app terms win), with the shared translations shipping inside the submodule at `DCommon/translations/poexports/`.

### GO (`core` directory)

1. Install the [Go Extension](https://code.visualstudio.com/docs/languages/go)
2. Ensure code is formatted with `make fmt`
3. Add appropriate test coverage and ensure tests pass with `make test`
4. Run `go mod tidy`
5. Open pull request

## Go guidelines

All Go commands below run from the `core/` directory (or via the root Makefile, which delegates).

### No CGO

The binary must build and test with `CGO_ENABLED=0`. The Makefile, CI, and pre-commit hooks all enforce this — do not add dependencies that require cgo (the SQLite driver is the pure-Go `modernc.org/sqlite` for this reason). The only exception is the CI race-detector step, which inherently needs cgo.

### Testing

- Tests use [testify](https://github.com/stretchr/testify): `assert`/`require` for plain tests, `suite` when tests share non-trivial setup (see `internal/sync/engine_test.go` or `api/calendar/handlers_test.go`).
- Tests must run sandboxed: no network, no system services, no pre-installed tools. Use `repo.OpenMemory` for an in-memory database, `t.TempDir()` for files, and `httptest`/`humatest` for HTTP. If a test needs named timezones, import `_ "time/tzdata"`.
- Prefer table-driven tests for pure functions.
- Run everything with `make test`, or `make cover` for a coverage report.

### Mocks

Mocks are generated with [mockery](https://vektra.github.io/mockery/) from `.mockery.yml` into `internal/mocks` — never write mocks by hand. To mock a new interface, add it under its package in `.mockery.yml` and run:

```bash
make mocks
```

Generated mocks use the expecter API:

```go
provider := mocks.NewMockProvider(t)
provider.EXPECT().ListCalendars(mock.Anything).Return(cals, nil)
```

### Style

- Use guard statements (early returns) instead of nested conditionals.
- Prefer `switch`/`case` over `if`/`else` chains.
- Keep comments sparse; explain constraints the code can't express, not what the code does.
- `gofmt -s` clean; `golangci-lint run` (config in `core/.golangci.yml`) must pass.

## Generative AI

Using an LLM to help write code is fine. Submitting its output unread is not.

- You are responsible for every line you submit. You have read it, tested it, and can explain it in review.
- Say in the PR when a meaningful part of the code was AI generated.
- Write PR descriptions, issues, and comments yourself. No AI-written or AI-rewritten text. A few plain sentences in your own words beat a page of generated summary. PRs and issues with AI-written text get closed without review.
- Do not file issues or leave comments you have not verified yourself. Reports that do not reproduce get closed.
- PRs that read like unreviewed output, with narrating comments, invented APIs, or style that ignores the file they are in, get closed without review.

## Pull request

Include screenshots/video if applicable in your pull request if applicable, to visualize what your change is affecting.
