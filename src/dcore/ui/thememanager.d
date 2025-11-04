module dcore.ui.thememanager;

import dlangui.core.logger;
import dlangui.graphics.colors;
import dlangui.graphics.drawbuf;
import dlangui.widgets.styles;
import dlangui.widgets.widget;

import std.json;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.string;
import std.conv;

import dcore.core;

/**
 * Theme - Represents a complete UI theme with syntax highlighting
 */
class Theme {
    // Theme metadata
    string name;
    string author;
    string description;
    bool isDark;
    
    // General colors
    uint backgroundColor;
    uint foregroundColor;
    uint selectionBackground;
    uint selectionForeground;
    uint cursorColor;
    uint lineHighlightColor;
    uint gutterBackground;
    uint gutterForeground;
    
    // UI element colors
    uint[string] uiColors;
    
    // Syntax highlighting colors
    struct SyntaxTokenStyle {
        uint foreground;
        uint background = 0x00000000; // Transparent by default
        bool bold;
        bool italic;
        bool underline;
    }
    
    // Syntax highlighting for each language
    SyntaxTokenStyle[string][string] syntaxStyles; // language -> token type -> style
    
    // Default syntax token types
    static string[] defaultTokenTypes = [
        "keyword", "identifier", "string", "number", "comment", "operator",
        "type", "function", "variable", "constant", "parameter", "class",
        "interface", "namespace", "preprocessor", "tag", "attribute"
    ];
    
    /**
     * Constructor for empty theme
     */
    this(string name = "Default") {
        this.name = name;
        
        // Set default values for colors
        backgroundColor = 0x1E1E1E; // Dark background
        foregroundColor = 0xD4D4D4; // Light text
        selectionBackground = 0x264F78; // Blue selection
        selectionForeground = 0xFFFFFF; // White text in selection
        cursorColor = 0xAEAFAD; // Gray cursor
        lineHighlightColor = 0x2D2D30; // Slightly lighter than background
        gutterBackground = 0x1E1E1E; // Same as background
        gutterForeground = 0x858585; // Gray text
        
        // Initialize default syntax highlighting
        initializeDefaultSyntaxHighlighting();
    }
    
    /**
     * Initialize default syntax highlighting
     */
    private void initializeDefaultSyntaxHighlighting() {
        // Default syntax highlighting for generic code
        SyntaxTokenStyle[string] defaultStyles;
        defaultStyles["keyword"] = SyntaxTokenStyle(0x569CD6, 0, true); // Blue, bold
        defaultStyles["identifier"] = SyntaxTokenStyle(0xD4D4D4); // Default text color
        defaultStyles["string"] = SyntaxTokenStyle(0xCE9178); // Brown-orange
        defaultStyles["number"] = SyntaxTokenStyle(0xB5CEA8); // Light green
        defaultStyles["comment"] = SyntaxTokenStyle(0x6A9955, 0, false, true); // Green, italic
        defaultStyles["operator"] = SyntaxTokenStyle(0xD4D4D4); // Default text color
        defaultStyles["type"] = SyntaxTokenStyle(0x4EC9B0); // Teal
        defaultStyles["function"] = SyntaxTokenStyle(0xDCDCAA); // Light yellow
        defaultStyles["variable"] = SyntaxTokenStyle(0x9CDCFE); // Light blue
        defaultStyles["constant"] = SyntaxTokenStyle(0x4FC1FF, 0, true); // Bright blue, bold
        defaultStyles["parameter"] = SyntaxTokenStyle(0x9CDCFE); // Light blue
        defaultStyles["class"] = SyntaxTokenStyle(0x4EC9B0, 0, true); // Teal, bold
        defaultStyles["interface"] = SyntaxTokenStyle(0xB8D7A3); // Light green
        defaultStyles["namespace"] = SyntaxTokenStyle(0xD4D4D4); // Default text color
        defaultStyles["preprocessor"] = SyntaxTokenStyle(0xC586C0); // Purple
        defaultStyles["tag"] = SyntaxTokenStyle(0x569CD6); // Blue
        defaultStyles["attribute"] = SyntaxTokenStyle(0x9CDCFE); // Light blue
        
        // Add to default language
        syntaxStyles["default"] = defaultStyles;
        
        // You can add language-specific defaults here
        // For example, D language-specific highlighting
        syntaxStyles["d"] = defaultStyles.dup;
        syntaxStyles["d"]["keyword"] = SyntaxTokenStyle(0x569CD6, 0, true); // Blue, bold
        
        // Python-specific highlighting
        syntaxStyles["python"] = defaultStyles.dup;
        syntaxStyles["python"]["keyword"] = SyntaxTokenStyle(0xFF569C, 0, true); // Pink, bold
        
        // JavaScript-specific highlighting
        syntaxStyles["javascript"] = defaultStyles.dup;
        syntaxStyles["javascript"]["keyword"] = SyntaxTokenStyle(0x569CD6, 0, true); // Blue, bold
    }
    
