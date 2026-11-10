package oauth_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/duxlabs-dev/dux-calendar/core/internal/oauth"
)

func TestBrokerDeliversToRegisteredState(t *testing.T) {
	broker := oauth.NewCallbackBroker()
	ch := broker.Register("state-1")

	delivered := broker.Deliver("state-1", oauth.CallbackPayload{Code: "code-1", State: "state-1"})
	require.True(t, delivered)

	payload, ok := <-ch
	require.True(t, ok)
	assert.Equal(t, "code-1", payload.Code)

	assert.False(t, broker.Deliver("state-1", oauth.CallbackPayload{}), "state should be consumed")
}

func TestBrokerDeliverUnknownState(t *testing.T) {
	broker := oauth.NewCallbackBroker()
	assert.False(t, broker.Deliver("missing", oauth.CallbackPayload{}))
}

func TestBrokerUnregisterClosesChannel(t *testing.T) {
	broker := oauth.NewCallbackBroker()
	ch := broker.Register("state-1")

	broker.Unregister("state-1")

	_, ok := <-ch
	assert.False(t, ok)
}

func TestStartBrokerFlowValidation(t *testing.T) {
	_, err := oauth.StartBrokerFlow(nil, "http://127.0.0.1/cb")
	require.Error(t, err)

	_, err = oauth.StartBrokerFlow(oauth.NewCallbackBroker(), "")
	require.Error(t, err)
}

func TestBrokerFlowProperties(t *testing.T) {
	broker := oauth.NewCallbackBroker()

	first, err := oauth.StartBrokerFlow(broker, "http://127.0.0.1/cb")
	require.NoError(t, err)
	defer first.Close()

	second, err := oauth.StartBrokerFlow(broker, "http://127.0.0.1/cb")
	require.NoError(t, err)
	defer second.Close()

	assert.NotEmpty(t, first.State())
	assert.NotEmpty(t, first.Verifier())
	assert.NotEqual(t, first.State(), second.State())
}

func TestBrokerFlowWaitSuccess(t *testing.T) {
	broker := oauth.NewCallbackBroker()
	flow, err := oauth.StartBrokerFlow(broker, "http://127.0.0.1/cb")
	require.NoError(t, err)

	go broker.Deliver(flow.State(), oauth.CallbackPayload{Code: "auth-code", State: flow.State()})

	result, err := flow.Wait(context.Background(), time.Second)
	require.NoError(t, err)
	assert.Equal(t, "auth-code", result.Code)
	assert.Equal(t, flow.State(), result.State)
}

func TestBrokerFlowWaitErrorPayload(t *testing.T) {
	broker := oauth.NewCallbackBroker()
	flow, err := oauth.StartBrokerFlow(broker, "http://127.0.0.1/cb")
	require.NoError(t, err)

	go broker.Deliver(flow.State(), oauth.CallbackPayload{Error: "access_denied", State: flow.State()})

	_, err = flow.Wait(context.Background(), time.Second)
	require.ErrorContains(t, err, "access_denied")
}

func TestBrokerFlowWaitTimeout(t *testing.T) {
	broker := oauth.NewCallbackBroker()
	flow, err := oauth.StartBrokerFlow(broker, "http://127.0.0.1/cb")
	require.NoError(t, err)

	_, err = flow.Wait(context.Background(), 10*time.Millisecond)
	require.ErrorContains(t, err, "timed out")

	assert.False(t, broker.Deliver(flow.State(), oauth.CallbackPayload{}), "timeout should unregister the state")
}

func TestBrokerFlowWaitContextCancelled(t *testing.T) {
	broker := oauth.NewCallbackBroker()
	flow, err := oauth.StartBrokerFlow(broker, "http://127.0.0.1/cb")
	require.NoError(t, err)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, err = flow.Wait(ctx, time.Second)
	require.ErrorIs(t, err, context.Canceled)
}

func TestBrokerFlowCloseUnregisters(t *testing.T) {
	broker := oauth.NewCallbackBroker()
	flow, err := oauth.StartBrokerFlow(broker, "http://127.0.0.1/cb")
	require.NoError(t, err)

	require.NoError(t, flow.Close())

	_, err = flow.Wait(context.Background(), time.Second)
	require.ErrorContains(t, err, "closed")
}
