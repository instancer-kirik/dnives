module dcore.utils.signals_impl;

import std.traits;
import std.typetuple;
import std.functional;
import core.atomic;
import std.stdio;

/**
 * A more advanced Signal implementation with multi-parameter support
 * This file provides implementation details for signals.d
 */

/**
 * SignalImpl - Base template for all signal implementations
 *
 * This is a utility class that provides common functionality for different
 * signal implementations with varying parameter counts.
 */
class SignalImpl(Args...) {
    alias HandlerFunc = void delegate(Args);
    
    private HandlerFunc[] _handlers;
    private shared bool _locked;
    
    /**
     * Connect a handler to this signal
     */
    public void connect(HandlerFunc handler) {
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
    
    /**
     * Disconnect a handler from this signal
     */
    public void disconnect(HandlerFunc handler) {
        if (handler is null || _handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Find and remove handler
        HandlerFunc[] newHandlers;
        foreach (h; _handlers) {
            if (h != handler)
                newHandlers ~= h;
        }
        
        _handlers = newHandlers;
        atomicStore(_locked, false);
    }
    
    /**
     * Emit the signal, calling all connected handlers
     */
    public void emit(Args args) {
        if (_handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Call all handlers
        foreach (handler; _handlers) {
            if (handler !is null)
                handler(args);
        }
        
        atomicStore(_locked, false);
    }
    
    /**
     * Clear all handlers
     */
    public void clear() {
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        _handlers.length = 0;
        
        atomicStore(_locked, false);
    }
}

/**
 * Function signature extraction utilities
 */
template ArgsOf(alias func) {
    static if (is(typeof(func) == delegate) || is(typeof(func) == function)) {
        alias ArgsOf = ParameterTypeTuple!(typeof(func));
    } else {
        static assert(false, "ArgsOf requires a function or delegate");
    }
}

template ReturnTypeOf(alias func) {
    static if (is(typeof(func) == delegate) || is(typeof(func) == function)) {
        alias ReturnTypeOf = ReturnType!(typeof(func));
    } else {
        static assert(false, "ReturnTypeOf requires a function or delegate");
    }
}

// Helper functions for signal creation
SignalImpl!() createSignal() {
    return new SignalImpl!();
}

SignalImpl!(T) createSignal(T)() {
    return new SignalImpl!(T)();
}

SignalImpl!(T1, T2) createSignal(T1, T2)() {
    return new SignalImpl!(T1, T2)();
}

SignalImpl!(T1, T2, T3) createSignal(T1, T2, T3)() {
    return new SignalImpl!(T1, T2, T3)();
}

// Signal adapter for return values
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