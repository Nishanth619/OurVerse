// Run this as a Node.js script to seed your Firestore questions collection:
// node seed_questions.js
//
// Prerequisites:
//   npm install firebase-admin
//   Set GOOGLE_APPLICATION_CREDENTIALS env var to your service account JSON path

const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.applicationDefault() });
const db = admin.firestore();

const questions = [
  // FUN
  { text: "What made you genuinely laugh today?", category: "fun" },
  { text: "If you could teleport anywhere right now, where would you go?", category: "fun" },
  { text: "What's the weirdest thing you've eaten this week?", category: "fun" },
  { text: "What song has been stuck in your head lately?", category: "fun" },
  { text: "If your life had a theme song right now, what would it be?", category: "fun" },
  { text: "What's the last thing that surprised you in a good way?", category: "fun" },
  { text: "What's your current go-to snack?", category: "fun" },
  { text: "What's a skill you wish you could learn overnight?", category: "fun" },
  { text: "If you had one free day with zero obligations, how would you spend it?", category: "fun" },
  { text: "What's the most random thing you've Googled recently?", category: "fun" },
  { text: "What hobby would you pick up if money and time weren't an issue?", category: "fun" },
  { text: "What's a movie or show you'd happily rewatch from the start today?", category: "fun" },
  { text: "If you could swap lives with any fictional character for a week, who?", category: "fun" },
  { text: "What's one thing about your childhood you still do as an adult?", category: "fun" },
  { text: "What's your most controversial food opinion?", category: "fun" },

  // DEEP
  { text: "What's something you've been putting off that you know you should do?", category: "deep" },
  { text: "What's a belief you hold that most people in your life probably don't share?", category: "deep" },
  { text: "What does a really good day look like to you?", category: "deep" },
  { text: "What's something you're quietly proud of that you rarely talk about?", category: "deep" },
  { text: "What's a small thing I do that actually means a lot to you?", category: "deep" },
  { text: "What's one thing you wish you'd known 5 years ago?", category: "deep" },
  { text: "What would you do differently if you knew no one would judge you?", category: "deep" },
  { text: "What does home mean to you right now?", category: "deep" },
  { text: "What's the kindest thing a stranger has ever done for you?", category: "deep" },
  { text: "What's a version of yourself that you've let go of?", category: "deep" },
  { text: "What's something you find genuinely hard that looks easy to others?", category: "deep" },
  { text: "What are you currently most afraid of?", category: "deep" },
  { text: "If you could send a message to your past self, what age would you pick?", category: "deep" },
  { text: "What does success look like to you right now, not years from now?", category: "deep" },
  { text: "What's a compliment that really stayed with you?", category: "deep" },

  // SPICY
  { text: "What's your most irrational pet peeve?", category: "spicy" },
  { text: "What's something you secretly find annoying about someone close to you?", category: "spicy" },
  { text: "What's an opinion you have that you'd never say at a family dinner?", category: "spicy" },
  { text: "What's something you've done that you'd never admit on social media?", category: "spicy" },
  { text: "What's a lie you've told recently — even a small one?", category: "spicy" },
  { text: "What's your most embarrassing purchase?", category: "spicy" },
  { text: "If you had to roast me, what would you say?", category: "spicy" },
  { text: "What's a dealbreaker you've softened on?", category: "spicy" },
  { text: "What's one thing about yourself that you'd change if you could?", category: "spicy" },
  { text: "What's the last white lie you told?", category: "spicy" },

  // FRIENDS
  { text: "What's a memory of us that you still randomly think about?", category: "friends" },
  { text: "What's something I do that genuinely makes you feel valued?", category: "friends" },
  { text: "How have you changed since we became friends?", category: "friends" },
  { text: "What's something you've been meaning to tell me but haven't yet?", category: "friends" },
  { text: "If we could plan any trip together, no budget limits, what would it be?", category: "friends" },
  { text: "What's something I helped you realize about yourself?", category: "friends" },

  // LDR
  { text: "What's the first thing you want to do when we're finally in the same city?", category: "ldr" },
  { text: "What part of your day do you most wish I was there for?", category: "ldr" },
  { text: "What's something about your life right now that you want me to understand better?", category: "ldr" },
  { text: "When you're having a hard day, how do you wish I could be there for you?", category: "ldr" },
  { text: "What's one ritual you want us to build when the distance is over?", category: "ldr" },
];

async function seed() {
  const batch = db.batch();
  const col = db.collection('questions');
  questions.forEach(q => {
    const ref = col.doc();
    batch.set(ref, { ...q, usedDates: [] });
  });
  await batch.commit();
  console.log(`✅ Seeded ${questions.length} questions`);
  process.exit(0);
}

seed().catch(err => {
  console.error(err);
  process.exit(1);
});
