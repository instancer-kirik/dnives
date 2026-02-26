module dcore.search.fuzzysearch;

import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.regex;
import std.path;
import std.typecons;
import std.range;
import std.utf;

/**
 * FuzzyMatch - Represents a fuzzy match result with score and match positions
 */
struct FuzzyMatch {
    string text;              // The text that was matched
    int score;                // Match score (higher is better)
    int[] matchPositions;     // Positions of matched characters
    
    /**
     * Compare matches for sorting (higher score first)
     */
    int opCmp(const FuzzyMatch other) const {
        return other.score - score; // Reverse order (highest score first)
    }
}

/**
 * SearchResult - Holds information about search results
 */
struct SearchResult {
    string type;              // Type of result (file, symbol, text)
    string path;              // Path or location
    string name;              // Name or label
    string details;           // Additional details
    FuzzyMatch match;         // Fuzzy match information
    
    /**
     * Compare search results for sorting (by match score)
     */
    int opCmp(const SearchResult other) const {
        return match.opCmp(other.match);
    }
}

/**
 * Options for fuzzy search
 */
struct FuzzyOptions {
    bool caseSensitive = false;       // Whether search is case-sensitive
    bool smartCase = true;            // Use case sensitivity if query contains uppercase
    bool includePatterns = true;      // Match file patterns (*.ext)
    bool fuzzy = true;                // Use fuzzy matching (vs. substring)
    int maxResults = 100;             // Maximum number of results to return
    
    // Scoring weights
    int consecutiveBonus = 15;        // Bonus for consecutive matches
    int separatorBonus = 30;          // Bonus for matches after separators (_.-/ )
    int camelBonus = 30;              // Bonus for matches on uppercase in camelCase
    int firstLetterBonus = 15;        // Bonus for matching first letter
    int leadingLetterPenalty = -5;    // Penalty for each unmatched letter before first match
    int unmatchedLetterPenalty = -1;  // Penalty for unmatched letters
}

/**
 * FuzzyMatcher - Core fuzzy search implementation
 */
class FuzzyMatcher {
    private FuzzyOptions options;
    
    /**
     * Constructor
     */
    this(FuzzyOptions options = FuzzyOptions()) {
        this.options = options;
    }
    
    /**
     * Match a query against a single text
     */
    FuzzyMatch match(string query, string text) {
        if (query.empty)
            return FuzzyMatch(text, 0, []);
            
        // Handle case sensitivity
        string queryToUse = query;
        string textToUse = text;
        
        bool caseSensitive = options.caseSensitive;
        if (options.smartCase && query.any!(c => c >= 'A' && c <= 'Z'))
            caseSensitive = true;
            
        if (!caseSensitive) {
            queryToUse = query.toLower();
            textToUse = text.toLower();
        }
        
        // Check if it's a pattern match (*.ext)
        if (options.includePatterns && query.indexOf('*') >= 0) {
            return matchPattern(query, text);
        }
        
        // Use fuzzy or substring matching based on options
        if (options.fuzzy)
            return fuzzyMatch(queryToUse, textToUse, text);
        else
            return substringMatch(queryToUse, textToUse, text);
    }
    
    /**
     * Do a fuzzy match with scoring
     */
    private FuzzyMatch fuzzyMatch(string query, string textLower, string originalText) {
        // Check if query is in text at all
        if (!isSubsequence(query, textLower))
            return FuzzyMatch(originalText, int.min, []);
            
        // Get all possible match positions
        int[] matchPositions = findBestMatchPositions(query, textLower);
        if (matchPositions.length == 0)
            return FuzzyMatch(originalText, int.min, []);
            
        // Calculate score
        int score = calculateScore(query, textLower, matchPositions);
        
        return FuzzyMatch(originalText, score, matchPositions);
    }
    
    /**
     * Match using pattern (*.ext)
     */
    private FuzzyMatch matchPattern(string pattern, string text) {
        // Convert glob pattern to regex
        string regexPattern = globToRegex(pattern);
        
        try {
            auto r = regex(regexPattern, "i");
            auto match = text.matchFirst(r);
            
            if (!match.empty) {
                // Use the match positions for highlighting
                int[] positions;
                for (size_t i = match.pre.length; i < match.pre.length + match.hit.length; i++) {
                    positions ~= cast(int)i;
                }
                
                // Higher score for exact matches
                int score = pattern == "*" ? 1 : 100; 
                if (pattern[0] != '*' && match.hit.startsWith(pattern[0..1]))
                    score += 50;
                
                return FuzzyMatch(text, score, positions);
            }
        } catch (Exception e) {
            // In case of regex error, fall back to substring match
        }
        
        return FuzzyMatch(text, int.min, []);
    }
    
    /**
     * Convert glob pattern to regex
     */
    private string globToRegex(string pattern) {
        string result = "^";
        
        foreach (c; pattern) {
            switch (c) {
                case '*':
                    result ~= ".*";
                    break;
                case '?':
                    result ~= ".";
                    break;
                case '.': case '+': case '(': case ')':
                case '[': case ']': case '{': case '}':
                case '^': case '$': case '|': case '\\':
                    result ~= "\\" ~ c;
                    break;
                default:
                    result ~= c;
                    break;
            }
        }
        
        result ~= "$";
        return result;
    }
    
