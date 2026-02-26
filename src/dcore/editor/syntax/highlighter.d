module dcore.editor.syntax.highlighter;

import dlangui.core.logger;
import dlangui.graphics.colors;
import std.string;
import std.regex;
import std.array;
import std.algorithm;
import std.conv;

import dcore.editor.syntax.tokenizer;
import dcore.editor.syntax.tokenizerregistry;
import dcore.ui.thememanager;

/**
 * SyntaxHighlighter - Highlights syntax based on tokenization and theme
 *
 * This class is responsible for:
 * - Coordinating the tokenization of text
 * - Applying theme styling to tokens
 * - Supporting multiple languages
 * - Providing highlighted segments for rendering
 */
class SyntaxHighlighter {
    private TokenizerRegistry _tokenizerRegistry;
    private ThemeManager _themeManager;
    private string _language = "text";
    
    /// Constructor
    this() {
        // Create tokenizer registry
        _tokenizerRegistry = new TokenizerRegistry();
        
        // Register built-in tokenizers
        registerDefaultTokenizers();
    }
    
    /// Set theme manager
    void setThemeManager(ThemeManager themeManager) {
        _themeManager = themeManager;
    }
    
    /// Set language
    void setLanguage(string language) {
        _language = language;
    }
    
    /// Get current language
    string getLanguage() {
        return _language;
    }
    
    /// Register default tokenizers
    private void registerDefaultTokenizers() {
        // Register built-in tokenizers for common languages
        
        // Generic code tokenizer (fallback)
        _tokenizerRegistry.registerTokenizer(new Tokenizer(), ["text"]);
        
        // D language tokenizer
        _tokenizerRegistry.registerTokenizer(new Tokenizer(), ["d"]);
        
        // C/C++ tokenizer
        _tokenizerRegistry.registerTokenizer(new Tokenizer(), ["c"]);
        _tokenizerRegistry.registerTokenizer(new Tokenizer(), ["cpp", "h", "hpp"]);
        
        // JavaScript tokenizer
        _tokenizerRegistry.registerTokenizer(new JavaScriptTokenizer(), ["js", "ts", "json"]);
        
        // Python tokenizer
        _tokenizerRegistry.registerTokenizer(new Tokenizer(), ["py", "python"]);
    }
    
    /// Register a custom tokenizer
    void registerTokenizer(string language, Tokenizer tokenizer) {
        _tokenizerRegistry.registerTokenizer(tokenizer, [language]);
    }
    
    /**
     * Highlight a line of text
     * Returns an array of highlighted segments
     */
    HighlightedSegment[] highlightLine(dstring text, int lineIndex) {
        HighlightedSegment[] result;
        
        // Get tokenizer for current language
        Tokenizer tokenizer = _tokenizerRegistry.getTokenizerForFile(_language);
        if (!tokenizer) {
            // Fallback to generic tokenizer
            tokenizer = _tokenizerRegistry.getTokenizerForFile("text");
            if (!tokenizer) {
                // No tokenizer available, return plain text
                result ~= HighlightedSegment(text, 0, cast(int)text.length, "text", 0xFFFFFF, 0, false, false, false);
                return result;
            }
        }
        
        // Tokenize the line
        Token[] tokens = tokenizer.tokenizeLine(text, lineIndex);
        
        // Create highlighted segments from tokens
        foreach (token; tokens) {
            // Get style from theme
            Theme.SyntaxTokenStyle style;
            
            if (_themeManager) {
                style = _themeManager.getSyntaxStyle(_language, token.type);
            } else {
                // Default style if no theme manager
                style = Theme.SyntaxTokenStyle(0xFFFFFF);
            }
            
            // Create highlighted segment
            HighlightedSegment segment = HighlightedSegment(
                text,
                token.position,
                token.length,
                token.type,
                style.foreground,
                style.background,
                style.bold,
                style.italic,
                style.underline
            );
            
            result ~= segment;
        }
        
        return result;
    }
    
    /**
     * Highlight multiple lines
     */
    HighlightedSegment[][] highlightLines(dstring[] lines) {
        HighlightedSegment[][] result;
        
        // Get tokenizer for current language
        Tokenizer tokenizer = _tokenizerRegistry.getTokenizerForFile(_language);
        if (!tokenizer) {
            // Fallback to generic tokenizer
            tokenizer = _tokenizerRegistry.getTokenizerForFile("text");
            if (!tokenizer) {
                // No tokenizer available, return plain text segments
                foreach (i, line; lines) {
                    HighlightedSegment[] lineSegments;
                    lineSegments ~= HighlightedSegment(line, 0, cast(int)line.length, "text", 0xFFFFFF, 0, false, false, false);
                    result ~= lineSegments;
                }
                return result;
            }
        }
        
        // First pass: tokenize all lines
        Token[][] allTokens;
        foreach (i, line; lines) {
            Token[] lineTokens = tokenizer.tokenizeLine(line, cast(int)i);
            allTokens ~= lineTokens;
        }
        
        // Second pass: apply multi-line token adjustments if necessary
        tokenizer.processMultiLineTokens(allTokens, lines);
        
        // Create highlighted segments
        foreach (i, tokens; allTokens) {
            HighlightedSegment[] lineSegments;
            
            foreach (token; tokens) {
                // Get style from theme
                Theme.SyntaxTokenStyle style;
                
                if (_themeManager) {
                    style = _themeManager.getSyntaxStyle(_language, token.type);
                } else {
                    // Default style if no theme manager
                    style = Theme.SyntaxTokenStyle(0xFFFFFF);
                }
                
                // Create highlighted segment
                HighlightedSegment segment = HighlightedSegment(
                    lines[i],
                    token.position,
                    token.length,
                    token.type,
                    style.foreground,
                    style.background,
                    style.bold,
                    style.italic,
                    style.underline
                );
                
                lineSegments ~= segment;
            }
            
            result ~= lineSegments;
        }
        
        return result;
    }
}

/**
 * HighlightedSegment - Represents a segment of text with highlighting
 */
struct HighlightedSegment {
    dstring text;              // The full line text
    int startPos;              // Start position within text
    int length;                // Length of segment
    string tokenType;          // Token type identifier
    uint foregroundColor;      // Text color
    uint backgroundColor;      // Background color (0 for transparent)
    bool bold;                 // Bold text
    bool italic;               // Italic text
    bool underline;            // Underlined text
    
    /// Get the segment text
    dstring segmentText() {
        if (startPos >= text.length)
            return "";
        
        int endPos = startPos + length;
        if (endPos > text.length)
            endPos = cast(int)text.length;
            
        return text[startPos..endPos];
    }
}