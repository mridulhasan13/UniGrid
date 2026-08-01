// ─────────────────────────────────────────────────────────────────────────────
// migrate_fcm_tokens.js
//
// ONE-TIME migration script — backfills `webTokens` and `nativeTokens` fields
// on all Firestore user documents that have `fcmTokens` but no typed fields.
//
// WHY: The new 4-path notification system (WWSender, WASender, AWSender, AASender)
// reads from `webTokens` / `nativeTokens` exclusively. Users who registered
// before this change only have the generic `fcmTokens` array.
//
// HOW IT DETECTS TOKEN TYPE:
//   - Native Android/iOS tokens contain ":APA91b" in their string
//   - Web Push (VAPID) tokens do NOT contain this string
//   This is the same heuristic used by send-notification.js
//
// RUN FROM: Y:\UniGrid\functions\
//   node migrate_fcm_tokens.js
//
// SAFE TO RE-RUN: Uses arrayUnion — no data is lost if run multiple times.
// DRY RUN: Set DRY_RUN = true below to preview changes without writing.
// ─────────────────────────────────────────────────────────────────────────────

const admin = require("firebase-admin");
const serviceAccount = require("../assets/service_account.json");

// ── Config ───────────────────────────────────────────────────────────────────
const DRY_RUN = false;         // Set true to preview without writing
const BATCH_SIZE = 400;        // Firestore batch limit is 500 — keep headroom
// ─────────────────────────────────────────────────────────────────────────────

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

/** Same heuristic as send-notification.js */
function isWebToken(token) {
  return !token.includes(":APA91b");
}

async function migrate() {
  console.log("═══════════════════════════════════════════════════════");
  console.log(" UniGrid — FCM Token Migration");
  console.log(` Mode: ${DRY_RUN ? "DRY RUN (no writes)" : "LIVE"}`);
  console.log("═══════════════════════════════════════════════════════\n");

  const usersRef = db.collection("users");
  const snapshot = await usersRef.get();

  if (snapshot.empty) {
    console.log("No users found. Exiting.");
    process.exit(0);
  }

  console.log(`Found ${snapshot.size} user document(s). Analysing...\n`);

  let totalUsers      = 0;
  let skippedUpToDate = 0;
  let skippedNoTokens = 0;
  let migrated        = 0;
  let errors          = 0;

  const toUpdate = [];

  for (const doc of snapshot.docs) {
    totalUsers++;
    const data = doc.data();

    const fcmTokens   = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    const singleToken = typeof data.fcmToken === "string" && data.fcmToken ? [data.fcmToken] : [];
    const allTokens   = [...new Set([...fcmTokens, ...singleToken])].filter(Boolean);

    if (allTokens.length === 0) {
      console.log(`  SKIP (no tokens)   uid=${doc.id}`);
      skippedNoTokens++;
      continue;
    }

    const hasWebTokens    = Array.isArray(data.webTokens)    && data.webTokens.length > 0;
    const hasNativeTokens = Array.isArray(data.nativeTokens) && data.nativeTokens.length > 0;
    if (hasWebTokens || hasNativeTokens) {
      console.log(`  SKIP (up-to-date)  uid=${doc.id}  web=${(data.webTokens||[]).length}  native=${(data.nativeTokens||[]).length}`);
      skippedUpToDate++;
      continue;
    }

    const webTokens    = allTokens.filter(t => isWebToken(t));
    const nativeTokens = allTokens.filter(t => !isWebToken(t));

    console.log(
      `  MIGRATE            uid=${doc.id}  ` +
      `total=${allTokens.length}  web=${webTokens.length}  native=${nativeTokens.length}`
    );

    toUpdate.push({ ref: doc.ref, webTokens, nativeTokens });
  }

  console.log(`\n──────────────────────────────────────────────────────`);
  console.log(`  Docs to migrate   : ${toUpdate.length}`);
  console.log(`  Already up-to-date: ${skippedUpToDate}`);
  console.log(`  No tokens         : ${skippedNoTokens}`);
  console.log(`──────────────────────────────────────────────────────\n`);

  if (DRY_RUN) {
    console.log("DRY RUN — no Firestore writes performed.");
    process.exit(0);
  }

  if (toUpdate.length === 0) {
    console.log("Nothing to migrate. All users are already up-to-date!");
    process.exit(0);
  }

  for (let i = 0; i < toUpdate.length; i += BATCH_SIZE) {
    const chunk = toUpdate.slice(i, i + BATCH_SIZE);
    const batch = db.batch();

    for (const { ref, webTokens, nativeTokens } of chunk) {
      const update = {};
      if (webTokens.length > 0) {
        update.webTokens = admin.firestore.FieldValue.arrayUnion(...webTokens);
      }
      if (nativeTokens.length > 0) {
        update.nativeTokens = admin.firestore.FieldValue.arrayUnion(...nativeTokens);
      }
      batch.update(ref, update);
    }

    try {
      await batch.commit();
      migrated += chunk.length;
      console.log(`  ✓ Batch ${Math.floor(i / BATCH_SIZE) + 1} committed (${chunk.length} docs)`);
    } catch (err) {
      errors += chunk.length;
      console.error(`  ✗ Batch ${Math.floor(i / BATCH_SIZE) + 1} FAILED: ${err.message}`);
    }
  }

  console.log(`\n═══════════════════════════════════════════════════════`);
  console.log(` Migration complete`);
  console.log(`   Total users   : ${totalUsers}`);
  console.log(`   Migrated      : ${migrated}`);
  console.log(`   Already OK    : ${skippedUpToDate}`);
  console.log(`   No tokens     : ${skippedNoTokens}`);
  console.log(`   Errors        : ${errors}`);
  console.log(`═══════════════════════════════════════════════════════`);

  process.exit(errors > 0 ? 1 : 0);
}

migrate().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
