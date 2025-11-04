module dcore.editor.syntax.pythontokenizer;

import dlangui.core.logger;
import std.string;
import std.regex;
import std.array;
import std.algorithm;
import std.conv;
import std.uni;

import dcore.editor.syntax.tokenizer;

/**
 * PythonTokenizer - Tokenizer for Python language
 */
class PythonTokenizer : Tokenizer {
    // Regular expressions for token matching
    private static Regex!char rxKeyword;
    private static Regex!char rxBuiltin;
    private static Regex!char rxString;
    private static Regex!char rxTripleString;
    private static Regex!char rxNumber;
    private static Regex!char rxComment;
    private static Regex!char rxDecorator;
    private static Regex!char rxIdentifier;
    private static Regex!char rxOperator;
    
    // Python keywords
    private static string[] keywords = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", 
        "def", "del", "elif", "else", "except", "finally", "for", "from", 
        "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", 
        "or", "pass", "raise", "return", "try", "while", "with", "yield", "False", 
        "None", "True"
    ];
    
    // Python built-in functions and types
    private static string[] builtins = [
        "abs", "all", "any", "bool", "bytearray", "bytes", "callable", "chr", 
        "classmethod", "compile", "complex", "delattr", "dict", "dir", "divmod", 
        "enumerate", "eval", "exec", "filter", "float", "format", "frozenset", 
        "getattr", "globals", "hasattr", "hash", "help", "hex", "id", "input", 
        "int", "isinstance", "issubclass", "iter", "len", "list", "locals", 
        "map", "max", "memoryview", "min", "next", "object", "oct", "open", 
        "ord", "pow", "print", "property", "range", "repr", "reversed", "round", 
        "set", "setattr", "slice", "sorted", "staticmethod", "str", "sum", "super", 
        "tuple", "type", "vars", "zip", "__import__"
    ];
    
    // State for tracking multiline strings
    private bool inTripleDoubleQuote = false;
    private bool inTripleSingleQuote = false;
    
    // Static constructor to initialize regexes
    static this() {
        // Create keyword pattern from keywords list
        string keywordPattern = `\b(` ~ join(keywords, "|") ~ `)\b`;
        rxKeyword = regex(keywordPattern);
        
        // Create builtin pattern from builtins list
        string builtinPattern = `\b(` ~ join(builtins, "|") ~ `)\b`;
        rxBuiltin = regex(builtinPattern);
        
        // String patterns (single line strings)
        rxString = regex(`"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'`);
        
        // Triple quoted strings (can span multiple lines)
        rxTripleString = regex(`"""(?:[^\\]|\\.|"(?!""))*"""|'''(?:[^\\]|\\.|'(?!''))*'''`);
        
        // Number pattern
        rxNumber = regex(`\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?j?\b|0[xXoObB][0-9a-fA-F]+\b`);
        
        // Comment pattern (single line only)
        rxComment = regex(`#.*$`);
        
        // Decorator pattern
        rxDecorator = regex(`@[a-zA-Z_][a-zA-Z0-9_\.]*`);
        
        // Identifier pattern
        rxIdentifier = regex(`\b[a-zA-Z_][a-zA-Z0-9_]*\b`);
        
        // Operator pattern
        rxOperator = regex(`[+\-*/%=&|^~<>!@:;,.\[\]{}()]`);
    }
    
    /// Tokenize a single line
    override Token[] tokenizeLine(dstring text, int lineIndex) {
        Token[] tokens;
        string strText = text.to!string();
        
        // Find all tokens in the line
        int pos = 0;
        while (pos < strText.length) {
            // Skip whitespace (but track indentation at start of line)
            if (std.uni.isWhite(strText[pos])) {
                if (pos == 0) {
                    // Count indentation at start of line
                    int indentPos = pos;
                    while (indentPos < strText.length && std.uni.isWhite(strText[indentPos])) {
                        indentPos++;
                    }
                    if (indentPos > pos) {
                        tokens ~= Token(pos, indentPos - pos, "whitespace", lineIndex, strText[pos..indentPos]);
                        pos = indentPos;
                        continue;
                    }
                }
                pos++;
                continue;
            }
            
            bool foundMatch = false;
            
            // Try to match a comment
            auto commentMatch = matchFirst(strText[pos..$], rxComment);
            if (!commentMatch.empty) {
                tokens ~= Token(pos, cast(int)commentMatch.hit.length, "comment", lineIndex, commentMatch.hit);
                pos += cast(int)commentMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // Try to match a triple quoted string
            auto tripleStringMatch = matchFirst(strText[pos..$], rxTripleString);
            if (!tripleStringMatch.empty) {
                tokens ~= Token(pos, cast(int)tripleStringMatch.hit.length, "string", lineIndex, tripleStringMatch.hit);
                pos += cast(int)tripleStringMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // Try to match a string
            auto stringMatch = matchFirst(strText[pos..$], rxString);
            if (!stringMatch.empty) {
                tokens ~= Token(pos, cast(int)stringMatch.hit.length, "string", lineIndex, stringMatch.hit);
                pos += cast(int)stringMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // Try to match a decorator
            auto decoratorMatch = matchFirst(strText[pos..$], rxDecorator);
            if (!decoratorMatch.empty) {
                tokens ~= Token(pos, cast(int)decoratorMatch.hit.length, "preprocessor", lineIndex, decoratorMatch.hit);
                pos += cast(int)decoratorMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // Try to match a number
            auto numberMatch = matchFirst(strText[pos..$], rxNumber);
            if (!numberMatch.empty) {
                tokens ~= Token(pos, cast(int)numberMatch.hit.length, "number", lineIndex, numberMatch.hit);
                pos += cast(int)numberMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // Try to match a keyword
            auto keywordMatch = matchFirst(strText[pos..$], rxKeyword);
            if (!keywordMatch.empty) {
                tokens ~= Token(pos, cast(int)keywordMatch.hit.length, "keyword", lineIndex, keywordMatch.hit);
                pos += cast(int)keywordMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // Try to match a builtin
            auto builtinMatch = matchFirst(strText[pos..$], rxBuiltin);
            if (!builtinMatch.empty) {
                tokens ~= Token(pos, cast(int)builtinMatch.hit.length, "function", lineIndex, builtinMatch.hit);
                pos += cast(int)builtinMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // Try to match an identifier
            auto identifierMatch = matchFirst(strText[pos..$], rxIdentifier);
            if (!identifierMatch.empty) {
                tokens ~= Token(pos, cast(int)identifierMatch.hit.length, "identifier", lineIndex, identifierMatch.hit);
                pos += cast(int)identifierMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // Try to match an operator
            auto operatorMatch = matchFirst(strText[pos..$], rxOperator);
            if (!operatorMatch.empty) {
                tokens ~= Token(pos, cast(int)operatorMatch.hit.length, "operator", lineIndex, operatorMatch.hit);
                pos += cast(int)operatorMatch.hit.length;
                foundMatch = true;
                continue;
            }
            
            // If no match found, treat as plain text
            if (!foundMatch) {
                tokens ~= Token(pos, 1, "text", lineIndex, [strText[pos]].idup);
                pos++;
            }
        }
        
        return tokens;
    }
    
    /// Process multiline tokens (like triple quoted strings)
    override void processMultiLineTokens(Token[][] tokens, dstring[] lines) {
        bool inDocString = false;
        int docStringStartLine = -1;
        int docStringStartPos = -1;
        string docStringDelimiter = "";
        
        for (int i = 0; i < tokens.length; i++) {
            // If in docstring, check for end
            if (inDocString) {
                bool foundEnd = false;
                string lineStr = lines[i].to!string();
                
                // Look for ending delimiter
                if (docStringDelimiter == "\"\"\"") {
                    long pos = lineStr.indexOf("\"\"\"");
                    if (pos >= 0) {
                        foundEnd = true;
                    }
                } else if (docStringDelimiter == "'''") {
                    long pos = lineStr.indexOf("'''");
                    if (pos >= 0) {
                        foundEnd = true;
                    }
                }
                
                if (foundEnd) {
                    inDocString = false;
                } else {
                    // Mark entire line as string
                    tokens[i] = [Token(0, cast(int)lines[i].length, "string", i, lines[i].to!string())];
                }
                continue;
            }
            
            // Check for docstring start
            for (int j = 0; j < tokens[i].length; j++) {
                Token token = tokens[i][j];
                if (token.type == "string") {
                    string value = token.text;
                    if (value.startsWith("\"\"\"") && !value.endsWith("\"\"\"")) {
                        inDocString = true;
                        docStringStartLine = i;
                        docStringStartPos = token.position;
                        docStringDelimiter = "\"\"\"";
                        break;
                    } else if (value.startsWith("'''") && !value.endsWith("'''")) {
                        inDocString = true;
                        docStringStartLine = i;
                        docStringStartPos = token.position;
                        docStringDelimiter = "'''";
                        break;
                    }
                }
            }
        }
    }
}