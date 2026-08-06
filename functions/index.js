// functions/index.js
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getDatabase } = require('firebase-admin/database');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp({
  databaseURL: 'https://bondly-28e6c-default-rtdb.firebaseio.com'
});
const db = getFirestore();
const rtdb = getDatabase();

async function verifyBearer(req) {
  const authHeader = req.get('authorization') || '';
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) {
    throw Object.assign(new Error('Missing auth token'), { status: 401 });
  }
  return getAuth().verifyIdToken(match[1]);
}

async function getSpaceForMember(spaceId, uid) {
  const spaceSnap = await db.collection('spaces').doc(spaceId).get();
  if (!spaceSnap.exists) {
    throw Object.assign(new Error('Space not found'), { status: 404 });
  }
  const space = spaceSnap.data();
  const members = Array.isArray(space.memberDeviceIds) ? space.memberDeviceIds : [];
  if (!members.includes(uid)) {
    throw Object.assign(new Error('Not a member of this space'), { status: 403 });
  }
  return { spaceSnap, space, members };
}

function memberMap(members) {
  return members.reduce((acc, uid) => {
    if (typeof uid === 'string' && uid.length > 0) acc[uid] = true;
    return acc;
  }, {});
}

async function syncRtdbMembers(spaceId, members) {
  await rtdb.ref(`spaceMembers/${spaceId}`).set(memberMap(members));
}

// Keep RTDB membership in sync with the canonical Firestore space document.
exports.syncSpaceMembers = onDocumentWritten('spaces/{spaceId}', async (event) => {
  const spaceId = event.params.spaceId;
  const after = event.data.after;
  if (!after.exists) {
    await rtdb.ref(`spaceMembers/${spaceId}`).remove();
    return;
  }

  const members = after.data().memberDeviceIds || [];
  await syncRtdbMembers(spaceId, Array.isArray(members) ? members : []);
});

// Repairs/backfills RTDB membership for the signed-in caller when opening an existing space.
exports.ensureSpaceMembership = onRequest({ cors: true }, async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

  try {
    const decoded = await verifyBearer(req);
    const { spaceId } = req.body || {};
    if (!spaceId) return res.status(400).json({ error: 'Missing spaceId' });

    const { members } = await getSpaceForMember(spaceId, decoded.uid);
    await syncRtdbMembers(spaceId, members);
    return res.status(200).json({ success: true });
  } catch (err) {
    const status = err.status || 500;
    console.error('[ensureSpaceMembership] failed:', err);
    return res.status(status).json({ error: err.message });
  }
});

// Server-side invite join. The client supplies only the invite code; membership and
// the RTDB mirror are updated atomically by trusted code.
exports.joinSpace = onRequest({ cors: true }, async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

  try {
    const decoded = await verifyBearer(req);
    const inviteCode = String((req.body || {}).inviteCode || '').trim().toUpperCase();
    if (!/^[A-Z0-9]{6}$/.test(inviteCode)) {
      return res.status(400).json({ error: 'Invalid invite code' });
    }

    const query = await db.collection('spaces')
      .where('inviteCode', '==', inviteCode)
      .limit(1)
      .get();

    if (query.empty) return res.status(404).json({ error: 'Code not found' });

    const spaceRef = query.docs[0].ref;
    let members = [];
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(spaceRef);
      if (!snap.exists) {
        throw Object.assign(new Error('Space not found'), { status: 404 });
      }

      const data = snap.data();
      members = Array.isArray(data.memberDeviceIds) ? [...data.memberDeviceIds] : [];
      if (!members.includes(decoded.uid)) {
        if (data.type === 'couple' && members.length >= 2) {
          throw Object.assign(new Error('This couple space is already full'), { status: 409 });
        }
        members.push(decoded.uid);
        tx.update(spaceRef, { memberDeviceIds: members });
      }
    });

    await syncRtdbMembers(spaceRef.id, members);
    return res.status(200).json({ success: true, spaceId: spaceRef.id });
  } catch (err) {
    const status = err.status || 500;
    console.error('[joinSpace] failed:', err);
    return res.status(status).json({ error: err.message });
  }
});

// ─── 1. Daily Question Rotation ──────────────────────────────────────────

exports.rotateDailyQuestion = onSchedule('0 0 * * *', async (event) => {
  const today = new Date();
  const yyyy = today.getFullYear();
  const mm = String(today.getMonth() + 1).padStart(2, '0');
  const dd = String(today.getDate()).padStart(2, '0');
  const dateKey = `${yyyy}-${mm}-${dd}`;

  console.log(`[rotateDailyQuestion] Starting rotation for date: ${dateKey}`);

  let spacesSnap, questionsSnap;
  try {
    [spacesSnap, questionsSnap] = await Promise.all([
      db.collection('spaces').get(),
      db.collection('questions').get(),
    ]);
  } catch (err) {
    console.error('[rotateDailyQuestion] Failed to fetch data:', err);
    return;
  }

  const allQuestions = questionsSnap.docs.map(d => ({ id: d.id, ...d.data() }));

  if (allQuestions.length === 0) {
    console.warn('[rotateDailyQuestion] No questions in Firestore — seed questions first.');
    return;
  }

  const results = await Promise.allSettled(
    spacesSnap.docs.map(async (spaceDoc) => {
      const spaceId = spaceDoc.id;
      try {
        const answersSnap = await db
          .collection('spaces')
          .doc(spaceId)
          .collection('dailyAnswers')
          .select('questionId')
          .get();

        const usedIds = new Set(
          answersSnap.docs
            .map(d => d.data().questionId)
            .filter(Boolean)
        );

        let available = allQuestions.filter(q => !usedIds.has(q.id));
        if (available.length === 0) {
          available = allQuestions;
        }

        const picked = available[Math.floor(Math.random() * available.length)];

        const answerRef = db
          .collection('spaces')
          .doc(spaceId)
          .collection('dailyAnswers')
          .doc(dateKey);

        const existing = await answerRef.get();
        if (!existing.exists) {
          await answerRef.set({
            questionId: picked.id,
            answers: {},
            revealed: false,
            createdAt: FieldValue.serverTimestamp(),
          });
        }
      } catch (spaceErr) {
        console.error(`[rotateDailyQuestion] Space ${spaceId} failed:`, spaceErr);
      }
    })
  );
  console.log(`[rotateDailyQuestion] Done.`);
});

