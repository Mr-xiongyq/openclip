# PopClip text-selection investigation

Date: 13 October 2026. This is an investigation, not an implementation proposal or a claim that every candidate is a live bug. The user deliberately withheld the known failure so discovery could be independent.

## Scope and artifacts

The inspected reference is PopClip 2026.8.1, build 6221, at `reference/popclip-rea/PopClip.app`. Its main executable contains x86_64 and arm64 slices. Main executable SHA-256: `653bb886c94c039cb49a9e3fdceb6528e4e1a0ed7b4065ecdc66757eed9fe0db`.

REA 6.4.0 was installed through its official npm package and registered with Codex, omitting workflow skills. Only Luna subagents were used for the delegated source, metadata, and API research in this investigation. Application source and original reference executable bytes were not changed.

Detailed working notes, raw evidence, and reproduction fixtures are under the gitignored `reference/popclip-rea/` directory. Preserve that directory separately if moving the investigation to another machine; it is deliberately not a distributable part of this repository. In particular:

- `INVESTIGATION.md`: setup history and evidence index.
- `evidence/dispatch.json`: REA metadata and implementation addresses.
- `popclip-selection-metadata.md`: metadata facts and investigation targets.
- `packaged-selection-policy.md`: shipped policy/configuration and browser-script inspection.
- `retrieval-alternatives.md`: Apple API research and OpenSelection comparisons.
- `openclip-selection-audit.md`: independent source audit, including ruled-out hypotheses.
- `evidence/CancellationProbeTests.swift` and `cancelled-web-retry-test.log`: a temporary-package reproduction, not changes to repository tests.

## Confirmed OpenSelection cancellation finding

The pinned OpenSelection web-area settle loop ignores `Task.sleep` cancellation and can start additional fresh inspections before its outer cancellation guard checks the task. See `openselection/Sources/OpenSelection/SelectionRetrievalCoordinator.swift`, the `.axWebArea` strategy loop (around lines 769–789), and the outer check around line 527.

A probe against a temporary copy of the actual package configured four attempts with a 0.5-second settle interval, supplied an empty AX web target, and canceled 25 ms after the first inspection. It observed `status=cancelled inspectCount=4 copyCount=0`: three further inspection calls after cancellation. The probe passed in 28 ms because its injected inspections returned promptly and canceled sleeps did not wait. This proves unnecessary work in the retry path; it does not measure real AX latency, establish stale-result delivery, or show the same defect in PopClip. Delivery still returned cancellation and no copy operation occurred.

The practical next investigation is to measure canceled retry work against slow providers and its effect on bounded worker capacity. A later fix should preserve cancellation status and stop new polls/re-inspections promptly, with a focused regression check. No fix has been applied.

## Ruled-out and unconfirmed concerns

OpenClip's explicit hotkey fallback to existing clipboard text is intentional, documented, represented as `clipboardFallback`, and tested. It is not reported as a selection bug.

The native AX range/value fallback adds `CFRange.location + length` before validating bounds. A malicious or malformed overflowing range is an input-validation concern; no live provider returning it was observed. Half-surrogate UTF-16 ranges also merit validation, but the normal Unicode cases already have coverage. Wall-clock-based clipboard deadlines are a low-probability timing weakness. Same-process, unobserved programmatic focus changes remain documented debt rather than a new finding.

## Better retrieval paths to evaluate

