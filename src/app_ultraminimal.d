module app_ultraminimal;

import dlangui;
import std.stdio;
import std.path;
import std.file;
import std.process : environment;

mixin APP_ENTRY_POINT;

/// Ultra-minimal test entry point for dnives
extern (C) int UIAppMain(string[] args)
{
    // Configure logging
    import dlangui.core.logger : LogLevel;

    Log.setLogLevel(LogLevel.Info);
    Log.i("Dnives Ultra-Minimal Test - Starting up");

    // embed non-standard resources listed in views/resources.list into executable
    embeddedResourceList.addResources(embedResourcesFromList!("resources.list")());

    Platform.instance.uiTheme = "ide_theme_default";

    // Font configuration
    FontManager.hintingMode = HintingMode.Normal;
    FontManager.minAnitialiasedFontSize = 0;
    FontManager.fontGamma = 1.0;

    version (unittest)
    {
        return 0;
    }
    else
    {
        try
        {
            // Test configuration directory
            string configDir = getConfigDirectory();
            Log.i("Using config directory: ", configDir);

            // Create a simple window to test
            Window window = Platform.instance.createWindow("Dnives Ultra-Minimal Test", null,
                WindowFlag.Resizable, 800, 600);

            // Create a simple widget
            import dlangui.widgets.layouts;
            import dlangui.widgets.controls;

            VerticalLayout content = new VerticalLayout();
            content.addChild(new TextWidget("test_label", "Dnives Architecture Test - Ready for Integration"d));
            content.addChild(new Button("test_button", "Test Configuration System"d));

            window.mainWidget = content;

            // Show window
            window.show();

            Log.i("Ultra-minimal test ready - entering message loop");

            // Run message loop
            int result = Platform.instance.enterMessageLoop();

            Log.i("Shutting down ultra-minimal test app");
            return result;
        }
        catch (Exception e)
        {
            Log.e("Fatal error during ultra-minimal test startup: ", e.msg);
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
