// UniGrid — Firebase Cloud Messaging Service Worker
// Served at /firebase-messaging-sw.js
//
// ─── How Firebase compat messaging works in a SW ────────────────────────────
// • `onBackgroundMessage` fires for ALL background messages (notification + data).
// • When the FCM payload has `notification` (top-level OR webpush.notification),
//   Firebase compat SDK auto-shows the notification BEFORE calling our handler.
//   → We must NOT call showNotification again to avoid a double popup.
// • When the payload is data-only (no `notification`), Firebase compat does NOT
//   auto-show — our handler MUST call showNotification itself.
//
// Cloud Functions send: top-level `notification` + `data` + `webpush.notification`
// → Firebase compat auto-shows from webpush.notification → we skip manual show.
// → Our handler only needs to run for edge-case data-only messages.

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
// Fires for ALL background messages — notification and data-only alike.
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Background message received:', JSON.stringify(payload));

  // If the payload already has a `notification` field, the Firebase compat SDK
  // auto-displayed it already. Don't show again → prevent double popup.
  if (payload.notification) {
    console.log('[SW] Notification field present — auto-shown by Firebase compat SDK, skipping manual show.');
    return;
  }

  // Data-only message → we must show the notification manually.
  const title = (payload.data && payload.data.title) ? payload.data.title : 'UniGrid';
  const body  = (payload.data && payload.data.body)  ? payload.data.body  : '';
  const tag   = (payload.data && payload.data.messageId) ? payload.data.messageId : 'unigrid-msg';

  if (!title && !body) return;

  console.log('[SW] Data-only message — showing notification manually.');
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
