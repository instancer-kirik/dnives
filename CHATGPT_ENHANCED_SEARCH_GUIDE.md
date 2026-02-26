# Enhanced ChatGPT Search Integration Guide

This guide shows how to integrate enhanced search functionality into your existing Dowel-Steek ChatGPT viewer to easily find project ideas, new words, jokes, lyrics, and technical discussions.

## Overview

The enhanced search system adds categorized pattern matching to your existing ChatGPT viewer, making it easy to rediscover specific types of content from your conversations.

### Categories

- **💡 Project Ideas**: App ideas, startup concepts, tools to build
- **📚 New Words**: Terminology, definitions, vocabulary learning
- **😄 Jokes**: Humor, puns, funny stories
- **🎵 Lyrics**: Songs, poetry, creative content
- **🔧 Technical**: Architecture discussions, frameworks, concepts  
- **💻 Code**: Programming examples, algorithms, code reviews

## Integration with Existing Viewer

### 1. Add Enhanced Search Module

Copy the enhanced search modules to your Dowel-Steek source directory:

```d
// In your existing chatgpt/models.d or similar file
import chatgpt_enhanced_search;

class ConversationCollection
{
    // Your existing code...
    
    private EnhancedChatGPTSearch enhancedSearch;
    
    this()
    {
        // Your existing initialization...
        enhancedSearch = new EnhancedChatGPTSearch();
    }
    
    /// Enhanced search with categorization
    SearchResult[] searchByCategory(SearchCategory category, string query = "", size_t maxResults = 50)
    {
        SearchResult[] allResults;
        
        foreach (i, conv; conversations)
        {
            if (!conv.isLoaded) conv.loadLazy(); // Use your existing lazy loading
            
            foreach (j, message; conv.messages)
            {
                auto results = enhancedSearch.searchByCategory(
                    message.content,
                    conv.id,
                    conv.title,
                    category,
                    query,
                    j
                );
                allResults ~= results;
            }
        }
        
        // Sort by score and limit results
        allResults.sort!((a, b) => a.score > b.score);
        return allResults.take(maxResults).array;
    }
    
    /// Quick category checks
    bool hasProjectIdeas() 
    { 
        foreach (conv; conversations)
        {
            foreach (msg; conv.messages)
            {
                if (enhancedSearch.hasProjectIdeas(msg.content))
                    return true;
            }
        }
        return false;
    }
    
    // Similar methods for other categories...
}
```

### 2. Add UI Controls

Add search buttons/menu items to your viewer UI:

