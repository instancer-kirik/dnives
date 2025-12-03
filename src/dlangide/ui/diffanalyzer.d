module dlangide.ui.diffanalyzer;

import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.range;
import std.stdio;
import std.regex;
import std.typecons;
import std.math;
import std.utf;

/// Represents a single line difference
struct LineDiff {
    enum Type {
        Equal,      // Lines are identical
        Insert,     // Line exists only in new text
        Delete,     // Line exists only in original text
        Change      // Line content has changed
    }

    Type type;
    int originalLine;    // Line number in original text (-1 if not applicable)
    int suggestedLine;   // Line number in suggested text (-1 if not applicable)
    string originalText; // Original line content
    string suggestedText; // Suggested line content
    double similarity;   // Similarity score for changed lines (0.0 - 1.0)
}

/// Represents a block of related changes
struct DiffHunk {
    int originalStart;
    int originalLength;
    int suggestedStart;
    int suggestedLength;
    LineDiff[] diffs;
    string context;      // Surrounding context for better understanding
    double confidence;   // Confidence in the diff quality
}

/// Configuration for diff analysis
struct DiffConfig {
    int contextLines = 3;           // Number of context lines to include
    double similarityThreshold = 0.7; // Threshold for considering lines similar
    bool ignoreWhitespace = true;    // Ignore whitespace differences
    bool ignoreCase = false;         // Ignore case differences
    string[] ignorePatterns = [];    // Regex patterns to ignore
    bool detectMoves = true;         // Detect moved code blocks
    int minMoveSize = 3;            // Minimum lines for move detection
}

/// Advanced diff analyzer with semantic understanding
class DiffAnalyzer {
    private DiffConfig _config;
    private string[][string] _cache;  // Cache for expensive operations

    this(DiffConfig config = DiffConfig()) {
        _config = config;
    }

    /// Perform comprehensive diff analysis
    DiffHunk[] analyzeDiff(string originalText, string suggestedText) {
        auto originalLines = preprocessLines(originalText.splitLines());
        auto suggestedLines = preprocessLines(suggestedText.splitLines());

        // Use Myers diff algorithm as base
        auto rawDiffs = myersDiff(originalLines, suggestedLines);

        // Post-process to create semantic hunks
        auto hunks = createHunks(rawDiffs, originalLines, suggestedLines);

        // Apply move detection if enabled
        if (_config.detectMoves) {
            hunks = detectMoves(hunks, originalLines, suggestedLines);
        }

        // Calculate confidence scores
        foreach (ref hunk; hunks) {
            hunk.confidence = calculateConfidence(hunk);
        }

        return hunks;
    }

    /// Calculate similarity between two strings
    double calculateSimilarity(string str1, string str2) {
        if (str1 == str2) return 1.0;
        if (str1.empty || str2.empty) return 0.0;

        // Use Levenshtein distance for basic similarity
        auto distance = levenshteinDistance(str1, str2);
        auto maxLen = max(str1.length, str2.length);

        return 1.0 - (cast(double)distance / maxLen);
    }

    /// Detect if two code blocks are semantically similar
    bool areSemanticallyEquivalent(string block1, string block2) {
        // Remove comments and normalize whitespace
        auto normalized1 = normalizeCode(block1);
        auto normalized2 = normalizeCode(block2);

        if (normalized1 == normalized2) return true;

        // Check structural similarity for code
        auto similarity = calculateStructuralSimilarity(block1, block2);
        return similarity > 0.9;
    }

    /// Extract meaningful code segments for comparison
    string[] extractCodeSegments(string text) {
        string[] segments;
        auto lines = text.splitLines();

        string[] currentSegment;
        int braceDepth = 0;
        bool inFunction = false;

        foreach (line; lines) {
            auto trimmed = line.strip();

            // Track brace depth
            foreach (ch; trimmed) {
                if (ch == '{') braceDepth++;
                else if (ch == '}') braceDepth--;
            }

            // Detect function/method starts
            if (isFunctionDeclaration(trimmed)) {
                if (currentSegment.length > 0) {
                    segments ~= currentSegment.join("\n");
                    currentSegment.length = 0;
                }
                inFunction = true;
            }

            currentSegment ~= line;

            // End of function/block
            if (inFunction && braceDepth == 0 && trimmed.endsWith("}")) {
                segments ~= currentSegment.join("\n");
                currentSegment.length = 0;
                inFunction = false;
            }
        }

        // Add remaining content
        if (currentSegment.length > 0) {
            segments ~= currentSegment.join("\n");
        }

        return segments;
    }

