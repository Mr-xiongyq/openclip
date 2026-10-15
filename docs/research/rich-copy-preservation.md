# Preserving rich content in built-in Copy

Research date: 15 October 2026. Scope: diagnose built-in Copy and recommend a fix;
no application implementation changes. Build 14 was a user guess and is not evidence.

## Recommendation

For a current live selection, built-in Copy should invoke the source application's native
Copy command and leave its resulting clipboard intact. Keep fast accessibility retrieval
for popup discovery and text-consuming actions. Do not make ordinary Copy rebuild the
clipboard from `SelectionContext.text`, or from a filtered rich snapshot.

This matches the bundled PopClip Copy implementation and the traced native dispatcher.
It avoids two separate losses: formatting missing from accessibility text, and application
formats/items omitted by OpenSelection's capture model. This is a supported design
recommendation, not a claim that an implementation has passed live Obsidian validation.

## Reported reproduction

The user selects formatted text in Obsidian, clicks OpenClip Copy, then pastes into the
same app using hold → Paste. Ordinary Command-V also loses formatting after OpenClip
Copy. Notes currently works. Reading view versus editor was not specified.

The Command-V result localizes the reported problem to Copy/output before the paste
entry point. It does not by itself prove the exact clipboard formats lost.

## OpenClip findings

1. Both Obsidian and Notes are in `DefaultAppRules.keyboardCopyApps`.
2. OpenSelection treats Obsidian as a multiprocess app. Its keyboard-copy policy first
   tries AX text/web selection, then performs keyboard Copy only if needed. Notes takes
   keyboard Copy directly. See `SelectionRetrievalCoordinator.swift:728` in OpenSelection.
3. `SelectionConfiguration.enrichRichContent` defaults to false. A successful text-only AX
   read therefore stays text-only. Commit `43f2866` changed the package default on
   23 September 2026; this is source history, not an established first affected release.
4. `CopyAction.perform` writes the captured rich payload when available and otherwise
   returns `.copy(selection.text)`. The effect handler clears the clipboard and writes
   that value as plain text. The built-in Paste instead posts native Command-V.
5. Even when capture runs, `PasteboardCopyEngine.captureFlavors` reads only the first
   pasteboard item and an allowlist of representations: string, HTML, RTF, RTFD, PDF,
   TSV, and Notes rich text. The payload has no multi-item structure. Thus enabling
   enrichment alone cannot make built-in Copy equivalent to native Copy.

Relevant source:

- `Sources/Core/Rules/DefaultAppRules.swift:144`
- `Sources/Core/Actions/Builtin/CopyAction.swift:28`
- `Sources/Core/Actions/Builtin/PasteAction.swift:25`
- `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift:159`
- `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift:466`
- `openselection/Sources/OpenSelection/SelectionConfiguration.swift:91`
- `openselection/Sources/OpenSelection/SelectionRetrievalCoordinator.swift:728`
- `openselection/Sources/OpenSelection/PasteboardCopyEngine.swift:260`

## Obsidian source inspection

Inspected installed Obsidian 1.12.7, `Contents/Resources/obsidian.asar`, without opening or
modifying a vault. The UTF-8 `app.js` SHA-256 is
`cc6d0c363cba3935207fb70e7d78736c9f0c2024545787871095288a1b185851`.
Offsets below are character offsets in that decoded bundled file.

- At offset 2414374, the editor's `clipboardCopyHook` writes `text/markdown` and, for
  selections no larger than one million characters, `text/html`.
- Table Copy near offset 1919576 writes plain text, Markdown, HTML, and `obsidian/table`.
- The paste handler near offset 1565878 recognizes an internal HTML marker, Markdown,
  and HTML conversion separately. Table paste near offset 1920047 reads `obsidian/table`.

These establish that the source app supplies meaningful representations beyond visible
AX text. Browser DataTransfer type names are not proof of their exact macOS pasteboard
UTI mapping; a live clipboard comparison is still needed for that mapping.

## PopClip confirmation

Luna traced the bundled `Resources/BuiltInExtensions/Copy.ts` and native ARM64 dispatch:

