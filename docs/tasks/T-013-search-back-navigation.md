# T-013 Search: Back from a selected result does not return to the sidebar

Status: OPEN. Not started. Branch from `main`. Not part of PR #41 (the back logic was left untouched there on purpose).

## Goal

In the search screen, pressing Back while a title in the result list is selected must move focus back to the sidebar.

## Observed

- Reported by the maintainer on 12 Nov 2026: going back from a selected title in the result list does not return to the sidebar.
- The back logic is identical on `main`, so the bug predates PR #41 and PR #40.

## Affected files

- `app/src/main/java/com/ipvio/stream/SearchScreen.kt`: `BackHandler(enabled = !inSidebar)` (about line 125). When the search field is not focused, `target` is `null`, so only `sideFocus.requestFocus()` runs. If that call fails (the sidebar item is not composed or not focusable at that moment) nothing visible happens. **Unverified:** the real cause has not been reproduced. Start by logging the result of `sideFocus.requestFocus()`.
- Overlap risk: PR #40 and PR #41 both change `SearchScreen.kt`. Start this task only after PR #41 is merged.

## Acceptance criteria

- Back on a selected result returns focus to the sidebar on Android TV and Fire TV.
- Back in the search field with a closed keyboard still goes to the recent searches or the first hit first (existing behaviour).
- Back in the sidebar on a tab other than 0 still goes to tab 0 (existing behaviour).

## Risks

- Focus handling in Compose depends on what is composed at that moment. A fix that works on the emulator may fail on a TV. Device test is required.

## Documentation needed

- `CHANGELOG.md` entry.

## Test results

None yet.
