// netlify/functions/send-notification.js
// Pure Node.js zero-dependency FCM HTTP v1 proxy.
// Uses built-in crypto & https modules — NO node_modules needed!
//
// KEY DESIGN DECISION — Platform-Split Payload:
//   • Android/iOS tokens: top-level `notification` + `data` (no webpush block)
//   • Web (browser) tokens: `data` only + `webpush.notification` (no top-level notification)
//     This prevents the Firebase Web JS SDK from showing a duplicate system popup
//     while ALSO letting our Service Worker show it once via onBackgroundMessage.
//
//   Web token format: starts with "http" or contains "fcm.googleapis.com/projects"
//   Android/iOS token format: opaque string (no http prefix)

const crypto = require("crypto");
const https = require("https");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ─── Detect if a token belongs to a Web Push subscription ───────────────────
// FCM Web tokens start with a very long base64url string (152+ chars).
// Native tokens are shorter.  Most reliable check is length (web tokens ≥ 140).
function isWebToken(token) {
  // Native Android/iOS FCM tokens contain the signature ':APA91b'.
  // Web Push VAPID tokens do not contain this signature.
  return !token.includes(":APA91b") && token.length >= 140;
}

// ─── Base64Url Helper ────────────────────────────────────────────────────────
function base64UrlEncode(str) {
  return Buffer.from(str)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

// ─── Generate Google OAuth2 Access Token via Private Key RSA-SHA256 ──────────
function getAccessToken(serviceAccount) {
  return new Promise((resolve, reject) => {
    try {
      const now = Math.floor(Date.now() / 1000);
      const header = JSON.stringify({ alg: "RS256", typ: "JWT" });
      const claimSet = JSON.stringify({
        iss: serviceAccount.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        exp: now + 3600,
        iat: now,
      });

      const encodedHeader = base64UrlEncode(header);
      const encodedClaim = base64UrlEncode(claimSet);
      const toSign = `${encodedHeader}.${encodedClaim}`;

      let privateKey = serviceAccount.private_key;
      if (typeof privateKey === "string") {
        privateKey = privateKey.replace(/\\n/g, "\n");
      }

      const signer = crypto.createSign("RSA-SHA256");
      signer.update(toSign);
      const signature = signer.sign(privateKey, "base64")
        .replace(/=/g, "")
        .replace(/\+/g, "-")
        .replace(/\//g, "_");

      const jwt = `${toSign}.${signature}`;
      const postData = `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`;

      const req = https.request(
        "https://oauth2.googleapis.com/token",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
            "Content-Length": Buffer.byteLength(postData),
          },
        },
        (res) => {
          let data = "";
          res.on("data", (chunk) => (data += chunk));
          res.on("end", () => {
            if (res.statusCode === 200) {
              const parsed = JSON.parse(data);
              resolve(parsed.access_token);
            } else {
              reject(new Error(`OAuth failed (${res.statusCode}): ${data}`));
            }
          });
        }
      );

      req.on("error", reject);
      req.write(postData);
      req.end();
    } catch (err) {
      reject(err);
    }
  });
}

// ─── Build Platform-Correct FCM HTTP v1 Payload ──────────────────────────────
function buildPayload(token, title, bodyText, senderUserId, notificationTag, targetPlatform) {
  const data = {
    title: title,
    body: bodyText,
    senderUserId: senderUserId || "",
    messageId: notificationTag,
  };

  const isWeb = targetPlatform ? targetPlatform === "web" : isWebToken(token);

  if (isWeb) {
    // ── Web Browser (PWA / Flutter Web) ──────────────────────────────────────
    // Do NOT include top-level `notification` — it causes Firebase Web SDK to
    // auto-display a system popup AND our onBackgroundMessage SW handler to
    // also call showNotification → double notification.
    // Instead, we use `webpush.notification` only, which is delivered exclusively
    // by the browser's Push API and shown once by our SW.
    return {
      message: {
        token: token,
        data: data,
        webpush: {
          headers: {
            Urgency: "high",
          },
          notification: {
            title: title,
            body: bodyText,
            icon: "https://unigrid.netlify.app/icons/Icon-192.png",
            badge: "https://unigrid.netlify.app/icons/Icon-192.png",
            image: "https://unigrid.netlify.app/icons/Icon-192.png",
            tag: notificationTag,
            renotify: true,
          },
          fcm_options: {
            link: "https://unigrid.netlify.app/",
          },
        },
      },
    };
  } else {
    // ── Android / iOS Native App ──────────────────────────────────────────────
    // Top-level `notification` tells FCM to display system tray notification
    // when the app is in background/terminated.
    // `data` carries extra info for our foreground handler.
    // NO `webpush` block — it would confuse FCM when targeting native tokens.
    return {
      message: {
        token: token,
        notification: {
          title: title,
          body: bodyText,
        },
        data: data,
        android: {
          priority: "high",
          notification: {
            title: title,
            body: bodyText,
            sound: "default",
            channel_id: "unigrid_notifications",
            tag: notificationTag,
            icon: "@mipmap/ic_launcher",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              alert: { title: title, body: bodyText },
              sound: "default",
            },
          },
        },
      },
    };
  }
}

