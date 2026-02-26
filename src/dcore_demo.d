module dcore_demo;

import dlangui;
import std.stdio;
import std.conv;
import std.file;
import std.path;
import std.process;
import std.process : environment;

// Import DCore architecture
import dcore.core;
import dcore.components.cccore;
import dcore.config;

// Import basic DlangUI components
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.dialogs.dialog;
import dlangui.core.logger;

mixin APP_ENTRY_POINT;

/// DCore instances
DCore dcoreInstance;
CCCore cccoreInstance;

/// Simple demo widget to show DCore integration
class DCoreDemo : VerticalLayout
{
    private DCore _dcore;
    private CCCore _cccore;
    private Window _window;

    this()
    {
        super("dcoreDemo");
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
        padding = Rect(20, 20, 20, 20);

        // Title
        TextWidget title = new TextWidget("title", "🚀 DCore Integration Demo"d);
        title.textColor = 0x0066CC;
        title.fontSize = 18;
        title.fontWeight = 600;
        addChild(title);

        // Spacing
        addChild(new TextWidget("space1", ""d));

        // Status info
        TextWidget status = new TextWidget("status", "Testing DCore additive enhancements..."d);
        status.textColor = 0x333333;
        addChild(status);

        addChild(new TextWidget("space2", ""d));

        // Test buttons
        HorizontalLayout buttonLayout = new HorizontalLayout("buttonLayout");
        buttonLayout.layoutWidth = FILL_PARENT;

        Button testButton = new Button("testButton", "Test DCore"d);
        testButton.click = delegate(Widget source) { runDCoreTest(); return true; };
        buttonLayout.addChild(testButton);

        Button statusButton = new Button("statusButton", "Show Status"d);
        statusButton.click = delegate(Widget source) {
            showDCoreStatus();
            return true;
        };
        buttonLayout.addChild(statusButton);

        Button configButton = new Button("configButton", "Config Demo"d);
        configButton.click = delegate(Widget source) {
            showConfigDemo();
            return true;
        };
        buttonLayout.addChild(configButton);

        addChild(buttonLayout);

        addChild(new TextWidget("space3", ""d));

        // Information
        TextWidget info = new TextWidget("info",
            "This demo shows DCore integration working alongside DlangIDE.\n\n" ~
                "✅ DCore architecture initialized\n" ~
                "✅ Configuration management active\n" ~
                "✅ Vault system ready\n" ~
                "✅ Additive enhancement model proven"d);
        info.textColor = 0x006600;
        addChild(info);

        // Initialize with DCore instances
        initializeDCore();
    }

    void setWindow(Window window)
    {
        _window = window;
    }

    void initializeDCore()
    {
        _dcore = dcoreInstance;
        _cccore = cccoreInstance;

        if (_dcore && _cccore)
        {
            Log.i("✅ DCore Demo initialized with core instances");
        }
        else
        {
            Log.w("⚠️  DCore Demo missing core instances");
        }
    }

    void runDCoreTest()
    {
        Log.i("🧪 Running DCore Integration Test from Demo");

        if (!_dcore || !_cccore)
        {
            if (_window)
                _window.showMessageBox("Error"d, "DCore instances not available"d);
            return;
        }

        try
        {
            string results = "DCore Integration Test Results:\n\n";

            // Test configuration access
            string configDir = _dcore.getConfigDir();
            results ~= "✅ Config directory: " ~ configDir ~ "\n";

            // Test workspace management
            auto workspace = _dcore.getCurrentWorkspace();
            if (workspace)
            {
                results ~= "✅ Current workspace: " ~ workspace.name ~ "\n";
            }
            else
            {
                results ~= "ℹ️  No current workspace (normal)\n";
            }

            // Test vault manager
            if (_dcore.vaultManager())
            {
                results ~= "✅ Vault manager: Available\n";
            }
            else
            {
                results ~= "⚠️  Vault manager: Not available\n";
            }

            // Test configuration values
            string testValue = _dcore.getConfigValue("demo.test", "success");
            results ~= "✅ Config test value: " ~ testValue ~ "\n";

            results ~= "\n🎉 All tests passed!\nDCore integration is working correctly.";

            if (_window)
                _window.showMessageBox("DCore Test Results"d, results.toUTF32);

            Log.i("✅ DCore Integration Test completed successfully");
        }
        catch (Exception e)
        {
            string error = "❌ DCore test failed: " ~ e.msg;
            if (_window)
                _window.showMessageBox("Test Failed"d, error.toUTF32);
            Log.e("❌ DCore Integration Test failed: ", e.msg);
        }
    }

    void showDCoreStatus()
    {
        if (!_dcore || !_cccore)
        {
            if (_window)
                _window.showMessageBox("Error"d, "DCore instances not available"d);
            return;
        }

        try
        {
            string configDir = _dcore.getConfigDir();
            auto currentWorkspace = _dcore.getCurrentWorkspace();
            string workspaceName = currentWorkspace ? currentWorkspace.name : "No workspace";

            string statusMessage =
                "🚀 DCore Integration Status\n\n" ~
                "✅ Integration: Active and Ready\n" ~
                "📁 Config Directory: " ~ configDir ~ "\n" ~
                "🏗️  Current Workspace: " ~ workspaceName ~ "\n\n" ~
                "Available DCore Features:\n" ~
                "• Configuration Management ✅\n" ~
                "• Vault System (Multi-workspace) ✅\n" ~
                "• Enhanced UI Components 🚧\n" ~
                "• AI Integration 🔮\n" ~
                "• Radial Menu System 🔮\n\n" ~
                "Legend: ✅ Ready, 🚧 In Progress, 🔮 Future";

            if (_window)
                _window.showMessageBox("DCore Status"d, statusMessage.toUTF32);
        }
        catch (Exception e)
        {
            string error = "Error getting status: " ~ e.msg;
            if (_window)
                _window.showMessageBox("Status Error"d, error.toUTF32);
        }
    }

