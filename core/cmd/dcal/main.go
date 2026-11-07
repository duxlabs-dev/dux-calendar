package main

import (
	"os"

	"github.com/duxlabs-dev/dux-calendar/core/internal/qtbaseembed"
	"github.com/duxlabs-dev/dux-go/log"
	"github.com/duxlabs-dev/dux-go/qtbase"
)

var (
	Version   = "dev"
	BuildTime = "unknown"
	Commit    = "unknown"
)

func main() {
	qtbase.MaybeRunAndExit(qtbaseembed.Extract)
	log.SetEnvPrefix("DANKCAL")
	if err := rootCmd.Execute(); err != nil {
		log.Errorf("%v", err)
		os.Exit(1)
	}
}
