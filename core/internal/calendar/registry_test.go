package calendar_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/duxlabs-dev/dux-calendar/core/internal/calendar"
	"github.com/duxlabs-dev/dux-calendar/core/internal/mocks"
)

func TestRegistryDispatchesByKind(t *testing.T) {
	registry := calendar.NewRegistry()

	factory := mocks.NewMockProviderFactory(t)
	provider := mocks.NewMockProvider(t)

	factory.EXPECT().Kind().Return(calendar.AccountLocal)
	factory.EXPECT().
		Build(context.Background(), calendar.Account{ID: "a", Kind: calendar.AccountLocal}, nil).
		Return(provider, nil)

	registry.Register(factory)

	got, err := registry.Build(context.Background(), calendar.Account{ID: "a", Kind: calendar.AccountLocal}, nil)
	require.NoError(t, err)
	require.Equal(t, provider, got)
}

func TestRegistryReturnsErrorForUnknownKind(t *testing.T) {
	registry := calendar.NewRegistry()
	_, err := registry.Build(context.Background(), calendar.Account{Kind: "wat"}, nil)
	require.Error(t, err)
}
