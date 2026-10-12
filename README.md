# Iris Geofenced Attendance System - Phase 1 Foundation

An institutional, privacy-conscious mobile attendance application built with Flutter, Material 3, and clean layered architecture. Combines future hardware iris recognition with campus GPS perimeter geofencing.

---

## 🏛 System Architecture

This project follows the official Flutter Layered Feature Architecture:

```text
iris_attendance/
├── lib/
│   ├── core/
│   │   ├── config/            # AppConfig (Environment, geofence radius & endpoints)
│   │   ├── routing/           # Declarative GoRouter configuration
│   │   ├── theme/             # Material 3 University Theme & color schemes
│   │   ├── utils/             # Geofence (Haversine math) & Form Validators
│   │   └── widgets/           # LoadingWidget, ErrorDisplayWidget, EmptyStateWidget
│   ├── data/
│   │   ├── models/            # User model, UserRole enum
│   │   └── repositories/      # AuthRepository & simulated handshake implementation
│   ├── ui/
│   │   └── features/
│   │       ├── auth/          # Splash, Welcome, Login, Register, Role Selection
│   │       │   ├── view_models/
│   │       │   └── views/
│   │       └── dashboard/     # Role-segregated Student, Teacher & Admin dashboards
│   └── main.dart              # Entrypoint with ProviderScope & environment loading
├── test/
│   └── unit/                  # Comprehensive unit tests for GeoUtils, Validators & Auth
├── pubspec.yaml
└── analysis_options.yaml
```

---

## 🚀 How to Run the Application

