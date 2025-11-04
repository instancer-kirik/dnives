module dcore.input.hotkeyhandler;

import dlangui.core.events;
import dlangui.widgets.widget;
import std.array;

/**
 * HotkeyHandler - Advanced keyboard shortcut handling
 */
class HotkeyHandler {
    private struct HotkeyAction {
        string name;
        uint keyCode;
        uint flags;
        void delegate() action;
    }

    private HotkeyAction[] actions;

    // Register a new hotkey action
    void registerHotkey(string name, uint keyCode, uint flags, void delegate() action) {
        actions ~= HotkeyAction(name, keyCode, flags, action);
    }

    // Handle key event
    bool handleKeyEvent(KeyEvent event) {
        foreach (action; actions) {
            if (event.keyCode == action.keyCode && event.flags == action.flags) {
                action.action();
                return true;
            }
        }
        return false;
    }
}
