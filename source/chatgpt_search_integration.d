/**
 * Integration example for enhanced ChatGPT search
 *
 * Shows how to integrate the enhanced search functionality
 * with your existing ChatGPT viewer implementation.
 */
module chatgpt_search_integration;

import chatgpt_enhanced_search;
import std.stdio;
import std.string;
import std.algorithm;
import std.array;
import std.conv;

/// Example integration with existing ChatGPT viewer
class ChatGPTSearchIntegration
{
    private EnhancedChatGPTSearch searchEngine;

    this()
    {
        searchEngine = new EnhancedChatGPTSearch();
    }

    /// Search conversations with enhanced categorization
    void searchProjectIdeas(string query = "")
    {
        writeln("🔍 Searching for project ideas...");
        writeln("==========================================");

        // This would integrate with your existing conversation data
        // For example, if you have a ConversationCollection:
        /*
        auto results = searchInConversations(SearchCategory.ProjectIdeas, query);
        displayResults(results);
        */

        writeln("Example project idea patterns to look for:");
        writeln("• 'build a mobile app for...'");
        writeln("• 'what if we created a tool that...'");
        writeln("• 'startup idea for...'");
        writeln("• 'API for managing...'");
        writeln();
    }

    void searchNewWords(string query = "")
    {
        writeln("📚 Searching for new words and terminology...");
        writeln("============================================");

        writeln("Example word learning patterns:");
        writeln("• 'what does [word] mean'");
        writeln("• 'never heard of [term] before'");
        writeln("• 'interesting word'");
        writeln("• 'definition of'");
        writeln("• 'etymology of'");
        writeln();
    }

    void searchJokes(string query = "")
    {
        writeln("😄 Searching for jokes and humor...");
        writeln("===================================");

        writeln("Example joke patterns:");
        writeln("• 'joke', 'funny', 'hilarious'");
        writeln("• 'LOL', 'haha', '😂'");
        writeln("• 'knock knock'");
        writeln("• 'what do you call'");
        writeln("• 'why did the ... cross'");
        writeln();
    }

    void searchLyrics(string query = "")
    {
        writeln("🎵 Searching for lyrics and creative content...");
        writeln("==============================================");

        writeln("Example lyric patterns:");
        writeln("• 'lyrics', 'song I wrote'");
        writeln("• 'verse and chorus'");
        writeln("• 'rhymes with'");
        writeln("• 'poetry', '🎶', '♪'");
        writeln("• 'melody', 'tune'");
        writeln();
    }

    void searchTechnical(string query = "")
    {
        writeln("🔧 Searching for technical discussions...");
        writeln("========================================");

        writeln("Example technical patterns:");
        writeln("• 'architecture', 'design pattern'");
        writeln("• 'microservices', 'API', 'database'");
        writeln("• 'machine learning', 'AI'");
        writeln("• 'performance', 'optimization'");
        writeln("• 'security', 'authentication'");
        writeln();
    }

    void searchCode(string query = "")
    {
        writeln("💻 Searching for code and programming content...");
        writeln("===============================================");

        writeln("Example code patterns:");
        writeln("• Code blocks: ```python, ```d, ```javascript");
        writeln("• Function definitions: 'function', 'def'");
        writeln("• Class definitions: 'class', 'struct'");
        writeln("• 'algorithm', 'data structure'");
        writeln("• 'code review', 'programming problem'");
        writeln();
    }

    /// Display search results in a formatted way
    void displayResults(SearchResult[] results)
    {
        if (results.length == 0)
        {
            writeln("No results found.");
            return;
        }

        writefln("Found %d results:", results.length);
        writeln();

        foreach (i, result; results)
        {
            writefln("📋 Result %d", i + 1);
            writefln("   Conversation: %s", result.conversationTitle);
            writefln("   Category: %s", searchEngine.getCategoryName(result.category));
            writefln("   Score: %.1f", result.score);
            writefln("   Keywords: %s", result.keywords.join(", "));
            writefln("   Message #%d:", result.messageIndex);
            writefln("   Snippet: %s", result.snippet);
            writeln();
        }
    }

    /// Get statistics about conversation content
    void showStatistics()
    {
        writeln("📊 Conversation Content Statistics");
        writeln("=================================");

        // This would integrate with your existing conversation data
        writeln("Implementation needed:");
        writeln("• Count messages in each category");
        writeln("• Calculate percentages");
        writeln("• Show total conversations and messages");
        writeln();

        writeln("Example output:");
        writeln("Project Ideas: 47 messages (12.3%)");
        writeln("Technical: 156 messages (40.8%)");
        writeln("Code: 89 messages (23.2%)");
        writeln("New Words: 23 messages (6.0%)");
        writeln("Jokes: 12 messages (3.1%)");
        writeln("Lyrics: 8 messages (2.1%)");
        writeln("Other: 47 messages (12.3%)");
        writeln();
        writeln("Total Conversations: 234");
        writeln("Total Messages: 382");
        writeln();
    }

