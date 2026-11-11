# Security

Status of known security items. Source: refactoring audit of 2026-11-11, section 8 (state at commit `b65e838`, tag `V1.3`), updated for T-002. File references are to `app/src/main/java/com/ipvio/stream/`.

Status values: **open**, **partly fixed**, **fixed**.

State after T-002: `/listimport` requires the access code (commit `a804180`). The commit is pushed. Emulator test reported as passing by the maintainer; test on a TV or Fire TV: PENDING.

## Items

| # | Item | Status | Detail | Planned task | Source |
|---|---|---|---|---|---|
| 1 | Phone pages over plain HTTP; server listens on all interfaces; no warning on phone or TV | open | no warning text found | P3 / S3 (warning, new texts in 10 languages) | `PhoneImport.kt:195`, `RemoteUi.kt:64, 73` |
| 2 | Access code has 4 digits | open | | P3 / S2 (6 digits) | `PhoneImport.kt:38` and the `maxlength="4"` lines |
| 3 | Failed-attempt counter and lock | partly fixed | fixed: counter is `AtomicInteger`, random from `SecureRandom`. Open: "locked?" check and increment are not atomic together; comparison is not constant-time | P3 / S2 | `PhoneImport.kt:170, 172, 254-263` |
| 4 | `/listimport` accepted uploads without a code while phone search was active; up to 16 MB reserved per request | fixed | T-002: code required, limit 16 MiB (`MAX_LIST_UPLOAD`), body read in 64 KiB chunks, answer 413 when too large | done (T-002) | was `PhoneImport.kt:307-312`; audit finding 4 |
| 5 | Backup via `GET /backup?code=...` (optionally with playlists and credentials) over HTTP | open | follows from item 1 | with S2/S3 | `PhoneImport.kt:180, 337-346` |
| 6 | `Secrets` falls back to plaintext without Android Keystore | partly fixed | hint exists in settings, but shows only when encryption was attempted in the current session. The fallback itself remains | none planned (PENDING) | `Secrets.kt:14-15, 41`, `SettingsHub.kt:1126` |
| 7 | Silent HTTPS-to-HTTP downgrade after a certificate hostname mismatch; used for Stalker login | open | credentials can go out unencrypted; reported only through `Diag.report`. Behaviour decision is open (audit section 14.6) | P3 / S4 | `TlsFallback.kt:47-65`, `StalkerApi.kt:20` |
| 8 | API keys in `Config.kt` | fixed | no keys in code. Values come from `secrets.properties` or user input | | `Config.kt:18-58` |
| 9 | Release APK contains no keys | fixed | verified for the APK in the repository root at the audit date | | audit section 2 |
| 10 | Google client secret could enter the APK through `secrets.properties` | open | `BuildConfig.GOOGLE_CLIENT_SECRET` is defined but unused. Needed for 1.4. TODO: status of resetting the old secret is unknown | before 1.4 | `app/build.gradle.kts:46-47` |
| 11 | App update | open | HTTPS required for GitHub assets; a custom update URL may use HTTP; verification by Android signature only, no hash check | none planned (PENDING) | `Round17Logic.kt:34, 42-44`, `AppUpdate.kt:44` |
| 12 | Parental PIN has 4 digits | open | lock after 5 failed attempts exists. Decision on a change: PENDING | none planned | `ParentalLogic.kt:20-26` |
| 13 | Cleartext traffic allowed globally | open | required for IPTV providers. No `networkSecurityConfig`. Documented here | none planned | `AndroidManifest.xml:36` |
| 14 | Licence terms of TMDB and IMDb data | open | unverified; to be documented only | PENDING | audit section 8 |

## Follow-ups found in T-002 (not in the audit)

Source: project note `t002_stand.md`.

| Item | Status | Detail |
|---|---|---|
| `/restore` reserves 4 MB up front (after the code check) | open | |
| ZIP parsing in `ListImport.kt` has no size limit | open | |
| Error message "Eingabe unvollständig oder ungültig" is the same for several cases | open | better messages need new texts in 10 languages (maintainer decision) |

## Android configuration (facts)

- `allowBackup=false`, `usesCleartextTraffic=true`, `largeHeap=true` (`AndroidManifest.xml:35-37`).
- `BootReceiver` is exported (`AndroidManifest.xml:39-71`).
- Permissions include `SYSTEM_ALERT_WINDOW`, `REQUEST_INSTALL_PACKAGES`, `SCHEDULE_EXACT_ALARM`, `FOREGROUND_SERVICE_DATA_SYNC` (`AndroidManifest.xml:11-18`).

## Not checked

- Known vulnerabilities in dependencies (OSV-Scanner not run).
- mobsfscan not run.
- No device test of the security items.
