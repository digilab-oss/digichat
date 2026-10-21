// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

package model

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// DIGILAB: the build runs these tests; see IncomingWebhook.MayPostTo.
func TestDigilabIncomingWebhookMayPostTo(t *testing.T) {
	own, other := NewId(), NewId()
	for _, locked := range []bool{true, false} {
		hook := &IncomingWebhook{ChannelId: own, ChannelLocked: locked}
		require.True(t, hook.MayPostTo(own), "ChannelLocked=%v", locked)
		require.False(t, hook.MayPostTo(other), "ChannelLocked=%v", locked)
	}
}

func TestDigilabIncomingWebhookNamesOwnChannel(t *testing.T) {
	own := &Channel{Id: NewId(), Name: "alerts"}
	for _, locked := range []bool{true, false} {
		hook := &IncomingWebhook{ChannelId: own.Id, ChannelLocked: locked}
		require.True(t, hook.NamesOwnChannel("alerts", own), "ChannelLocked=%v", locked)
		require.True(t, hook.NamesOwnChannel("#alerts", own), "ChannelLocked=%v", locked)
		require.False(t, hook.NamesOwnChannel("ops", own), "ChannelLocked=%v", locked)
		require.False(t, hook.NamesOwnChannel("#ops", own), "ChannelLocked=%v", locked)
		require.False(t, hook.NamesOwnChannel("@alerts", own), "ChannelLocked=%v", locked)
		require.False(t, hook.NamesOwnChannel("alerts", &Channel{Id: NewId(), Name: "alerts"}), "ChannelLocked=%v", locked)
	}
}
