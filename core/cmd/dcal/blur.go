package main

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/duxlabs-dev/dux-calendar/core/internal/blur"
)

var blurCmd = &cobra.Command{
	Use:   "blur",
	Short: "Background blur utilities",
}

var blurCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Report whether the compositor supports ext-background-effect-v1 blur",
	Args:  cobra.NoArgs,
	RunE: func(_ *cobra.Command, _ []string) error {
		supported, err := blur.ProbeSupport()
		if err != nil {
			return err
		}
		fmt.Println(blurVerdict(supported))
		return nil
	},
}

func blurVerdict(supported bool) string {
	if supported {
		return "supported"
	}
	return "unsupported"
}

func init() {
	blurCmd.AddCommand(blurCheckCmd)
}