// ─── Post single FCM message to FCM HTTP v1 API ─────────────────────────────
function sendSingleFCM(projectId, accessToken, token, title, bodyText, senderUserId, messageId, targetPlatform) {
  const notificationTag = messageId || "unigrid-notification";
  const payload = JSON.stringify(buildPayload(token, title, bodyText, senderUserId, notificationTag, targetPlatform));

  return new Promise((resolve) => {
    const req = https.request(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
          "Content-Length": Buffer.byteLength(payload),
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          resolve({ status: res.statusCode, body: data });
        });
      }
    );

    req.on("error", (err) => resolve({ status: 500, error: err.message }));
    req.write(payload);
    req.end();
  });
}

// ─── Main Handler ─────────────────────────────────────────────────────────────
exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 204, headers: CORS, body: "" };
  }
  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers: CORS, body: JSON.stringify({ error: "Method not allowed" }) };
  }

  let body;
  try {
    body = JSON.parse(event.body);
  } catch {
    return { statusCode: 400, headers: CORS, body: JSON.stringify({ error: "Invalid JSON body" }) };
  }

  const { tokens, title, bodyText, senderUserId, messageId, targetPlatform } = body;
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return { statusCode: 400, headers: CORS, body: JSON.stringify({ error: "'tokens' array is required" }) };
  }
  if (!title || !bodyText) {
    return { statusCode: 400, headers: CORS, body: JSON.stringify({ error: "'title' and 'bodyText' are required" }) };
  }

  // Require service_account.json directly so Netlify's bundler bundles it into the function zip.
  let serviceAccount;
  try {
    serviceAccount = require("./service_account.json");
    if (!serviceAccount.private_key || !serviceAccount.client_email) {
      return { statusCode: 500, headers: CORS, body: JSON.stringify({ error: "service_account.json is missing required fields (placeholder?)" }) };
    }
  } catch (err) {
    return { statusCode: 500, headers: CORS, body: JSON.stringify({ error: "Could not load service_account.json: " + err.message }) };
  }

  let accessToken;
  try {
    accessToken = await getAccessToken(serviceAccount);
  } catch (err) {
    console.error("OAuth error:", err);
    return { statusCode: 500, headers: CORS, body: JSON.stringify({ error: "OAuth failed: " + err.message }) };
  }

  const projectId = serviceAccount.project_id;
  let sentCount = 0;
  let failCount = 0;
  const deadTokens = [];

  for (const token of tokens) {
    const res = await sendSingleFCM(projectId, accessToken, token, title, bodyText, senderUserId, messageId, targetPlatform);
    if (res.status === 200) {
      sentCount++;
      console.log(`FCM sent OK — ${isWebToken(token) ? "WEB" : "NATIVE"} token: ${token.slice(0, 20)}...`);
    } else {
      failCount++;
      const bodyStr = res.body || "";
      if (res.status === 404 || bodyStr.includes("UNREGISTERED") || bodyStr.includes("NOT_FOUND") || bodyStr.includes("INVALID_ARGUMENT")) {
        deadTokens.push(token);
        console.log(`Dead token detected: ${token.slice(0, 20)}...`);
      } else {
        console.warn(`FCM send failed for ${isWebToken(token) ? "WEB" : "NATIVE"} token ${token.slice(0, 15)}...: ${res.status} ${res.body || res.error}`);
      }
    }
  }

  return {
    statusCode: 200,
    headers: { ...CORS, "Content-Type": "application/json" },
    body: JSON.stringify({ success: true, sent: sentCount, failed: failCount, total: tokens.length, deadTokens }),
  };
};
