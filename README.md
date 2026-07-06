# UniGrid Digital Hub

This is the central app for our UniGrid platform. We built it to make sharing notes, checking schedules, keeping track of class test marks, and chatting with each other much easier than using scattered messenger groups.

---

## Features

### Notes and study materials
* **Upload multiple files at once:** You can select a bunch of slides, books, or note PDFs together. The app will upload them all in the background so you do not have to do it one by one.
* **Review files before uploading:** When you select files, a clean list shows up listing their names and sizes. If you accidentally picked the wrong document, just click the delete button next to it before starting the upload.
* **Class Test (CT) Marks:** Class Representatives can upload several CT Marks PDFs for a course. They will show up as clean gradient badges on the course registry card, and you can just tap them to open.
* **Automatic naming:** The app automatically appends the actual filename to whatever title you type in so notes are always easy to tell apart.

### Chats and image sharing
* **Group and private chats:** We have real-time chat rooms for group discussions and private one-on-one messages.
* **Send multiple images:** You can pick and send multiple photos at the same time. The chat list will show a preview like "3 Images" so you know what was sent.

### Deletion and security
* **Deletions are protected:** Only Class Representatives or the student who originally uploaded a note can delete it. This prevents people from accidentally deleting shared study materials.
* **Double check:** A confirmation dialog pops up whenever you click delete to make sure you actually meant to do it.
* **Pending accounts:** To keep the portal secure, newly registered accounts are set to pending until a Class Representative or Admin approves them.
* **Administrative Data Wiping:** Class Representatives can instantly purge all previous announcements, department chat history, and direct messages in one single safe administrative swipe, making new semester transitions completely seamless.

### Calendar and routine
* **Live schedules:** A shared calendar lists our weekly classes, rooms, and upcoming exams.
* **Easy editing:** Class Representatives can edit class times, rooms, and teacher details in real-time, which updates for everyone instantly.

### Over-the-Air (OTA) Updates & App Lifecycle
* **Dynamic In-App Updates:** The app handles self-updating on startup, entirely bypassing manual APK transfers or App Store searches.
* **Flexible Forced/Optional Update Modes:** Administrators can enforce a mandatory blocking update (for critical fixes/security patches) using an elegant glassmorphic blur block-screen, or offer a dismissible optional update using a premium, sliding glass notification banner at the top of the viewport.
* **Download Speed & Progress Trackers:** Live progress percentage and background download tracking keep users fully informed prior to launching the system's package installer.
* **Manual Profile Check:** Integrates a responsive checker inside the Profile page, locking itself and displaying `Up to Date` once it confirms the local build matches the cloud registry.

---

## How the Features are Built

### Multi-File Upload and Naming
We use the `file_picker` package configured with `allowMultiple: true` to let users select multiple files at once from their device or browser. To prevent memory and race condition issues, the selected files are processed sequentially. The app iterates through the files, uploads each file bytes/stream asynchronously to Supabase Storage, and maps them to Firestore documents. During notes uploading, the actual filename is parsed and appended to the notes' database record to automatically preserve clean and descriptive naming conventions.

### Platform-Aware Google Authentication
To avoid platform-specific errors on Web targets (such as the standard `UnimplementedError` when calling mobile authentication bindings in Chrome), the login system uses platform-aware dispatching:
* **Web:** We import `package:flutter/foundation.dart` and check `kIsWeb`. If true, the system calls `signInWithPopup(GoogleAuthProvider())` which launches a secure browser popup window, handles OAuth, and redirects the authentication token back seamlessly.
* **Mobile:** If `kIsWeb` is false, it uses `signInWithProvider(GoogleAuthProvider())` to support native Android and iOS redirects safely.

### Role-Based File Deletion
Firestore study material documents store an `uploadedBy` string field that matches the uploader's registered email. When a user views the materials list, the UI performs a reactive check:
```dart
bool canDelete = isCR || (currentUser != null && material.uploadedBy == currentUser.email);
```
If this expression evaluates to true, the delete option is rendered next to the file. Tapping it calls a secure Firestore deletion routine and triggers a Supabase Storage API call to remove the actual file object.