// ─── 2. Push Notifications (Migrated from Vercel) ────────────────────────

exports.moodPing = onRequest({ cors: true }, async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

  try {
    const decoded = await verifyBearer(req);
    const { emoji, partnerDeviceId, spaceId } = req.body;
    if (!emoji || !partnerDeviceId || !spaceId) {
      return res.status(400).send('Missing params');
    }

    const { members } = await getSpaceForMember(spaceId, decoded.uid);
    if (!members.includes(partnerDeviceId)) {
      return res.status(403).send('Partner is not in this space');
    }

    const tokenDoc = await db.collection('deviceTokens').doc(partnerDeviceId).get();
    if (!tokenDoc.exists) return res.status(404).send('Token not found');

    const tokenData = tokenDoc.data();
    if (tokenData.receiveMoodPings === false) {
      return res.status(200).json({ success: true, skipped: 'disabled' });
    }

    const fcmToken = tokenData.fcmToken;
    if (!fcmToken) return res.status(404).send('FCM Token empty');

    const payload = {
      token: fcmToken,
      notification: {
        title: `Your partner updated their mood ${emoji}`,
        body: 'Open Closer to see how they are feeling today 💞'
      },
      data: {
        type: 'mood_ping',
        emoji: String(emoji),
        title: `Your partner updated their mood ${emoji}`,
        body: 'Open Closer to see how they are feeling today'
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'closer_mood_ping',
          defaultSound: true,
          defaultVibrateTimings: false,
          vibrateTimingsMillis: [0, 250, 100, 250]
        }
      }
    };

    await getMessaging().send(payload);
    res.status(200).json({ success: true });
  } catch (err) {
    console.error('Ping failed:', err);
    res.status(500).json({ error: err.message });
  }
});

exports.flashPing = onRequest({ cors: true }, async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

  const { partnerDeviceId } = req.body;
  if (!partnerDeviceId) return res.status(400).send('Missing params');

  try {
    const tokenDoc = await db.collection('deviceTokens').doc(partnerDeviceId).get();
    if (!tokenDoc.exists) return res.status(404).send('Token not found');

    const fcmToken = tokenDoc.data().fcmToken;
    if (!fcmToken) return res.status(404).send('FCM Token empty');

    const payload = {
      token: fcmToken,
      notification: {
        title: 'Your partner uploaded a Flash! 📸',
        body: 'Take a look before it resets at midnight ⚡'
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'closer_mood_ping',
          defaultSound: true,
          defaultVibrateTimings: false,
          vibrateTimingsMillis: [0, 250, 100, 250]
        }
      }
    };

    await getMessaging().send(payload);
    res.status(200).json({ success: true });
  } catch (err) {
    console.error('Flash ping failed:', err);
    res.status(500).json({ error: err.message });
  }
});

exports.callPing = onRequest({ cors: true }, async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

  const { partnerDeviceId, spaceId, callerName } = req.body;
  if (!partnerDeviceId || !spaceId || !callerName) return res.status(400).send('Missing params');

  try {
    const tokenDoc = await db.collection('deviceTokens').doc(partnerDeviceId).get();
    if (!tokenDoc.exists) return res.status(404).send('Token not found');

    const fcmToken = tokenDoc.data().fcmToken;
    if (!fcmToken) return res.status(404).send('FCM Token empty');

    const payload = {
      token: fcmToken,
      data: {
        type: 'call',
        spaceId: spaceId,
        callerName: callerName
      },
      android: {
        priority: 'high'
      },
      apns: {
        payload: {
          aps: {
            'content-available': 1,
            'push-type': 'background',
            priority: 5
          }
        }
      }
    };

    await getMessaging().send(payload);
    res.status(200).json({ success: true });
  } catch (err) {
    console.error('Call ping failed:', err);
    res.status(500).json({ error: err.message });
  }
});

exports.endCallPing = onRequest({ cors: true }, async (req, res) => {
  if (req.method === 'OPTIONS') return res.status(204).send('');
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');

  const { partnerDeviceId, spaceId } = req.body;
  if (!partnerDeviceId || !spaceId) return res.status(400).send('Missing params');

  try {
    const tokenDoc = await db.collection('deviceTokens').doc(partnerDeviceId).get();
    if (!tokenDoc.exists) return res.status(404).send('Token not found');

    const fcmToken = tokenDoc.data().fcmToken;
    if (!fcmToken) return res.status(404).send('FCM Token empty');

    const payload = {
      token: fcmToken,
      data: {
        type: 'end_call',
        spaceId: spaceId
      },
      android: {
        priority: 'high'
      }
    };

    await getMessaging().send(payload);
    res.status(200).json({ success: true });
  } catch (err) {
    console.error('End call ping failed:', err);
    res.status(500).json({ error: err.message });
  }
});

