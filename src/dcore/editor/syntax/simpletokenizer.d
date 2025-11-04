module dcore.editor.syntax.simpletokenizer;

import std.string;
import std.array;
import std.algorithm;
import std.conv;
import std.uni;
import std.ascii;

/**
 * TokenType - The type of syntax token
 */
enum TokenType {
    Unknown,
    Whitespace,
    Keyword,
    Identifier,
    String,
    Number,
    Comment,
    Operator,
    Punctuation
}

/**
 * Token - Represents a syntax token
 */
struct Token {
    int position;     // Character position in line
    int length;       // Token length in characters
    TokenType type;   // Token type
    int lineIndex;    // Line index in document
    string text;      // Token text
    
    // Constructor
    this(int position, int length, TokenType type, int lineIndex, string text) {
        this.position = position;
        this.length = length;
        this.type = type;
        this.lineIndex = lineIndex;
        this.text = text;
    }
}

/**
 * SimpleTokenizer - Basic tokenizer implementation without complex regex
 */
class SimpleTokenizer {
    // Language-specific settings
    protected string[] keywords;
    protected string[] operators;
    
    /**
     * Constructor
     */
    this() {
        // Default constructor
        initializeDefaults();
    }
    
    /**
     * Initialize default settings
     */
    protected void initializeDefaults() {
        // Common keywords across languages
        keywords = [
            "if", "else", "while", "for", "switch", "case", "break", 
            "continue", "return", "function", "class", "import", "export",
            "var", "let", "const", "public", "private", "protected"
        ];
        
        // Common operators
        operators = [
            "+", "-", "*", "/", "%", "=", "==", "!=", "<", ">", "<=", ">=",
            "&&", "||", "!", "&", "|", "^", "~", "++", "--", "+=", "-=", "*=",
            "/=", "%=", "&=", "|=", "^=", "<<", ">>", ">>>", "..", "...", "?",
            ":", "=>", "?."
        ];
    }
    
    /**
     * Get name of tokenizer
     */
    string getName() {
        return "Simple";
    }
    
    /**
     * Get tokenizer description
     */
    string getDescription() {
        return "Simple character-based tokenizer";
    }
    
    /**
     * Get supported file extensions
     */
    string[] getFileExtensions() {
        return [];
    }
    
    /**
     * Get supported languages
     */
    string[] getLanguages() {
        return [];
    }
    
    /**
     * Tokenize text into syntax tokens
     */
    Token[][] tokenize(dstring[] lines) {
        Token[][] result;
        
        // Tokenize each line
        for (int i = 0; i < lines.length; i++) {
            result ~= tokenizeLine(lines[i], i);
        }
        
        return result;
    }
    
