// netlify/functions/send-notification.js
// Pure Node.js zero-dependency FCM HTTP v1 proxy.
// Uses built-in crypto & https modules — NO node_modules needed!

const crypto = require("crypto");
const https = require("https");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

// ─── Post single FCM message to FCM HTTP v1 API ─────────────────────────────
function sendSingleFCM(projectId, accessToken, token, title, bodyText, senderUserId, messageId) {
  const notificationTag = messageId || "unigrid-notification";
  return new Promise((resolve) => {
    const payload = JSON.stringify({
      message: {
        token: token,
        notification: {
          title: title,
          body: bodyText,
        },
        data: {
          title: title,
          body: bodyText,
          senderUserId: senderUserId || "",
          messageId: notificationTag,
        },
        android: {
          priority: "high",
          notification: {
            title: title,
            body: bodyText,
            sound: "default",
            channel_id: "unigrid_notifications",
            tag: notificationTag,
            icon: "@mipmap/ic_launcher",
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: title,
                body: bodyText,
              },
              sound: "default",
            },
          },
        },
        webpush: {
          headers: {
            Urgency: "high",
          },
          fcm_options: { link: "/" },
        },
      },
    });

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

  const { tokens, title, bodyText, senderUserId, messageId } = body;
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return { statusCode: 400, headers: CORS, body: JSON.stringify({ error: "'tokens' array is required" }) };
  }
  if (!title || !bodyText) {
    return { statusCode: 400, headers: CORS, body: JSON.stringify({ error: "'title' and 'bodyText' are required" }) };
  }

  const rawEnv = process.env.SERVICE_ACCOUNT_JSON;
  if (!rawEnv) {
    return { statusCode: 500, headers: CORS, body: JSON.stringify({ error: "SERVICE_ACCOUNT_JSON not set on Netlify" }) };
  }

  let serviceAccount;
  try {
    serviceAccount = typeof rawEnv === "object" ? rawEnv : JSON.parse(rawEnv);
  } catch (err) {
    return { statusCode: 500, headers: CORS, body: JSON.stringify({ error: "Invalid SERVICE_ACCOUNT_JSON: " + err.message }) };
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
    const res = await sendSingleFCM(projectId, accessToken, token, title, bodyText, senderUserId, messageId);
    if (res.status === 200) {
      sentCount++;
    } else {
      failCount++;
      const bodyStr = res.body || "";
      if (res.status === 404 || bodyStr.includes("UNREGISTERED") || bodyStr.includes("NOT_FOUND") || bodyStr.includes("INVALID_ARGUMENT")) {
        deadTokens.push(token);
        console.log(`Identified dead/unregistered FCM token: ${token.slice(0, 20)}...`);
      } else {
        console.warn(`FCM send failed for token ${token.slice(0, 15)}...: ${res.status} ${res.body || res.error}`);
      }
    }
  }

  return {
    statusCode: 200,
    headers: { ...CORS, "Content-Type": "application/json" },
    body: JSON.stringify({ success: true, sent: sentCount, failed: failCount, total: tokens.length, deadTokens: deadTokens }),
  };
};
