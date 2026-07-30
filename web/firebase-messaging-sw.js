// UniGrid — Firebase Cloud Messaging Service Worker
// Served at /firebase-messaging-sw.js
//
// KEY: When FCM payload contains `notification` at top-level, Firebase JS SDK
// shows the notification automatically. When payload is data-only (no top-level
// `notification`), our onBackgroundMessage fires and we show it manually.
//
// Our Netlify function sends:
//   • Android/iOS tokens → top-level `notification` (handled natively by OS)
//   • Web tokens → NO top-level `notification`, only `webpush.notification`
//
// The Firebase compat SDK handles `webpush.notification` automatically, so
// onBackgroundMessage is NOT called for webpush messages. The browser's built-in
// Push API delivers webpush.notification directly.
//
// This file handles ONLY the data-only fallback case.

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
// This ONLY fires for data-only messages (no `notification` key in payload).
// For webpush.notification messages, the browser handles display automatically.
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Data-only background message:', payload);

  // Extract title/body from data field
  const title = (payload.data && payload.data.title) ? payload.data.title : 'UniGrid';
  const body  = (payload.data && payload.data.body)  ? payload.data.body  : '';
  const tag   = (payload.data && payload.data.messageId) ? payload.data.messageId : 'unigrid-msg';

  if (!title && !body) return;

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
