// EmojiDescription — macOS port
// Original Windows plugin: "Emoji Description" by Ruberoid (GPL v2).
// https://github.com/Ruberoid/npp_emoji_description
//
// Shows the encoding information of the character under the cursor:
//   Unicode code point (U+XXXX), decimal, hexadecimal, HTML entity (&#…;),
//   and the UTF-8 byte sequence. Works for ASCII, BMP, and astral characters
//   (emoji, etc.).
//
// The decode/format logic (decodeUtf8Char / formatCharacterCodes) is ported
// VERBATIM from the Windows source — same byte parsing, same output string.
// Only the platform layer changes: ::SendMessage → nppData._sendMessage,
// std::wstringstream → std::ostringstream (UTF-8 char on macOS), MessageBox →
// NSAlert.
//
// ─────────────────────────────────────────────────────────────────────────────
// HOST DIVERGENCE (documented, intentional — no host changes):
//   The Windows plugin pushes its result text into the status bar continuously
//   via NPPM_SETSTATUSBAR(STATUSBAR_DOC_TYPE, …) on every SCN_UPDATEUI.
//   The Nextpad++ macOS host does NOT implement NPPM_SETSTATUSBAR (it falls
//   through to the dispatcher's `default:` → logs "Unimplemented NPPM message"
//   and returns 0), and its status bar exposes no plugin-addressable segment.
//   See notepad-plus-plus-macos/src/NppPluginManager.mm (-handleNppMessage:)
//   and MainWindowController.mm (only _statusLeft/_statusRight text fields).
//
//   Hacking the host is forbidden, so the result is surfaced through the
//   nearest faithful macOS equivalent: the "Show Character Info" command
//   computes the info for the character under the cursor on demand and shows
//   it in an alert — identical data, on demand instead of passively. The live
//   SCN_UPDATEUI / NPPN_BUFFERACTIVATED path still tracks the current codepoint
//   (cheap), so the command always reflects the current caret instantly. If the
//   host later implements NPPM_SETSTATUSBAR, restore the passive behavior by
//   routing showCurrentCharInfo()'s string there instead of to the alert.
// ─────────────────────────────────────────────────────────────────────────────

#include "NppPluginInterfaceMac.h"
#include "Scintilla.h"
#import <Cocoa/Cocoa.h>

#include <cstdint>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <string>

static const char *PLUGIN_NAME = "Emoji Description";
static const int   nbFunc      = 2;

