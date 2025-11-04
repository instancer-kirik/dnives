module dcore.utils.signals;

import std.traits;
import std.typetuple;
import std.functional;
import core.atomic;

/**
 * Basic Signal implementation compatible with dlangui 
 */

// Simple callback interface for parameterless signals
interface SignalHandler {
    void handle();
}

// Simple signal implementation with no parameters
struct Signal() {
    private SignalHandler[] _handlers;
    private shared bool _locked;
    
    /**
     * Connect a handler to this signal
     */
    void connect(SignalHandler handler) {
        if (handler is null)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Add handler if not already connected
        bool found = false;
        foreach (h; _handlers) {
            if (h is handler) {
                found = true;
                break;
            }
        }
        
        if (!found)
            _handlers ~= handler;
            
        atomicStore(_locked, false);
    }
    
    /**
     * Connect a delegate to this signal
     */
    void connect(void delegate() handler) {
        if (handler is null)
            return;
            
        class DelegateWrapper : SignalHandler {
            private void delegate() _dg;
            
            this(void delegate() dg) {
                _dg = dg;
            }
            
            void handle() {
                if (_dg)
                    _dg();
            }
        }
        
        connect(new DelegateWrapper(handler));
    }
    
    /**
     * Disconnect a handler from this signal
     */
    void disconnect(SignalHandler handler) {
        if (handler is null || _handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Find and remove handler
        SignalHandler[] newHandlers;
        foreach (h; _handlers) {
            if (h !is handler)
                newHandlers ~= h;
        }
        
        _handlers = newHandlers;
        atomicStore(_locked, false);
    }
    
    /**
     * Emit the signal, calling all connected handlers
     */
    void emit() {
        if (_handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Call all handlers
        foreach (handler; _handlers) {
            if (handler !is null)
                handler.handle();
        }
        
        atomicStore(_locked, false);
    }
    
    /**
     * Alternative emit syntax
     */
    void opCall() {
        emit();
    }
    
    /**
     * Clear all handlers
     */
    void clear() {
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        _handlers.length = 0;
        
        atomicStore(_locked, false);
    }
}

// Signal with one parameter
struct Signal(T) {
    private void delegate(T)[] _handlers;
    private shared bool _locked;
    
    @property bool assigned() {
        return _handlers.length > 0;
    }
    
    void connect(void delegate(T) handler) {
        if (handler is null)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Add handler if not already connected
        bool found = false;
        foreach (h; _handlers) {
            if (h == handler) {
                found = true;
                break;
            }
        }
        
        if (!found)
            _handlers ~= handler;
            
        atomicStore(_locked, false);
    }
    
    void disconnect(void delegate(T) handler) {
        if (handler is null || _handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Find and remove handler
        void delegate(T)[] newHandlers;
        foreach (h; _handlers) {
            if (h != handler)
                newHandlers ~= h;
        }
        
        _handlers = newHandlers;
        atomicStore(_locked, false);
    }
    
    void emit(T arg) {
        if (_handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Call all handlers
        foreach (handler; _handlers) {
            if (handler !is null)
                handler(arg);
        }
        
        atomicStore(_locked, false);
    }
    
    void opCall(T arg) {
        emit(arg);
    }
    
    void clear() {
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        _handlers.length = 0;
        
        atomicStore(_locked, false);
    }
}

// Signal with two parameters
struct Signal(T1, T2) {
    private void delegate(T1, T2)[] _handlers;
    private shared bool _locked;
    
    void connect(void delegate(T1, T2) handler) {
        if (handler is null)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Add handler if not already connected
        bool found = false;
        foreach (h; _handlers) {
            if (h == handler) {
                found = true;
                break;
            }
        }
        
        if (!found)
            _handlers ~= handler;
            
        atomicStore(_locked, false);
    }
    
    void disconnect(void delegate(T1, T2) handler) {
        if (handler is null || _handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Find and remove handler
        void delegate(T1, T2)[] newHandlers;
        foreach (h; _handlers) {
            if (h != handler)
                newHandlers ~= h;
        }
        
        _handlers = newHandlers;
        atomicStore(_locked, false);
    }
    
    void emit(T1 arg1, T2 arg2) {
        if (_handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Call all handlers
        foreach (handler; _handlers) {
            if (handler !is null)
                handler(arg1, arg2);
        }
        
        atomicStore(_locked, false);
    }
    
    void opCall(T1 arg1, T2 arg2) {
        emit(arg1, arg2);
    }
    
    void clear() {
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        _handlers.length = 0;
        
        atomicStore(_locked, false);
    }
}

// Signal with three parameters
struct Signal(T1, T2, T3) {
    private void delegate(T1, T2, T3)[] _handlers;
    private shared bool _locked;
    
    void connect(void delegate(T1, T2, T3) handler) {
        if (handler is null)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Add handler if not already connected
        bool found = false;
        foreach (h; _handlers) {
            if (h == handler) {
                found = true;
                break;
            }
        }
        
        if (!found)
            _handlers ~= handler;
            
        atomicStore(_locked, false);
    }
    
    void disconnect(void delegate(T1, T2, T3) handler) {
        if (handler is null || _handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Find and remove handler
        void delegate(T1, T2, T3)[] newHandlers;
        foreach (h; _handlers) {
            if (h != handler)
                newHandlers ~= h;
        }
        
        _handlers = newHandlers;
        atomicStore(_locked, false);
    }
    
    void emit(T1 arg1, T2 arg2, T3 arg3) {
        if (_handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Call all handlers
        foreach (handler; _handlers) {
            if (handler !is null)
                handler(arg1, arg2, arg3);
        }
        
        atomicStore(_locked, false);
    }
    
    void opCall(T1 arg1, T2 arg2, T3 arg3) {
        emit(arg1, arg2, arg3);
    }
    
    void clear() {
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        _handlers.length = 0;
        
        atomicStore(_locked, false);
    }
}

// Return value adapter for signal callbacks
struct SignalAdapter(T) {
    T value;
    bool handled;
    
    this(T v) {
        value = v;
        handled = true;
    }
    
    static SignalAdapter!T unhandled() {
        SignalAdapter!T result;
        result.handled = false;
        return result;
    }
}