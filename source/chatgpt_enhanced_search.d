/**
 * Enhanced search functionality for ChatGPT conversations
 *
 * Provides categorized search for:
 * - Project ideas and startup concepts
 * - New words and terminology
 * - Jokes and humor
 * - Lyrics and creative content
 * - Technical discussions
 * - Code examples
 */
module chatgpt_enhanced_search;

import std.regex;
import std.string;
import std.algorithm;
import std.array;
import std.uni;
import std.conv;

/// Categories for search classification
enum SearchCategory
{
    ProjectIdeas,
    NewWords,
    Jokes,
    Lyrics,
    Technical,
    Code,
    All
}

/// Search result with category and score
struct SearchResult
{
    string conversationId;
    string conversationTitle;
    string messageContent;
    string snippet;
    SearchCategory category;
    double score;
    string[] keywords;
    size_t messageIndex;
}

/// Enhanced search engine for ChatGPT conversations
class EnhancedChatGPTSearch
{
    private Regex!char[SearchCategory] patterns;
    private string[SearchCategory] categoryNames;

    this()
    {
        initializePatterns();
        initializeCategoryNames();
    }

    private void initializePatterns()
    {
        // Project ideas patterns
        patterns[SearchCategory.ProjectIdeas] = regex(
            r"\b(?:project|idea|build|create|develop|make)\b.*\b(?:app|website|tool|game|system|platform|service)\b" ~
            r"|\bwhat if we\b.*\b(?:built|created|made|developed)\b" ~
            r"|\b(?:startup|business)\s+idea\b" ~
            r"|\bside project\b" ~
            r"|\bopen source\b.*\b(?:project|library|tool)\b" ~
            r"|\b(?:mobile|web|desktop)\s+(?:app|application)\b" ~
            r"|\bAPI\s+(?:for|to|that)\b" ~
            r"|\btool\s+(?:for|to|that)\s+(?:helps|automates|manages)\b",
            "i"
        );

        // New words patterns
        patterns[SearchCategory.NewWords] = regex(
            r"\bnew word[s]?\b" ~
            r"|\bterm[s]?\s+(?:I|we)\s+(?:learned|discovered|found)\b" ~
            r"|\bvocabulary\b" ~
            r"|\b(?:interesting|cool|weird)\s+word\b" ~
            r"|\bmeaning of\b" ~
            r"|\bdefinition of\b" ~
            r"|\bwhat does\s+\w+\s+mean\b" ~
            r"|\bnever heard of\b.*\bbefore\b" ~
            r"|\b(?:etymology|origin)\s+of\b" ~
            r"|\blanguage\s+(?:fact|trivia)\b",
            "i"
        );

        // Jokes patterns
        patterns[SearchCategory.Jokes] = regex(
            r"\bjoke[s]?\b" ~
            r"|\bfunny\b.*\b(?:story|thing|moment)\b" ~
            r"|\bpun[s]?\b" ~
            r"|\bhilarious\b" ~
            r"|\blol\b|LOL\b|\bhaha\b|\bHAHA\b" ~
            r"|\bwhy did\b.*\bcross\b" ~
            r"|\bknock knock\b" ~
            r"|\bwhat do you call\b" ~
            r"|\bhumor\b|\bhumour\b" ~
            r"|\bcomedy\b" ~
            r"|😂|🤣|😄|😆",
            "i"
        );

        // Lyrics patterns
        patterns[SearchCategory.Lyrics] = regex(
            r"\blyrics\b" ~
            r"|\bsong\s+(?:I|we)\s+(?:wrote|composed|created)\b" ~
            r"|\bverse[s]?\b.*\bchorus\b" ~
            r"|\brhyme[s]?\b|\brhyming\b" ~
            r"|\bmusic\b.*\b(?:lyrics|words)\b" ~
            r"|\b(?:singing|song)\s+about\b" ~
            r"|\bpoetry\b" ~
            r"|♪|♫|🎵|🎶" ~
            r"|\b(?:melody|tune|beat)\b",
            "i"
        );

        // Technical patterns
        patterns[SearchCategory.Technical] = regex(
            r"\b(?:architecture|design pattern|framework|library)\b" ~
            r"|\b(?:database|API|frontend|backend|devops)\b" ~
            r"|\b(?:machine learning|AI|neural network)\b" ~
            r"|\b(?:security|authentication|encryption)\b" ~
            r"|\b(?:performance|optimization|scaling)\b" ~
            r"|\b(?:testing|debugging|deployment)\b" ~
            r"|\bmicroservices\b|\bmonolith\b" ~
            r"|\b(?:docker|kubernetes|container)\b",
            "i"
        );

        // Code patterns
        patterns[SearchCategory.Code] = regex(
            r"```(?:python|javascript|java|c\+\+|rust|go|typescript|html|css|sql|d)" ~
            r"|\bfunction\s+\w+\s*\(" ~
            r"|\bclass\s+\w+\s*[:{]" ~
            r"|\bimport\s+\w+" ~
            r"|\bdef\s+\w+\s*\(" ~
            r"|\b(?:algorithm|data structure|pattern)\b" ~
            r"|\bcode\s+(?:review|example|snippet)\b" ~
            r"|\bprogramming\s+(?:language|concept|problem)\b" ~
            r"|\binterface\s+\w+\s*[:{]" ~
            r"|\bstruct\s+\w+\s*[:{]",
            "i"
        );
    }