namespace {

NppData  nppData;
FuncItem funcItem[nbFunc];

// Plugin state — mirrors g_showCharInfo from the Windows source. When OFF, the
// command stops reporting (matches the original toggle semantics).
bool gShowCharInfo  = true;
// Last codepoint computed by the live notification path (0 = none / end of doc).
uint32_t gLastCodepoint = 0;

// ── platform helpers ────────────────────────────────────────────────────────
NppHandle currentScintilla() {
    int which = -1;
    nppData._sendMessage(nppData._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, (intptr_t)&which);
    if (which == 0) return nppData._scintillaMainHandle;
    if (which == 1) return nppData._scintillaSecondHandle;
    return 0;
}

intptr_t sci(NppHandle h, uint32_t msg, uintptr_t wp = 0, intptr_t lp = 0) {
    return nppData._sendMessage(h, msg, wp, lp);
}

// ── ported logic (verbatim semantics) ───────────────────────────────────────
//
// Decode the UTF-8 character at the start of `text`. Sets bytesRead to the
// number of bytes consumed (0 on malformed input). Identical to the Windows
// decodeUtf8Char().
uint32_t decodeUtf8Char(const unsigned char *text, int &bytesRead) {
    bytesRead = 0;
    if (!text || !text[0])
        return 0;

    unsigned char firstByte = text[0];

    // 1-byte character (ASCII)
    if ((firstByte & 0x80) == 0) {
        bytesRead = 1;
        return firstByte;
    }

    // 2-byte character
    if ((firstByte & 0xE0) == 0xC0) {
        if ((text[1] & 0xC0) != 0x80)
            return 0;
        bytesRead = 2;
        return ((firstByte & 0x1F) << 6) | (text[1] & 0x3F);
    }

    // 3-byte character
    if ((firstByte & 0xF0) == 0xE0) {
        if ((text[1] & 0xC0) != 0x80 || (text[2] & 0xC0) != 0x80)
            return 0;
        bytesRead = 3;
        return ((firstByte & 0x0F) << 12) | ((text[1] & 0x3F) << 6) | (text[2] & 0x3F);
    }

    // 4-byte character (includes emoji)
    if ((firstByte & 0xF8) == 0xF0) {
        if ((text[1] & 0xC0) != 0x80 || (text[2] & 0xC0) != 0x80 || (text[3] & 0xC0) != 0x80)
            return 0;
        bytesRead = 4;
        return ((firstByte & 0x07) << 18) | ((text[1] & 0x3F) << 12) |
               ((text[2] & 0x3F) << 6) | (text[3] & 0x3F);
    }

    return 0;
}

// Format the code-point's representations into a single line. Byte-for-byte the
// same output as the Windows formatCharacterCodes() (wstringstream → ostringstream;
// the text is pure ASCII so the bytes are identical).
std::string formatCharacterCodes(uint32_t codepoint) {
    if (!codepoint)
        return "No character";

    std::ostringstream ss;

    // Unicode code point
    ss << "U+" << std::uppercase << std::hex << std::setfill('0') << std::setw(4) << codepoint;

    // Decimal
    ss << " | Dec: " << std::dec << codepoint;

    // Hexadecimal
    ss << " | Hex: 0x" << std::uppercase << std::hex << codepoint;

    // HTML entity
    ss << " | HTML: &#" << std::dec << codepoint << ";";

    // UTF-8 bytes
    ss << " | UTF-8: ";
    if (codepoint < 0x80) {
        ss << "0x" << std::uppercase << std::hex << std::setfill('0') << std::setw(2) << codepoint;
    } else if (codepoint < 0x800) {
        unsigned char b1 = static_cast<unsigned char>(0xC0 | (codepoint >> 6));
        unsigned char b2 = static_cast<unsigned char>(0x80 | (codepoint & 0x3F));
        ss << "0x" << std::uppercase << std::hex << std::setfill('0') << std::setw(2) << (int)b1
           << " 0x" << std::setw(2) << (int)b2;
    } else if (codepoint < 0x10000) {
        unsigned char b1 = static_cast<unsigned char>(0xE0 | (codepoint >> 12));
        unsigned char b2 = static_cast<unsigned char>(0x80 | ((codepoint >> 6) & 0x3F));
        unsigned char b3 = static_cast<unsigned char>(0x80 | (codepoint & 0x3F));
        ss << "0x" << std::uppercase << std::hex << std::setfill('0') << std::setw(2) << (int)b1
           << " 0x" << std::setw(2) << (int)b2
           << " 0x" << std::setw(2) << (int)b3;
    } else {
        unsigned char b1 = static_cast<unsigned char>(0xF0 | (codepoint >> 18));
        unsigned char b2 = static_cast<unsigned char>(0x80 | ((codepoint >> 12) & 0x3F));
        unsigned char b3 = static_cast<unsigned char>(0x80 | ((codepoint >> 6) & 0x3F));
        unsigned char b4 = static_cast<unsigned char>(0x80 | (codepoint & 0x3F));
        ss << "0x" << std::uppercase << std::hex << std::setfill('0') << std::setw(2) << (int)b1
           << " 0x" << std::setw(2) << (int)b2
           << " 0x" << std::setw(2) << (int)b3
           << " 0x" << std::setw(2) << (int)b4;
    }

    return ss.str();
}

// Read the character under the caret of the current editor and decode it.
// Returns the code point (0 = none), sets atEnd when the caret sits at end of
// document. Mirrors the read half of the Windows updateCharacterInfo().
uint32_t codepointUnderCaret(bool &atEnd) {
    atEnd = false;
    NppHandle s = currentScintilla();
    if (!s)
        return 0;

    Sci_Position pos       = (Sci_Position)sci(s, SCI_GETCURRENTPOS);
    Sci_Position docLength = (Sci_Position)sci(s, SCI_GETLENGTH);
    if (pos >= docLength) {
        atEnd = true;
        return 0;
    }

    // Read up to 4 bytes for a full UTF-8 sequence.
    unsigned char buffer[5] = {0};
    Sci_TextRangeFull tr;
    tr.chrg.cpMin = pos;
    tr.chrg.cpMax = pos + 4;
    if (tr.chrg.cpMax > docLength)
        tr.chrg.cpMax = docLength;
    tr.lpstrText = (char *)buffer;

    sci(s, SCI_GETTEXTRANGEFULL, 0, (intptr_t)&tr);

    int bytesRead = 0;
    return decodeUtf8Char(buffer, bytesRead);
}

// Keep gLastCodepoint current. Called from the live notification path. Cheap;
// no UI. (On Windows this also wrote the status bar — unavailable here, see the
// HOST DIVERGENCE note at the top of the file.)
void refreshCharacterInfo() {
    if (!gShowCharInfo) {
        gLastCodepoint = 0;
        return;
    }
    bool atEnd = false;
    gLastCodepoint = codepointUnderCaret(atEnd);
}

// ── commands ─────────────────────────────────────────────────────────────────
void showCurrentCharInfo() {
    @autoreleasepool {
        // Toggle semantics preserved: this command flips the on/off state, like
        // the Windows "Show Character Info". When turned ON we also report the
        // current character immediately; when turned OFF we just acknowledge.
        gShowCharInfo = !gShowCharInfo;
        nppData._sendMessage(nppData._nppHandle, NPPM_SETMENUITEMCHECK,
                             (uintptr_t)funcItem[0]._cmdID, gShowCharInfo ? 1 : 0);

        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"Emoji Description";
        a.alertStyle  = NSAlertStyleInformational;

        if (!gShowCharInfo) {
            a.informativeText = @"Character info reporting turned OFF.";
            [a runModal];
            return;
        }

        bool atEnd = false;
        uint32_t cp = codepointUnderCaret(atEnd);
        gLastCodepoint = cp;

        NSString *body;
        if (atEnd) {
            body = @"End of document — no character under the cursor.";
        } else if (cp == 0) {
            body = @"No character under the cursor.";
        } else {
            body = [NSString stringWithUTF8String:formatCharacterCodes(cp).c_str()];
        }
        a.informativeText = body;
        [a runModal];
    }
}

void aboutDialog() {
    @autoreleasepool {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"About Emoji Description";
        a.alertStyle  = NSAlertStyleInformational;
        a.informativeText =
            @"Emoji Description v0.1.0 (macOS port)\n\n"
             "Shows detailed character-encoding information for the character "
             "under the cursor.\n\n"
             "Reports for any character:\n"
             "- Unicode code point (U+XXXX)\n"
             "- Decimal and Hexadecimal values\n"
             "- HTML entity (&#XXXX;)\n"
             "- UTF-8 byte sequence\n\n"
             "Supports all Unicode characters including emoji.\n\n"
             "Note: the Nextpad++ macOS host does not expose a plugin-writable "
             "status bar, so \"Show Character Info\" reports the current "
             "character on demand instead of passively in the status bar.\n\n"
             "Original Windows plugin by Ruberoid.\n"
             "https://github.com/Ruberoid/npp_emoji_description";
        [a addButtonWithTitle:@"OK"];
        [a addButtonWithTitle:@"Project Page"];
        NSModalResponse r = [a runModal];
        if (r == NSAlertSecondButtonReturn) {
            [[NSWorkspace sharedWorkspace]
                openURL:[NSURL URLWithString:@"https://github.com/Ruberoid/npp_emoji_description"]];
        }
    }
}

} // namespace

