// netlify/functions/send-notification.js
// Netlify serverless function for FCM push notification proxy (125k requests/mo free).
//
// Expects POST body: { tokens: string[], title: string, bodyText: string, senderUserId: string }

const admin = require("firebase-admin");

let initialized = false;
function ensureInit() {
  if (admin.apps.length > 0) {
    initialized = true;
    return;
  }
  const raw = process.env.SERVICE_ACCOUNT_JSON;
  if (!raw) throw new Error("SERVICE_ACCOUNT_JSON environment variable not set in Netlify");
  let serviceAccount;
  try {
    serviceAccount = typeof raw === "object" ? raw : JSON.parse(raw);
  } catch (e) {
    throw new Error("Invalid SERVICE_ACCOUNT_JSON format: " + e.message);
  }

  if (serviceAccount.private_key) {
    serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, "\n");
  }

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

  let totalSent = 0;
  let totalFailed = 0;
  const chunkSize = 500;
  const db = admin.firestore();

  try {
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const chunkMessage = { ...message, tokens: chunk };
      const result = await admin.messaging().sendEachForMulticast(chunkMessage);
      totalSent += result.successCount;
      totalFailed += result.failureCount;

      // Clean up dead tokens from this chunk
      if (result.responses) {
        result.responses.forEach(async (resp, idx) => {
          if (!resp.success) {
            const code = resp.error?.code;
            if (
              code === "messaging/registration-token-not-registered" ||
              code === "messaging/invalid-registration-token"
            ) {
              const deadToken = chunk[idx];
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
    }

    console.log(`FCM Multicast total sent ${totalSent}/${tokens.length}`);

    return {
      statusCode: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
      body: JSON.stringify({
        success: true,
        sent: totalSent,
        failed: totalFailed,
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
