// UniGrid — Firebase Cloud Messaging Service Worker
// Served at /firebase-messaging-sw.js

importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js');

// Force immediate activation across all open tabs
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(clients.claim());
});

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
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Background message received:', JSON.stringify(payload));

  // If payload contains notification details, browser/SDK auto-renders it.
  // Skip manual showNotification to prevent double popup.
  if (payload.notification || (payload.webpush && payload.webpush.notification)) {
    console.log('[SW] Notification payload present — browser handles display automatically.');
    return;
  }

  // Handle data-only push messages
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
