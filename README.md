# Emoji Description — macOS port

macOS (Nextpad++) port of the Windows Notepad++ plugin
**[Emoji Description](https://github.com/Ruberoid/npp_emoji_description)** by Ruberoid (GPL v2).

Shows the encoding information of the character under the cursor:

- **Unicode code point** (`U+XXXX`)
- **Decimal** value
- **Hexadecimal** value
- **HTML entity** (`&#XXXX;`)
- **UTF-8 byte sequence**

Works for ASCII, BMP characters (Cyrillic, CJK, …), and astral characters
including emoji.

Example output for `😀`:

```
U+1F600 | Dec: 128512 | Hex: 0x1F600 | HTML: &#128512; | UTF-8: 0xF0 0x9F 0x98 0x80
```

## Menu

`Plugins → Emoji Description`:

- **Show Character Info** — reports the character under the cursor (also toggles
  reporting on/off, matching the Windows default-on toggle).
- **About** — plugin information.

## macOS difference from the Windows version

The Windows plugin streams its result into the Notepad++ **status bar**
continuously as you move the cursor (via `NPPM_SETSTATUSBAR`). The Nextpad++
macOS host does **not** implement `NPPM_SETSTATUSBAR` and exposes no
plugin-writable status-bar segment, so this port surfaces the **same
information on demand**: choosing *Show Character Info* reports the current
character in an alert. The live cursor-tracking notifications
(`SCN_UPDATEUI` / `NPPN_BUFFERACTIVATED`) are still handled, so the report
always reflects the current caret. If the host gains `NPPM_SETSTATUSBAR`, the
passive status-bar behavior can be restored with a one-line change (see the
header comment in `src/EmojiDescription.mm`).

## Build

```sh
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Produces a universal (`arm64;x86_64`) `EmojiDescription.dylib`. Install with:

```sh
cmake --install build
```

which copies it to
`~/Library/Application Support/Nextpad++/plugins/EmojiDescription/`.

## License

GPL v2 — see [LICENSE](LICENSE). Same license as the original plugin and
Notepad++.
