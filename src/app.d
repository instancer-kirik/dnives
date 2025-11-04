module app;

import dlangui;
import std.stdio;
import std.conv;
import std.file;
import std.path;
import std.process;
import std.process : environment;

// Import your DCore architecture
import dcore.core;
import dcore.components.cccore;
import dcore.config;

// Keep D-specific functionality
import dlangide.ui.frame;
import dlangide.ui.commands;
import dlangide.ui.dcore_integration;
import dlangide.workspace.workspace;

static if (__VERSION__ > 2100)
{
    import std.logger;
}
else
{
    import std.experimental.logger;
}

mixin APP_ENTRY_POINT;

/// Global DCore instance
DCore dcoreInstance;
CCCore cccoreInstance;

/// entry point for dnives - multi-language IDE
extern (C) int UIAppMain(string[] args)
{
    // Configure logging
    import dlangui.core.logger : LogLevel;

    Log.setLogLevel(LogLevel.Info);
    Log.i("Dnives IDE starting up - Multi-language development environment");

    //debug(TestDMDTraceParser) {
    //    import dlangide.tools.d.dmdtrace;
    //    long start = currentTimeMillis;
    //    DMDTraceLogParser parser = parseDMDTraceLog("trace.log");
    //    if (parser) {
    //        Log.d("trace.log is parsed ok in ", currentTimeMillis - start, " seconds");
    //    }
    //}
    debug (TestParser)
    {
        import ddc.lexer.parser;

        runParserTests();
    }

    // D Completion Daemon logging config
    static if (__VERSION__ > 2100)
    {
        debug
        {
            sharedLog = cast(shared) new NullLogger();
        }
    else
        {
            sharedLog = cast(shared) new NullLogger();
        }
    }
    else
    {
        debug
        {
            sharedLog = new NullLogger();
        }
    else
        {
            sharedLog = new NullLogger();
        }
    }

    // embed non-standard resources listed in views/resources.list into executable
    embeddedResourceList.addResources(embedResourcesFromList!("resources.list")());

    Platform.instance.uiTheme = "ide_theme_default";

    // Font configuration
    FontManager.hintingMode = HintingMode.Normal;
    FontManager.minAnitialiasedFontSize = 0;
    FontManager.fontGamma = 1.0;
    version (NO_OPENGL)
    {
        FontManager.subpixelRenderingMode = SubpixelRenderingMode.BGR;
    }
    else
    {
        FontManager.subpixelRenderingMode = SubpixelRenderingMode.None;
    }
    version (USE_OPENGL)
    {
        FontManager.subpixelRenderingMode = SubpixelRenderingMode.None;
        FontManager.fontGamma = 0.9;
        FontManager.hintingMode = HintingMode.AutoHint;
    }
    else
    {
        version (USE_FREETYPE)
        {
            FontManager.fontGamma = 0.8;
            FontManager.hintingMode = HintingMode.AutoHint;
        }
    }

    Log.i("Initializing Dnives IDE core systems");

    version (unittest)
    {
        return 0;
    }
    else
    {
        try
        {
            // Initialize configuration directory
            string configDir = getConfigDirectory();
            Log.i("Using config directory: ", configDir);

            // Initialize configuration manager
            ConfigManager configManager = new ConfigManager(configDir);

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

            // Create main window
            Window window = Platform.instance.createWindow("Dnives IDE - Multi-Language Development Environment", null, WindowFlag
                    .Resizable, 1200, 800);
            static if (BACKEND_GUI)
            {
                // Set window icon
                window.windowIcon = drawableCache.getImage("dlangui-logo1");
            }

            Log.i("Creating IDE frame");
            IDEFrame frame = new IDEFrame(window);

            // Initialize DCore integration
            bool dcoreReady = initializeDCoreGlobal(dcoreInstance, cccoreInstance, frame);
            if (dcoreReady)
            {
                Log.i("🎉 DCore additive enhancements ready!");

                // Demonstrate DCore integration
                auto integration = getDCoreIntegration();
                if (integration)
                {
                    integration.showStatus();
                    integration.runDCoreTest();
                }
            }
            else
            {
                Log.w("⚠️  DCore integration not available");
            }

            // Open project, if specified in command line
            if (args.length > 1)
            {
                Action a = ACTION_FILE_OPEN_WORKSPACE.clone();
                a.stringParam = args[1].toAbsolutePath;
                frame.handleAction(a);
                frame.isOpenedWorkspace(true);
            }

            // Open home screen tab if no workspace opened
            if (!frame.isOpenedWorkspace)
                frame.showHomeScreen();

            // Show window
            window.show();

            // Restore UI state
            frame.restoreUIStateOnStartup();

            Log.i("Dnives IDE initialization complete - entering message loop");

            // Run message loop
            int result = Platform.instance.enterMessageLoop();

            // Cleanup
            Log.i("Shutting down Dnives IDE");
            if (dcoreInstance)
            {
                dcoreInstance.cleanup();
            }
            if (cccoreInstance)
            {
                cccoreInstance.cleanup();
            }

            return result;

        }
        catch (Exception e)
        {
            Log.e("Fatal error during Dnives IDE startup: ", e.msg);
            return 1;
        }
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
            return buildPath(appData, "Dnives");
        }
        return buildPath(expandTilde("~"), ".dnives");
    }
    else version (Posix)
    {
        string xdgConfig = environment.get("XDG_CONFIG_HOME", "");
        if (xdgConfig.length > 0)
        {
            return buildPath(xdgConfig, "dnives");
        }
        return buildPath(expandTilde("~"), ".config", "dnives");
    }
    else
    {
        return buildPath(expandTilde("~"), ".dnives");
    }
}