### 1. Prerequisites
- **Flutter SDK** (Version 3.24+ recommended) installed and present on your `PATH`.
  - To install Flutter on Windows: [https://docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows)
  - Verify with:
    ```bash
    flutter doctor
    ```

### 2. Install Dependencies
Navigate to the project directory:
```bash
cd "C:\Users\RAHUL\Documents\project\iris_attendance"
flutter pub get
```

### 3. Run Static Analysis & Unit Tests
```bash
# Analyze code quality and formatting
flutter analyze

# Execute all unit tests (Geofence math, Validators, Auth Repository)
flutter test
```

### 4. Launch the Application
Run on Chrome, Windows Desktop, or an Android/iOS emulator:
```bash
# Launch in development environment
flutter run -d chrome

# Or launch with custom environment variables:
flutter run -d chrome --dart-define=ENV=dev --dart-define=GEOFENCE_RADIUS_METERS=150.0
```

---

## 🔒 Authentication & Role-Based Access Control (RBAC) Architecture

### 1. Server-Enforced Role Resolution
- **Client inputs are never trusted for role authorization**. The client submits only authentication credentials (email & password).
- The authenticated role is fetched from the server database (`public.profiles` table via Row-Level Security).
- Route guards dynamically intercept all navigation attempts in `routerProvider`, ensuring users can never manually route to forbidden consoles.

### 2. Dual Backend Mode: Supabase & Development-Safe Mode
- **Live Supabase Auth Mode**: Triggered when `SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided in `--dart-define`. Handles session tokens, password recovery emails, and PostgreSQL RLS.
- **Development-Safe Mode**: If credentials are unset or placeholder, the application automatically activates labeled `[DEVELOPMENT MODE ACTIVE]`. Displays handy quick-login chips for testing Student, Faculty, and Admin personas with full session simulation.

### 3. Database Schema & RLS
Run [supabase_schema.sql](file:///C:/Users/RAHUL/Documents/project/iris_attendance/supabase_schema.sql) in your Supabase SQL editor:
- Creates `public.app_role` enum (`student`, `teacher`, `admin`).
- Creates `public.profiles` table with foreign key to `auth.users(id)`.
- Enforces strict RLS: users view only their profile; admins view all; role modifications by non-admins are blocked.
- Installs trigger `on_auth_user_created` to provision profiles on signup.

---

## 📱 Implemented Flows & Screens

1. **Splash Screen (`/`)**: Biometric eye animation with session auto-check.
2. **Welcome Screen (`/welcome`)**: Entry banner and security overview.
3. **Login Screen (`/login`)**: Validated institutional login. Includes Development Mode quick switcher when keys are unset.
4. **Registration Screen (`/register`)**: Separate profile provisioning for student roll numbers and faculty departments.
5. **Password Reset Screen (`/forgot-password`)**: Institutional email password reset dispatch with feedback banners.
6. **Student Dashboard (`/student-dashboard`)**: Student attendance rate, iris scan trigger, and personal profile.
7. **Teacher Console (`/teacher-dashboard`)**: Classroom geofence session controller and lecture roll calls.
8. **Admin Suite (`/admin-dashboard`)**: Campus GPS perimeter boundaries and hardware iris scanner monitors.
9. **Access Denied Screen (`/unauthorized`)**: Rejects mismatched role attempts and redirects to permitted zones.

---

---

## 🗄 Backend, Database & PostGIS Geospatial Architecture

### 1. Database Schema Components
- **`public.profiles`**: Separated user identities linked to `auth.users(id)` with server-enforced role assignments (`student`, `teacher`, `admin`).
- **`public.campus_locations`**: PostGIS `geography(POLYGON, 4326)` geofence perimeters and center coordinates with spatial GIST indexes.
- **`public.courses` & `public.course_instructors`**: Class offerings and teacher-to-course assignments.
- **`public.course_enrollments`**: Student class enrollment rosters with unique composite constraints.
- **`public.attendance_sessions`**: Lecture attendance windows created by instructors, tied to physical campus location polygons.
- **`public.attendance_records`**: Check-in records with GPS coordinates. Includes composite constraint `UNIQUE (session_id, student_id)` to prevent duplicate attendance submissions.
- **`public.biometric_templates`**: Salted cryptographic hash / feature vectors for iris matching. **Zero raw eye images are stored**.
- **`public.audit_logs`**: Tamper-evident logging of logins, session events, geofence breaches, and perimeter changes.

### 2. Server-Side PostGIS Geofence Validation
The database provides `public.submit_attendance_check_in(session_id, lat, lng, device_info)` which executes inside PostgreSQL:
- Confirms session is active and student is enrolled.
- Enforces composite uniqueness (blocks duplicate check-ins).
- Calculates `ST_Covers(boundary_polygon, student_point)` and `ST_Distance(center_point, student_point)`.
- Flags status as `pending_verification` (inside perimeter) or `flagged_outside_geofence`.
- Writes an immutable entry to `public.audit_logs`.
- **Note**: `is_biometrically_verified` remains strictly `FALSE` until Phase 3 biometric hardware integration.

### 3. Migrations & Rollback Procedures

#### Running Migrations (Supabase Dashboard or CLI)
1. In your Supabase Project -> **SQL Editor**, execute:
   - [`supabase/migrations/20261011000001_initial_schema.sql`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/supabase/migrations/20261011000001_initial_schema.sql)
2. To load sample development entities (campus polygon, courses, active session), run:
   - [`supabase/migrations/20261011000002_seed_data.sql`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/supabase/migrations/20261011000002_seed_data.sql)
3. If using Supabase CLI:
   ```bash
   supabase db reset
   ```

#### Rollback Procedure
If you need to roll back the schema:
1. Execute [`supabase/migrations/20261011000001_rollback.sql`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/supabase/migrations/20261011000001_rollback.sql) in your SQL editor.

---

---

## 🛰 Geofencing Module & Spoof Detection Architecture

### 1. Geospatial Algorithms
- **Haversine Distance**: Great-circle metric used for circular buffer boundary comparisons.
- **Ray-Casting Algorithm**: Ray intersection algorithm evaluating complex concave/convex polygon boundaries.
- **Edge Tolerance (ST_Covers policy)**: Points located directly on the polygon perimeter boundary are treated as strictly inside the allowed zone.
- **Numerical Edge Cases**: Automatic rejection of `NaN`, `Infinite`, and out-of-range latitude/longitude coordinates.

### 2. Mobile GPS Quality & Spoofing Constraints
- Captures `latitude`, `longitude`, `timestamp`, `accuracyMeters`, and `isMockLocation`.
- Detects disabled location services, denied permissions, and stale fixes (> 60s).
- **Security Reality Check (GPS Spoofing)**: Client-side mock-location flags are transmitted to the backend as quality indicators. However, **client-side detection alone can NEVER guarantee GPS authenticity**, because compromised devices or rooted environments can spoof GPS drivers. Therefore:
  - Mobile app claims of presence are **never trusted as sole proof**.
  - Server-side PostGIS executes `ST_Covers` / `ST_DWithin`.
  - Rate limiting (max 5 checks/minute) and tamper-evident audit logging are enforced on PostgreSQL.
  - Full attendance validation requires biometric verification (Phase 3).

### 3. Student Dashboard Interactive Geofence Radar
The student portal features an interactive vector radar displaying:
- Campus boundary polygon and center anchor.
- Real-time student position marker with visual GPS accuracy halo.
- High-contrast visual badge: `INSIDE PERIMETER` (Green) vs. `OUTSIDE ZONE` (Red).
- Dynamic error banners explaining poor accuracy or disabled GPS.
- One-click testing chips for simulated inside, boundary-edge, outside, and mock GPS modes.

---

---

## 👁️ Iris Capture & Biometric Processing Module

### 1. Scientific Reality & Feasibility
- **Landmarks vs Identity**: Eye landmarks from MediaPipe provide geometric gaze and contour points only. **They possess zero biometric uniqueness**. Landmark detection is never treated as identity verification.
- **Hardware Limitations**: Commercial iris systems rely on **Near-Infrared (NIR, 700–900nm)** lighting to penetrate melanin in dark-pigmented irises. Standard smartphone RGB sensors suffer from melanin absorption and specular corneal glare.
- **Detailed Research**: See full engineering feasibility analysis in [`docs/IRIS_BIOMETRIC_RESEARCH.md`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/docs/IRIS_BIOMETRIC_RESEARCH.md).

### 2. Implemented Modular Architecture
- **Stage A (Quality Checks)**: [`iris_quality_assessment.dart`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/lib/core/biometrics/iris_quality_assessment.dart) computes real-time sharpness (Laplacian variance), illumination, contrast, and occlusion with retry guidance.
- **Stage B (Localization)**: [`iris_localization.dart`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/lib/core/biometrics/iris_localization.dart) interfaces pupil and limbus boundary segmentation.
- **Stage C (Recognition Engine)**: [`daugman_iris_engine.dart`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/lib/core/biometrics/daugman_iris_engine.dart) implements Daugman's Rubber Sheet polar transformation ($r, \theta$), 2D Gabor wavelet phase demodulation (2048-bit binary IrisCode), and multi-shift Normalized Hamming Distance.
- **Stage D (Mobile Screen)**: [`iris_camera_capture_screen.dart`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/lib/ui/features/dashboard/views/iris_camera_capture_screen.dart) provides an interactive circular reticle, animated laser sweep, live focus/illumination meters, and disclaimer dialogues.

---

## 🛡️ Presentation Attack Defense & Security Hardening Architecture

### 1. Implemented Safeguards vs. Documented Limitations
- **Liveness Detection (PAD)**: [`liveness_detector.dart`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/lib/core/biometrics/liveness_detector.dart) implements multi-frame temporal delta checks, dynamic blink sequences, guided gaze tracking (`blinkChallenge`, `guidedGazeLeft`, `guidedGazeRight`), and 2D spatial moire raster analysis.
- **Important Scientific Reality**:
  - *Blinking alone never proves liveness* (photos can be mechanically animated, video loops can be replayed).
  - *VPN detection does not prevent GPS spoofing*.
  - We combine temporal micro-saccade dynamics, challenge-response eye movements, and screen raster frequency analysis.
- **Single-Use Server Nonces (Anti-Replay)**:
  - Students must request a cryptographically secure 256-bit server nonce (`generate_attendance_nonce`) valid strictly for **90 seconds**.
  - Nonces are consumed atomically upon first verification (`auth_nonces` table with row-level locks). Replayed nonces are rejected with tamper-evident audit logs.
- **Device Hardware Key Signing**:
  - [`secure_key_store.dart`](file:///C:/Users/RAHUL/Documents/project/iris_attendance/lib/core/security/secure_key_store.dart) interfaces platform hardware (Android Keystore / iOS Keychain / Secure Enclave). Payloads are cryptographically signed on-device.
- **Strict Failure Handling**:
  - Any uncertainty in liveness ($< 0.70$) or failed biometric distance ($> 0.33$) triggers hard rejection. **No failed verification is ever bypassed**.

---

## 🧪 Comprehensive Unit & Security Test Suites
- `test/unit/teacher_admin_dashboard_test.dart`: RBAC for assigned instructor sessions, roster search & status filtering, audited attendance correction with mandatory justification, RFC CSV export generation, administrator PostGIS geofence perimeter update, unauthorized student audit log access rejection, and GDPR biometric template erasure audit logging.
- `test/unit/security_hardening_test.dart`: Live dynamic eye validation, static photo attack rejection, screen-replay moire rejection, replayed nonce rejection, forged nonce rejection, and low liveness rejection.
- `test/unit/iris_biometrics_test.dart`: Quality assessment, Daugman Rubber Sheet template generation, genuine Hamming Distance ($\approx 0.00$), and imposter rejection ($> 0.33$).
- `test/unit/core_utils_test.dart`: Haversine calculation, polygon ray-casting, boundary edges, and invalid coordinate handling.
- `test/unit/geofence_view_model_test.dart`: Mobile GPS permission handling, mock-location detection, and stale fix warnings.
- `test/unit/backend_database_test.dart`: Geospatial check-in, duplicate submission rejection, unauthorized role rejection, and data privacy isolation.
- `test/unit/auth_repository_test.dart`: Session persistence, profile fetching, and logout lifecycle.
- `test/unit/auth_view_model_test.dart`: StateNotifier mutations and profile model serialization.
- `test/unit/navigation_rbac_test.dart`: Navigation guards, unauthorized route redirects, and role isolation.

---

## 📊 Teacher & Administrator Dashboard Architecture

### 1. Teacher Dashboard (`/teacher-dashboard`)
- **Assigned Class Sessions**: Live display of sessions assigned to the authenticated faculty instructor.
- **Session Controls**: Instant start and termination of active 15–30 minute geofence check-in windows.
- **Student Attendance Roster**: Displays real-time check-ins with clear status indicators (`PRESENT`, `OUTSIDE GEOFENCE`, `BIOMETRIC REJECTED`, `ABSENT`).
- **Dynamic Search & Filtering**: Real-time filtering by student full name, roll number, or specific verification status.
- **Audited Manual Corrections**: Allows teachers to override attendance only upon providing a mandatory justification reason ($\ge 10$ characters). Every correction logs the operator ID, prior status, new status, timestamp, and justification into immutable audit logs.
- **Authorized CSV Export**: Exports RFC-compliant attendance reports directly to clipboard or local storage.

### 2. Administrator Dashboard (`/admin-dashboard`)
- **PostGIS Geofence Coordinator**: Real-time management and updating of campus center coordinates ($\text{lat}, \text{lng}$) and buffer radii ($\text{meters}$).
- **Security & Telemetry Overview**: System-wide statistics on total verifications, geofence violations, and biometric rejections.
- **Biometric Retention & GDPR / DPDP Compliance**: Complete "Right to be Forgotten" implementation allowing administrators to purge biometric template hashes upon user request.
- **System Audit Log Viewer**: Read-only telemetry of all privileged actions, manual overrides, logins, and geofence reconfigurations with timestamps and actor identities.