    /// Create a three-way merge of texts
    string performThreeWayMerge(string baseText, string originalText, string suggestedText) {
        // This is a simplified three-way merge
        // In practice, you'd want more sophisticated conflict resolution

        auto baseLines = baseText.splitLines();
        auto originalLines = originalText.splitLines();
        auto suggestedLines = suggestedText.splitLines();

        string[] result;

        // For now, use a simple strategy: take suggested changes that don't conflict
        auto baseDiffs = myersDiff(baseLines, originalLines);
        auto suggestedDiffs = myersDiff(baseLines, suggestedLines);

        // Merge non-conflicting changes
        // This would need much more sophisticated logic for real use
        result = suggestedLines; // Simplified

        return result.join("\n");
    }

    private string[] preprocessLines(string[] lines) {
        string[] processed;

        foreach (line; lines) {
            string processedLine = line;

            if (_config.ignoreWhitespace) {
                processedLine = processedLine.strip();
            }

            if (_config.ignoreCase) {
                processedLine = processedLine.toLower();
            }

            // Apply ignore patterns
            foreach (pattern; _config.ignorePatterns) {
                auto regex = ctRegex!(pattern);
                processedLine = processedLine.replaceAll(regex, "");
            }

            processed ~= processedLine;
        }

        return processed;
    }

    private LineDiff[] myersDiff(string[] original, string[] suggested) {
        // Simplified Myers diff algorithm
        // For production use, you'd want a full implementation

        LineDiff[] diffs;

        int origIndex = 0;
        int suggIndex = 0;

        while (origIndex < original.length || suggIndex < suggested.length) {
            if (origIndex >= original.length) {
                // Remaining lines are insertions
                diffs ~= LineDiff(LineDiff.Type.Insert, -1, suggIndex,
                                "", suggested[suggIndex], 0.0);
                suggIndex++;
            } else if (suggIndex >= suggested.length) {
                // Remaining lines are deletions
                diffs ~= LineDiff(LineDiff.Type.Delete, origIndex, -1,
                                original[origIndex], "", 0.0);
                origIndex++;
            } else if (original[origIndex] == suggested[suggIndex]) {
                // Lines are equal
                diffs ~= LineDiff(LineDiff.Type.Equal, origIndex, suggIndex,
                                original[origIndex], suggested[suggIndex], 1.0);
                origIndex++;
                suggIndex++;
            } else {
                // Lines are different - check for similarity
                auto similarity = calculateSimilarity(original[origIndex], suggested[suggIndex]);

                if (similarity > _config.similarityThreshold) {
                    diffs ~= LineDiff(LineDiff.Type.Change, origIndex, suggIndex,
                                    original[origIndex], suggested[suggIndex], similarity);
                    origIndex++;
                    suggIndex++;
                } else {
                    // Try to find better match
                    auto bestMatch = findBestMatch(original[origIndex], suggested[suggIndex..$], suggIndex);

                    if (bestMatch.found && bestMatch.similarity > _config.similarityThreshold) {
                        // Insert lines before the match
                        foreach (i; suggIndex..bestMatch.index) {
                            diffs ~= LineDiff(LineDiff.Type.Insert, -1, cast(int)i,
                                            "", suggested[i], 0.0);
                        }
                        diffs ~= LineDiff(LineDiff.Type.Change, origIndex, bestMatch.index,
                                        original[origIndex], suggested[bestMatch.index], bestMatch.similarity);
                        origIndex++;
                        suggIndex = bestMatch.index + 1;
                    } else {
                        // No good match found, treat as delete + insert
                        diffs ~= LineDiff(LineDiff.Type.Delete, origIndex, -1,
                                        original[origIndex], "", 0.0);
                        diffs ~= LineDiff(LineDiff.Type.Insert, -1, suggIndex,
                                        "", suggested[suggIndex], 0.0);
                        origIndex++;
                        suggIndex++;
                    }
                }
            }
        }

        return diffs;
    }