    /**
     * Tokenize a single line
     */
    Token[] tokenizeLine(dstring dtext, int lineIndex) {
        Token[] tokens;
        string text = to!string(dtext);
        
        int pos = 0;
        while (pos < text.length) {
            // Skip whitespace (handle separately if needed for display)
            if (std.uni.isWhite(text[pos])) {
                int start = pos;
                while (pos < text.length && std.uni.isWhite(text[pos])) {
                    pos++;
                }
                tokens ~= Token(start, pos - start, TokenType.Whitespace, lineIndex, text[start..pos]);
                continue;
            }
            
            // Check for comments
            if (pos + 1 < text.length) {
                // Line comment
                if (text[pos] == '/' && text[pos + 1] == '/') {
                    int start = pos;
                    pos = cast(int)text.length; // Go to end of line
                    tokens ~= Token(start, pos - start, TokenType.Comment, lineIndex, text[start..pos]);
                    continue;
                }
                
                // Block comment
                if (text[pos] == '/' && text[pos + 1] == '*') {
                    int start = pos;
                    pos += 2;
                    
                    // Search for end of comment
                    bool foundEnd = false;
                    while (pos + 1 < text.length) {
                        if (text[pos] == '*' && text[pos + 1] == '/') {
                            pos += 2;
                            foundEnd = true;
                            break;
                        }
                        pos++;
                    }
                    
                    // If end not found, consume to end of line
                    if (!foundEnd) {
                        pos = cast(int)text.length;
                    }
                    
                    tokens ~= Token(start, pos - start, TokenType.Comment, lineIndex, text[start..pos]);
                    continue;
                }
            }
            
            // Check for strings
            if (text[pos] == '"' || text[pos] == '\'') {
                char quoteChar = text[pos];
                int start = pos;
                pos++; // Skip opening quote
                
                // Find closing quote
                bool escaped = false;
                while (pos < text.length) {
                    // Handle escape sequences
                    if (text[pos] == '\\') {
                        escaped = !escaped;
                        pos++;
                        continue;
                    }
                    
                    // Check for closing quote (not escaped)
                    if (text[pos] == quoteChar && !escaped) {
                        pos++; // Include closing quote
                        break;
                    }
                    
                    escaped = false;
                    pos++;
                }
                
                tokens ~= Token(start, pos - start, TokenType.String, lineIndex, text[start..pos]);
                continue;
            }
            
            // Check for numbers
            if (isDigit(text[pos]) || (text[pos] == '.' && pos + 1 < text.length && isDigit(text[pos + 1]))) {
                int start = pos;
                bool hasDecimal = (text[pos] == '.');
                
                // Check for hex number
                bool isHex = false;
                if (text[pos] == '0' && pos + 1 < text.length && (text[pos + 1] == 'x' || text[pos + 1] == 'X')) {
                    isHex = true;
                    pos += 2;
                    
                    // Parse hex digits
                    while (pos < text.length && (isHexDigit(text[pos]))) {
                        pos++;
                    }
                } else {
                    // Parse decimal digits
                    while (pos < text.length && (isDigit(text[pos]) || text[pos] == '.')) {
                        if (text[pos] == '.') {
                            if (hasDecimal) break; // Second decimal point - not part of this number
                            hasDecimal = true;
                        }
                        pos++;
                    }
                    
                    // Check for exponent (1e3, 1e-3, etc.)
                    if (pos < text.length && (text[pos] == 'e' || text[pos] == 'E')) {
                        pos++;
                        
                        // Optional + or -
                        if (pos < text.length && (text[pos] == '+' || text[pos] == '-')) {
                            pos++;
                        }
                        
                        // Parse exponent digits
                        while (pos < text.length && isDigit(text[pos])) {
                            pos++;
                        }
                    }
                }
                
                tokens ~= Token(start, pos - start, TokenType.Number, lineIndex, text[start..pos]);
                continue;
            }
            
            // Check for identifiers and keywords
            if (std.uni.isAlpha(text[pos]) || text[pos] == '_') {
                int start = pos;
                
                // Parse identifier
                while (pos < text.length && (std.uni.isAlphaNum(text[pos]) || text[pos] == '_')) {
                    pos++;
                }
                
                string word = text[start..pos];
                
                // Check if it's a keyword
                if (keywords.canFind(word)) {
                    tokens ~= Token(start, pos - start, TokenType.Keyword, lineIndex, word);
                } else {
                    tokens ~= Token(start, pos - start, TokenType.Identifier, lineIndex, word);
                }
                
                continue;
            }
            
            // Check for operators
            bool foundOperator = false;
            foreach (op; operators) {
                if (pos + op.length <= text.length && text[pos..pos+op.length] == op) {
                    tokens ~= Token(pos, cast(int)op.length, TokenType.Operator, lineIndex, op);
                    pos += op.length;
                    foundOperator = true;
                    break;
                }
            }
            
            if (foundOperator) {
                continue;
            }
            
            // Everything else is punctuation or unknown
            TokenType type = isPunctuation(text[pos]) ? TokenType.Punctuation : TokenType.Unknown;
            tokens ~= Token(pos, 1, type, lineIndex, text[pos..pos+1]);
            pos++;
        }
        
        return tokens;
    }
    
    /**
     * Check if character is punctuation
     */
    protected bool isPunctuation(char c) {
        return c == '.' || c == ',' || c == ';' || c == ':' || 
               c == '(' || c == ')' || c == '[' || c == ']' || 
               c == '{' || c == '}';
    }
    
    /**
     * Check if character is hex digit
     */
    protected bool isHexDigit(char c) {
        return isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }
}

/**
 * JavaScriptTokenizer - Tokenizer for JavaScript syntax
 */