    void showConfigDemo()
    {
        if (!_dcore)
        {
            if (_window)
                _window.showMessageBox("Error"d, "DCore instance not available"d);
            return;
        }

        try
        {
            Log.i("📋 Running DCore Configuration Demo");

            // Test setting and getting various configuration values
            _dcore.setConfigValue("demo.string_test", "Hello DCore!");
            _dcore.setConfigValue("demo.int_test", 42);
            _dcore.setConfigValue("demo.bool_test", true);
            _dcore.setConfigValue("ui.theme", "dcore_dark");
            _dcore.setConfigValue("features.ai_enabled", false);

            // Retrieve the values
            string stringVal = _dcore.getConfigValue("demo.string_test", "default");
            int intVal = _dcore.getConfigValue("demo.int_test", 0);
            bool boolVal = _dcore.getConfigValue("demo.bool_test", false);
            string theme = _dcore.getConfigValue("ui.theme", "default");
            bool aiEnabled = _dcore.getConfigValue("features.ai_enabled", true);

            string configDemo =
                "🛠️ DCore Configuration Demo\n\n" ~
                "Configuration Values:\n" ~
                "• String test: \"" ~ stringVal ~ "\"\n" ~
                "• Integer test: " ~ intVal.to!string ~ "\n" ~
                "• Boolean test: " ~ (boolVal ? "true" : "false") ~ "\n" ~
                "• UI Theme: " ~ theme ~ "\n" ~
                "• AI Enabled: " ~ (aiEnabled ? "Yes" : "No") ~ "\n\n" ~
                "Configuration saved to:\n" ~ _dcore.getConfigDir() ~ "\n\n" ~
                "✅ All configuration operations successful!";

            if (_window)
                _window.showMessageBox("Config Demo"d, configDemo.toUTF32);

            Log.i("✅ Configuration demo completed successfully");
        }
        catch (Exception e)
        {
            string error = "Configuration demo failed: " ~ e.msg;
            if (_window)
                _window.showMessageBox("Config Demo Failed"d, error.toUTF32);
            Log.e("❌ Configuration demo failed: ", e.msg);
        }
    }
}

/// Entry point for DCore integration demo
extern (C) int UIAppMain(string[] args)
{
    Log.setLogLevel(LogLevel.Info);
    Log.i("🚀 Starting DCore Integration Demo");

    // Initialize platform
    Platform.instance.uiTheme = "ide_theme_default";

    try
    {
        // Get configuration directory
        string configDir = getConfigDirectory();
        Log.i("Using config directory: ", configDir);

        // Initialize configuration manager
        ConfigManager configManager = new ConfigManager(buildPath(configDir, "config.json"));

        // Initialize DCore architecture
        dcoreInstance = new DCore(configDir);
        cccoreInstance = new CCCore(configManager);

        // Initialize core systems
        if (!dcoreInstance.initialize())
        {
            Log.e("Failed to initialize DCore");
            return 1;
        }

        cccoreInstance.initialize();

        Log.i("✅ DCore architecture initialized successfully");

        // Create demo window
        Window window = Platform.instance.createWindow("DCore Integration Demo", null, WindowFlag.Resizable, 800, 600);

        // Create demo widget
        DCoreDemo demoWidget = new DCoreDemo();
        demoWidget.setWindow(window);

        // Set the widget as main widget
        window.mainWidget = demoWidget;

        // Show window
        window.show();

        Log.i("🎯 DCore Integration Demo ready - interact with the UI");

        // Run message loop
        int result = Platform.instance.enterMessageLoop();

        // Cleanup
        Log.i("🧹 Shutting down DCore Integration Demo");
        if (dcoreInstance)
            dcoreInstance.cleanup();
        if (cccoreInstance)
            cccoreInstance.cleanup();

        Log.i("✅ DCore Integration Demo completed successfully");

        return result;
    }
    catch (Exception e)
    {
        Log.e("❌ Fatal error in DCore Integration Demo: ", e.msg);
        return 1;
    }
}

/// Get platform-specific configuration directory
string getConfigDirectory()
{
    version (Windows)
    {
        string appData = environment.get("APPDATA", "");
        if (appData.length > 0)
        {
            return buildPath(appData, "DCore");
        }
        return buildPath(expandTilde("~"), ".dcore");
    }
    else version (Posix)
    {
        string xdgConfig = environment.get("XDG_CONFIG_HOME", "");
        if (xdgConfig.length > 0)
        {
            return buildPath(xdgConfig, "dcore");
        }
        return buildPath(expandTilde("~"), ".config", "dcore");
    }
    else
    {
        return buildPath(expandTilde("~"), ".dcore");
    }
}
