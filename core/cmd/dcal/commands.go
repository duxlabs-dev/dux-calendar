package main

import (
	"fmt"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:     "dcal",
	Short:   "Dux Calendar CLI",
	Long:    "Dux Calendar — local, Google, Microsoft, CalDAV, and iCloud calendars in one standalone app.",
	Args:    cobra.NoArgs,
	PreRunE: shellApp.ResolveConfig,
	RunE: func(_ *cobra.Command, _ []string) error {
		return shellApp.CallOrLaunch("ui.show", nil)
	},
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Show version information",
	RunE: func(_ *cobra.Command, _ []string) error {
		if jsonOutput {
			return printJSON(map[string]string{
				"version":   Version,
				"commit":    Commit,
				"buildTime": BuildTime,
			})
		}
		fmt.Printf("dcal %s (commit %s, built %s)\n", Version, Commit, BuildTime)
		return nil
	},
}

func init() {
	rootCmd.PersistentFlags().StringVarP(shellApp.CustomConfigVar(), "config", "c", "", "Path to a UI config dir (containing shell.qml) to use instead of the embedded UI (env: DANKCAL_SHELL_DIR)")
	rootCmd.PersistentFlags().BoolVar(&jsonOutput, "json", false, "Output JSON for programmatic usage (where supported)")

	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(daemonCmd)
	rootCmd.AddCommand(shellApp.Commands()...)
	showCmd.Flags().StringVar(&windowView, "view", "", "Open on a specific view: month|week|day|agenda")
	toggleCmd.Flags().StringVar(&windowView, "view", "", "Open on a specific view: month|week|day|agenda")

	rootCmd.AddCommand(showCmd)
	rootCmd.AddCommand(toggleCmd)
	rootCmd.AddCommand(openCmd)
	rootCmd.AddCommand(ipcCmd)
	rootCmd.AddCommand(accountCmd)
	rootCmd.AddCommand(syncCmd)
	rootCmd.AddCommand(remindersCmd)
	rootCmd.AddCommand(eventsCmd)
	rootCmd.AddCommand(blurCmd)
}