    /// Interactive search menu
    void runInteractiveSearch()
    {
        writeln("🔍 Enhanced ChatGPT Search");
        writeln("=========================");
        writeln();
        writeln("Available search categories:");
        writeln("1. Project Ideas 💡");
        writeln("2. New Words 📚");
        writeln("3. Jokes 😄");
        writeln("4. Lyrics 🎵");
        writeln("5. Technical 🔧");
        writeln("6. Code 💻");
        writeln("7. All Categories 🔍");
        writeln("8. Statistics 📊");
        writeln("9. Exit");
        writeln();

        while (true)
        {
            write("Enter choice (1-9): ");
            string input = readln().strip();

            switch (input)
            {
                case "1":
                    write("Enter search query (or press Enter for all): ");
                    string query = readln().strip();
                    searchProjectIdeas(query);
                    break;

                case "2":
                    write("Enter search query (or press Enter for all): ");
                    string query = readln().strip();
                    searchNewWords(query);
                    break;

                case "3":
                    write("Enter search query (or press Enter for all): ");
                    string query = readln().strip();
                    searchJokes(query);
                    break;

                case "4":
                    write("Enter search query (or press Enter for all): ");
                    string query = readln().strip();
                    searchLyrics(query);
                    break;

                case "5":
                    write("Enter search query (or press Enter for all): ");
                    string query = readln().strip();
                    searchTechnical(query);
                    break;

                case "6":
                    write("Enter search query (or press Enter for all): ");
                    string query = readln().strip();
                    searchCode(query);
                    break;

                case "7":
                    write("Enter search query: ");
                    string query = readln().strip();
                    searchAllCategories(query);
                    break;

                case "8":
                    showStatistics();
                    break;

                case "9":
                    writeln("Goodbye! 👋");
                    return;

                default:
                    writeln("Invalid choice. Please enter 1-9.");
                    break;
            }

            writeln();
        }
    }

    void searchAllCategories(string query)
    {
        writeln("🔍 Searching all categories for: " ~ query);
        writeln("=====================================");

        // This would search across all categories
        writeln("This would search through all conversation categories...");
        writeln();
    }
}

/// Integration with existing ChatGPT models
/// This shows how you might integrate with your existing conversation data
/*
SearchResult[] searchInConversations(SearchCategory category, string query = "")
{
    SearchResult[] results;
    auto search = new EnhancedChatGPTSearch();

    // Example integration with your ConversationCollection
    // foreach (conv; conversationCollection.conversations)
    // {
    //     foreach (i, message; conv.messages)
    //     {
    //         auto messageResults = search.searchByCategory(
    //             message.content,
    //             conv.id,
    //             conv.title,
    //             category,
    //             query,
    //             i
    //         );
    //         results ~= messageResults;
    //     }
    // }

    return results;
}
*/

/// Command-line interface for search - DISABLED to avoid duplicate main
/*
void main(string[] args)
{
    auto integration = new ChatGPTSearchIntegration();

    if (args.length > 1)
    {
        switch (args[1])
        {
            case "ideas":
                string query = args.length > 2 ? args[2..$].join(" ") : "";
                integration.searchProjectIdeas(query);
                break;

            case "words":
                string query = args.length > 2 ? args[2..$].join(" ") : "";
                integration.searchNewWords(query);
                break;

            case "jokes":
                string query = args.length > 2 ? args[2..$].join(" ") : "";
                integration.searchJokes(query);
                break;

            case "lyrics":
                string query = args.length > 2 ? args[2..$].join(" ") : "";
                integration.searchLyrics(query);
                break;

            case "tech":
                string query = args.length > 2 ? args[2..$].join(" ") : "";
                integration.searchTechnical(query);
                break;

            case "code":
                string query = args.length > 2 ? args[2..$].join(" ") : "";
                integration.searchCode(query);
                break;

            case "stats":
                integration.showStatistics();
                break;

            case "interactive":
                integration.runInteractiveSearch();
                break;

            default:
                writeln("Usage: chatgpt_search [ideas|words|jokes|lyrics|tech|code|stats|interactive] [query]");
                writeln();
                writeln("Examples:");
                writeln("  chatgpt_search ideas mobile app");
                writeln("  chatgpt_search jokes programming");
                writeln("  chatgpt_search words etymology");
                writeln("  chatgpt_search stats");
                writeln("  chatgpt_search interactive");
                break;
        }
    }
    else
    {
        integration.runInteractiveSearch();
    }
}
*/
