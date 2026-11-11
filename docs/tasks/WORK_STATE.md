# Work state

Last update: 2026-11-11. Read `CLAUDE.md` first, then this file.

## Current task

**U-1** (move the Media3-dependent code out of `PlayerLogic.kt`) is done on branch `refactor/U-1`, based on `pre-U-1`. The pull request is open; the CI check "Build APK" decides whether it is merged. The maintainer confirms the merge.

## Completed steps

- P2 batch 8 (comment sweep) is on `main` (commit 8d01000 and the work-state commit 581099c). The earlier note "commit pending" is obsolete.
- U-1: `collectTracks`, `TrackOpt`, `trackLabel` and `httpStatusOf` moved verbatim into the new `PlayerTracks.kt` (Media3 side).
- U-1: `PlaybackErrorCodes` (eight numbers, `internal`) and `IptvRetryRules` (pure) added to `PlayerLogic.kt`; `epgSane` moved from `Epg.kt` into `PlayerLogic.kt`.
- U-1: `IptvLoadErrorPolicy` companion delegates to `IptvRetryRules`; the class name stays.
- U-1: `CoreLogicTest` uses `PlaybackErrorCodes` (import removed); `PlayerBufferTest` uses `IptvRetryRules`.
- U-1: new `Media3ContractTest.kt` compares the eight numbers with Media3 `PlaybackException`.
- U-1: `PlayerLogic.kt` has no `androidx`/`android` import left.

## Changed files

Main: `PlayerLogic.kt`, `PlayerTracks.kt` (new), `PlayerNet.kt`, `Epg.kt`.
Tests: `CoreLogicTest.kt`, `PlayerBufferTest.kt`, `Media3ContractTest.kt` (new).
Docs: `docs/REFACTORING-PROGRESS.md`, `docs/tasks/WORK_STATE.md`, `CHANGELOG.md` (Unreleased entry).

## Test results

- Literal fingerprint of `app/src/main`: 4206 distinct string literals, identical before and after.
- Run in the cloud (Kotlin 2.0.21 compiler, JUnit 4.13.2): `PlayerLogicTest` and `PlayerBufferTest`, 20 tests, OK.
- Not run in the cloud: Gradle (`assembleDebug`, `testDebugUnitTest`), `CoreLogicTest` (its dependencies do not translate without Android), `Media3ContractTest` (needs the Media3 jars). The CI workflow "Build APK" on the pull request is the check for these.

## Open problems

- `PlaybackErrorCodes` values come from the Media3 documentation; `Media3ContractTest` verifies them in CI.
- Device test for U-1 is still open (see `docs/REFACTORING-PROGRESS.md`).
- T-004 (quality baseline values), T-006 (backup NAMES, `Backup.kt:17`) and the CHANGELOG entries for 1.2 and 1.3 remain open.
- T-002: device test on TV or Fire TV.

## Next step

U-2 (inventory of German identifiers, list only) after U-1 is merged.