### Cross-Platform Compliance and Link Launching
To ensure links and PDFs open perfectly across different operating systems:
* **Android 11 and above:** Added an explicit `<queries>` tag to `AndroidManifest.xml` containing `http` and `https` intents. This lets Flutter's `url_launcher` search the system package manager and open the default mobile browser without runtime restrictions.
* **iOS Configs:** Added detailed usage description keys in `Info.plist` (such as `NSPhotoLibraryUsageDescription` and `UISupportsDocumentBrowser`) so that iOS grants direct sandbox permissions to access the local file explorer and photo gallery without crashing.

### Live Firestore-Driven OTA Updates
The app leverages the `ota_update` and `package_info_plus` packages combined with Cloud Firestore dynamic document stream listening:
1. On app start, a background listener retrieves the update configuration from `admin_settings/app_update`.
2. The current device `buildNumber` is retrieved from platform packages and compared with `latestBuildNumber` from Firestore.
3. If an update is available:
   - **Forced:** Mounts an un-dismissible glass-morphic layout with a full-screen image-blur and a download trigger.
   - **Optional:** Mounts a sliding `TweenAnimationBuilder` notification card that stays active unless dismissed.
4. Tapping update runs `OtaUpdate().execute()` pointing to the hosted binary. Events are tracked (`OtaStatus.DOWNLOADING`) to paint a detailed progress indicator, before transitioning to `OtaStatus.INSTALLING` to trigger the system APK package manager.

### Transaction-Safe Administrative Data Wiping
To clean up database tables cleanly, the administrative console in `cr_panel_screen.dart` utilizes standard Firestore transaction batches (`WriteBatch`):
* Deletes all department `announcements` documents.
* Deletes all department `chat_messages` documents.
* Wipes global private `conversations` documents.
The entire deletion process is structured within an atomic Firestore batch operation (`batch.commit()`) to prevent partial failures or orphaned database records, wrapped in a strict validation check restricting execution exclusively to users with department-level scope (`hasDeptScope` authorization).

---

## OTA Update Deployment Guide

To deploy a new OTA (Over-the-Air) version update of the UniGrid App to your users, follow these step-by-step instructions:

### 1. Build the Release APK
In your terminal, build the production release APK from the project root:
```bash
flutter build apk --release
```
This compiles the application and outputs the production APK at:
`build/app/outputs/flutter-apk/app-release.apk`

### 2. Host the APK on Dropbox (Direct Download Link)
For dynamic in-app updating via the `ota_update` plugin, the app needs a direct binary file stream download link.
* > [!WARNING]
  > **Do not use Google Drive:** Google Drive shows an intermediary HTML page saying *"Google Drive can't scan this file for viruses"* for files of this size, which breaks the programmatic background stream parser of `OtaUpdate`.
* **Use Dropbox:** 
  1. Upload the built `app-release.apk` file to a Dropbox folder.
  2. Create a sharing link for the file. The generated sharing link will look like:
     `https://www.dropbox.com/scl/fi/abc123xyz/app-release.apk?rlkey=key123&dl=0`
  3. **Convert to a direct download link:** Change the `dl=0` at the very end of the sharing link to **`dl=1`**:
     `https://www.dropbox.com/scl/fi/abc123xyz/app-release.apk?rlkey=key123&dl=1`
     *(This forces the server to return the raw binary application/vnd.android.package-archive stream instead of HTML wrapper pages).*

### 3. Update the Firestore Cloud Registry
Go to your Firebase Console and update the single update configuration document located at:
**Collection:** `admin_settings`  
**Document:** `app_update`

