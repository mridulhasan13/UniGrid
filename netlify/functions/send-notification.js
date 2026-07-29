// netlify/functions/send-notification.js
// Netlify serverless function for FCM push notification proxy (125k requests/mo free).
//
// Expects POST body: { tokens: string[], title: string, bodyText: string, senderUserId: string }

const admin = require("firebase-admin");

let initialized = false;
function ensureInit() {
  if (initialized) return;
  const raw = process.env.SERVICE_ACCOUNT_JSON;
  if (!raw) throw new Error("SERVICE_ACCOUNT_JSON environment variable not set in Netlify");
  const serviceAccount = JSON.parse(raw);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  initialized = true;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 204, headers: CORS, body: "" };
  }
  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers: CORS, body: JSON.stringify({ error: "Method not allowed" }) };
  }

  let parsed;
  try {
    parsed = JSON.parse(event.body);
  } catch {
    return { statusCode: 400, headers: CORS, body: JSON.stringify({ error: "Invalid JSON body" }) };
  }

  const { tokens, title, bodyText, senderUserId } = parsed;

  if (!Array.isArray(tokens) || tokens.length === 0) {
    return { statusCode: 400, headers: CORS, body: JSON.stringify({ error: "'tokens' must be a non-empty array" }) };
  }
  if (!title || !bodyText) {
    return { statusCode: 400, headers: CORS, body: JSON.stringify({ error: "'title' and 'bodyText' are required" }) };
  }

  try {
    ensureInit();
  } catch (err) {
    console.error("Firebase init error:", err.message);
    return { statusCode: 500, headers: CORS, body: JSON.stringify({ error: err.message }) };
  }

  const message = {
    tokens: tokens,
    notification: {
      title: title,
      body: bodyText,
    },
    data: {
      senderUserId: senderUserId || "",
    },
    android: {
      priority: "high",
      notification: {
        channelId: "unigrid_notifications",
        sound: "default",
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
    webpush: {
      notification: {
        title: title,
        body: bodyText,
        icon: "/icons/Icon-192.png",
        requireInteraction: false,
      },
      fcmOptions: {
        link: "/",
      },
    },
  };

  try {
    const result = await admin.messaging().sendEachForMulticast(message);
    console.log(`FCM Multicast sent ${result.successCount}/${tokens.length}`);

    // Clean up any dead/stale tokens from Firestore asynchronously
    if (result.responses) {
      const db = admin.firestore();
      result.responses.forEach(async (resp, i) => {
        if (!resp.success) {
          const code = resp.error?.code;
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            const deadToken = tokens[i];
            console.log(`Cleaning dead FCM token from Firestore: ${deadToken}`);
            try {
              const snap = await db.collection("users")
                  .where("fcmTokens", "array-contains", deadToken)
                  .get();
              snap.forEach(async (doc) => {
                await doc.ref.update({
                  fcmTokens: admin.firestore.FieldValue.arrayRemove(deadToken),
                });
                if (doc.data().fcmToken === deadToken) {
                  await doc.ref.update({ fcmToken: admin.firestore.FieldValue.delete() });
                }
              });
            } catch (cleanErr) {
              console.error(`Error cleaning dead token:`, cleanErr);
            }
          }
        }
      });
    }

    return {
      statusCode: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
      body: JSON.stringify({
        success: true,
        sent: result.successCount,
        failed: result.failureCount,
        total: tokens.length,
      }),
    };
  } catch (err) {
    console.error("FCM multicast error:", err);
    return {
      statusCode: 500,
      headers: CORS,
      body: JSON.stringify({ error: "FCM multicast failed", detail: err.message }),
    };
  }
};