    private void initializeCategoryNames()
    {
        categoryNames[SearchCategory.ProjectIdeas] = "Project Ideas";
        categoryNames[SearchCategory.NewWords] = "New Words";
        categoryNames[SearchCategory.Jokes] = "Jokes";
        categoryNames[SearchCategory.Lyrics] = "Lyrics";
        categoryNames[SearchCategory.Technical] = "Technical";
        categoryNames[SearchCategory.Code] = "Code";
        categoryNames[SearchCategory.All] = "All Categories";
    }

    /// Search messages and categorize them
    SearchResult[] searchByCategory(string content, string conversationId, string conversationTitle,
                                   SearchCategory targetCategory = SearchCategory.All,
                                   string query = "", size_t messageIndex = 0)
    {
        SearchResult[] results;
        string lowerContent = content.toLower();

        // If searching all categories, check each one
        if (targetCategory == SearchCategory.All)
        {
            foreach (category; [SearchCategory.ProjectIdeas, SearchCategory.NewWords,
                               SearchCategory.Jokes, SearchCategory.Lyrics,
                               SearchCategory.Technical, SearchCategory.Code])
            {
                auto categoryResults = searchSingleCategory(content, conversationId, conversationTitle,
                                                           category, query, messageIndex);
                results ~= categoryResults;
            }
        }
        else
        {
            results = searchSingleCategory(content, conversationId, conversationTitle,
                                         targetCategory, query, messageIndex);
        }

        // Sort by score descending
        results.sort!((a, b) => a.score > b.score);

        return results;
    }

    private SearchResult[] searchSingleCategory(string content, string conversationId, string conversationTitle,
                                              SearchCategory category, string query, size_t messageIndex)
    {
        SearchResult[] results;
        string lowerContent = content.toLower();

        // Check if content matches category pattern
        if (category in patterns && !matchAll(lowerContent, patterns[category]).empty)
        {
            double score = calculateScore(content, category, query);

            // Only include if score is above threshold or query matches
            if (score > 0.5 || (query.length > 0 && lowerContent.canFind(query.toLower())))
            {
                SearchResult result;
                result.conversationId = conversationId;
                result.conversationTitle = conversationTitle;
                result.messageContent = content;
                result.category = category;
                result.score = score;
                result.keywords = extractKeywords(content, category);
                result.snippet = createSnippet(content, result.keywords, query);
                result.messageIndex = messageIndex;

                results ~= result;
            }
        }

        return results;
    }