    /**
     * Get syntax style for a token type in a specific language
     */
    SyntaxTokenStyle getSyntaxStyle(string language, string tokenType) {
        // Check if language exists
        if (language !in syntaxStyles) {
            // Fall back to default language
            language = "default";
        }
        
        // Check if token type exists for language
        if (tokenType !in syntaxStyles[language]) {
            // Fall back to default token type
            if ("default" in syntaxStyles[language])
                return syntaxStyles[language]["default"];
            else
                return SyntaxTokenStyle(foregroundColor); // Use foreground color
        }
        
        return syntaxStyles[language][tokenType];
    }
    
    /**
     * Set syntax style for a token type in a specific language
     */
    void setSyntaxStyle(string language, string tokenType, SyntaxTokenStyle style) {
        // Ensure language exists
        if (language !in syntaxStyles) {
            syntaxStyles[language] = (SyntaxTokenStyle[string]).init;
        }
        
        // Set style
        syntaxStyles[language][tokenType] = style;
    }
    
    /**
     * Get UI color
     */
    uint getUIColor(string elementId, uint defaultColor) {
        if (elementId in uiColors)
            return uiColors[elementId];
        return defaultColor;
    }
    
    /**
     * Set UI color
     */
    void setUIColor(string elementId, uint color) {
        uiColors[elementId] = color;
    }
    
    /**
     * Apply theme to widget and its children
     */
    void applyToWidget(Widget widget) {
        if (!widget)
            return;
            
        // Apply background color
        widget.backgroundColor = backgroundColor;
        
        // Apply text color
        widget.textColor = foregroundColor;
        
        // Apply to all children
        for (int i = 0; i < widget.childCount; i++) {
            applyToWidget(widget.child(i));
        }
    }
    
    /**
     * Convert theme to JSON
     */
    JSONValue toJSON() {
        JSONValue json = parseJSON("{}");
        
        // Metadata
        json["name"] = name;
        json["author"] = author;
        json["description"] = description;
        json["isDark"] = isDark;
        
        // General colors
        json["backgroundColor"] = backgroundColor;
        json["foregroundColor"] = foregroundColor;
        json["selectionBackground"] = selectionBackground;
        json["selectionForeground"] = selectionForeground;
        json["cursorColor"] = cursorColor;
        json["lineHighlightColor"] = lineHighlightColor;
        json["gutterBackground"] = gutterBackground;
        json["gutterForeground"] = gutterForeground;
        
        // UI colors
        JSONValue uiColorsJson = parseJSON("{}");
        foreach (elementId, color; uiColors) {
            uiColorsJson[elementId] = color;
        }
        json["uiColors"] = uiColorsJson;
        
        // Syntax highlighting
        JSONValue syntaxStylesJson = parseJSON("{}");
        foreach (language, tokenStyles; syntaxStyles) {
            JSONValue langStylesJson = parseJSON("{}");
            
            foreach (tokenType, style; tokenStyles) {
                JSONValue styleJson = parseJSON("{}");
                styleJson["foreground"] = style.foreground;
                styleJson["background"] = style.background;
                styleJson["bold"] = style.bold;
                styleJson["italic"] = style.italic;
                styleJson["underline"] = style.underline;
                
                langStylesJson[tokenType] = styleJson;
            }
            
            syntaxStylesJson[language] = langStylesJson;
        }
        json["syntaxStyles"] = syntaxStylesJson;
        
        return json;
    }
    
