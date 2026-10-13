# Issue #159: automatic Copy on non-text gestures

Investigation date: 2026-10-13. Issue: https://github.com/ganeshmshetty/openclip/issues/159

## Reproduction and diagnosis

The report describes system alerts after double-clicking Photos images or Windows App connection tiles, and dragging over an empty Outlook body with automatic appearance set to Always.

A failing OpenSelection regression reproduced the responsible side effect: an AXImage target with no selected text or range could invoke the Copy callback after a double-click. The coordinator waived evidence for opaque AX surfaces. Another pipeline regression models an empty text control and an unknown Copy menu; weak role evidence previously permitted a shortcut. These tests reproduce unauthorized Copy, not the audible OS alert itself.

Existing production Photos logs independently show `copy allowed without ax evidence` for `com.apple.Photos` and double-click attempts ending in Copy timeouts. A controlled audible reproduction was not completed: UI accessibility actions opened images but did not generate monitored mouse events, and coordinate interaction failed with `noWindowsAvailable`. No private photo or selected-text content is retained here.

## PopClip comparison

Static REA/Ghidra analysis of PopClip 2026.8.1 (build 6221) shows layered filtering: `PopEvent completeWithTrigger:` (0x10001d440) invokes pre-probe and target policy checks; `captureElement:` (0x10001c63c) examines role and text-control/web ancestry; `PopDiscovery runAttempt:` (0x10001f9fc) prefers AX/native or web text before invoking its pasteboard helper.

Its packaged policy normally requires a beam cursor, with app-specific lenient gesture exceptions and blocked control roles. This is a practical heuristic, but the allowlists require maintenance, and text-control roles or cursor shape alone cannot prove selected text. We use structural selection evidence and command availability rather than reproducing those app lists. The helper's nested polling closure and live behavior in the three reported apps remain unverified; this is not a claim that PopClip cannot beep.

Detailed static evidence and decompilations remain in the gitignored `reference/popclip-rea/` directory, including `issue159-popclip.md`. See also [the broader investigation](popclip-text-selection.md).

## Fix

- Evidence-required retrieval no longer waives checks for opaque targets or specific app identities.
- Selected text, resolved marker text, or a positive selected range remain strong evidence. Beam cursor and text-control role are weak evidence.
- Weak automatic capture requires a positively enabled Copy command. Unknown/disabled states return `copyBlocked` before pasteboard preparation or shortcut delivery.
- Image and collection/item contexts without positive text evidence are blocked. Editable text controls still settle for lagging AX updates.
- Explicit `requireCopyEvidence: false` callers and legacy request construction retain their compatibility behavior.

`CopyRequest.requiresEnabledCopyMenu` carries the requirement through OpenClip's mouse-monitor bridge into `AutomaticCopyCapture`. The app's explicit hotkey callers opt out intentionally. `project.yml` links `openselection/` locally, and XcodeGen regenerated the project. The dependency is a separate gitignored repository: its source changes must be published separately before switching back to a remote package pin.

## Verification

Regression coverage includes opaque media, empty weak evidence with unknown/disabled commands, unchanged pasteboard and zero Copy triggers on rejection, enabled weak fallback, strong selection, explicit opt-out, and lagging AX evidence. App integration coverage checks that the strict requirement reaches the detailed Copy request.

Verification passed: OpenSelection `swift test` ran 237 tests with zero failures; OpenClip `./scripts/test.sh` ran 1,510 tests with zero failures; the Debug app build succeeded using the local dependency. Both repositories pass `git diff --check`. Manual follow-up should exercise Photos images versus editable captions/search, Windows App tiles versus text fields, and Outlook empty versus selected body text. Observe Copy branch/status logs without logging text payloads. The intentional compatibility tradeoff is that automatic retrieval may now decline weak selections in apps whose Copy availability cannot be determined; explicit shortcut retrieval remains available.

## Chrome title-bar follow-up

The user tested the development build and reported an Edit-menu flash on title-bar double-click. Chrome's default cascade uses AX web selection then keyboard Copy, not menu Copy. Recent blocked Chrome logs contain no Copy-menu timing. Both Copy and Paste availability probes read AX attributes; only the menu-Copy strategy calls AXPress. Therefore the flash alone does not establish which operation ran.

REA analysis additionally found `PopMouseFilter.clicked` (0x10000dbac) waits 50 ms before checking window changes, and `PopClickDetector.dispatch:` gates dispatch using its rejection state. OpenClip previously checked window geometry synchronously at mouse-up, which can precede the zoom frame change. This explains a plausible timing gap; it does not prove the flash's exact runtime cause. A delayed asynchronous recheck is useful for zoom, but cannot detect title-bar clicks in fullscreen or when no resize occurs. The follow-up also needs pointer-target chrome classification before retrieval. No fixed title-bar height or Chrome-specific exclusion is warranted.

Detailed evidence: `reference/popclip-rea/chrome-titlebar-filter.md` and `chrome-gesture-diagnosis.md`. Coordinate UI reproduction remains blocked by `noWindowsAvailable`; manual verification is still required.

The implemented follow-up rejects AX-identified chrome using a bounded off-main point hit-test before selection retrieval, rechecks multi-click window geometry after an asynchronous 50 ms interval, and defers mouse-up Paste probing until valid text is accepted. Tests include unchanged-window chrome, delayed window disappearance, and a stable content double-click control. The AX guard intentionally fails open on timeout or ambiguous generic groups; an unlabelled custom title bar can still require further live evidence. This is not a universal fullscreen guarantee. The Debug build succeeds; the final app test run is recorded after completion.

Follow-up verification: 78 focused monitor tests passed and the Debug build succeeded. The full app suite ran the new probe regressions but failed in the unrelated `SettingsRouterTests.testAOneCommandPackageIsStillAnExtensionWithItsOneCommand` navigation assertion. This is recorded rather than reported as a clean full-suite pass; the focused SettingsRouterTests rerun reproduced the same failure. No settings/navigation code was changed for this investigation.
