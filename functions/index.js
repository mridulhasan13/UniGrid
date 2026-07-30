const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

function isWebToken(token) {
  return token.length >= 140;
}

// ─────────────────────────────────────────────
// Helper: Send notification to target tokens with platform split
// ─────────────────────────────────────────────
async function sendSplitNotification(tokens, title, body, senderUserId, notificationTag) {
  if (!tokens || tokens.length === 0) return;

  const nativeTokens = [];
  const webTokens = [];

  tokens.forEach((t) => {
    if (isWebToken(t)) {
      webTokens.push(t);
    } else {
      nativeTokens.push(t);
    }
  });

  const promises = [];

  // 1. Native tokens (Android / iOS): include top-level `notification`
  if (nativeTokens.length > 0) {
    promises.push(
      admin.messaging().sendEachForMulticast({
        tokens: nativeTokens,
        notification: {
          title: title,
          body: body,
        },
        data: {
          title: title,
          body: body,
          senderUserId: senderUserId || "",
          messageId: notificationTag,
        },
        android: {
          priority: "high",
          notification: {
            title: title,
            body: body,
            channelId: "unigrid_notifications",
            priority: "high",
            tag: notificationTag,
            icon: "@mipmap/ic_launcher",
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: title,
                body: body,
              },
              sound: "default",
            },
          },
        },
      })
    );
  }

  // 2. Web tokens: data + webpush.notification ONLY (NO top-level notification to prevent double popup)
  if (webTokens.length > 0) {
    promises.push(
      admin.messaging().sendEachForMulticast({
        tokens: webTokens,
        data: {
          title: title,
          body: body,
          senderUserId: senderUserId || "",
          messageId: notificationTag,
        },
        webpush: {
          notification: {
            title: title,
            body: body,
            icon: "/icons/Icon-192.png",
            badge: "/icons/Icon-192.png",
            tag: notificationTag,
            renotify: false,
          },
          headers: {
            Urgency: "high",
          },
          fcmOptions: {
            link: "/",
          },
        },
      })
    );
  }

  const results = await Promise.all(promises);
  let totalSuccess = 0;
  let totalFailure = 0;
  results.forEach((res) => {
    totalSuccess += res.successCount;
    totalFailure += res.failureCount;

    if (res.failureCount > 0) {
      res.responses.forEach((resp, idx) => {
        if (!resp.success && resp.error) {
          const errCode = resp.error.code || "";
          if (errCode.includes("not-registered") || errCode.includes("invalid-registration-token")) {
            const deadToken = tokens[idx];
            if (deadToken) {
              console.log(`Purging dead FCM token: ${deadToken.substring(0, 20)}...`);
              admin.firestore().collection("users")
                  .where("fcmTokens", "arrayContains", deadToken)
                  .get()
                  .then((snap) => {
                    snap.forEach((doc) => {
                      doc.ref.update({
                        fcmTokens: admin.firestore.FieldValue.arrayRemove(deadToken),
                      });
                    });
                  })
                  .catch((err) => console.error("Error purging dead token:", err));
            }
          }
        }
      });
    }
  });

  console.log(`Sent notifications: ${totalSuccess} succeeded, ${totalFailure} failed (out of ${tokens.length} tokens).`);
}

// ─────────────────────────────────────────────
// Helper: Send notification to a specific department and batch
// ─────────────────────────────────────────────
async function notifyScopedUsers(dept, batch, title, body, senderUserId, messageId) {
  const notificationTag = messageId || "unigrid-notification";
  try {
    const usersSnap = await admin.firestore().collection("users")
        .where("department", "==", dept)
        .where("batch", "==", batch)
        .get();

    const tokensSet = new Set();
    usersSnap.forEach((doc) => {
      if (doc.id === senderUserId) return;
      const data = doc.data();
      if (Array.isArray(data.fcmTokens)) {
        data.fcmTokens.forEach((t) => { if (t) tokensSet.add(t); });
      }
      if (data.fcmToken) tokensSet.add(data.fcmToken);
    });
    const tokens = Array.from(tokensSet);

    if (tokens.length === 0) {
      console.log(`No tokens found to notify in department: ${dept}, batch: ${batch}`);
      return;
    }

    await sendSplitNotification(tokens, title, body, senderUserId, notificationTag);
  } catch (error) {
    console.error("Error sending scoped messages:", error);
  }
}