```d
// In your viewer widget
class ChatGPTViewer : Widget
{
    // Your existing code...
    
    private void createSearchControls()
    {
        auto searchPanel = new HorizontalLayout();
        
        // Category search buttons
        auto ideasBtn = new Button("💡 Ideas");
        ideasBtn.click = delegate(Widget w) { searchCategory(SearchCategory.ProjectIdeas); return true; };
        
        auto wordsBtn = new Button("📚 Words");  
        wordsBtn.click = delegate(Widget w) { searchCategory(SearchCategory.NewWords); return true; };
        
        auto jokesBtn = new Button("😄 Jokes");
        jokesBtn.click = delegate(Widget w) { searchCategory(SearchCategory.Jokes); return true; };
        
        auto lyricsBtn = new Button("🎵 Lyrics");
        lyricsBtn.click = delegate(Widget w) { searchCategory(SearchCategory.Lyrics); return true; };
        
        auto techBtn = new Button("🔧 Tech");
        techBtn.click = delegate(Widget w) { searchCategory(SearchCategory.Technical); return true; };
        
        auto codeBtn = new Button("💻 Code");
        codeBtn.click = delegate(Widget w) { searchCategory(SearchCategory.Code); return true; };
        
        searchPanel.addChild(ideasBtn);
        searchPanel.addChild(wordsBtn);
        searchPanel.addChild(jokesBtn);
        searchPanel.addChild(lyricsBtn);
        searchPanel.addChild(techBtn);
        searchPanel.addChild(codeBtn);
        
        // Add to your main layout
        addChild(searchPanel);
    }
    
    private void searchCategory(SearchCategory category)
    {
        string query = searchBox.text; // Your existing search box
        auto results = conversationCollection.searchByCategory(category, query);
        displaySearchResults(results);
    }
    
    private void displaySearchResults(SearchResult[] results)
    {
        // Clear existing results
        resultsListWidget.removeAllChildren();
        
        if (results.length == 0)
        {
            resultsListWidget.addChild(new TextWidget(null, "No results found"d));
            return;
        }
        
        foreach (result; results)
        {
            auto resultWidget = createResultWidget(result);
            resultsListWidget.addChild(resultWidget);
        }
    }
    
    private Widget createResultWidget(SearchResult result)
    {
        auto container = new VerticalLayout();
        
        // Title and category
        auto titleText = new TextWidget(null, result.conversationTitle ~ " (" ~ 
                                       enhancedSearch.getCategoryName(result.category) ~ ")"d);
        titleText.styleId = "search-result-title";
        
        // Snippet
        auto snippetText = new TextWidget(null, to!dstring(result.snippet));
        snippetText.styleId = "search-result-snippet";
        
        // Score and keywords
        auto metaText = new TextWidget(null, format("Score: %.1f | Keywords: %s", 
                                     result.score, result.keywords.join(", ")).to!dstring);
        metaText.styleId = "search-result-meta";
        
        container.addChild(titleText);
        container.addChild(snippetText);
        container.addChild(metaText);
        
        // Click to open conversation
        container.click = delegate(Widget w) {
            openConversation(result.conversationId);
            return true;
        };
        
        return container;
    }
}
```

### 3. Keyboard Shortcuts

Add keyboard shortcuts for quick category searches:

```d
// In your main window or viewer
override bool onKeyEvent(KeyEvent event) 
{
    if (event.action == KeyAction.KeyDown && event.modifiers & KeyMods.Control)
    {
        switch (event.key)
        {
            case Key.Key1: // Ctrl+1 - Project Ideas
                searchCategory(SearchCategory.ProjectIdeas);
                return true;
                
            case Key.Key2: // Ctrl+2 - New Words
                searchCategory(SearchCategory.NewWords);
                return true;
                
            case Key.Key3: // Ctrl+3 - Jokes
                searchCategory(SearchCategory.Jokes);
                return true;
                
            case Key.Key4: // Ctrl+4 - Lyrics
                searchCategory(SearchCategory.Lyrics);
                return true;
                
            case Key.Key5: // Ctrl+5 - Technical
                searchCategory(SearchCategory.Technical);
                return true;
                
            case Key.Key6: // Ctrl+6 - Code
                searchCategory(SearchCategory.Code);
                return true;
                
            default:
                break;
        }
    }
    
    return super.onKeyEvent(event);
}
```

## Usage Examples

### 1. Finding Project Ideas

```d
// Search for all project ideas
auto results = collection.searchByCategory(SearchCategory.ProjectIdeas);

// Search for mobile app ideas specifically  
auto mobileResults = collection.searchByCategory(SearchCategory.ProjectIdeas, "mobile app");

// Check if any conversations contain project ideas
if (collection.hasProjectIdeas())
{
    writeln("You have discussed project ideas!");
}
```

### 2. Finding New Words

```d
// Find all vocabulary learning discussions
auto wordResults = collection.searchByCategory(SearchCategory.NewWords);

// Search for etymology discussions
auto etymologyResults = collection.searchByCategory(SearchCategory.NewWords, "etymology");
```

### 3. Statistical Analysis

```d
// Get statistics about your conversation content
auto stats = collection.getCategoryStatistics();

foreach (category; [SearchCategory.ProjectIdeas, SearchCategory.NewWords, 
                   SearchCategory.Jokes, SearchCategory.Lyrics])
{
    writefln("%s: %d messages (%.1f%%)", 
             enhancedSearch.getCategoryName(category),
             stats.counts[category],
             stats.percentages[category]);
}
```