Keep direct `AXSelectedText` as the first plain-text read. Where the target supports it, evaluate `AXStringForRange` using its selected range before retrieving all of `AXValue` and slicing locally. This can reduce how much unrelated document text is requested; it is not a measured speedup, and unsupported/missing attributes must remain distinct from an empty selection. [Apple parameterized-attribute API](https://developer.apple.com/documentation/applicationservices/1461203-axuielementcopyparameterizedattr), [range-string attribute](https://developer.apple.com/documentation/applicationservices/kaxstringforrangeparameterizedattribute).

OpenSelection's inspector currently collects selected text, full value, selected range, and bounds eagerly in its snapshot. Reducing full-value reads therefore requires evaluating the inspection stage too, not just inserting a new strategy after the existing snapshot is collected. Preserve provider deadlines and provenance/range validation when comparing staged reads; additional reads can introduce focus/selection races. Do not claim a performance benefit before measuring large-document cases.

Evaluate `AXSelectedTextRanges` for noncontiguous selections while retaining the separate ranges and an explicit flattening policy. Current range/value fallback represents one range; direct selected-text behavior in multi-selection editors must be measured before claiming lost text. [Apple multiple-ranges attribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangesattribute).

Retain the exact element that supplied a web text-marker range when resolving its string/bounds. Keep source PID, focused-element/window identity, generation, and selected range as distinct evidence; none alone proves the target stayed unchanged. Editability should remain separate from whether read-only text is selectable. Synthetic Copy should follow explicit selection evidence and a clipboard ownership/restore policy.

## PopClip facts established before decompilation

REA decoded Objective-C metadata for `PopEvent`, `PopDiscovery`, `PopDiscoveryAttempt`, `PopMouseFilter`, `PopClickDetector`, `PopSelectionWrapper`, and `PopEventPipeline`. This gives concrete function starts for capture, attempts, pasteboard checks, and presentation. The metadata establishes declarations and locations, not execution order or bug conditions.

The packaged policy contains app-specific AX, pasteboard, menu/keyboard-grab, cursor, and trigger rules. Its text-control role group includes `AXStaticText` as well as editable roles. The bundled Safari/Chromium/Arc scripts fetch URL and title/name; those scripts do not fetch selected text. Policy matching precedence and runtime enforcement must be established from the native implementation or controlled observations.

## Successful native-analysis pass

REA with Ghidra 12.1.4 successfully decompiled 16 event/discovery/filter methods, followed by ten lower-level AX/pasteboard methods and blocks. Instruction listings were retained for the central predicates and AX getters, with target hash and analysis profile in each result. Both session closures succeeded. This was static analysis; PopClip's binary code was not executed by the disassembler.

`PopEvent.selectedText` returns the plain-string entry from captured data. `PopDiscovery.runAttempt:` obtains native selected text and a web selection candidate, applies a string fixup, and asks whether captured text is sufficient. The sufficiency predicate checks nonempty plain text, a candidate-snippet condition, `DeepCapture`, and a synthetic-trigger condition. Insufficient results can go to the delegated pasteboard helper. `PopEventPipeline.processEvent:` cancels the previous token when accepting a new event. The detailed report preserves unresolved selector dispatch and floating-point ABI caveats.

The lower-level AX paths use `AXSelectedText`, `AXSelectedTextMarkerRange` with `AXStringForTextMarkerRange`, and native/web-marker bounds attributes. The marker string and bounds queries use the same wrapper object that obtained the corresponding range. `PopMouseFilter.checkPasteboard` compares the **drag pasteboard**, so its name must not be interpreted as proof of general-clipboard freshness protection.

`PopDiscovery.fixupString:withTextControl:logger:` queries `AXValue` and `AXSelectedTextRange`, builds candidate strings, and conditionally substitutes a repaired string when its comparison matches. Its special-character and range semantics need a controlled rich-text fixture before being copied or changed. The pasteboard helper serializes capture on a private dispatch queue and checks cancellation at worker entry; its restore branch compares pasteboard ownership/change counts. Its nested polling closure was not decompiled in this pass, so mid-wait cancellation and exact timing remain open questions.

One PopClip hypothesis worth testing is disagreement between native selected text and a web marker candidate: the observed discovery code prefers a non-nil native candidate, which may differ from a substantial-text check. The selected-text accessor delegates to `stringAttributeWithName:`; that helper's empty-string normalization is unresolved. A browser can also retain a stale page selection while a focused field has a newer selection. Test both provenance and content before changing preference order; neither a guaranteed lost-selection bug nor a universally safer fallback is established by this trace.

Assembly cross-checking matters: the `captureSelectionBounds` pseudocode shows an apparent permanently-zero boolean, but actual instructions branch on `_NSPointInRect`'s returned `w0` and store the accepted bounds. That apparent always-rejecting bug is a decompiler artifact. Keep typed return values and Objective-C block/dispatch uncertainty explicit before classifying a defect.

## Tool setup and analysis limits

Use [REA installation documentation](https://github.com/morluto/rea/blob/main/docs/installation.md) and the installed version's actual schemas. Setup was scoped to `--client codex --skill=false`; no skills were run. Codex registration is pinned to REA 6.4.0, and a Codex restart/reconnection is required for its MCP tools to appear in a new session. CLI investigations can run immediately.

Hopper installed successfully, but its native launcher failed before bridge readiness. A path/Spotlight lookup problem was followed by `Cannot launch Hopper! The handler some object is not defined.` Readiness checks establish installed prerequisites, not a working target session. The failure evidence is retained; do not describe it as successful decompilation.

Ghidra 12.1.4 was obtained from the official release and its SHA-256 checked. The release omits macOS native binaries, so the documented `support/gradle/gradlew buildNatives` process is required with Xcode tools and the existing full JDK 21. An ARM64-only analysis copy was prepared using `lipo` because REA's Ghidra provider rejects universal Mach-O imports. It has SHA-256 `54a61407a8bb9cc5006731785c03ce3eb167cae19e82ec09a11a1a32a728651b`; its addresses correspond to the same arm64 image, while file offsets differ from the original FAT container.

The native build and scoped Ghidra readiness check passed. Codex's verified registration includes Ghidra/JDK paths and `REA_ANALYSIS_PROVIDER=ghidra`; its scoped readiness check passed too. For this machine, use the working Ghidra backend as the default. Hopper remains installed but its failed launcher workflow is not the recommended operational path until repaired.

For CLI use on this Mac, export the provider path explicitly; CLI processes do not inherit Codex's MCP registration environment:

```sh
export GHIDRA_INSTALL_DIR=/Users/ganesh/.local/share/rea-tools/ghidra_12.1.4_PUBLIC
npx --yes rea-agents@6.4.0 doctor --provider ghidra --format json
npx --yes rea-agents@6.4.0 decompile \
  /Users/ganesh/dev/openclip/reference/popclip-rea/evidence/PopClip-arm64 \
  0x10001f9fc --provider ghidra --format json
```

The decompile command is a repeatable follow-up example for `runAttempt:`; the recorded investigation used the persistent session harness to avoid importing the entire binary separately for every query. Prefer a connected REA MCP session for interactive investigation after restarting Codex. The retained `investigate.mjs` is pinned to REA 6.4.0's internal session API; recheck that API before upgrading it.

The default 5,000-record REA metadata budget missed later classes. A 20,000-record scan yielded 537 class/metaclass records but still exhausted its category and Swift metadata budgets; the filename `dispatch-full.json` does not mean complete coverage. Later `NMUIElement`/pasteboard method addresses were recovered through `otool` and validated selector fixups. Do not infer absence from a truncated inventory. A minimal reproduction should prefer a single slice and a narrow set of metadata-derived starts over claiming whole-program recovery.

PopClip's distributed build is hardened and lacks `get-task-allow`; REA's LLDB route is therefore constrained. No signing or OS protections were changed. A brief CUA launch check exposed no usable PopClip window and was cleaned up; no controlled runtime selection matrix has yet been completed. Static findings and fixture-based source findings must remain separate from observed PopClip behavior.