    private struct MatchResult {
        bool found;
        int index;
        double similarity;
    }

    private MatchResult findBestMatch(string target, string[] candidates, int baseIndex) {
        MatchResult best;

        foreach (i, candidate; candidates) {
            auto similarity = calculateSimilarity(target, candidate);
            if (similarity > best.similarity) {
                best.found = true;
                best.index = baseIndex + cast(int)i;
                best.similarity = similarity;
            }
        }

        return best;
    }

    private DiffHunk[] createHunks(LineDiff[] diffs, string[] originalLines, string[] suggestedLines) {
        DiffHunk[] hunks;
        DiffHunk currentHunk;

        foreach (i, diff; diffs) {
            if (diff.type == LineDiff.Type.Equal) {
                if (currentHunk.diffs.length > 0) {
                    // End current hunk
                    currentHunk.context = extractContext(currentHunk, originalLines, suggestedLines);
                    hunks ~= currentHunk;
                    currentHunk = DiffHunk.init;
                }
            } else {
                if (currentHunk.diffs.length == 0) {
                    // Start new hunk
                    currentHunk.originalStart = max(0, diff.originalLine - _config.contextLines);
                    currentHunk.suggestedStart = max(0, diff.suggestedLine - _config.contextLines);
                }
                currentHunk.diffs ~= diff;
            }
        }

        // Add final hunk if exists
        if (currentHunk.diffs.length > 0) {
            currentHunk.context = extractContext(currentHunk, originalLines, suggestedLines);
            hunks ~= currentHunk;
        }

        return hunks;
    }

    private string extractContext(DiffHunk hunk, string[] originalLines, string[] suggestedLines) {
        string[] contextLines;

        // Add context before
        int contextStart = max(0, hunk.originalStart - _config.contextLines);
        foreach (i; contextStart..hunk.originalStart) {
            if (i < originalLines.length) {
                contextLines ~= originalLines[i];
            }
        }

        return contextLines.join("\n");
    }

    private DiffHunk[] detectMoves(DiffHunk[] hunks, string[] originalLines, string[] suggestedLines) {
        // Simplified move detection
        // Look for deleted blocks that appear as insertions elsewhere

        foreach (ref hunk; hunks) {
            // This would contain sophisticated move detection logic
            // For now, just mark potential moves based on content similarity
        }

        return hunks;
    }

    private double calculateConfidence(DiffHunk hunk) {
        if (hunk.diffs.empty) return 1.0;

        double totalSimilarity = 0.0;
        int count = 0;

        foreach (diff; hunk.diffs) {
            if (diff.type == LineDiff.Type.Change) {
                totalSimilarity += diff.similarity;
                count++;
            }
        }

        return count > 0 ? totalSimilarity / count : 0.8;
    }

    private string normalizeCode(string code) {
        // Remove comments and normalize whitespace
        auto result = code.replaceAll(ctRegex!(`//.*$`, "gm"), "");
        result = result.replaceAll(ctRegex!(`/\*.*?\*/`, "gs"), "");
        result = result.replaceAll(ctRegex!(`\s+`, "g"), " ");
        return result.strip();
    }

    private double calculateStructuralSimilarity(string code1, string code2) {
        // Extract structural elements (brackets, keywords, etc.)
        auto structure1 = extractStructure(code1);
        auto structure2 = extractStructure(code2);

        return calculateSimilarity(structure1, structure2);
    }

    private string extractStructure(string code) {
        // Extract just the structural elements
        string structure = "";

        auto tokens = code.split();
        foreach (token; tokens) {
            if (token.among("{", "}", "(", ")", "[", "]", ";", "=", "def", "class", "if", "else", "for", "while")) {
                structure ~= token ~ " ";
            }
        }

        return structure.strip();
    }

    private bool isFunctionDeclaration(string line) {
        // Simple function detection - would need to be language-specific
        return line.canFind("def ") || line.canFind("function ") ||
               line.canFind("void ") || line.canFind("int ") ||
               (line.canFind("(") && line.canFind(")") && line.canFind("{"));
    }

