const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// ─────────────────────────────────────────────
// Helper: Send notification to a specific department and batch
// ─────────────────────────────────────────────
async function notifyScopedUsers(dept, batch, title, body, senderUserId) {
  try {
    const usersSnap = await admin.firestore().collection("users")
        .where("department", "==", dept)
        .where("batch", "==", batch)
        .get();

    const tokens = [];
    usersSnap.forEach((doc) => {
      const data = doc.data();
      // Exclude sender and ensure token exists
      if (doc.id !== senderUserId && data.fcmToken) {
        tokens.push(data.fcmToken);
      }
    });

    if (tokens.length === 0) {
      console.log(`No tokens found to notify in department: ${dept}, batch: ${batch}`);
      return;
    }

    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokens,
      notification: {
        title: title,
        body: body,
      },
      data: {
        senderUserId: senderUserId || "",
      },
      android: {
        notification: {
          channelId: "unigrid_notifications",
          priority: "high",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
      // Required for web push tokens — without this block FCM silently
      // drops the message for browser (PWA / Flutter Web) endpoints.
      webpush: {
        notification: {
          title: title,
          body: body,
          icon: "/icons/Icon-192.png",
          requireInteraction: false,
        },
        fcmOptions: {
          link: "/",
        },
      },
    });

    console.log(`Successfully sent ${tokens.length} messages (successCount: ${response.successCount})`);
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
      const { dept, batch } = context.params;
      const title = `📢 New ${data.type || "Announcement"}`;
      const body = data.title || "A new announcement has been posted.";
      const senderUserId = data.postedByUserId || "";
      await notifyScopedUsers(dept, batch, title, body, senderUserId);
    });

// ─────────────────────────────────────────────
// TRIGGER 2: New Study Material
// ─────────────────────────────────────────────
exports.onNewMaterial = functions.firestore
    .document("depts/{dept}/batches/{batch}/materials/{materialId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const { dept, batch } = context.params;
      const type = data.type || "Material";
      const title = `📚 New ${type} Uploaded`;
      const body = `${data.title || "A new file"} has been added to ${data.subject || "your subjects"}.`;
      const senderUserId = data.uploadedByUserId || "";
      await notifyScopedUsers(dept, batch, title, body, senderUserId);
    });

// ─────────────────────────────────────────────
// TRIGGER 3: New Chat Message (Group Chat)
// ─────────────────────────────────────────────
exports.onNewMessage = functions.firestore
    .document("depts/{dept}/batches/{batch}/chat_messages/{messageId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const { dept, batch } = context.params;

      // Don't notify for image-only messages or system messages
      if (!data.text && !data.content) return null;

      const senderName = data.authorName || "Someone";
      const text = data.text || data.content || "Sent a message.";
      const title = `💬 ${senderName}`;
      // Truncate long messages for the notification body
      const body = text.length > 80 ? text.substring(0, 80) + "..." : text;
      const senderUserId = data.authorId || "";

      await notifyScopedUsers(dept, batch, title, body, senderUserId);
    });

// ─────────────────────────────────────────────
// TRIGGER 4: New Private Message
// ─────────────────────────────────────────────
exports.onNewPrivateMessage = functions.firestore
    .document("conversations/{conversationId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const { conversationId } = context.params;

      // Don't notify if message text is missing
      if (!data.text && !data.uri) return null;

      const authorId = data.authorId;
      if (!authorId) return null;

      // Parse recipientId from conversationId (format: uid1_uid2, sorted alphabetically)
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
        const token = recipientData.fcmToken;
        if (!token) {
          console.log(`No FCM token found for recipient: ${recipientId}`);
          return null;
        }

        const message = {
          token: token,
          notification: {
            title: senderName,
            body: body,
          },
          data: {
            senderUserId: authorId,
          },
          android: {
            notification: {
              channelId: "unigrid_notifications",
              priority: "high",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
          // Required for web push tokens.
          webpush: {
            notification: {
              title: senderName,
              body: body,
              icon: "/icons/Icon-192.png",
              requireInteraction: false,
            },
            fcmOptions: {
              link: "/",
            },
          },
        };

        const response = await admin.messaging().send(message);
        console.log(`Successfully sent private message notification:`, response);
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
      
      // Only notify if user registration needs approval (isApproved is false and they are not auto-approved as CR)
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

        const response = await admin.messaging().sendEachForMulticast({
          tokens: tokens,
          notification: {
            title: title,
            body: body,
          },
          data: {
            senderUserId: "system",
          },
          android: {
            notification: {
              channelId: "unigrid_notifications",
              priority: "high",
            },
          },
        });

        console.log(`Successfully notified ${tokens.length} CR(s) of new registration request`);
      } catch (error) {
        console.error("Error notifying CR of new registration:", error);
      }
    });