    private double calculateScore(string content, SearchCategory category, string query)
    {
        double score = 0.0;
        string lowerContent = content.toLower();

        // Base score from pattern matches
        if (category in patterns)
        {
            auto matches = matchAll(lowerContent, patterns[category]);
            score += matches.array.length * 1.0;
        }

        // Bonus for query match
        if (query.length > 0 && lowerContent.canFind(query.toLower()))
        {
            score += 2.0;
        }

        // Length bonus (longer content might be more substantial)
        if (content.length > 100)
        {
            score += 0.5;
        }

        return score;
    }

    private string[] extractKeywords(string content, SearchCategory category)
    {
        string[] keywords;
        string lowerContent = content.toLower();

        if (category in patterns)
        {
            auto matches = matchAll(lowerContent, patterns[category]);
            foreach (match; matches)
            {
                if (match.hit.length > 0 && match.hit.length < 50) // Reasonable keyword length
                {
                    keywords ~= match.hit;
                }
            }
        }

        // Remove duplicates
        keywords = keywords.sort().uniq().array;

        return keywords;
    }

    private string createSnippet(string content, string[] keywords, string query, size_t maxLength = 200)
    {
        string lowerContent = content.toLower();
        size_t bestStart = 0;

        // Try to find position around first keyword or query
        if (keywords.length > 0)
        {
            auto pos = lowerContent.indexOf(keywords[0].toLower());
            if (pos != -1)
            {
                bestStart = pos;
            }
        }
        else if (query.length > 0)
        {
            auto pos = lowerContent.indexOf(query.toLower());
            if (pos != -1)
            {
                bestStart = pos;
            }
        }

        // Create snippet around best position
        size_t start = bestStart >= maxLength/2 ? bestStart - maxLength/2 : 0;
        size_t end = start + maxLength;
        if (end > content.length)
        {
            end = content.length;
            start = end >= maxLength ? end - maxLength : 0;
        }

        string snippet = content[start..end];

        // Add ellipsis if truncated
        if (start > 0) snippet = "..." ~ snippet;
        if (end < content.length) snippet = snippet ~ "...";

        return snippet;
    }

    /// Get category name as string
    string getCategoryName(SearchCategory category)
    {
        return categoryNames.get(category, "Unknown");
    }

    /// Get all available categories
    SearchCategory[] getAllCategories()
    {
        return [SearchCategory.ProjectIdeas, SearchCategory.NewWords,
                SearchCategory.Jokes, SearchCategory.Lyrics,
                SearchCategory.Technical, SearchCategory.Code];
    }

    /// Quick search for specific patterns
    bool hasProjectIdeas(string content)
    {
        return !matchAll(content.toLower(), patterns[SearchCategory.ProjectIdeas]).empty;
    }

    bool hasNewWords(string content)
    {
        return !matchAll(content.toLower(), patterns[SearchCategory.NewWords]).empty;
    }

    bool hasJokes(string content)
    {
        return !matchAll(content.toLower(), patterns[SearchCategory.Jokes]).empty;
    }

    bool hasLyrics(string content)
    {
        return !matchAll(content.toLower(), patterns[SearchCategory.Lyrics]).empty;
    }

    bool hasTechnicalContent(string content)
    {
        return !matchAll(content.toLower(), patterns[SearchCategory.Technical]).empty;
    }

    bool hasCodeContent(string content)
    {
        return !matchAll(content.toLower(), patterns[SearchCategory.Code]).empty;
    }
}

/// Utility function to search conversations with enhanced categorization
SearchResult[] enhancedSearch(T)(T conversations, SearchCategory category = SearchCategory.All,
                                string query = "", size_t maxResults = 50)
{
    auto search = new EnhancedChatGPTSearch();
    SearchResult[] allResults;

    // This would integrate with your existing conversation collection
    // Implementation depends on your data structure

    return allResults.take(maxResults).array;
}

/// Statistics about conversation categories
struct CategoryStats
{
    size_t[SearchCategory] counts;
    double[SearchCategory] percentages;
    size_t totalMessages;
}

/// Get statistics about conversation content
CategoryStats getCategoryStatistics(T)(T conversations)
{
    CategoryStats stats;
    auto search = new EnhancedChatGPTSearch();

    // Count messages in each category
    // Implementation depends on your conversation data structure

    return stats;
}