// ── plugin exports ────────────────────────────────────────────────────────────
extern "C" NPP_EXPORT void setInfo(NppData data) {
    nppData = data;
    memset(funcItem, 0, sizeof(funcItem));

    strncpy(funcItem[0]._itemName, "Show Character Info", NPP_MENU_ITEM_SIZE - 1);
    funcItem[0]._pFunc      = showCurrentCharInfo;
    funcItem[0]._pShKey     = nullptr;
    funcItem[0]._init2Check = true;   // checked on init (matches the Windows default-on)

    strncpy(funcItem[1]._itemName, "About", NPP_MENU_ITEM_SIZE - 1);
    funcItem[1]._pFunc      = aboutDialog;
    funcItem[1]._pShKey     = nullptr;
}

extern "C" NPP_EXPORT const char *getName() { return PLUGIN_NAME; }

extern "C" NPP_EXPORT FuncItem *getFuncsArray(int *nbF) { *nbF = nbFunc; return funcItem; }

extern "C" NPP_EXPORT void beNotified(SCNotification *n) {
    if (!n) return;
    switch (n->nmhdr.code) {
        case SCN_UPDATEUI:
            // Cursor moved or content/selection changed — keep our cached
            // codepoint current (matches the Windows trigger mask).
            if (n->updated & (SC_UPDATE_SELECTION | SC_UPDATE_CONTENT))
                refreshCharacterInfo();
            break;

        case NPPN_BUFFERACTIVATED:
            // Switched documents — refresh.
            refreshCharacterInfo();
            break;

        default:
            break;
    }
}

extern "C" NPP_EXPORT intptr_t messageProc(uint32_t m, uintptr_t w, intptr_t l) {
    (void)m; (void)w; (void)l;
    return 1;
}
