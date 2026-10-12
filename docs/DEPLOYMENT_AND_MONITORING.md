# Deployment, Backups, and Monitoring Guide
## Iris Geofenced Attendance System

This document specifies the operational deployment, database backups, audit logging, and observability procedures for deploying the Iris Geofenced Attendance System to staging or production.

---

## 1. Deployment Prerequisites

### 1.1 Infrastructure Requirements
- **PostgreSQL Database**: PostgreSQL 15+ with the `postgis` (v3.3+) and `uuid-ossp` extensions enabled.
- **Supabase Self-Hosted or Cloud**:
  - Supabase Auth service enabled with email confirmations, JWT expiration (default: 3600s), and rate limiting enabled.
  - PostgreSQL Row Level Security (RLS) enabled on all public schema tables.
- **Application Build Environments**:
  - Flutter SDK 3.24+ (Dart 3.5+).
  - Android compileSdk 34+, minSdk 24 (Android 7.0+ for Keystore cryptographic provider support).
  - iOS deployment target 14.0+ with Secure Enclave capabilities.

### 1.2 Environment Configuration
Configure production environment parameters during Flutter compilation using `--dart-define` or `.env` injection. **Never commit production credentials to source control.**

```bash
# Production Flutter Web / Mobile Build
flutter build apk --release \
  --dart-define=ENV=prod \
  --dart-define=API_BASE_URL=https://api.irisattendance.edu/v1 \
  --dart-define=SUPABASE_URL=https://<your-project-id>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-production-anon-key> \
  --dart-define=CAMPUS_LAT=12.9716 \
  --dart-define=CAMPUS_LNG=77.5946 \
  --dart-define=GEOFENCE_RADIUS_METERS=120.0 \
  --dart-define=IRIS_ENGINE_VERSION=v2.4-edge
```

---

## 2. Database Migration & Rollback Procedures

### 2.1 Applying Migrations
Apply migrations in chronological sequence using the Supabase CLI or PostgreSQL client:

```bash
# Using Supabase CLI:
supabase db push

# Using psql:
psql -h <db-host> -U postgres -d postgres -f supabase/migrations/20261011000001_initial_schema.sql
psql -h <db-host> -U postgres -d postgres -f supabase/migrations/20261011000003_security_hardening.sql
psql -h <db-host> -U postgres -d postgres -f supabase/migrations/20261011000004_teacher_admin_dashboard_rpcs.sql
```

### 2.2 Rolling Back Migrations
If an issue occurs during initial deployment, execute the rollback script:
```bash
psql -h <db-host> -U postgres -d postgres -f supabase/migrations/20261011000001_rollback.sql
```

---

## 3. Database Backup & Disaster Recovery

### 3.1 Automated Scheduled Backups (WAL-G / pg_dump)
Implement automated physical backups using pgBackRest or logical daily dumps using `pg_dump`:

```bash
# Daily Logical Backup Script (run via cron at 02:00 UTC)
#!/usr/bin/env bash
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/iris_db"
mkdir -p "$BACKUP_DIR"

pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$BACKUP_DIR/iris_db_$TIMESTAMP.dump"

# Retain backups for 30 days
find "$BACKUP_DIR" -type f -name "*.dump" -mtime +30 -exec rm {} +
```

### 3.2 Point-In-Time Recovery (PITR)
On cloud-managed Supabase instances, ensure **Point-In-Time Recovery (PITR)** is enabled with continuous Write-Ahead Log (WAL) archiving to restore the state within seconds before any database corruption event.

---

## 4. Audit Logging & Security Telemetry

### 4.1 Audit Log Architecture
All security-sensitive operations generate immutable entries in `public.audit_logs`:
- **`user_login`**: Tracks user authentication events.
- **`attendance_submitted`**: Logs submission coordinates, geofence compliance, and device metadata.
- **`geofence_breach_detected`**: Triggered when check-ins originate outside the allowed boundary polygon.
- **`ATTENDANCE_MANUAL_CORRECTION`**: Logs teacher/admin manual status overrides with required written justifications.
- **`BIOMETRIC_TEMPLATE_PURGED`**: Logs GDPR Right to be Forgotten erasure events.
- **`CAMPUS_BOUNDARY_UPDATED`**: Logs geofence parameter updates made by administrators.

### 4.2 Querying Security Audit Logs
Administrators can inspect recent audit records via SQL:
```sql
SELECT 
    id, 
    actor_email, 
    action, 
    table_name, 
    details, 
    created_at 
FROM public.audit_logs 
ORDER BY created_at DESC 
LIMIT 50;
```

---

## 5. Health Monitoring & Observability

### 5.1 Key Performance Indicators (KPIs) & Alerts
| Metric | Threshold | Alert Severity | Action |
| :--- | :--- | :--- | :--- |
| **High Geofence Rejection Rate** | $> 35\%$ in 15 min | Warning | Investigate GPS accuracy issues or perimeter boundary displacement |
| **High Biometric Rejection Rate** | $> 25\%$ in 15 min | Warning | Inspect ambient illumination or camera lens clarity at capture location |
| **Replayed Nonce Rate** | $> 5$ in 5 min | Critical | Potential replay attack; inspect client IP and block malicious device |
| **Database Connection Pool Saturation** | $> 80\%$ usage | Critical | Scale PostgreSQL PgBouncer pool / replica nodes |

### 5.2 Liveness & Health Endpoints
- Configure uptime monitoring (e.g. Prometheus / Datadog) targeting the Supabase API health check:
  `GET https://<your-project>.supabase.co/rest/v1/`