Set/update the following fields:
* `latestBuildNumber` (`Number`): The integer build number of the new release (e.g., `2`, which must be greater than the user's current build number defined in `pubspec.yaml`).
* `latestVersion` (`String`): The human-readable version name (e.g., `"1.0.1"`).
* `downloadUrl` (`String`): The converted Dropbox direct link ending in `?dl=1`.
* `forceUpdate` (`Boolean`): Set to `true` to block the app interface and force an immediate update, or `false` to display a dismissible top sliding banner that can be updated later.

Once updated, all running app instances will reactively receive the config and prompt users to update instantly!

---

## Tech Stack

* **Frontend:** Flutter and Dart (Runs smoothly on Web, Android, and iOS)
* **Auth:** Firebase Auth with Google Sign-In
* **Database:** Cloud Firestore
* **Storage:** Supabase Storage (Where notes and chat images are stored)

---

## Local Setup

### What you need
* Make sure you have the Flutter SDK installed on your machine.

### How to run it

1. **Clone the repository:**
   ```bash
   git clone https://github.com/mridulhasan13/UniGrid.git
   cd UniGrid
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Add Firebase config files:**
   * Create a Firebase project in your console.
   * Drop `google-services.json` inside the `android/app/` folder.
   * Drop `GoogleService-Info.plist` inside the `ios/Runner/` folder.
   * Configure Google Sign-in on your Firebase authentication console.

4. **Add Supabase keys:**
   * Set up a public storage bucket named `notes` in your Supabase console.
   * Paste your Supabase project URL and public anon key in `lib/services/supabase_config.dart`.

5. **Run the app:**
   * For web:
     ```bash
     flutter run -d chrome
     ```
   * For mobile:
     ```bash
     flutter run
     ```

---

## Platform Notes

### Android (11 and above)
Android 11 restricts opening external links by default. We have added package query intents in `AndroidManifest.xml` so that academic PDFs and links open perfectly in your web browser.

### iOS Configuration
We have added security keys in `Info.plist` describing why the app needs access to the photo library (for choosing slides and avatar images) and camera (for taking photos in chat) to prevent the app from crashing on iPhones.

---

## Directory Structure

To keep the repository clean and scalable, the codebase follows a highly organized, modular structure. For a comprehensive, file-by-file breakdown of every module, model, service, and view within the application, please refer to our detailed **[STRUCTURE.md](file:///b:/UniGrid/STRUCTURE.md)** architecture guide.

Here is a high-level overview of the folder hierarchy:
* **`lib/models/`**: Structured schema declarations mapping database records into strongly-typed Dart objects.
* **`lib/screens/`**: Page layouts, visual interfaces, data streams, and platform-specific view layers.
* **`lib/services/`**: Connection logic interfacing with Firebase Authentication, Cloud Firestore, Supabase Storage, and Notification APIs.
* **`lib/utils/`**: Design tokens, glassmorphic palette parameters, typography tables, and academic mapping helpers.
* **`lib/widgets/`**: Reusable structural interface blocks, weekly calendars, and global middleware wrappers (Offline gates and OTA update panels).

---

## Developer

<img src="https://mahmudulhasanmridul.netlify.app/m-logo.svg" width="50" height="50" alt="Mahmudul Hasan Mridul Logo" align="left" style="margin-right: 15px;" />

**Mahmudul Hasan Mridul**  
Industrial and Production Engineering Student, Founder, and Developer.

<br clear="left"/>

[![Portfolio](https://img.shields.io/badge/Portfolio-000000?style=for-the-badge&logo=https%3A%2F%2Fmahmudulhasanmridul.netlify.app%2Fm-logo.svg)](https://mahmudulhasanmridul.netlify.app/)
[![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/mridulhasan13)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/mahmudul-hasan-mridul1/)
[![Facebook](https://img.shields.io/badge/Facebook-1877F2?style=for-the-badge&logo=facebook&logoColor=white)](https://www.facebook.com/mahmudulhasan.mridul01/)
[![Instagram](https://img.shields.io/badge/Instagram-E4405F?style=for-the-badge&logo=instagram&logoColor=white)](https://www.instagram.com/mustard_slevalion/)
[![Twitter/X](https://img.shields.io/badge/Twitter/X-000000?style=for-the-badge&logo=x&logoColor=white)](https://x.com/m_h_mridul)
[![Email](https://img.shields.io/badge/Email-D14836?style=for-the-badge&logo=gmail&logoColor=white)](mailto:hmridul27@gmail.com)

---

## License

This project is licensed under the MIT License. Feel free to contribute or adapt it!

