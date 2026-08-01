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

// Force immediate activation of updated Service Worker (purges old cached SW in Samsung Internet)
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(clients.claim());
});

const messaging = firebase.messaging();

// ─── Background message handler ───────────────────────────────────────────────
// Called by browser Push API when a notification arrives while the web tab is
// unfocused, minimized, or backgrounded.
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Background message received:', JSON.stringify(payload));
  // WebPush notifications configured with `webpush.notification` in FCM HTTP v1
  // are automatically displayed by the browser's native Push engine.
  // We log the payload here for background data sync and do NOT call
  // self.registration.showNotification to prevent duplicate system popups.
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
