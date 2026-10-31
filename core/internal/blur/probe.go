package blur

import (
	client "github.com/duxlabs-dev/dux-go/wayland/client"
)

const backgroundEffectManager = "ext_background_effect_manager_v1"

func ProbeSupport() (bool, error) {
	display, err := client.Connect("")
	if err != nil {
		return false, err
	}
	defer display.Context().Close()

	registry, err := display.GetRegistry()
	if err != nil {
		return false, err
	}

	found := false
	registry.SetGlobalHandler(func(e client.RegistryGlobalEvent) {
		if e.Interface == backgroundEffectManager {
			found = true
		}
	})

	if err := roundtrip(display); err != nil {
		return false, err
	}
	return found, nil
}

func roundtrip(display *client.Display) error {
	callback, err := display.Sync()
	if err != nil {
		return err
	}
	done := false
	callback.SetDoneHandler(func(client.CallbackDoneEvent) {
		done = true
	})
	for !done {
		if err := display.Context().Dispatch(); err != nil {
			return err
		}
	}
	return nil
}
