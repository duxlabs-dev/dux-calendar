package ipc

import "testing"

func TestParseGoogleStartParamsPassthrough(t *testing.T) {
	t.Setenv("DANKCAL_GOOGLE_CLIENT_ID", "")
	t.Setenv("DANKCAL_GOOGLE_CLIENT_SECRET", "")

	got, err := parseGoogleStartParams(map[string]any{
		"displayName":  " Work ",
		"clientId":     " my-id ",
		"clientSecret": " my-secret ",
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.DisplayName != "Work" || got.ClientID != "my-id" || got.ClientSecret != "my-secret" {
		t.Fatalf("got %+v, want trimmed explicit params", got)
	}
}