## Building and Testing

### 1. Build the enhanced search

```bash
cd dnives
dub build --config=search-tool -f dub_chatgpt_search.json
```

### 2. Test the command-line interface

```bash
# Interactive search
./chatgpt-search interactive

# Search for project ideas
./chatgpt-search ideas mobile app

# Search for jokes
./chatgpt-search jokes programming

# View statistics
./chatgpt-search stats
```

### 3. Integration with existing dub.json

Add to your main `dub.json`:

```json
{
  "configurations": [
    {
      "name": "chatgpt_viewer_enhanced",
      "mainSourceFile": "source/chatgpt_app.d",
      "dependencies": {
        "chatgpt-enhanced-search": {"path": "./"}
      },
      "versions": ["USE_SDL", "USE_FREETYPE", "BACKEND_SDL", "ENHANCED_SEARCH"]
    }
  ]
}
```

## Advanced Features

### 1. Custom Pattern Matching

You can extend the patterns for better matching:

```d
// Add custom patterns for your specific conversations
auto customSearch = new EnhancedChatGPTSearch();

// Add patterns for your specific interests
customSearch.addCustomPattern(SearchCategory.ProjectIdeas, 
    regex(r"\bD language\s+(?:project|library|tool)\b", "i"));
```

### 2. Export Search Results

```d
void exportSearchResults(SearchResult[] results, string filename)
{
    auto file = File(filename, "w");
    
    file.writeln("# Search Results Export");
    file.writefln("Generated: %s", Clock.currTime());
    file.writefln("Total Results: %d", results.length);
    file.writeln();
    
    foreach (i, result; results)
    {
        file.writefln("## Result %d", i + 1);
        file.writefln("**Conversation**: %s", result.conversationTitle);
        file.writefln("**Category**: %s", result.category);
        file.writefln("**Score**: %.1f", result.score);
        file.writefln("**Keywords**: %s", result.keywords.join(", "));
        file.writeln();
        file.writefln("**Content**:");
        file.writefln("```");
        file.writeln(result.snippet);
        file.writefln("```");
        file.writeln();
    }
}
```

### 3. Search History

```d
class SearchHistory
{
    struct SearchEntry
    {
        DateTime timestamp;
        SearchCategory category;
        string query;
        size_t resultCount;
    }
    
    private SearchEntry[] history;
    
    void addSearch(SearchCategory category, string query, size_t resultCount)
    {
        history ~= SearchEntry(Clock.currTime(), category, query, resultCount);
        
        // Keep only last 100 searches
        if (history.length > 100)
            history = history[$ - 100 .. $];
    }
    
    SearchEntry[] getRecentSearches(size_t count = 10)
    {
        return history[max(0, history.length - count) .. $];
    }
}
```

## Troubleshooting

### Common Issues

1. **No results found**: Check if conversations are properly loaded and indexed
2. **Poor pattern matching**: Adjust regex patterns in `chatgpt_enhanced_search.d`
3. **Performance issues**: Use lazy loading and limit result counts
4. **Memory usage**: Consider pagination for large result sets

### Debug Mode

Enable debug output to see what patterns are matching:

```d
version(DEBUG_SEARCH)
{
    writefln("DEBUG: Searching category %s with query '%s'", category, query);
    writefln("DEBUG: Found %d matches", results.length);
}
```

Build with debug flags:
```bash
dub build --config=search-tool -b debug -f dub_chatgpt_search.json
```

## Future Enhancements

- **Semantic search**: Use embeddings for meaning-based search
- **Tag system**: Manual tagging of conversations
- **Search suggestions**: Auto-complete based on conversation content  
- **Export formats**: JSON, CSV, markdown export options
- **Search analytics**: Track what you search for most
- **Favorites system**: Bookmark important conversations/results

## Contributing

To extend the search functionality:

1. Add new categories to `SearchCategory` enum
2. Define regex patterns in `initializePatterns()`
3. Add corresponding UI controls
4. Test with your conversation data
5. Submit improvements back to the project

Happy searching! 🔍