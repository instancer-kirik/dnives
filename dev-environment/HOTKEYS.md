# Hotkey / Action Registration — dnives Dev Guide

dnives is built on **dlangui** and uses its `Action` + `acceleratorMap` system as the
canonical way to bind keyboard shortcuts.  There are two other mechanisms in the codebase
(`HotkeyHandler` / `KeyboardManager` in dcore, and `MainWindow.addKeyboardShortcut`) but
**do not use those for new features in the IDEFrame host** — they are dead/stub code that
does not integrate with the menu or enable/disable state machinery.

---

## The Canonical Pattern (3 steps)

### Step 1 — Add an enum value to `IDEActions`

`src/dlangide/ui/commands.d`

```d
enum IDEActions : int
{
    // ... existing values ...
    WindowToggleTerminal,   // existing example
    MyNewFeature,           // add yours here
}
```

The integer value is assigned automatically (sequential).  The enum is used as the
`Action.id` throughout the codebase — never use a raw integer.

---

### Step 2 — Declare a module-level `const Action`

Same file (`commands.d`), after the existing `const Action` declarations:

```d
// No key binding:
const Action ACTION_MY_FEATURE = new Action(IDEActions.MyNewFeature, "MENU_MY_FEATURE"c);

// With a key binding:
const Action ACTION_MY_FEATURE = new Action(
    IDEActions.MyNewFeature,
    "MENU_MY_FEATURE"c,   // i18n id — add to views/res/i18n/en.ini
    null,                  // icon drawable id, or null
    KeyCode.F8,            // primary key
    cast(KeyFlag)0);       // modifier flags (KeyFlag.Control, .Shift, .Alt, or combinations)

// Additional accelerator (second shortcut for same action):
const Action ACTION_MY_FEATURE = (new Action(...)).addAccelerator(KeyCode.KEY_M, KeyFlag.Control);

// Disabled by default (requires context to enable — see Step 3b):
const Action ACTION_MY_FEATURE = (new Action(...)).disableByDefault();
```

**KeyFlag combinations** use bitwise OR:

| Combo          | Value                               |
|----------------|-------------------------------------|
| Ctrl           | `KeyFlag.Control`                   |
| Ctrl+Shift     | `KeyFlag.Control \| KeyFlag.Shift`  |
| Ctrl+Alt       | `KeyFlag.Control \| KeyFlag.Alt`    |
| Ctrl+Shift+Alt | all three OR'd                      |
| No modifier    | `cast(KeyFlag)0`                    |

---

### Step 3a — Register in `STD_IDE_ACTIONS` (makes it globally active)

At the bottom of `commands.d`:

```d
const Action[] STD_IDE_ACTIONS = [
    // ... existing ...
    ACTION_MY_FEATURE,
];
```

This adds the action to the frame's `acceleratorMap` automatically.  **Omit this for
actions that are context-sensitive** (e.g. only valid when a project is open) and use
`disableByDefault()` + Step 3b instead.

---

### Step 3b — Handle enable/disable state (optional but recommended)

`src/dlangide/ui/frame.d` → `IDEFrame.handleActionStateRequest`:

```d
case IDEActions.MyNewFeature:
    a.state = (currentWorkspace !is null) ? ACTION_STATE_ENABLED : ACTION_STATE_DISABLE;
    return true;
```

---

### Step 4 — Handle the action

`src/dlangide/ui/frame.d` → `IDEFrame.handleAction`:

```d
case IDEActions.MyNewFeature:
    doMyFeature();
    return true;
```

---

### Step 5 — Add to a menu (optional)

`src/dlangide/ui/frame.d` → `createMainMenu` (or wherever the relevant `MenuItem` is built):

```d
subMenu.add(ACTION_MY_FEATURE);
```

The menu item text comes from the i18n key (`"MENU_MY_FEATURE"`) — add it to
`views/res/i18n/en.ini`:

```ini
MENU_MY_FEATURE=My Feature
```

---

## Adding Accelerators to a Dock Widget's Local Scope

For hotkeys that only apply when a specific dock/panel has focus (e.g. workspace panel
file-tree shortcuts), add them to that widget's `acceleratorMap` directly:

```d
// In the widget constructor:
acceleratorMap.add([ACTION_MY_FEATURE, ACTION_OTHER]);

// Override findKeyAction to attach context (e.g. selected tree item):
override Action findKeyAction(uint keyCode, uint flags) {
    Action action = _acceleratorMap.findByKey(keyCode, flags);
    if (action) {
        action.objectParam = selectedItem;
        return action;
    }
    return super.findKeyAction(keyCode, flags);
}
```

See `src/dlangide/ui/wspanel.d` for a full working example.

---

## What NOT to use

| Mechanism                             | Location                              | Status       |
|---------------------------------------|---------------------------------------|--------------|
| `HotkeyHandler.registerHotkey`        | `src/dcore/input/hotkeyhandler.d`     | Stub — no-op in IDEFrame host |
| `KeyboardManager.registerHotkey`      | `src/dcore/input/keyboardmanager.d`   | Stub — no-op in IDEFrame host |
| `MainWindow.addKeyboardShortcut`      | `src/dcore/ui/mainwindow.d`           | Stub — no-op in IDEFrame host |
| `AIIntegration.setupKeyboardShortcuts`| `src/dcore/ai/integration.d`          | Only runs under legacy `MainWindow`, never under `IDEFrame` |

---

## Quick Reference — Existing Key Bindings

| Key            | Action                     | Enum                             |
|----------------|----------------------------|----------------------------------|
| F4             | Toggle AI Chat             | `AIChatToggle`                   |
| F5 Ctrl+Shift  | Start Debugging            | `DebugStart`                     |
| F5 Ctrl        | Run without debug          | `DebugStartNoDebug`              |
| F6             | Toggle Terminal            | `WindowToggleTerminal`           |
| F7             | Build project              | `BuildProject`                   |
| F9             | Toggle breakpoint          | `DebugToggleBreakpoint`          |
| F10            | Step over                  | `DebugStepOver`                  |
| F11            | Step into                  | `DebugStepInto`                  |
| Ctrl+N         | New source file            | `FileNew`                        |
| Ctrl+O         | Open file                  | `FileOpen`                       |
| Ctrl+S         | Save                       | `FileSave`                       |
| Ctrl+Shift+S   | Save all                   | `FileSaveAll`                    |
| Ctrl+W         | Close document             | `WindowCloseDocument`            |
| Ctrl+G         | Go to definition           | `GoToDefinition`                 |
| Ctrl+Space     | Autocomplete               | `GetCompletionSuggestions`       |
| Ctrl+Shift+N   | New AI conversation        | `AINewConversation`              |
| Ctrl+L Alt     | Go to line                 | `GotoLine`                       |
| Ctrl+Shift+F   | Find in files              | `FindInFiles`                    |
