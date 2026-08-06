// web/firebase-messaging-sw.js
// FCM Background Service Worker for UniGrid Web App

importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

// Initialize Firebase in the Service Worker with exact dept-ipe credentials
firebase.initializeApp({
  apiKey: "AIzaSyAKJPM0bF7HtrLMaq95cKTTM0HF4NrxgfE",
  projectId: "dept-ipe",
  messagingSenderId: "113354293876",
  appId: "1:113354293876:web:751f8f635f4ca6f79f0721",
  authDomain: "dept-ipe.firebaseapp.com",
  storageBucket: "dept-ipe.firebasestorage.app",
});

// Force immediate activation of updated Service Worker (purges old cached SW)
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) => {
      return Promise.all(names.map((name) => caches.delete(name)));
    }).then(() => clients.claim())
  );
});

const messaging = firebase.messaging();

// ─── Background message handler ───────────────────────────────────────────────
// Called by browser Push API when a notification arrives while the web tab is
// unfocused, minimized, or backgrounded.
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Background message received:', JSON.stringify(payload));

  // Chromium, Safari, Firefox, and Samsung Internet automatically display notifications
  // when `payload.notification` or `payload.webpush.notification` is present in the WebPush payload.
  // Returning early here prevents browsers from showing a second duplicate popup.
  if (payload.notification || (payload.webpush && payload.webpush.notification)) {
    console.log('[SW] Notification block present — handled automatically by browser native engine.');
    return;
  }

  const notificationTitle = (payload.data && payload.data.title) || (payload.notification && payload.notification.title) || 'UniGrid Notification';
  const notificationBody = (payload.data && payload.data.body) || (payload.notification && payload.notification.body) || '';

  const notificationOptions = {
    body: notificationBody,
    icon: 'https://unigrid.netlify.app/icons/Icon-maskable-192.png',
    badge: 'https://unigrid.netlify.app/icons/Icon-maskable-192.png',
    tag: (payload.data && payload.data.messageId) || (payload.notification && payload.notification.tag) || 'unigrid-notification',
    renotify: false,
    data: payload.data || {},
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// ─── Notification click → focus or open tab ───────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const targetUrl = (event.notification.data && event.notification.data.url) || '/';

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
        return clients.openWindow(targetUrl);
      }
    })
  );
});
