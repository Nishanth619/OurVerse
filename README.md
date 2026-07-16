# Closer — Flutter App

Daily question + mood check-in + light games for couples and friend groups. 100% free-tier infrastructure (Firebase Spark plan), no login required.

---

## Quick Start

### 1. Firebase setup
```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Create a Firebase project at console.firebase.google.com, then:
flutterfire configure
# This generates lib/firebase_options.dart — never commit this to public repos
```

Enable these in Firebase Console:
- **Authentication** → Anonymous sign-in
- **Firestore Database** → Start in production mode
- **Cloud Messaging** (for future push notifications)
- **Cloud Functions** (Blaze plan required for scheduler)

### 2. Uncomment Firebase lines in main.dart
```dart
// In lib/main.dart, uncomment:
import 'firebase_options.dart';
// ...
options: DefaultFirebaseOptions.currentPlatform,
```

### 3. Install dependencies
```bash
flutter pub get
```

### 4. Run
```bash
flutter run
```

---

## Firestore Security Rules

Paste into Firebase Console → Firestore → Rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Anyone can read/join a space by invite code
    match /spaces/{spaceId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update: if request.auth != null
        && request.auth.uid in resource.data.memberDeviceIds;

      match /dailyAnswers/{date} {
        allow read, write: if request.auth != null
          && request.auth.uid in get(/databases/$(database)/documents/spaces/$(spaceId)).data.memberDeviceIds;
      }

      match /moods/{date} {
        allow read, write: if request.auth != null
          && request.auth.uid in get(/databases/$(database)/documents/spaces/$(spaceId)).data.memberDeviceIds;
      }
    }

    // Questions are read-only for users, writeable only by admin (Cloud Functions)
    match /questions/{questionId} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions can write
    }
  }
}
```

---

## Seed Questions
```bash
# From project root:
npm install firebase-admin
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
node seed_questions.js
```

---

## Deploy Cloud Function (Optional)
```bash
cd functions
npm install
firebase deploy --only functions
```

The function runs at midnight daily to pre-pick tomorrow's question for each space.  
Without it, the app picks its own question on first load — works fine for early users.

---

## Android Home Widget Setup

The widget XML files are at:
- `android/app/src/main/res/layout/closer_widget.xml`
- `android/app/src/main/res/xml/closer_widget_info.xml`

Add to your `AndroidManifest.xml` inside `<application>`:
```xml
<receiver
    android:name=".CloserWidgetProvider"
    android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/closer_widget_info" />
</receiver>
```

Then create `android/app/src/main/kotlin/.../CloserWidgetProvider.kt`:
```kotlin
class CloserWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        // home_widget package handles this via HomeWidget.updateWidget()
    }
}
```

---

## Project Structure

```
lib/
├── core/
│   ├── constants/        # AppConstants
│   ├── theme/            # AppTheme (palette, typography)
│   └── utils/            # AppUtils (date helpers, invite code)
├── data/
│   ├── models/           # SpaceModel, QuestionModel, etc.
│   ├── repositories/     # SpaceRepository, QuestionRepository
│   └── services/         # AuthService, NotificationService, HomeWidgetService
├── features/
│   ├── onboarding/       # Welcome, Create Space, Join Space
│   ├── home/             # Home screen + shell nav
│   ├── question/         # Question detail + reveal
│   ├── games/            # Would You Rather
│   └── settings/         # Space info, notifications, widget mode
├── shared/
│   └── providers/        # All Riverpod providers
├── router.dart           # GoRouter config
└── main.dart             # Entry point
```

---

## Build for Play Store
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab`

---

## Phase Roadmap (from spec)

- [x] Phase 1 — Core loop (space, daily question, mood, streak, notifications)
- [x] Phase 2a — Would You Rather game
- [ ] Phase 2b — home_widget native Kotlin provider
- [ ] Phase 2c — Expand question bank (seed script ready)
- [ ] Phase 3 — App icon, splash, store listing
- [ ] Phase 4 — Launch + Day-7 retention watch
