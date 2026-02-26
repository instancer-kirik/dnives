module dcore.editor.syntax.tokenizerregistry;

import std.string;
import std.algorithm;
import std.array;
import std.path;
import std.file;

import dlangui.core.logger;

import dcore.editor.syntax.tokenizer;

/**
 * TokenizerRegistry - Manages syntax tokenizers for different file types
 * 
 * This registry keeps track of available tokenizers and helps to select
 * the appropriate tokenizer based on file extension or content.
 */
class TokenizerRegistry {
    private {
        Tokenizer[string] _tokenizers;        // Tokenizers by file extension
        Tokenizer _defaultTokenizer;          // Default tokenizer for unknown file types
        string[] _supportedExtensions;        // List of supported file extensions
    }
    
    /**
     * Constructor
     */
    this() {
        // Initialize with default tokenizer
        _defaultTokenizer = new Tokenizer();
        
        // Register built-in tokenizers
        registerBuiltInTokenizers();
    }
    
    /**
     * Register built-in tokenizers for common languages
     */
    private void registerBuiltInTokenizers() {
        // Registration will happen later when tokenizers are implemented
        // Example: registerTokenizer(new PythonTokenizer(), ["py"]);
        
        Log.i("Registered built-in tokenizers");
    }
    
    /**
     * Register a tokenizer for specific file extensions
     * 
     * Params:
     *   tokenizer = The tokenizer to register
     *   extensions = Array of file extensions to associate with this tokenizer
     */
    void registerTokenizer(Tokenizer tokenizer, string[] extensions) {
        if (tokenizer is null || extensions.length == 0)
            return;
            
        foreach (ext; extensions) {
            string normalizedExt = ext.toLower();
            
            // Skip if already registered
            if (normalizedExt in _tokenizers)
                continue;
                
            // Register tokenizer for this extension
            _tokenizers[normalizedExt] = tokenizer;
            
            // Add to supported extensions if not already there
            if (!_supportedExtensions.canFind(normalizedExt))
                _supportedExtensions ~= normalizedExt;
        }
        
        // Sort extensions for faster lookup
        _supportedExtensions.sort();
    }
    
    /**
     * Unregister a tokenizer for the given extensions
     * 
     * Params:
     *   extensions = Array of file extensions to unregister
     */
    void unregisterTokenizer(string[] extensions) {
        if (extensions.length == 0)
            return;
            
        foreach (ext; extensions) {
            string normalizedExt = ext.toLower();
            
            // Remove from registry
            if (normalizedExt in _tokenizers)
                _tokenizers.remove(normalizedExt);
                
            // Remove from supported extensions
            _supportedExtensions = _supportedExtensions.filter!(e => e != normalizedExt).array;
        }
    }
    
    /**
     * Get tokenizer for a specific file
     * 
     * Params:
     *   filename = The filename to get a tokenizer for
     * 
     * Returns: The appropriate tokenizer for this file, or default tokenizer if none matches
     */
    Tokenizer getTokenizerForFile(string filename) {
        if (filename.length == 0)
            return _defaultTokenizer;
            
        // Extract extension
        string ext = extension(filename).toLower();
        if (ext.startsWith("."))
            ext = ext[1..$]; // Remove leading dot
            
        // Return tokenizer for this extension if found
        if (ext in _tokenizers)
            return _tokenizers[ext];
            
        // Try to detect by content if file exists
        if (exists(filename) && isFile(filename)) {
            try {
                // TODO: Add content-based detection
            } catch (Exception e) {
                Log.w("Failed to detect tokenizer by content: ", e.msg);
            }
        }
        
        return _defaultTokenizer;
    }
    
    /**
     * Check if a file extension is supported
     * 
     * Params:
     *   extension = The file extension to check
     * 
     * Returns: true if the extension is supported, false otherwise
     */
    bool isExtensionSupported(string extension) {
        string ext = extension.toLower();
        
        // Remove leading dot if present
        if (ext.startsWith("."))
            ext = ext[1..$];
            
        return (ext in _tokenizers) !is null;
    }
    
    /**
     * Get list of all supported file extensions
     * 
     * Returns: Array of supported file extensions
     */
    string[] getSupportedExtensions() {
        return _supportedExtensions.dup;
    }
    
    /**
     * Set the default tokenizer for unknown file types
     * 
     * Params:
     *   tokenizer = The tokenizer to use as default
     */
    void setDefaultTokenizer(Tokenizer tokenizer) {
        if (tokenizer !is null)
            _defaultTokenizer = tokenizer;
    }
    
    /**
     * Get the default tokenizer
     * 
     * Returns: The default tokenizer
     */
    Tokenizer getDefaultTokenizer() {
        return _defaultTokenizer;
    }
}