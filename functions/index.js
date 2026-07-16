// functions/index.js
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore();

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

  const { emoji, partnerDeviceId } = req.body;
  if (!emoji || !partnerDeviceId) return res.status(400).send('Missing params');

  try {
    const tokenDoc = await db.collection('deviceTokens').doc(partnerDeviceId).get();
    if (!tokenDoc.exists) return res.status(404).send('Token not found');

    const fcmToken = tokenDoc.data().fcmToken;
    if (!fcmToken) return res.status(404).send('FCM Token empty');

    const payload = {
      token: fcmToken,
      notification: {
        title: `Your partner updated their mood ${emoji}`,
        body: 'Open Closer to see how they are feeling today 💞'
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