- Ordinary Copy calls `performCommand("copy", { transform: "none" })`.
- The native `none` branch invokes Copy through the selected commander and waits for
  a pasteboard change. It does not run the plain capture/rewrite helper.
- The explicit `plain` branch calls `copyPlainWithCommander:cut:completion:`, captures
  only the plain-string content kind, and rewrites the pasteboard as string-only.
- PopClip also registers a deferred capture callback supporting requested String/RTF/HTML
  kinds. That mechanism is distinct from ordinary built-in native Copy.

Detailed addresses and REA evidence IDs are recorded in
`reference/popclip-rea/rich-copy-capture.md`. The bundled Copy source is directly readable
at `reference/popclip-rea/PopClip.app/Contents/Resources/BuiltInExtensions/Copy.ts`.
PopClip's [official guide](https://www.popclip.app/guide/actions) describes ordinary
clipboard actions as native-like, with Shift explicitly stripping formatting.

## Alternatives considered

| Approach | Assessment |
| --- | --- |
| Enable rich capture for every selection | Adds synthetic Copy during discovery; still filters app formats and items. |
| Add an Obsidian-specific exception | Leaves the same failure possible in other apps. |
| Capture rich data when Copy is clicked, then rewrite it | Fixes many HTML/RTF cases but inherits first-item/allowlist losses and extra clipboard ownership transitions. |
| Invoke native Copy on click, retain its output | Recommended: source app owns serialization, formats, items, and lazy providers. |

## Implementation boundaries for the next task

- Represent live-selection Copy with a typed Core effect, handled in the platform effect
  layer; do not switch on action IDs in presentation code or add AppKit to Core.
- Route only the built-in live-selection operation through native Copy. Explicit `.copy`
  and `.copyContent` results from text actions retain their supplied-output semantics.
  OCR Copy remains a text operation. Existing Copy click behavior should remain stable.
- Bind the operation to the captured source PID and selection generation. Recheck after
  clipboard acquisition and immediately before posting; refuse stale selections or a
  different active app. Preserve keyboard-popup activation behavior.
- Use the existing clipboard coordinator at user-action priority through a bounded
  command-response window. Do not clear the clipboard, recapture filtered flavors,
  rewrite the result, or schedule restoration over a successful native Copy.
- Reuse command/menu policy and existing guarded event posting. A standalone `.keyPress`
  would lack clipboard ownership and completion confirmation.
- A failed/unavailable command must not silently replace an intervening clipboard write
  with cached plain text or report an unconfirmed success. Define failure behavior and
  the bounded confirmation contract explicitly during implementation.
- Keep general enrichment defaults unchanged. Cut's current plain-text reconstruction
  is a separate related limitation; changing destructive Cut behavior needs its own proof.

## Validation performed and required

Passed existing tests:

- `testTextOnlyWebAreaWinSkipsRichEnrichmentByDefault`: confirms the current loss path.
- `testCopyActionWithRichText`: captured rich data reaches the Copy result.
- `testCopyContentHandlerWritesRawFlavorsVerbatim`: supplied raw flavors are written intact.

A standalone temporary probe used OpenSelection's public capture engine against a named
test pasteboard, with a fake Copy trigger that supplied two items and a custom format.
It returned `htmlCaptured=true customTypeCaptured=false secondItemCaptured=false
originalClipboardRestored=true`. No user clipboard content or vault was changed. Source
and result are retained under `reference/popclip-rea/evidence/openclip-rich-copy-probe.*`.

Before calling the fix complete, compare native Command-C with OpenClip Copy on the same
Obsidian fixture in editor and Reading view, then paste via Command-V and hold → Paste.
Include bold, links, lists, and tables; compare clipboard item counts, format identifiers,
and bytes using synthetic content. Verify Notes, source changes, stale selection,
unavailable Copy, delayed response, overlapping clipboard operations, and OCR Copy.
Unit checks should prove that a successful native Copy retains custom types and multiple
items without an OpenClip rewrite. No live Obsidian/PopClip replay was performed here.