    /**
     * Load theme from JSON
     */
    static Theme fromJSON(JSONValue json) {
        Theme theme = new Theme();
        
        // Metadata
        if ("name" in json) theme.name = json["name"].str;
        if ("author" in json) theme.author = json["author"].str;
        if ("description" in json) theme.description = json["description"].str;
        if ("isDark" in json) theme.isDark = json["isDark"].boolean;
        
        // General colors
        if ("backgroundColor" in json) theme.backgroundColor = cast(uint)json["backgroundColor"].integer;
        if ("foregroundColor" in json) theme.foregroundColor = cast(uint)json["foregroundColor"].integer;
        if ("selectionBackground" in json) theme.selectionBackground = cast(uint)json["selectionBackground"].integer;
        if ("selectionForeground" in json) theme.selectionForeground = cast(uint)json["selectionForeground"].integer;
        if ("cursorColor" in json) theme.cursorColor = cast(uint)json["cursorColor"].integer;
        if ("lineHighlightColor" in json) theme.lineHighlightColor = cast(uint)json["lineHighlightColor"].integer;
        if ("gutterBackground" in json) theme.gutterBackground = cast(uint)json["gutterBackground"].integer;
        if ("gutterForeground" in json) theme.gutterForeground = cast(uint)json["gutterForeground"].integer;
        
        // UI colors
        if ("uiColors" in json && json["uiColors"].type == JSONType.object) {
            foreach (elementId, colorValue; json["uiColors"].object) {
                theme.uiColors[elementId] = cast(uint)colorValue.integer;
            }
        }
        
        // Syntax highlighting
        if ("syntaxStyles" in json && json["syntaxStyles"].type == JSONType.object) {
            foreach (language, langStylesJson; json["syntaxStyles"].object) {
                SyntaxTokenStyle[string] langStyles;
                
                foreach (tokenType, styleJson; langStylesJson.object) {
                    SyntaxTokenStyle style;
                    if ("foreground" in styleJson) style.foreground = cast(uint)styleJson["foreground"].integer;
                    if ("background" in styleJson) style.background = cast(uint)styleJson["background"].integer;
                    if ("bold" in styleJson) style.bold = styleJson["bold"].boolean;
                    if ("italic" in styleJson) style.italic = styleJson["italic"].boolean;
                    if ("underline" in styleJson) style.underline = styleJson["underline"].boolean;
                    
                    langStyles[tokenType] = style;
                }
                
                theme.syntaxStyles[language] = langStyles;
            }
        }
        
        return theme;
    }
}

/**
 * ThemeManager - Manages themes for the application
 */
class ThemeManager {
    private DCore _core;
    private Theme[string] _themes;
    private string _currentThemeName;
    private Theme _currentTheme;
    private string _themesDir;
    
    /**
     * Constructor
     */
    this(DCore core, string themesDir) {
        _core = core;
        _themesDir = themesDir;
        
        // Create default themes
        createDefaultThemes();
        
        // Set default theme
        _currentThemeName = "Dark";
        _currentTheme = _themes["Dark"];
        
        Log.i("ThemeManager: Initialized with default themes");
    }
    
