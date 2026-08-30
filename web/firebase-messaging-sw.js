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

// ─── Duplicate Blocker ────────────────────────────────────────────────────────
const seenMessageIds = new Set();
function checkAndMarkDuplicate(id) {
  if (!id) return false;
  // Strip platform prefixes for canonical check
  let clean = id.replace(/^(native_|web_|ww_|wa_|aa_|aw_)/, '');
  if (seenMessageIds.has(clean)) return true;
  if (seenMessageIds.size >= 300) {
    const first = seenMessageIds.values().next().value;
    seenMessageIds.delete(first);
  }
  seenMessageIds.add(clean);
  return false;
}

// ─── Nested Message Thread Storage (WhatsApp Style Stacking) ─────────────────
const threadStacks = new Map(); // tag -> Array of lines

// ─── Background message handler ───────────────────────────────────────────────
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Background message received:', JSON.stringify(payload));

  const data = payload.data || {};
  const msgId = data.messageId || (payload.notification && payload.notification.tag) || ('msg_' + Date.now());

  // 1. Duplicate guard — blocks duplicate deliveries completely
  if (checkAndMarkDuplicate(msgId)) {
    console.log('[SW] Duplicate message suppressed:', msgId);
    return;
  }

  const rawTitle = data.title || (payload.notification && payload.notification.title) || 'UniGrid';
  const rawBody = data.body || (payload.notification && payload.notification.body) || '';
  const senderName = data.senderName || rawTitle;

  const target = (data.target || data.type || data.route || '').toLowerCase();
  const isPrivate = target.includes('private');
  const isChat = isPrivate || target.includes('chat') || data.categoryTag === 'unigrid_chats';

  // Tag determines which thread the notification stacks into
  let tag = data.androidTag || data.categoryTag || 'unigrid_alerts';
  if (isPrivate && data.senderUserId) {
    tag = 'unigrid_dm_' + data.senderUserId;
  } else if (isChat) {
    tag = 'unigrid_batch_chat';
  } else if (target.includes('schedule') || target.includes('routine')) {
    tag = 'unigrid_routine';
  }

  // 2. Nested Stack System
  let stack = threadStacks.get(tag) || [];
  const line = isChat
    ? (isPrivate ? rawBody : (rawTitle && rawTitle !== senderName ? `${rawTitle}: ${rawBody}` : `${senderName}: ${rawBody}`))
    : (rawTitle ? `${rawTitle}: ${rawBody}` : rawBody);

  if (line.trim().length > 0) {
    stack.push(line);
    if (stack.length > 6) stack.shift(); // Keep latest 6 lines
    threadStacks.set(tag, stack);
  }

  let finalTitle = rawTitle;
  let finalBody = rawBody;

  if (stack.length > 1) {
    if (isPrivate) {
      finalTitle = `${senderName} (${stack.length} new messages)`;
      finalBody = stack.slice(-4).map(l => '• ' + l).join('\n');
    } else if (isChat) {
      finalTitle = `Department Chat (${stack.length} new messages)`;
      finalBody = stack.slice(-4).map(l => '• ' + l).join('\n');
    } else {
      finalTitle = `${rawTitle || 'UniGrid'} (${stack.length} updates)`;
      finalBody = stack.slice(-4).map(l => '• ' + l).join('\n');
    }
  }

  const notificationOptions = {
    body: finalBody,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: tag,
    renotify: true,
    requireInteraction: false,
    timestamp: Date.now(),
    data: {
      ...data,
      url: data.url || (data.route ? '/' : 'https://unigrid.netlify.app/'),
      tag: tag,
    },
  };

  return self.registration.showNotification(finalTitle, notificationOptions);
});

// ─── Notification click → focus or open tab & clear stack ─────────────────────
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const notifData = event.notification.data || {};
  const tag = notifData.tag || event.notification.tag;
  if (tag) {
    threadStacks.delete(tag); // Reset stacked messages on tap
  }

  const targetUrl = notifData.url || '/';

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
