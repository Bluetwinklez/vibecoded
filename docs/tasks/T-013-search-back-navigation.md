# T-013 Search: Back from a selected result does not return to the sidebar

Status: FIX WRITTEN, device test PENDING. Branch `fix/T-013-search-back`. Not part of PR #41 (the back logic was left untouched there on purpose).

## Goal

In the search screen, pressing Back while a title in the result list is selected must move focus back to the sidebar.

## Observed

- Reported by the maintainer on 12 Nov 2026: going back from a selected title in the result list does not return to the sidebar.
- The back logic is identical on `main`, so the bug predates PR #41 and PR #40.

## Affected files

- `app/src/main/java/com/ipvio/stream/SearchScreen.kt`: `BackHandler(enabled = !inSidebar)` (about line 125). When the search field is not focused, `target` is `null`, so only `sideFocus.requestFocus()` runs. If that call fails (the sidebar item is not composed or not focusable at that moment) nothing visible happens. **Unverified:** the real cause has not been reproduced. Start by logging the result of `sideFocus.requestFocus()`.
- Overlap risk: PR #40 and PR #41 both change `SearchScreen.kt`. Start this task only after PR #41 is merged.

## Cause (from reading the code, not reproduced on a device)

- The Search entry (menu id 4) is hidden by default (`MenuLogic.DEFAULT_HIDDEN = "4,6"`).
- `Sidebar` attached the `activeFocus` requester (`sideFocus` in `SearchScreen.kt`) only to the entry of the active tab. With Search hidden, no entry carried it.
- `sideFocus.requestFocus()` therefore failed and `runCatching` swallowed the error, so Back did nothing.

## Fix

- `Sidebar.kt`: if the active tab is not visible in the menu, the requester goes to the first visible entry (`anchorId`). Both sidebar layouts (top bar and side bar) use it. The behaviour for visible tabs and the `enterTo` rule are unchanged.

## Acceptance criteria

- Back on a selected result returns focus to the sidebar on Android TV and Fire TV.
- Back in the search field with a closed keyboard still goes to the recent searches or the first hit first (existing behaviour).
- Back in the sidebar on a tab other than 0 still goes to tab 0 (existing behaviour).

## Risks

- Focus handling in Compose depends on what is composed at that moment. A fix that works on the emulator may fail on a TV. Device test is required.

## Documentation needed

- `CHANGELOG.md` entry.

## Test results

Not run: Gradle and a device are not available to the assistant.

Test steps for the maintainer (debug build):
1. Default menu (Search hidden): open Search, type a word, move to a result, press Back. Expected: focus goes to the sidebar.
2. Same with Search shown in the menu (Settings > menu): Back goes to the Search entry.
3. Back in the search field with a closed keyboard still goes to the first hit; Back in the sidebar on tab 4 still goes to Home.
4. Sidebar at the top and on the right: repeat step 1.