class JavaScriptTokenizer : SimpleTokenizer {
    /**
     * Constructor
     */
    this() {
        super();
        
        // JavaScript keywords
        keywords = [
            "await", "break", "case", "catch", "class", "const", "continue", "debugger",
            "default", "delete", "do", "else", "export", "extends", "false", "finally",
            "for", "function", "if", "import", "in", "instanceof", "new", "null",
            "return", "super", "switch", "this", "throw", "true", "try", "typeof",
            "var", "void", "while", "with", "yield", "let", "static", "async", "of"
        ];
        
        // JavaScript operators
        operators = [
            "+", "-", "*", "/", "%", "=", "==", "===", "!=", "!==", 
            "<", ">", "<=", ">=", "&&", "||", "!", "&", "|", "^", 
            "~", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", 
            "^=", "<<", ">>", ">>>", "<<=", ">>=", ">>>=", "=>", "?", ":"
        ];
    }
    
    /**
     * Get name of tokenizer
     */
    override string getName() {
        return "JavaScript";
    }
    
    /**
     * Get tokenizer description
     */
    override string getDescription() {
        return "JavaScript syntax tokenizer";
    }
    
    /**
     * Get supported file extensions
     */
    override string[] getFileExtensions() {
        return ["js", "jsx", "mjs"];
    }
    
    /**
     * Get supported languages
     */
    override string[] getLanguages() {
        return ["javascript", "js"];
    }
}

/**
 * CSSTokenizer - Tokenizer for CSS syntax
 */
class CSSTokenizer : SimpleTokenizer {
    /**
     * Constructor
     */
    this() {
        super();
        
        // CSS keywords
        keywords = [
            "import", "charset", "namespace", "media", "keyframes", "from", "to",
            "important", "not", "only", "and", "or", "rgb", "rgba", "url",
            "calc", "var", "attr", "animation", "transition"
        ];
        
        // CSS operators and punctuation
        operators = [
            "+", ">", "~", ":", "::", ",", ";", "{", "}", "(", ")", "[", "]", "="
        ];
    }
    
    /**
     * Get name of tokenizer
     */
    override string getName() {
        return "CSS";
    }
    
    /**
     * Get tokenizer description
     */
    override string getDescription() {
        return "CSS syntax tokenizer";
    }
    
    /**
     * Get supported file extensions
     */
    override string[] getFileExtensions() {
        return ["css", "scss", "less"];
    }
    
    /**
     * Get supported languages
     */
    override string[] getLanguages() {
        return ["css", "scss", "less"];
    }
}

/**
 * HTMLTokenizer - Tokenizer for HTML syntax
 */
class HTMLTokenizer : SimpleTokenizer {
    /**
     * Constructor
     */
    this() {
        super();
        
        // HTML keywords (common tags and attributes)
        keywords = [
            "html", "head", "body", "div", "span", "a", "img", "script", "style",
            "link", "meta", "title", "p", "h1", "h2", "h3", "h4", "h5", "h6",
            "ul", "ol", "li", "table", "tr", "td", "th", "form", "input", "button",
            "class", "id", "href", "src", "alt", "width", "height", "type"
        ];
        
        // HTML operators (tag brackets, etc.)
        operators = [
            "<", ">", "=", "/", "!", "&"
        ];
    }
    
    /**
     * Get name of tokenizer
     */
    override string getName() {
        return "HTML";
    }
    
    /**
     * Get tokenizer description
     */
    override string getDescription() {
        return "HTML syntax tokenizer";
    }
    
    /**
     * Get supported file extensions
     */
    override string[] getFileExtensions() {
        return ["html", "htm", "xhtml", "xml"];
    }
    
    /**
     * Get supported languages
     */
    override string[] getLanguages() {
        return ["html", "xml"];
    }
    
