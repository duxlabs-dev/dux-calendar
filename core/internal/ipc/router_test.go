package ipc

import (
	"bufio"
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"

	"github.com/duxlabs-dev/dux-go/files"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func routeAndRead(t *testing.T, req Request, deps Deps) map[string]any {
	t.Helper()
	client, srv := net.Pipe()
	t.Cleanup(func() {
		_ = client.Close()
		_ = srv.Close()
	})

	done := make(chan struct{})
	go func() {
		defer close(done)
		Route(context.Background(), NewConnWriter(srv), req, deps)
	}()

	line, err := bufio.NewReader(client).ReadBytes('\n')
	require.NoError(t, err)

	var out map[string]any
	require.NoError(t, json.Unmarshal(line, &out))
	<-done
	return out
}

func TestRouteVersion(t *testing.T) {
	out := routeAndRead(t, Request{ID: 1, Method: "version"}, Deps{Version: "1.2.3"})

	result, ok := out["result"].(map[string]any)
	require.True(t, ok)
	assert.Equal(t, "1.2.3", result["version"])
	assert.Equal(t, float64(APIVersion), result["apiVersion"])
}

func TestRouteUnknownMethod(t *testing.T) {
	out := routeAndRead(t, Request{ID: 2, Method: "nope.nothing"}, Deps{})

	errMsg, ok := out["error"].(string)
	require.True(t, ok)
	assert.Contains(t, errMsg, "unknown method: nope.nothing")
	assert.Nil(t, out["result"])
}

func TestParamString(t *testing.T) {
	params := map[string]any{"name": "main", "count": 3}

	assert.Equal(t, "main", ParamString(params, "name"))
	assert.Empty(t, ParamString(params, "count"))
	assert.Empty(t, ParamString(params, "missing"))
}

func TestParamInt(t *testing.T) {
	params := map[string]any{"float": float64(5), "int": 7, "str": "9"}

	assert.Equal(t, 5, ParamInt(params, "float"))
	assert.Equal(t, 7, ParamInt(params, "int"))
	assert.Zero(t, ParamInt(params, "str"))
	assert.Zero(t, ParamInt(params, "missing"))
}

func TestParamBool(t *testing.T) {
	params := map[string]any{"bool": true, "str": "true", "bad": "nope", "num": 1}

	assert.True(t, ParamBool(params, "bool"))
	assert.True(t, ParamBool(params, "str"))
	assert.False(t, ParamBool(params, "bad"))
	assert.False(t, ParamBool(params, "num"))
	assert.False(t, ParamBool(params, "missing"))
}

func TestParamStringSlice(t *testing.T) {
	params := map[string]any{
		"ids":   []any{"a", "b", 3},
		"plain": "x",
	}

	assert.Equal(t, []string{"a", "b"}, ParamStringSlice(params, "ids"))
	assert.Nil(t, ParamStringSlice(params, "plain"))
	assert.Nil(t, ParamStringSlice(params, "missing"))
}

func TestRouteFilesList(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(root, "x.ics"), nil, 0o644))
	svc := files.NewService(nil, t.TempDir(), nil)
	t.Cleanup(svc.Close)

	out := routeAndRead(t, Request{ID: 3, Method: "files.list", Params: map[string]any{"path": root}}, Deps{Files: svc})

	result, ok := out["result"].(map[string]any)
	require.True(t, ok)
	entries, ok := result["entries"].([]any)
	require.True(t, ok)
	require.Len(t, entries, 1)
	assert.Equal(t, "x.ics", entries[0].(map[string]any)["name"])
}

func TestRouteFilesWithoutService(t *testing.T) {
	out := routeAndRead(t, Request{ID: 4, Method: "files.list", Params: map[string]any{"path": t.TempDir()}}, Deps{})
	assert.Equal(t, "file service unavailable", out["error"])
}

func TestRegisteredFilesMethodsReachTheService(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	deps := Deps{Files: files.NewService(nil, t.TempDir(), nil)}
	t.Cleanup(deps.Files.Close)

	for _, spec := range Methods {
		if spec.Group != "files" {
			continue
		}
		out := routeAndRead(t, Request{ID: 5, Method: spec.Name}, deps)
		assert.NotEqual(t, string(files.CodeNotSupported), out["code"], spec.Name)
	}
}
