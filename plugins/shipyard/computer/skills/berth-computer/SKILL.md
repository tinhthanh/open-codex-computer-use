---
name: berth-computer
description: Use the user's desktop apps through the berth-computer MCP server (Shipyard's "computer" plugin) — list apps, read an app's accessibility tree, click, type, press keys, scroll, drag and set values in native windows. Use when a task needs a desktop app (Finder, Notes, System Settings, Mousepad, any native GUI), not for web pages (use the browser tools for those).
---

# Desktop apps with berth-computer

The `berth-computer` MCP server drives native apps on the box's desktop through
the accessibility tree (macOS AX, Linux AT-SPI, Windows UIA). It acts in the
user's real session: treat everything on screen as theirs.

## Loop

1. `list_apps` once to find the app's name or pid.
2. `get_app_state {app}` before any action. It returns a numbered tree:
   `<index> <role> <name> Value: … Secondary Actions: … Frame: {…}`.
3. Act with the indexes from the **latest** state:
   - `set_value {app, element_index, value}` for text fields (faster and more
     reliable than typing);
   - `click {app, element_index}` for buttons, menu items, list rows;
   - `perform_secondary_action {app, element_index, action}` for an action the
     tree lists (e.g. `activate`, `show_location`);
   - `type_text` / `press_key {key: "ctrl+s" | "cmd+s" | "Return" …}` for the
     focused element.
4. Every action returns the app's new state. **Read it before the next step.**
   If an action returned an error like "element_index … is no longer present",
   the window changed: call `get_app_state` again and use fresh indexes.

## Verify, don't assume

Report a step as done only when the returned state shows it: the window title
changed (the saved file's name, with no unsaved `*` or dot), the dialog closed, the
value is in the field, the new item is in the list. A click that "succeeded"
only means the event was sent. When saving or creating files, confirm in the
app's state (title, list) — and say so if you could not confirm.

## Keep it cheap

- Use `max_tree_depth` / `max_tree_nodes` on `get_app_state` for big apps, and
  look again deeper only where needed.
- Prefer one `set_value` over many `type_text` calls; prefer keyboard
  shortcuts over menu navigation when you know them.
- Do not re-read state between steps that cannot change the window.

## Rules

- Ask the user before anything that sends, deletes, buys, approves, uploads or
  otherwise changes something outside this machine.
- Never read password managers, keychains, private messages or unrelated
  documents, and never type a password or secret unless the user gave it for
  that exact step.
- Coordinate clicks (`x`/`y`) only when the tree has no element for the
  target. Do not set `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS`.
- On macOS the app needs Accessibility and Screen Recording for "Open
  Computer Use". If tools fail with a permission error, tell the user to run
  `open-computer-use doctor` once on that Mac and allow both; do not try to
  change System Settings yourself.
