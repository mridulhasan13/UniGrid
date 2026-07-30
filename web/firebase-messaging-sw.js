// UniGrid — Firebase Cloud Messaging Service Worker
// Served at /firebase-messaging-sw.js
//
// ─── Firebase compat messaging SW behavior (v10.x) ──────────────────────────
// • `onBackgroundMessage` fires for ALL background messages (notification + data).
// • When `onBackgroundMessage` IS registered, Firebase compat does NOT auto-show
//   the notification — it calls our handler and expects us to show it.
// • We ALWAYS call showNotification here.
// • To guard against any future SDK version that might auto-show AND call the
//   handler, we set `tag` on every notification. The browser deduplates by tag:
//   a second notification with the same tag simply replaces the first, so the
//   user still sees exactly ONE notification regardless.

importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAKJPM0bF7HtrLMaq95cKTTM0HF4NrxgfE',
  authDomain: 'dept-ipe.firebaseapp.com',
  projectId: 'dept-ipe',
  storageBucket: 'dept-ipe.firebasestorage.app',
  messagingSenderId: '113354293876',
  appId: '1:113354293876:web:751f8f635f4ca6f79f0721',
});

const messaging = firebase.messaging();

// ─── Background message handler ───────────────────────────────────────────────
// Fires for ALL background messages.
// We ALWAYS show the notification here — Firebase compat does NOT auto-show
// when this handler is registered. The `tag` field prevents any duplicates.
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Background message received:', JSON.stringify(payload));

  // Prefer data fields (sent by Cloud Functions); fall back to notification fields.
  const title = (payload.data && payload.data.title)
      ? payload.data.title
      : (payload.notification && payload.notification.title)
          ? payload.notification.title
          : 'UniGrid';

  const body = (payload.data && payload.data.body)
      ? payload.data.body
      : (payload.notification && payload.notification.body)
          ? payload.notification.body
          : '';

  // Use messageId as tag so the browser deduplicates — same message = same tag
  // = replaces any existing notification with the same tag (1 popup max).
  const tag = (payload.data && payload.data.messageId)
      ? payload.data.messageId
      : (payload.notification && payload.notification.tag)
          ? payload.notification.tag
          : 'unigrid-msg';

  if (!title && !body) {
    console.log('[SW] Empty title and body — skipping notification.');
    return;
  }

  console.log('[SW] Showing notification:', title, body);
  return self.registration.showNotification(title, {
    body: body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: tag,
    renotify: false,
    data: payload.data || {},
  });
});

// ─── Notification click → focus or open tab ───────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url && 'focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
