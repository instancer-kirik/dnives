module dcore.input.keyboardmanager;

import std.container : DList;
import std.array : array;
import std.algorithm : canFind;
import std.stdio : writeln;

import dlangui.core.events;
import dlangui.widgets.widget;

import dcore.input.hotkeyhandler;

/**
 * KeyboardManager - Manages keyboard input for the application
 *
 * This class provides centralized keyboard input handling including:
 * - Key state tracking (pressed/released)
 * - Modifier state tracking (Alt, Ctrl, Shift)
 * - Keyboard event routing
 * - Integration with HotkeyHandler for shortcuts
 */
class KeyboardManager {
    private:
        HotkeyHandler _hotkeyHandler;
        bool[uint] _keyStates;  // Tracks which keys are currently pressed
        uint _modifiers;        // Current modifier state
        Widget _focusWidget;    // Current widget that has keyboard focus
        
        // List of key event listeners
        alias KeyEventListener = bool delegate(KeyEvent);
        DList!KeyEventListener _listeners;
        
        // Special keys to track
        enum SpecialKey {
            Tab = 9,
            Enter = 13,
            Escape = 27,
            Space = 32,
            Backspace = 8,
            Delete = 127
        }
        
    public:
        /// Constructor
        this() {
            _hotkeyHandler = new HotkeyHandler();
            _modifiers = 0;
        }
        
        /// Register a hotkey
        void registerHotkey(string name, uint keyCode, uint flags, void delegate() action) {
            _hotkeyHandler.registerHotkey(name, keyCode, flags, action);
        }
        
        /// Add a keyboard event listener
        void addKeyEventListener(KeyEventListener listener) {
            _listeners.insertBack(listener);
        }
        
        /// Remove a keyboard event listener
        void removeKeyEventListener(KeyEventListener listener) {
            // Convert to array for easier manipulation
            auto listenersArray = _listeners.array();
            
            // Find and remove the listener
            foreach (i, l; listenersArray) {
                if (l == listener) {
                    _listeners.clear();
                    foreach (remaining; listenersArray) {
                        if (remaining != listener)
                            _listeners.insertBack(remaining);
                    }
                    break;
                }
            }
        }
        
        /// Set the widget that currently has keyboard focus
        void setFocusWidget(Widget widget) {
            _focusWidget = widget;
        }
        
        /// Get the widget that currently has keyboard focus
        Widget getFocusWidget() {
            return _focusWidget;
        }
        
        /// Handle a keyboard event
        bool handleKeyEvent(KeyEvent event) {
            // Update key state
            if (event.action == KeyAction.KeyDown)
                _keyStates[event.keyCode] = true;
            else if (event.action == KeyAction.KeyUp)
                _keyStates[event.keyCode] = false;
                
            // Update modifier state
            _modifiers = event.flags;
            
            // First, try to handle via hotkey handler
            if (event.action == KeyAction.KeyDown && _hotkeyHandler.handleKeyEvent(event))
                return true;
                
            // Next, pass to focus widget
            if (_focusWidget && _focusWidget.onKeyEvent(event))
                return true;
                
            // Finally, pass to registered listeners
            foreach (listener; _listeners) {
                if (listener(event))
                    return true;
            }
            
            return false;
        }
        
        /// Check if a key is currently pressed
        bool isKeyPressed(uint keyCode) {
            return (keyCode in _keyStates) ? _keyStates[keyCode] : false;
        }
        
        /// Check if a modifier key is active
        bool isModifierActive(uint modifier) {
            return (_modifiers & modifier) != 0;
        }
        
        /// Check if Ctrl is pressed
        bool isCtrlPressed() {
            return isModifierActive(KeyFlag.Control);
        }
        
        /// Check if Shift is pressed
        bool isShiftPressed() {
            return isModifierActive(KeyFlag.Shift);
        }
        
        /// Check if Alt is pressed
        bool isAltPressed() {
            return isModifierActive(KeyFlag.Alt);
        }
}