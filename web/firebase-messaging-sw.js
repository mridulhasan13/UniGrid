// web/firebase-messaging-sw.js
// FCM Background Service Worker for UniGrid Web App

importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

// Initialize Firebase in the Service Worker
firebase.initializeApp({
  apiKey: "AIzaSy...", // auto-loaded by FCM SDK from options
  projectId: "unigrid-f5979",
  messagingSenderId: "1071295244583",
  appId: "1:1071295244583:web:...",
});

const messaging = firebase.messaging();

// ─── Background message handler ───────────────────────────────────────────────
// Called by browser Push API when a notification arrives while the web tab is
// unfocused, minimized, or backgrounded.
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Background message received:', JSON.stringify(payload));

  const title = (payload.notification && payload.notification.title)
    || (payload.webpush && payload.webpush.notification && payload.webpush.notification.title)
    || (payload.data && payload.data.title)
    || 'UniGrid';

  const body = (payload.notification && payload.notification.body)
    || (payload.webpush && payload.webpush.notification && payload.webpush.notification.body)
    || (payload.data && payload.data.body)
    || '';

  const tag = (payload.data && payload.data.messageId)
    || (payload.webpush && payload.webpush.notification && payload.webpush.notification.tag)
    || 'unigrid-msg';

  if (!title && !body) return;

  // Always show the system desktop notification popup for background web pushes
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
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // If a tab is already open, focus it
      for (let i = 0; i < windowClients.length; i++) {
        const client = windowClients[i];
        if (client.url.includes(self.registration.scope) && 'focus' in client) {
          return client.focus();
        }
      }
      // Otherwise open a new window
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});
