// UniGrid — Firebase Cloud Messaging Service Worker
// This file MUST be at the root of the web directory (served at /firebase-messaging-sw.js).
// It handles FCM push notifications when the web tab is in the background or closed.
// Firebase SDK version must match the version used in the app.

importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js');

// ─────────────────────────────────────────────────────────────────────────────
// Initialize Firebase in the service worker context.
// These values MUST match lib/firebase_options.dart (web config).
// ─────────────────────────────────────────────────────────────────────────────
firebase.initializeApp({
  apiKey: 'AIzaSyAKJPM0bF7HtrLMaq95cKTTM0HF4NrxgfE',
  authDomain: 'dept-ipe.firebaseapp.com',
  projectId: 'dept-ipe',
  storageBucket: 'dept-ipe.firebasestorage.app',
  messagingSenderId: '113354293876',
  appId: '1:113354293876:web:751f8f635f4ca6f79f0721',
});

const messaging = firebase.messaging();

// ─────────────────────────────────────────────────────────────────────────────
// Handle background messages (tab hidden or closed).
// When the tab is in the FOREGROUND, FCMService.dart handles the message via
// FirebaseMessaging.onMessage — this handler is only called in the background.
// ─────────────────────────────────────────────────────────────────────────────
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Background message received:', payload);

  const title = payload.data?.title || payload.notification?.title || payload.webpush?.notification?.title || 'UniGrid';
  const body  = payload.data?.body  || payload.notification?.body  || payload.webpush?.notification?.body  || '';
  const tag   = payload.data?.messageId || payload.data?.tag || payload.notification?.tag || 'unigrid-notification';

  const options = {
    body: body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: tag,
    renotify: false,
    data: payload.data ?? {},
  };

  return self.registration.showNotification(title, options);
});

// ─────────────────────────────────────────────────────────────────────────────
// Handle notification click — bring the app tab into focus (or open a new tab).
// ─────────────────────────────────────────────────────────────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // If a UniGrid tab is already open, focus it
      for (const client of clientList) {
        if (client.url && 'focus' in client) {
          return client.focus();
        }
      }
      // Otherwise open a new tab
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});