    /**
     * Create default themes
     */
    private void createDefaultThemes() {
        // Dark theme (default)
        Theme darkTheme = new Theme("Dark");
        darkTheme.author = "CompyutinatorCode";
        darkTheme.description = "Default dark theme";
        darkTheme.isDark = true;
        
        // General colors already set in Theme constructor
        
        // Add to themes
        _themes["Dark"] = darkTheme;
        
        // Light theme
        Theme lightTheme = new Theme("Light");
        lightTheme.author = "CompyutinatorCode";
        lightTheme.description = "Default light theme";
        lightTheme.isDark = false;
        
        // Set light theme colors
        lightTheme.backgroundColor = 0xFDFDFD; // Near-white background
        lightTheme.foregroundColor = 0x1E1E1E; // Near-black text
        lightTheme.selectionBackground = 0xADD6FF; // Light blue selection
        lightTheme.selectionForeground = 0x1E1E1E; // Near-black text in selection
        lightTheme.cursorColor = 0x000000; // Black cursor
        lightTheme.lineHighlightColor = 0xF8F8F8; // Slightly darker than background
        lightTheme.gutterBackground = 0xF5F5F5; // Slightly darker than background
        lightTheme.gutterForeground = 0x6E6E6E; // Gray text
        
        // Set light theme syntax highlighting
        lightTheme.syntaxStyles.clear();
        
        // Default syntax highlighting for light theme
        Theme.SyntaxTokenStyle[string] lightDefaultStyles;
        lightDefaultStyles["keyword"] = Theme.SyntaxTokenStyle(0x0000FF, 0, true); // Blue, bold
        lightDefaultStyles["identifier"] = Theme.SyntaxTokenStyle(0x1E1E1E); // Default text color
        lightDefaultStyles["string"] = Theme.SyntaxTokenStyle(0xA31515); // Dark red
        lightDefaultStyles["number"] = Theme.SyntaxTokenStyle(0x098658); // Green
        lightDefaultStyles["comment"] = Theme.SyntaxTokenStyle(0x008000, 0, false, true); // Green, italic
        lightDefaultStyles["operator"] = Theme.SyntaxTokenStyle(0x1E1E1E); // Default text color
        lightDefaultStyles["type"] = Theme.SyntaxTokenStyle(0x267F99); // Dark teal
        lightDefaultStyles["function"] = Theme.SyntaxTokenStyle(0x795E26); // Brown
        lightDefaultStyles["variable"] = Theme.SyntaxTokenStyle(0x1F377F); // Dark blue
        lightDefaultStyles["constant"] = Theme.SyntaxTokenStyle(0x0070C1, 0, true); // Blue, bold
        lightDefaultStyles["parameter"] = Theme.SyntaxTokenStyle(0x1F377F); // Dark blue
        lightDefaultStyles["class"] = Theme.SyntaxTokenStyle(0x267F99, 0, true); // Dark teal, bold
        lightDefaultStyles["interface"] = Theme.SyntaxTokenStyle(0x267F99); // Dark teal
        lightDefaultStyles["namespace"] = Theme.SyntaxTokenStyle(0x1E1E1E); // Default text color
        lightDefaultStyles["preprocessor"] = Theme.SyntaxTokenStyle(0xA31515); // Dark red
        lightDefaultStyles["tag"] = Theme.SyntaxTokenStyle(0x800000); // Maroon
        lightDefaultStyles["attribute"] = Theme.SyntaxTokenStyle(0xFF0000); // Red
        
        // Add to light theme
        lightTheme.syntaxStyles["default"] = lightDefaultStyles;
        
        // Add light theme to themes
        _themes["Light"] = lightTheme;
        
        // Cyberpunk theme
        Theme cyberpunkTheme = new Theme("Cyberpunk");
        cyberpunkTheme.author = "CompyutinatorCode";
        cyberpunkTheme.description = "Cyberpunk-inspired theme with neon colors";
        cyberpunkTheme.isDark = true;
        
        // Set cyberpunk colors
        cyberpunkTheme.backgroundColor = 0x0A0A16; // Deep blue-black
        cyberpunkTheme.foregroundColor = 0xEBF4FF; // Light blue-white
        cyberpunkTheme.selectionBackground = 0xFF1694; // Neon pink
        cyberpunkTheme.selectionForeground = 0xEBF4FF; // Light blue-white
        cyberpunkTheme.cursorColor = 0x00FF9C; // Neon green
        cyberpunkTheme.lineHighlightColor = 0x0E1429; // Slightly lighter deep blue
        cyberpunkTheme.gutterBackground = 0x0A0A16; // Same as background
        cyberpunkTheme.gutterForeground = 0x2A3B56; // Muted blue
        
        // Set cyberpunk syntax highlighting
        Theme.SyntaxTokenStyle[string] cyberpunkStyles;
        cyberpunkStyles["keyword"] = Theme.SyntaxTokenStyle(0xFF1694, 0, true); // Neon pink, bold
        cyberpunkStyles["identifier"] = Theme.SyntaxTokenStyle(0xEBF4FF); // Default text color
        cyberpunkStyles["string"] = Theme.SyntaxTokenStyle(0xFFC600); // Bright yellow
        cyberpunkStyles["number"] = Theme.SyntaxTokenStyle(0x00FF9C); // Neon green
        cyberpunkStyles["comment"] = Theme.SyntaxTokenStyle(0x2A9CFF, 0, false, true); // Bright blue, italic
        cyberpunkStyles["operator"] = Theme.SyntaxTokenStyle(0xFF9C00); // Bright orange
        cyberpunkStyles["type"] = Theme.SyntaxTokenStyle(0x36F9F6); // Cyan
        cyberpunkStyles["function"] = Theme.SyntaxTokenStyle(0xFF2C70); // Red-pink
        cyberpunkStyles["variable"] = Theme.SyntaxTokenStyle(0x7A82DA); // Purple-blue
        cyberpunkStyles["constant"] = Theme.SyntaxTokenStyle(0xFFFC58, 0, true); // Yellow, bold
        cyberpunkStyles["parameter"] = Theme.SyntaxTokenStyle(0x7A82DA); // Purple-blue
        cyberpunkStyles["class"] = Theme.SyntaxTokenStyle(0x36F9F6, 0, true); // Cyan, bold
        cyberpunkStyles["interface"] = Theme.SyntaxTokenStyle(0x94DBFB); // Light blue
        cyberpunkStyles["namespace"] = Theme.SyntaxTokenStyle(0x7A82DA); // Purple-blue
        cyberpunkStyles["preprocessor"] = Theme.SyntaxTokenStyle(0xF92AAD); // Pink
        cyberpunkStyles["tag"] = Theme.SyntaxTokenStyle(0x36F9F6); // Cyan
        cyberpunkStyles["attribute"] = Theme.SyntaxTokenStyle(0x94DBFB); // Light blue
        
        // Add to cyberpunk theme
        cyberpunkTheme.syntaxStyles["default"] = cyberpunkStyles;
        
        // Add cyberpunk theme to themes
        _themes["Cyberpunk"] = cyberpunkTheme;
    }
    