    /**
     * Do a substring match (consecutive characters)
     */
    private FuzzyMatch substringMatch(string query, string textLower, string originalText) {
        auto index = textLower.indexOf(query);
        if (index < 0)
            return FuzzyMatch(originalText, int.min, []);
            
        // Create match positions for consecutive matches
        int[] positions;
        for (int i = 0; i < query.length; i++) {
            positions ~= cast(int)(index + i);
        }
        
        // Calculate score - higher for matches at start and on word boundaries
        int score = 100 - cast(int)index;
        
        // Bonus for matching at start
        if (index == 0)
            score += 50;
            
        // Bonus for matching after separator
        if (index > 0 && isSeparator(textLower[index - 1]))
            score += 25;
            
        return FuzzyMatch(originalText, score, positions);
    }
    
    /**
     * Check if a character is a separator
     */
    private bool isSeparator(dchar c) {
        return c == '_' || c == '-' || c == '.' || c == '/' || c == '\\' || c == ' ';
    }
    
    /**
     * Check if string contains query as a subsequence
     */
    private bool isSubsequence(string query, string text) {
        size_t j = 0;
        
        for (size_t i = 0; i < text.length && j < query.length; i++) {
            if (text[i] == query[j])
                j++;
        }
        
        return j == query.length;
    }
    
    /**
     * Find best match positions for query in text
     */
    private int[] findBestMatchPositions(string query, string text) {
        int[] positions;
        size_t textIndex = 0;
        
        // Find rightmost match for each character in query
        foreach (qchar; query) {
            bool found = false;
            
            // Find the current character
            for (; textIndex < text.length; textIndex++) {
                if (text[textIndex] == qchar) {
                    positions ~= cast(int)textIndex;
                    textIndex++;
                    found = true;
                    break;
                }
            }
            
            if (!found)
                return [];
        }
        
        return positions;
    }
    
    /**
     * Calculate score for a match
     */
    private int calculateScore(string query, string text, int[] positions) {
        int score = 0;
        
        // Base score starts at 100
        score = 100;
        
        // Penalty for unmatched characters
        score += options.unmatchedLetterPenalty * (cast(int)text.length - cast(int)query.length);
        
        // Penalty for leading unmatched characters
        score += options.leadingLetterPenalty * positions[0];
        
        // Bonus for consecutive matches
        for (int i = 1; i < positions.length; i++) {
            if (positions[i] == positions[i-1] + 1)
                score += options.consecutiveBonus;
        }
        
        // Bonus for matches after separators
        for (int i = 0; i < positions.length; i++) {
            int pos = positions[i];
            
            // First letter bonus
            if (pos == 0)
                score += options.firstLetterBonus;
                
            // After separator bonus
            else if (pos > 0 && isSeparator(text[pos - 1]))
                score += options.separatorBonus;
                
            // CamelCase bonus
            else if (pos > 0 && text[pos] >= 'A' && text[pos] <= 'Z')
                score += options.camelBonus;
        }
        
        return score;
    }
    
    /**
     * Search a list of strings
     */
    SearchResult[] search(string query, string[] items, string type = "text") {
        SearchResult[] results;
        
        foreach (item; items) {
            FuzzyMatch match = this.match(query, item);
            
            if (match.score > int.min) {
                results ~= SearchResult(type, item, item, "", match);
            }
        }
        
        // Sort results by score
        sort(results);
        
        // Limit results
        if (results.length > options.maxResults)
            results.length = options.maxResults;
            
        return results;
    }
    
    /**
     * Search files
     */
    SearchResult[] searchFiles(string query, string[] filePaths) {
        SearchResult[] results;
        
        foreach (path; filePaths) {
            string filename = baseName(path);
            
            FuzzyMatch match = this.match(query, filename);
            
            if (match.score > int.min) {
                results ~= SearchResult("file", path, filename, dirName(path), match);
            }
        }
        
        // Sort results by score
        sort(results);
        
        // Limit results
        if (results.length > options.maxResults)
            results.length = options.maxResults;
            
        return results;
    }
    
    /**
     * Search symbols
     */
    SearchResult[] searchSymbols(string query, Tuple!(string, string, string)[] symbols) {
        SearchResult[] results;
        
        foreach (symbol; symbols) {
            string name = symbol[0];
            string type = symbol[1];
            string location = symbol[2];
            
            FuzzyMatch match = this.match(query, name);
            
            if (match.score > int.min) {
                results ~= SearchResult("symbol", location, name, type, match);
            }
        }
        
        // Sort results by score
        sort(results);
        
        // Limit results
        if (results.length > options.maxResults)
            results.length = options.maxResults;
            
        return results;
    }
}

/**
 * Create highlighted text with match positions
 */
struct HighlightedText {
    string text;
    string highlighted;
    
    /**
     * Generate HTML with highlighted matches
     */
    string toHtml() {
        return highlighted;
    }
}

/**
 * Create highlighted text from a match
 */
HighlightedText highlightMatch(FuzzyMatch match, string highlightStart = "<b>", string highlightEnd = "</b>") {
    if (match.matchPositions.length == 0)
        return HighlightedText(match.text, match.text);
        
    auto builder = appender!string();
    int lastPos = 0;
    
    foreach (pos; match.matchPositions) {
        if (pos >= lastPos) {
            // Add text before match
            if (pos > lastPos)
                builder.put(match.text[lastPos..pos]);
                
            // Add highlighted character
            builder.put(highlightStart);
            builder.put(match.text[pos..pos+1]);
            builder.put(highlightEnd);
            
            lastPos = pos + 1;
        }
    }
    
    // Add remaining text
    if (lastPos < match.text.length)
        builder.put(match.text[lastPos..$]);
        
    return HighlightedText(match.text, builder.data);
}