    private int levenshteinDistance(string s1, string s2) {
        auto len1 = s1.length;
        auto len2 = s2.length;

        if (len1 == 0) return cast(int)len2;
        if (len2 == 0) return cast(int)len1;

        auto matrix = new int[][](len1 + 1, len2 + 1);

        foreach (i; 0..len1 + 1) matrix[i][0] = cast(int)i;
        foreach (j; 0..len2 + 1) matrix[0][j] = cast(int)j;

        foreach (i; 1..len1 + 1) {
            foreach (j; 1..len2 + 1) {
                auto cost = s1[i-1] == s2[j-1] ? 0 : 1;
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                );
            }
        }

        return matrix[len1][len2];
    }
}

/// Utility functions for diff operations
struct DiffUtils {
    /// Create a unified diff format string
    static string createUnifiedDiff(DiffHunk[] hunks, string originalFile = "original",
                                   string suggestedFile = "suggested") {
        string[] result;
        result ~= format("--- %s", originalFile);
        result ~= format("+++ %s", suggestedFile);

        foreach (hunk; hunks) {
            result ~= format("@@ -%d,%d +%d,%d @@",
                           hunk.originalStart, hunk.originalLength,
                           hunk.suggestedStart, hunk.suggestedLength);

            foreach (diff; hunk.diffs) {
                final switch (diff.type) {
                    case LineDiff.Type.Equal:
                        result ~= " " ~ diff.originalText;
                        break;
                    case LineDiff.Type.Delete:
                        result ~= "-" ~ diff.originalText;
                        break;
                    case LineDiff.Type.Insert:
                        result ~= "+" ~ diff.suggestedText;
                        break;
                    case LineDiff.Type.Change:
                        result ~= "-" ~ diff.originalText;
                        result ~= "+" ~ diff.suggestedText;
                        break;
                }
            }
        }

        return result.join("\n");
    }

    /// Apply a set of diffs to create the final text
    static string applyDiffs(string originalText, DiffHunk[] hunks) {
        auto lines = originalText.splitLines();
        string[] result;

        int currentLine = 0;

        foreach (hunk; hunks) {
            // Add unchanged lines before this hunk
            while (currentLine < hunk.originalStart) {
                if (currentLine < lines.length) {
                    result ~= lines[currentLine];
                }
                currentLine++;
            }

            // Apply changes in this hunk
            foreach (diff; hunk.diffs) {
                final switch (diff.type) {
                    case LineDiff.Type.Equal:
                        result ~= diff.originalText;
                        currentLine++;
                        break;
                    case LineDiff.Type.Delete:
                        // Skip this line
                        currentLine++;
                        break;
                    case LineDiff.Type.Insert:
                        result ~= diff.suggestedText;
                        break;
                    case LineDiff.Type.Change:
                        result ~= diff.suggestedText;
                        currentLine++;
                        break;
                }
            }
        }

        // Add remaining unchanged lines
        while (currentLine < lines.length) {
            result ~= lines[currentLine];
            currentLine++;
        }

        return result.join("\n");
    }

    /// Generate statistics about the diff
    static auto generateStats(DiffHunk[] hunks) {
        struct DiffStats {
            int linesAdded;
            int linesDeleted;
            int linesChanged;
            int hunksCount;
            double averageConfidence;
        }

        DiffStats stats;
        stats.hunksCount = cast(int)hunks.length;

        double totalConfidence = 0;

        foreach (hunk; hunks) {
            totalConfidence += hunk.confidence;

            foreach (diff; hunk.diffs) {
                final switch (diff.type) {
                    case LineDiff.Type.Equal:
                        break;
                    case LineDiff.Type.Delete:
                        stats.linesDeleted++;
                        break;
                    case LineDiff.Type.Insert:
                        stats.linesAdded++;
                        break;
                    case LineDiff.Type.Change:
                        stats.linesChanged++;
                        break;
                }
            }
        }

        stats.averageConfidence = hunks.length > 0 ? totalConfidence / hunks.length : 0;

        return stats;
    }
}