// ─────────────────────────────────────────────
// TRIGGER 1: New Announcement
// ─────────────────────────────────────────────
exports.onNewAnnouncement = functions.firestore
    .document("depts/{dept}/batches/{batch}/announcements/{announcementId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const { dept, batch, announcementId } = context.params;
      const id = data.id || announcementId;
      const title = `📢 New ${data.type || "Announcement"}`;
      const body = data.title || "A new announcement has been posted.";
      const senderUserId = data.postedByUserId || "";
      await notifyScopedUsers(dept, batch, title, body, senderUserId, id);
    });

// ─────────────────────────────────────────────
// TRIGGER 2: New Study Material
// ─────────────────────────────────────────────
exports.onNewMaterial = functions.firestore
    .document("depts/{dept}/batches/{batch}/materials/{materialId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const { dept, batch, materialId } = context.params;
      const id = data.id || materialId;
      const type = data.type || "Material";
      const title = `📚 New ${type} Uploaded`;
      const body = `${data.title || "A new file"} has been added to ${data.subject || "your subjects"}.`;
      const senderUserId = data.uploadedByUserId || "";
      await notifyScopedUsers(dept, batch, title, body, senderUserId, id);
    });

// ─────────────────────────────────────────────
// TRIGGER 3: New Chat Message (Group Chat)
// ─────────────────────────────────────────────
exports.onNewMessage = functions.firestore
    .document("depts/{dept}/batches/{batch}/chat_messages/{messageId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const { dept, batch, messageId } = context.params;
      const id = data.id || messageId;

      if (!data.text && !data.content) return null;

      const senderName = data.authorName || "Someone";
      const text = data.text || data.content || "Sent a message.";
      const title = `💬 ${senderName}`;
      const body = text.length > 80 ? text.substring(0, 80) + "..." : text;
      const senderUserId = data.authorId || "";

      await notifyScopedUsers(dept, batch, title, body, senderUserId, id);
    });

// ─────────────────────────────────────────────
// TRIGGER 4: New Private Message
// ─────────────────────────────────────────────
exports.onNewPrivateMessage = functions.firestore
    .document("conversations/{conversationId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const { conversationId, messageId } = context.params;
      const id = data.id || messageId;
      const notificationTag = id || "unigrid-notification";

      if (!data.text && !data.uri) return null;

      const authorId = data.authorId;
      if (!authorId) return null;

      const participants = conversationId.split("_");
      const recipientId = participants.find((id) => id !== authorId);
      if (!recipientId) return null;

      const senderName = data.authorName || "Someone";
      const text = data.text || "Sent an image.";
      const body = text.length > 80 ? text.substring(0, 80) + "..." : text;

      try {
        const recipientSnap = await admin.firestore().doc(`users/${recipientId}`).get();
        if (!recipientSnap.exists) return null;

        const recipientData = recipientSnap.data();
        const tokensSet = new Set();
        if (Array.isArray(recipientData.fcmTokens)) {
          recipientData.fcmTokens.forEach((t) => { if (t) tokensSet.add(t); });
        }
        if (recipientData.fcmToken) tokensSet.add(recipientData.fcmToken);
        const tokens = Array.from(tokensSet);

        if (tokens.length === 0) {
          console.log(`No FCM tokens found for recipient: ${recipientId}`);
          return null;
        }

        await sendSplitNotification(tokens, senderName, body, authorId, notificationTag);
      } catch (error) {
        console.error("Error sending private message notification:", error);
      }
    });

// ─────────────────────────────────────────────
// TRIGGER 5: New User Registration (Awaiting Approval)
// ─────────────────────────────────────────────
exports.onNewUserRegistration = functions.firestore
    .document("users/{userId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      
      if (data.isApproved === true || data.isCR === true) return null;

      const studentName = data.name || "Someone";
      const studentId = data.studentId || "";
      const department = data.department || "";
      const batch = data.batch || "";

      try {
        const crSnap = await admin.firestore().collection("users")
            .where("department", "==", department)
            .where("batch", "==", batch)
            .where("isCR", "==", true)
            .get();

        const tokens = [];
        crSnap.forEach((doc) => {
          const crData = doc.data();
          if (crData.fcmToken) {
            tokens.push(crData.fcmToken);
          }
        });

        if (tokens.length === 0) {
          console.log(`No CRs found to notify for ${department} Batch ${batch}`);
          return null;
        }

        const title = "🆕 New Registration Request";
        const body = `${studentName} (ID: ${studentId}) registered in ${department} Batch ${batch}. Tap to review/approve.`;

        await sendSplitNotification(tokens, title, body, "system", "unigrid-registration");
      } catch (error) {
        console.error("Error notifying CR of new registration:", error);
      }
    });
