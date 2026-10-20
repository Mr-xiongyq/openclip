# Standalone script snippets (`OpenClipSnippetParser`)

In addition to `.openclipext` package directories, OpenClip supports standalone single-file script snippets (`.js`, `.applescript`, `.sh`, `.py`). Standalone scripts declare action metadata in header comment blocks that are extracted by [`OpenClipSnippetParser`](../../Sources/Core/Extensions/OpenClipSnippetParser.swift).

## Parser architecture and design constraints

- `OpenClipSnippetParser` works only on string content and line scanning.
- It is non-isolated and `Sendable`, so it runs on background queues during extension directory scanning without main-actor hops.

## Header syntax and format

Header metadata can be specified using single-line comment prefixes (`//` or `#`) or block keys.

### Example 1: standalone JavaScript snippet (`upper.js`)

```javascript
// title: Upper Case Transformer
// icon: symbol:textformat.characters
// identifier: com.user.snippet.uppercase
// javascript:
var text = openclip.input.text;
openclip.paste(text.toUpperCase());
```

### Example 2: standalone shell script (`format-sql.sh`)

```bash
#!/bin/bash
# title: Format SQL Query
# icon: symbol:server.rack
# identifier: com.user.snippet.sqlformat
# shell script:
python3 -c "import sqlparse, sys; print(sqlparse.format(sys.stdin.read(), reindent=True))"
```

### Example 3: standalone AppleScript snippet (`create-note.applescript`)

```applescript
-- title: New Quick Note
-- icon: symbol:note.text
-- identifier: com.user.snippet.newnote
-- applescript:
tell application "Notes"
 make new note at folder "Notes" with data OPENCLIP_TEXT
end tell
```

### Example 4: standalone URL search snippet (`search-mdn.sh`)

```bash
# title: Search MDN
# icon: symbol:doc.text.magnifyingglass
# url: https://developer.mozilla.org/en-US/search?q={query}
```

## Header keys matrix

The parser extracts key-value metadata matching the following recognized keys:

| Header Key | Recognized Aliases | Description |
| :--- | :--- | :--- |
| Title | `title`, `name` | User-facing display title in popup panel and preferences. |
| Icon | `icon` | Icon specifier (`symbol:name`, `icon.png`, or SF Symbol string). |
| Identifier | `identifier`, `id` | Unique action identifier string (defaults to `snippet.<slug>`). |
| URL Action | `url` | URL template string containing `{query}` or `{text}` placeholders. |
| JavaScript | `javascript`, `js` | Inline code block or multiline code following the key. |
| AppleScript | `applescript` | Inline AppleScript automation snippet block. |
| Shell Script | `shell script`, `sh`, `shell` | Inline Zsh/Bash/Python executable script block. |

## Parsing algorithm details

1. Scan up to `Constants.maxHeaderLinesToScan` lines for header comment prefixes (`//`, `#`, `//openclip`, `#openclip`).
2. Split each line on the first colon (`:`) into a key and a value.
3. Multiline body mode: when a runtime key (`url`, `javascript`, `applescript`, `shell script`) appears without inline content, the following lines are accumulated as the script body. Body mode ends only when a `#`-prefixed recognized header key appears (for example, a later `# Icon:` line). `//`-prefixed lines and everything else stay part of the body, so JS comments and URLs containing `#` fragments are preserved.
4. The parsed tuple `(ExtensionMetadata, ExtensionActionMetadata)` is passed to `DefaultActionFactory` to instantiate the runtime action.
