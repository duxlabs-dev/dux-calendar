package main

import (
	"context"
	"os"
	"strconv"

	"github.com/duxlabs-dev/dux-calendar/core/internal/paths"
	"github.com/duxlabs-dev/dux-calendar/core/internal/qtbaseembed"
	"github.com/duxlabs-dev/dux-calendar/core/internal/settings"
	"github.com/duxlabs-dev/dux-calendar/core/internal/shellembed"
	"github.com/duxlabs-dev/dux-go/shellapp"
)

var shellApp = shellapp.New(shellapp.Config{
	ID:       "dankcal",
	QSAppID:  "dev.duxlabs.calendar",
	Version:  Version,
	Embedded: embeddedShell{},
	QtBase:   qtbaseembed.Extract,
	Boot:     bootBackend,
	ExtraEnv: func(string) []string {
		return uiEnv(settings.Load(), os.Getenv("QT_SCALE_FACTOR") != "", consumeShowAfterRestart())
	},
})

// exec keeps the last duplicate key, so these entries override the inherited
// environment. A QT_SCALE_FACTOR set by the user is left alone.
func uiEnv(s settings.UISettings, envScale, showAfterRestart bool) []string {
	var env []string
	if !envScale {
		scale := strconv.FormatFloat(s.UIScale, 'f', -1, 64)
		env = append(env, "DANKCAL_UI_SCALE="+scale)
		if s.UIScale != 1 {
			env = append(env, "QT_SCALE_FACTOR="+scale)
		}
	}
	if showAfterRestart {
		env = append(env, "DANKCAL_START_HIDDEN=")
	}
	return env
}

func consumeShowAfterRestart() bool {
	path, err := paths.ShowAfterRestartPath()
	if err != nil {
		return false
	}
	return os.Remove(path) == nil
}

func bootBackend(ctx context.Context) (shellapp.Backend, error) {
	svc, err := bootDaemonServices(ctx)
	if err != nil {
		return nil, err
	}
	return svc, nil
}

type embeddedShell struct{}

func (embeddedShell) Available() bool { return shellembed.Available() }

func (embeddedShell) Extract(baseDir string) (string, error) { return shellembed.Extract(baseDir) }

func (embeddedShell) Prune(baseDir, keep string) { shellembed.Prune(baseDir, keep) }
