# UniGrid

UniGrid is a comprehensive academic coordination and resource management platform developed to streamline communication, scheduling, and coursework distribution across university departments. The platform bridges the operational workflow between students, Class Representatives (CRs), and faculty by replacing fragmented communication channels with a unified, cross-platform workspace.

Built with Flutter, Google Firebase, and Supabase Cloud Storage, UniGrid runs natively across Web, Android, and iOS environments with real-time data synchronization and persistent offline caching.

---

## Overview and Problem Statement

University academic coordination often suffers from fragmented tools. Weekly class schedules are frequently shared as static images, course materials are scattered across third-party drives, and urgent class updates get buried inside high-volume social media group chats.

UniGrid addresses these structural challenges through a dedicated, role-aware academic portal that provides:

1. A dynamic, interactive weekly class routine with real-time status indicators.
2. A categorized, high-speed repository for lecture slides, reference books, and coursework documents.
3. A real-time batch messenger featuring user mentions, message threading, and instant push notifications.
4. Administrative workflows for Class Representatives to manage schedules, approve student registrations, and broadcast announcements.
5. Strict privacy safeguards, role-based database security rules, and user-initiated data deletion controls.

---

## Core Capabilities

### 1. Interactive Routine and Schedule Management
* Dynamic Weekly Timetable: Automatically organizes class periods across weekdays with start and end times, room numbers, course codes, and teacher designations.
* Real-Time Slot Statuses: Class Representatives can flag individual slots as Upcoming, Completed, Cancelled, or No Class. Status changes reflect immediately for all batch members without requiring manual page reloads.
* Faculty and Course Profiles: Tapping any class card opens a detailed sheet displaying the instructor's full name, academic initials, contact credentials, and course information.
* Schedule Overrides and Exam Tracking: Accommodates temporary makeup lectures, rescheduled time slots, and upcoming examination dates.

### 2. Academic Materials and Document Hub
* Multi-File Background Uploads: Students and CRs can upload multiple PDF lecture notes, presentations, and reference books simultaneously.
* Category and Subject Filtering: Materials are automatically indexed by course code, academic subject, and document type (Notes, Books, Videos, Others).
* Cloud Storage Integration: Files are hosted on resilient Supabase object storage buckets, ensuring fast download speeds and direct in-app document viewing via integrated PDF viewers.
* Protected Document Lifecycle: File deletion permissions are strictly enforced. Documents can only be removed by the original uploader or an authorized Class Representative.

### 3. Real-Time Batch Messaging and Collaboration
* Instant Group Communication: Low-latency batch messaging powered by Firebase Firestore real-time streams.
* Smart Mentions: Typing the "@" character brings up an autocomplete member directory to notify specific classmates or broadcast to the entire section.
* High-Resolution Image Sharing: Native image compression preserves the sharpness of handwritten equations, technical drawings, and slides while optimizing network payload size.
* Moderation and Content Reporting: In-app reporting mechanisms allow users to flag inappropriate messages for Class Representative review, ensuring a safe academic environment.

### 4. Class Representative (CR) Administration
* Student Verification and Approval: Newly registered student accounts enter a secure pending queue until verified and approved by the department CR.
* Centralized Routine Builder: Provides CRs with visual schedule drafting tools to define default timetable templates, semester courses, and room allocations.
* Emergency Broadcast Alerts: Dispatches high-priority push notifications across Android, iOS, and Web clients for urgent room changes, cancellations, or official notices.

### 5. Security, Privacy, and User Rights
* Scoped Data Architecture: Database queries and collections are strictly isolated by department and batch identifiers, ensuring students only access their relevant academic environment.
* In-App Account Deletion: Users retain full ownership of their data with a self-service account deletion workflow under Security settings, permanently purging authentication records and personal profiles.
* Transparent Privacy Standards: Fully compliant with Google Play Data Safety requirements and published privacy policies.

---