    /**
     * Load themes from directory
     */
    void loadThemes() {
        if (!exists(_themesDir))
            return;
            
        try {
            // Find theme files
            foreach (string file; dirEntries(_themesDir, "*.json", SpanMode.shallow)) {
                loadThemeFromFile(file);
            }
            
            Log.i("ThemeManager: Loaded themes from ", _themesDir);
        }
        catch (Exception e) {
            Log.e("ThemeManager: Error loading themes: ", e.msg);
        }
    }
    
    /**
     * Load theme from file
     */
    Theme loadThemeFromFile(string filePath) {
        try {
            // Read file
            string content = readText(filePath);
            
            // Parse JSON
            JSONValue json = parseJSON(content);
            
            // Create theme
            Theme theme = Theme.fromJSON(json);
            
            // Add to themes
            if (theme.name.length > 0)
                _themes[theme.name] = theme;
                
            Log.i("ThemeManager: Loaded theme from file: ", filePath);
            
            return theme;
        }
        catch (Exception e) {
            Log.e("ThemeManager: Error loading theme from file: ", e.msg, " - ", filePath);
            return null;
        }
    }
    
    /**
     * Save theme to file
     */
    bool saveThemeToFile(string themeName, string filePath = null) {
        if (themeName !in _themes)
            return false;
            
        Theme theme = _themes[themeName];
        
        try {
            // Get file path
            string path = filePath;
            if (!path || path.length == 0) {
                path = buildPath(_themesDir, themeName.toLower().replace(" ", "_") ~ ".json");
            }
            
            // Create directory if needed
            string dir = dirName(path);
            if (!exists(dir))
                mkdirRecurse(dir);
                
            // Convert theme to JSON
            JSONValue json = theme.toJSON();
            
            // Write to file
            std.file.write(path, json.toPrettyString());
            
            Log.i("ThemeManager: Saved theme to file: ", path);
            
            return true;
        }
        catch (Exception e) {
            Log.e("ThemeManager: Error saving theme to file: ", e.msg);
            return false;
        }
    }
    
    /**
     * Get theme by name
     */
    Theme getTheme(string name) {
        if (name in _themes)
            return _themes[name];
        return null;
    }
    
    /**
     * Get current theme
     */
    Theme getCurrentTheme() {
        return _currentTheme;
    }
    
    /**
     * Set current theme
     */
    bool setCurrentTheme(string name) {
        if (name !in _themes)
            return false;
            
        _currentThemeName = name;
        _currentTheme = _themes[name];
        
        // Save preference
        if (_core)
            _core.setConfigValue("ui.theme", name);
            
        Log.i("ThemeManager: Current theme set to: ", name);
        
        return true;
    }
    
    /**
     * Get all theme names
     */
    string[] getThemeNames() {
        return _themes.keys;
    }
    
    /**
     * Apply current theme to widget
     */
    void applyThemeToWidget(Widget widget) {
        if (!_currentTheme || !widget)
            return;
            
        _currentTheme.applyToWidget(widget);
    }
    
    /**
     * Get syntax style for token
     */
    Theme.SyntaxTokenStyle getSyntaxStyle(string language, string tokenType) {
        if (!_currentTheme)
            return Theme.SyntaxTokenStyle(0xFFFFFF); // Default white
            
        return _currentTheme.getSyntaxStyle(language, tokenType);
    }
}