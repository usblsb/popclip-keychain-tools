# JL Keychain Tools — PopClip extension

A [PopClip](https://www.popclip.app/) extension to **save, retrieve, list and delete API keys / passwords** in the macOS Keychain. All entries are namespaced with the `jl-` prefix so they don't mix with system entries (Wi-Fi, Safari passwords, etc.).

![macOS](https://img.shields.io/badge/macOS-12%2B-blue) ![PopClip](https://img.shields.io/badge/PopClip-4069%2B-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## Why

Stop pasting API keys into chats, scripts, plain `.env` files or shell history. With this extension you can:

- Select an API key in any app → click **Save** → it lives encrypted in the macOS Keychain.
- When you need it, select the name → click **Get** → the value is copied to your clipboard.
- Use **List** to browse what you've stored. Use **Delete** to remove obsolete keys.

Zero external dependencies — uses only the macOS-bundled `security` CLI and AppleScript dialogs (`osascript`).

## What's in the menu

| # | Action | Icon | Input (selected text) | Effect |
|---|---|---|---|---|
| 1 | **Save to Keychain** | 🔒 lock | The value, with or without `NAME=VALUE` form | Stores the value in Keychain. Auto-detects `KEY=value` pattern; otherwise asks for a name with a native dialog. |
| 2 | **Get from Keychain** | 🔑 key | The name of the entry (with or without `jl-` prefix) | **Copies the value to the clipboard** (does not paste in place, for safety on shared screens) and shows a notification. |
| 3 | **List Keychain (jl-*)** | 📋 list | (any text — selection is required by PopClip but ignored) | Shows a native list of all your `jl-*` entries. Pick one → its value is copied to the clipboard. |
| 4 | **Delete from Keychain** | 🗑 trash | The name of the entry | Asks for confirmation and removes the entry. |

## Save — automatic vs prompted name

The extension picks one of two modes depending on what you select:

### Auto mode (when the selection contains `=`)

If you select something that looks like a `.env` line or a shell variable assignment, the extension parses it and saves with no extra question:

| Selected text | Stored as |
|---|---|
| `OPENROUTER_API_KEY=sk-or-v1-abc123` | `jl-openrouter-api-key` → `sk-or-v1-abc123` |
| `OPENROUTER_API_KEY="sk-or-v1-abc123"` | (quotes stripped) |
| `OPENROUTER_API_KEY='sk-or-v1-abc123'` | (single quotes stripped) |
| `OPENROUTER_API_KEY = sk-or-v1-abc123` | (spaces around `=` trimmed) |
| `export OPENROUTER_API_KEY=sk-or-v1-abc123` | (leading `export ` removed) |
| `OPENROUTER_API_KEY=sk-or-v1-abc123  # my key` | (trailing inline comment removed) |
| `OPENROUTER_API_KEY=base64+pad==` | (only the **first** `=` is the separator) |

### Prompted mode (no `=` in selection)

If you select just the value (e.g. `sk-or-v1-abc123` on its own), a native macOS dialog asks for the name. You type something like `openrouter-api-key`, press OK, and it's stored.

### Name normalization

The name you give (or that's parsed from a `KEY=VALUE` line) gets normalized:

- Lowercased: `OPENROUTER_API_KEY` → `openrouter_api_key`
- Non-`[a-z0-9-]` characters become `-`: `openrouter_api_key` → `openrouter-api-key`
- Multiple `-` collapsed and trimmed: `--foo--bar--` → `foo-bar`
- `jl-` prefix added if missing: `openrouter-api-key` → `jl-openrouter-api-key`

Why the `jl-` prefix? So that **List** shows only your own entries, not the hundreds of unrelated items macOS keeps in the login keychain (Wi-Fi networks, Safari saved passwords, app credentials, etc.).

## Requirements

- macOS 12 or later
- [PopClip](https://www.popclip.app/) 4069 or later
- That's it. `security`, `osascript` and `pbcopy` ship with macOS.

## Installation

### Option A — Clone the repo

```bash
git clone https://github.com/usblsb/popclip-keychain-tools.git
cd popclip-keychain-tools
open JlKeychainTools.popclipext
```

PopClip will pick up the folder and prompt you to install.

### Option B — Download

1. Download the latest `JlKeychainTools.popclipext.zip` from [Releases](../../releases) and unzip.
2. Double-click the unzipped folder.
3. PopClip will ask to install — confirm.

## First-run authorization (important)

The first time the extension reads from or writes to the Keychain, macOS shows a **"Allow access"** prompt with three options:

- **Deny** — the operation fails.
- **Allow** — works once; macOS will ask again next time.
- **Always Allow** — recommended. You won't be prompted again for the same item.

If you don't choose **Always Allow** the first time, you'll get the auth prompt every time you click Get. To grant **Always Allow** later for an entry that already exists, open **Keychain Access**, find your `jl-*` entry, double-click it → **Access Control** tab → add `bash` and `security` to the always-allow list.

## Usage

1. Select any text in any macOS app.
2. The PopClip popover appears with the 4 buttons.
3. Click an action. macOS may ask for Touch ID / password the first time.

### Examples

**Save your OpenRouter API key from the OpenRouter dashboard**

1. Copy `sk-or-v1-abc123def456...` from https://openrouter.ai/keys
2. Paste it somewhere temporarily, select it (or copy as a `.env` line `OPENROUTER_API_KEY="sk-or-v1-..."` for auto mode).
3. PopClip → **Save to Keychain**.
4. (If you didn't use the `KEY=VALUE` form) Type `openrouter-api-key` in the dialog, press OK.
5. Done. Stored as `jl-openrouter-api-key`.

**Use it later**

1. In any app, type or paste `openrouter-api-key`, select that text.
2. PopClip → **Get from Keychain**.
3. (First time) Click **Always Allow** on the macOS prompt.
4. The selection is replaced in place by the actual value. Done.

**See what you have stored**

1. Select any text (PopClip needs a selection to show its menu).
2. PopClip → **List Keychain (jl-*)**.
3. Pick an entry from the dialog → its value replaces your original selection in place.

**Remove an entry**

1. Select the entry name (e.g. `openrouter-api-key`).
2. PopClip → **Delete from Keychain**.
3. Confirm in the dialog.

## Viewing your entries with the macOS Keychain Access app

Sometimes you want to browse, audit or clean up your saved entries outside PopClip — for example to see what's there, change access controls, or remove old keys in bulk. macOS has a built-in app for this.

> ⚠️ **Important**: on macOS Sequoia (15+) Apple split the system into two apps:
> - **Passwords** (the new one) — only shows website / browser passwords. **Your `jl-*` API keys do NOT appear here.**
> - **Keychain Access** (the classic one) — shows the full Keychain. **This is the one you need.**

### Open the app

- Spotlight (`⌘ + Space`) → type **`Keychain Access`** (or **`Acceso a Llaveros`** in Spanish) → Enter.
- Or: Finder → **Applications → Utilities → Keychain Access.app**.

### Browse your entries

1. **Sidebar (left)** → expand **Default Keychains** → click **`login`**. This is where every entry the extension saves lives.
2. **Categories (bottom-left)** → click **Passwords**. Filters out certificates and keys, leaving only the password-style items.
3. **Search box (top-right)** → type `jl-` to see only the entries created by this extension. Type `averiado-` (or any extra prefix you've configured) to see those too.

You'll see a list like:

```
jl-openrouter-api-key
jl-test-api-key
averiado-openrouter-api-key
averiado-stripe-secret-key
...
```

### View the value of an entry

1. **Double-click** the entry row.
2. In the sheet that opens, tick **Show password** at the bottom.
3. macOS asks for your login password or Touch ID → confirm.
4. The value appears in the field next to the checkbox.

### Manage access permissions

In the same detail window, click the **Access Control** tab to see which apps can read this entry without prompting:

- **Allow all applications to access this item** — most permissive (not recommended for secrets).
- **Confirm before allowing access** — prompts every time (most secure, most friction).
- **Always allow access by these applications** — list the binaries that should be allowed silently. To grant the extension's silent access, add `/bin/bash` and `/usr/bin/security` to this list.

### Delete entries

- Select the row → press **Delete** / **Backspace**, or right-click → **Delete**.
- macOS asks to confirm. After confirming the entry is gone — the extension's `List` will not show it anymore either.

### Quick inventory from the terminal

To dump just the **names** (not the values) of every entry in your login keychain to a file on the Desktop:

```bash
security dump-keychain 2>/dev/null | awk -F'"' '/"svce"<blob>=/{print $4}' | sort -u > ~/Desktop/keychain-inventory.txt
```

Open that file in any editor — it's plain text, one entry name per line. Useful for auditing or for finding all the prefixes you might want to add to the **Extra prefixes** option.

## How it works

The extension is a single PopClip shell action defined in [`JlKeychainTools.popclipext/Config.json`](JlKeychainTools.popclipext/Config.json). Each of the 4 actions runs the same Bash script with a different subcommand:

- [`jl_keychain.sh`](JlKeychainTools.popclipext/jl_keychain.sh) reads `$POPCLIP_TEXT` (the selection) and dispatches to one of `cmd_save`, `cmd_get`, `cmd_list`, `cmd_delete`.
- For the Keychain calls it uses macOS' built-in `security` CLI (`add-generic-password`, `find-generic-password`, `delete-generic-password`, `dump-keychain`).
- For the dialogs and notifications it uses `osascript` (AppleScript).
- Get and List write the retrieved value to **stdout**, and PopClip pastes it in place via `after: paste-result`. So your selection is replaced by the actual value with a single click — no manual `Cmd+V` needed.
- Save and Delete don't paste anything; they only show macOS notifications.

The account field for every `security` call is derived from `id -un` (because PopClip strips `$USER` from the action environment).

The script targets Bash 3.2 (the macOS default `/bin/bash`). No external dependencies.

## Configuring extra prefixes

By default, only entries whose service name starts with `jl-` are shown by **List** and accepted by **Get** / **Delete** without renaming. If you have older entries from other tools or projects (e.g. names starting with `averiado-`, `mycompany-`, `oldproject-`), open **PopClip → Preferences → Extensions → JL Keychain Tools** (gear icon) and fill the **Extra prefixes** field with a comma-separated list, e.g.:

```
averiado-,mycompany-,oldproject-
```

Effects:

- **List** now includes entries with any of those prefixes (still excludes the rest of the system Keychain).
- **Get** and **Delete** no longer auto-prepend `jl-` if the selected name already starts with one of the allowed prefixes — so selecting `averiado-openrouter-api-key` resolves to that exact entry.
- **Save** is unaffected: new entries are still always created with `jl-` prefix. To create an entry under another prefix, use the `security` CLI directly.

## Security notes

- All values are stored in the **login keychain**, encrypted by macOS and tied to your user account.
- The script never logs values, never sends anything to the network, and never writes secrets to disk (the debug log at `/tmp/jl_keychain_debug.log` only contains environment metadata, never `POPCLIP_TEXT` content beyond what's needed for the matching, and never the resolved value).
- Get and List replace the selection in place. If your screen is being shared (Zoom, Teams, etc.), the value will become visible in the document. For a copy-only flow, retrieve from Keychain Access manually.

## Limitations

- **List** uses `security dump-keychain` and filters by allowed prefixes. On a heavily populated login keychain this can take 1-2 seconds.
- The List dialog isn't searchable. If you ever store dozens of entries, scroll or rename for clarity.
- All values are saved as **generic passwords**. Internet passwords (`security add-internet-password`) are not used here.
- The script does not support multiple accounts per service. One value per `jl-name`.
- **Save** always uses the `jl-` prefix. To save under another prefix, use the `security` CLI directly (see Configuring extra prefixes above).

## License

MIT — see [LICENSE](LICENSE).

## Credits

- **Idea, product direction & UX decisions** — [Juan Luis Martel](https://github.com/usblsb).
- **Built with love using [Claude Code](https://claude.com/claude-code)** powered by **Claude Opus 4.7 (1M context)** — Anthropic's CLI for Claude. Claude wrote the Bash script, the AppleScript dialogs, the `.env`-style parser, the name normalizer, and the PopClip configuration under Juan's supervision and review.
- **Built on top of** macOS' [`security`](x-man-page://1/security) CLI and [PopClip](https://www.popclip.app/).