## System Architecture

UniGrid employs a multi-tiered, reactive client-server architecture designed for reliability and performance:

* Frontend Client: Built with Flutter and Dart, utilizing the Provider state management pattern for reactive UI updates and the IndexedStack pattern for zero-latency screen navigation.
* Authentication Layer: Firebase Authentication handling secure email/password flows and OAuth-based Google Sign-In with cross-platform web and mobile dispatchers.
* Real-Time Database: Google Cloud Firestore configured with unlimited offline persistence and granular security rules enforced at the document level.
* Media and Document Storage: Supabase Cloud Storage managing binary object storage with authenticated token access.
* Push Notification Pipeline: Firebase Cloud Messaging (FCM) combined with local notification channels to guarantee delivery across background, foreground, and terminated application states.

---

## Codebase Organization

The codebase is structured modularly to separate business logic, UI components, and backend integrations:

```
UniGrid/
|-- android/                  # Native Android configuration, manifests, and signing keys
|-- ios/                      # Native iOS Xcode workspace, pods, and permission descriptions
|-- web/                      # Web entry points, service workers, and privacy policy assets
|-- firestore.rules           # Granular Firestore security and role validation rules
|-- lib/
    |-- main.dart             # Application entry point, service initialization, and route guards
    |-- models/               # Strongly-typed data models (User, Routine, Material, Chat)
    |-- notifications/        # FCM handlers, local notifications, and in-app alert banners
    |-- screens/              # Primary application views (Home, Schedule, Materials, Chat, Profile)
    |-- services/             # Firebase, Supabase, Authentication, and Theme management services
    |-- utils/                # Constants, color palettes, academic mappings, and route scopes
    |-- widgets/              # Reusable UI components, loaders, routine cards, and navigation bars
```

---

## Local Development Setup

### Prerequisites
* Flutter SDK (Version 3.19.0 or higher recommended)
* Dart SDK
* Android Studio / Xcode (for native mobile compilation)
* Google Chrome (for web target testing)

### Installation Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/mridulhasan13/UniGrid.git
   cd UniGrid
   ```

2. Install project dependencies:
   ```bash
   flutter pub get
   ```

3. Configure Firebase Credentials:
   * Place `google-services.json` inside the `android/app/` directory.
   * Place `GoogleService-Info.plist` inside the `ios/Runner/` directory.
   * Ensure Email/Password and Google Sign-In providers are enabled in your Firebase Authentication Console.

4. Configure Supabase Storage:
   * Create a public or authenticated bucket in your Supabase dashboard.
   * Provide your Supabase project URL and anon public key in `lib/services/supabase_config.dart`.

5. Run the development build:
   * To run on Web:
     ```bash
     flutter run -d chrome
     ```
   * To run on Android:
     ```bash
     flutter run -d android
     ```
   * To run on iOS:
     ```bash
     flutter run -d ios
     ```

---

## Technical Specifications

| Parameter | Specification |
| :--- | :--- |
| Framework | Flutter / Dart |
| Database | Cloud Firestore (Multi-region) |
| File Storage | Supabase Storage API |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Target Android SDK | API Level 35 (Android 15) |
| Minimum Android SDK | API Level 21 (Android 5.0) |
| Architecture Support | 64-bit (arm64-v8a, x86_64) |
| State Management | Provider / ChangeNotifier |

---

## Developer

**Mahmudul Hasan Mridul**  
Department of Industrial and Production Engineering (IPE)  
Bangladesh University of Textiles (BUTEX)  
Email: hmridul27@gmail.com / unigrid.app@gmail.com  
Portfolio: https://mahmudulhasanmridul.netlify.app/  
GitHub: https://github.com/mridulhasan13  
LinkedIn: https://www.linkedin.com/in/mahmudul-hasan-mridul1/  

---

## License

This project is licensed under the MIT License. See the LICENSE file for full licensing terms and copyright details.