    /**
     * Tokenize a single line - override to handle HTML specifics
     */
    override Token[] tokenizeLine(dstring dtext, int lineIndex) {
        Token[] tokens;
        string text = to!string(dtext);
        
        int pos = 0;
        while (pos < text.length) {
            // Skip whitespace
            if (std.uni.isWhite(text[pos])) {
                int start = pos;
                while (pos < text.length && std.uni.isWhite(text[pos])) {
                    pos++;
                }
                tokens ~= Token(start, pos - start, TokenType.Whitespace, lineIndex, text[start..pos]);
                continue;
            }
            
            // HTML Comment
            if (pos + 3 < text.length && text[pos..pos+4] == "<!--") {
                int start = pos;
                pos += 4;
                
                // Search for end of comment
                while (pos + 2 < text.length) {
                    if (text[pos..pos+3] == "-->") {
                        pos += 3;
                        break;
                    }
                    pos++;
                }
                
                tokens ~= Token(start, pos - start, TokenType.Comment, lineIndex, text[start..pos]);
                continue;
            }
            
            // HTML Tag (opening or closing)
            if (text[pos] == '<') {
                int start = pos;
                pos++;
                
                // Check for closing tag
                bool isClosing = (pos < text.length && text[pos] == '/');
                if (isClosing) pos++;
                
                // Parse tag name
                while (pos < text.length && (std.uni.isAlphaNum(text[pos]) || text[pos] == '-' || text[pos] == '_')) {
                    pos++;
                }
                
                // Skip attributes until '>'
                while (pos < text.length && text[pos] != '>') {
                    // Handle quoted attribute values
                    if (text[pos] == '"' || text[pos] == '\'') {
                        char quote = text[pos];
                        pos++;
                        while (pos < text.length && text[pos] != quote) {
                            pos++;
                        }
                        if (pos < text.length) pos++; // Skip closing quote
                    } else {
                        pos++;
                    }
                }
                
                // Include the closing '>'
                if (pos < text.length && text[pos] == '>') {
                    pos++;
                }
                
                tokens ~= Token(start, pos - start, TokenType.Keyword, lineIndex, text[start..pos]);
                continue;
            }
            
            // String (attribute values)
            if (text[pos] == '"' || text[pos] == '\'') {
                char quote = text[pos];
                int start = pos;
                pos++;
                
                while (pos < text.length && text[pos] != quote) {
                    pos++;
                }
                
                if (pos < text.length) pos++; // Include closing quote
                
                tokens ~= Token(start, pos - start, TokenType.String, lineIndex, text[start..pos]);
                continue;
            }
            
            // Entity references (&nbsp;, etc.)
            if (text[pos] == '&') {
                int start = pos;
                pos++;
                
                // Parse entity name
                while (pos < text.length && std.uni.isAlphaNum(text[pos])) {
                    pos++;
                }
                
                // Include semicolon
                if (pos < text.length && text[pos] == ';') {
                    pos++;
                }
                
                tokens ~= Token(start, pos - start, TokenType.Identifier, lineIndex, text[start..pos]);
                continue;
            }
            
            // Plain text
            int start = pos;
            while (pos < text.length && text[pos] != '<' && text[pos] != '&') {
                pos++;
            }
            
            if (pos > start) {
                tokens ~= Token(start, pos - start, TokenType.Unknown, lineIndex, text[start..pos]);
            } else {
                pos++;
            }
        }
        
        return tokens;
    }
}

/**
 * TokenizerFactory - Factory for creating tokenizers
 */
class TokenizerFactory {
    private static SimpleTokenizer[] _tokenizers;
    
    // Initialize tokenizers
    static this() {
        // Register built-in tokenizers
        registerTokenizer(new JavaScriptTokenizer());
        registerTokenizer(new CSSTokenizer());
        registerTokenizer(new HTMLTokenizer());
    }
    
    // Register a tokenizer
    static void registerTokenizer(SimpleTokenizer tokenizer) {
        _tokenizers ~= tokenizer;
    }
    
    // Get tokenizer by file extension
    static SimpleTokenizer getTokenizerForFile(string filename) {
        foreach (tokenizer; _tokenizers) {
            if (tokenizer.getFileExtensions().canFind!(ext => filename.endsWith("." ~ ext))()) {
                return tokenizer;
            }
        }
        
        // Return default tokenizer if no specific one found
        return new SimpleTokenizer();
    }
    
    // Get tokenizer by language name
    static SimpleTokenizer getTokenizerForLanguage(string language) {
        foreach (tokenizer; _tokenizers) {
            if (tokenizer.getLanguages().canFind(language.toLower())) {
                return tokenizer;
            }
        }
        
        // Return default tokenizer if no specific one found
        return new SimpleTokenizer();
    }
    
    // Get all registered tokenizers
    static SimpleTokenizer[] getAllTokenizers() {
        return _tokenizers.dup;
    }
}