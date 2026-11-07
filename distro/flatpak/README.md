# Dux Calendar Flatpak

The build provides `dcal` and dux-qt-base, the Quickshell runtime, in `/app/lib/dcal`.
It installs the desktop file, metainfo, and icon as `com.danklinux.dankcalendar`.
The exported desktop file registers ICS/VCS files and webcal/webcals links;
Flatpak rewrites its `%U` launcher for document-portal file forwarding.

## Sandbox permissions

Notifications and credential storage go through the XDG desktop portals
(`org.freedesktop.portal.Notification` and `org.freedesktop.portal.Secret`),
so no direct DBus talk permissions are needed. Credentials are kept in an
encrypted file keyring keyed by the per-app master secret from the Secret
portal.

Dynamic theme colors and fonts from Dux Shell live in the host cache, outside
the sandbox. To enable theme sync, grant read-only access:

```bash
flatpak override --user --filesystem=xdg-cache/dms:ro com.danklinux.dankcalendar
```

Local ICS calendar directories and custom theme files also live outside the
sandbox and need an explicit per-directory grant, e.g.:

```bash
flatpak override --user --filesystem=~/calendars com.danklinux.dankcalendar
```

or the equivalent in Flatseal.

## Build and install

From the repository root:

```bash
flatpak run org.flatpak.Builder \
  --force-clean --user --install --repo=repo \
  --mirror-screenshots-url=https://dl.flathub.org/media \
  --compose-url-policy=full \
  builddir distro/flatpak/com.danklinux.dankcalendar.yml
```

```bash
flatpak run com.danklinux.dankcalendar
```

To rebuild cached modules & tools:

```bash
flatpak run org.flatpak.Builder \
  --force-clean --disable-cache --user --install --repo=repo \
  --mirror-screenshots-url=https://dl.flathub.org/media \
  --compose-url-policy=full \
  builddir distro/flatpak/com.danklinux.dankcalendar.yml
```

## Uninstall

Flatpak stores app data under `~/.var/app/com.danklinux.dankcalendar/` separately from a native `make install`.

```bash
flatpak uninstall --delete-data com.danklinux.dankcalendar
```

## Lint

```bash
flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
  manifest distro/flatpak/com.danklinux.dankcalendar.yml
```

```bash
flatpak run --command=flatpak-builder-lint org.flatpak.Builder \
  repo repo
```
