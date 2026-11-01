package io.github.itsonlyjames.blacklevel

import android.service.notification.NotificationListenerService

// Android only shows other apps' media sessions (MediaSessionManager.getActiveSessions) to an enabled
// notification listener. adb enables this one once (see README); it reads no notifications itself.
class NowPlayingListener : NotificationListenerService()
