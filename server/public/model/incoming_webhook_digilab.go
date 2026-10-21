// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

package model

import "strings"

// DIGILAB: an incoming webhook posts only to its own channel. ChannelLocked and the
// bypass_incoming_webhook_channel_lock permission are database state that mmctl or a role reset
// changes, so neither is consulted.
func (o *IncomingWebhook) MayPostTo(channelID string) bool {
	return o.ChannelId == channelID
}

// DIGILAB: whether a request's channel field ("name", "#name" or "@user") names own, the hook's
// channel. Checked before the field is resolved, so a refused request creates no DM and its
// status does not reveal which users or channels exist.
func (o *IncomingWebhook) NamesOwnChannel(requested string, own *Channel) bool {
	if own == nil || own.Id != o.ChannelId || strings.HasPrefix(requested, "@") {
		return false
	}
	return strings.TrimPrefix(requested, "#") == own.Name
}
