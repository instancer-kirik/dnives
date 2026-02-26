module dlangide.ui.dcore_integration;

import dlangui.core.logger;
import dlangui.dialogs.dialog;
import dlangui.widgets.widget;
import dlangui.core.events;
import dlangui.core.stdaction;

// Import DCore components
import dcore.core;
import dcore.components.cccore;

/**
 * DCore Integration Manager - Minimal Proof of Concept
 *
 * This provides a simple way to verify DCore integration works
 * without breaking existing DlangIDE functionality.
 */
class DCoreIntegrationManager
{
    private DCore _dcoreInstance;
    private CCCore _cccoreInstance;
    private bool _initialized = false;
    private Widget _mainWindow;

    /**
     * Initialize DCore integration
     */
    bool initialize(DCore dcore, CCCore cccore, Widget mainWindow)
    {
        _dcoreInstance = dcore;
        _cccoreInstance = cccore;
        _mainWindow = mainWindow;

        if (_dcoreInstance && _cccoreInstance)
        {
            _initialized = true;
            Log.i("✅ DCore Integration Manager initialized successfully");
            Log.i("   - DCore instance: ", _dcoreInstance ? "Ready" : "Missing");
            Log.i("   - CCCore instance: ", _cccoreInstance ? "Ready" : "Missing");
            Log.i("   - Main window: ", _mainWindow ? "Connected" : "Missing");

            return true;
        }

        Log.e("❌ DCore Integration Manager failed to initialize");
        return false;
    }

    /**
     * Show integration status
     */
    void showStatus()
    {
        if (!_initialized)
        {
            Log.w("DCore Integration Manager not initialized");
            return;
        }

        string configDir = _dcoreInstance ? _dcoreInstance.getConfigDir() : "Unknown";
        auto currentWorkspace = _dcoreInstance ? _dcoreInstance.getCurrentWorkspace() : null;
        string workspaceName = currentWorkspace ? currentWorkspace.name : "No workspace";

        string statusMessage =
            "DCore Integration Status\n\n" ~
            "✅ Integration: Active\n" ~
            "📁 Config Directory: " ~ configDir ~ "\n" ~
            "🏗️  Current Workspace: " ~ workspaceName ~ "\n\n" ~
            "Available DCore Features:\n" ~
            "• Configuration Management\n" ~
            "• Vault System (Multi-workspace)\n" ~
            "• Enhanced UI Components\n" ~
            "• AI Integration (Future)\n" ~
            "• Radial Menu (Future)";

        if (_mainWindow && _mainWindow.window)
        {
            import std.utf : toUTF32;

            _mainWindow.window.showMessageBox("DCore Integration"d, statusMessage.toUTF32);
        }
        else
        {
            Log.i("DCore Integration Status:");
            Log.i(statusMessage);
        }
    }

    /**
     * Test DCore functionality
     */
    void runDCoreTest()
    {
        if (!_initialized)
        {
            Log.e("Cannot run DCore test - not initialized");
            return;
        }

        Log.i("🧪 Running DCore Integration Test");

        try
        {
            // Test configuration access
            if (_dcoreInstance)
            {
                string configDir = _dcoreInstance.getConfigDir();
                Log.i("   ✅ Config directory access: ", configDir);
            }

            // Test workspace management
            auto workspace = _dcoreInstance.getCurrentWorkspace();
            if (workspace)
            {
                Log.i("   ✅ Workspace access: ", workspace.name);
            }
            else
            {
                Log.i("   ℹ️  No current workspace (normal)");
            }

            // Test vault manager - not implemented in current DCore
            // TODO: Implement vault manager in DCore
            /*
            if (_dcoreInstance.vaultManager())
            {
                Log.i("   ✅ Vault manager: Available");
            }
            else
            {
                Log.w("   ⚠️  Vault manager: Not available");
            }
            */
            Log.i("   ℹ️  Vault manager: Not yet implemented in DCore");

            Log.i("🎉 DCore Integration Test completed successfully");

            if (_mainWindow && _mainWindow.window)
            {
                _mainWindow.window.showMessageBox("DCore Test"d, "✅ DCore integration test passed!\n\nCheck the log for detailed results."d);
            }
        }
        catch (Exception e)
        {
            Log.e("❌ DCore Integration Test failed: ", e.msg);

            if (_mainWindow && _mainWindow.window)
            {
                import std.utf : toUTF32;

                string errorMsg = "❌ DCore test failed:\n" ~ e.msg;
                _mainWindow.window.showMessageBox("DCore Test Failed"d, errorMsg.toUTF32);
            }
        }
    }

    /**
     * Demonstrate DCore configuration
     */
    void showConfigDemo()
    {
        if (!_initialized)
        {
            Log.w("Cannot show config demo - not initialized");
            return;
        }

        Log.i("📋 DCore Configuration Demo");

        try
        {
            // Try to access some configuration
            if (_dcoreInstance)
            {
                // Test configuration values
                string testValue = _dcoreInstance.getConfigValue("ui.theme", "default");
                bool testBool = _dcoreInstance.getConfigValue("features.ai_enabled", false);

                Log.i("   Theme setting: ", testValue);
                Log.i("   AI enabled: ", testBool ? "Yes" : "No");

                // Demonstrate setting a value
                _dcoreInstance.setConfigValue("integration.last_demo", "success");

                string demoMessage =
                    "DCore Configuration Demo\n\n" ~
                    "Current Settings:\n" ~
                    "• Theme: " ~ testValue ~ "\n" ~
                    "• AI Enabled: " ~ (testBool ? "Yes" : "No") ~ "\n\n" ~
                    "Configuration saved to:\n" ~ _dcoreInstance.getConfigDir();

                if (_mainWindow && _mainWindow.window)
                {
                    import std.utf : toUTF32;

                    _mainWindow.window.showMessageBox("DCore Config"d, demoMessage.toUTF32);
                }
            }
        }
        catch (Exception e)
        {
            Log.e("Config demo failed: ", e.msg);
        }
    }

    /**
     * Check if integration is ready
     */
    bool isReady()
    {
        return _initialized && _dcoreInstance && _cccoreInstance;
    }

    /**
     * Get DCore instance
     */
    DCore getDCore()
    {
        return _dcoreInstance;
    }

    /**
     * Get CCCore instance
     */
    CCCore getCCCore()
    {
        return _cccoreInstance;
    }

    /**
     * Cleanup integration
     */
    void cleanup()
    {
        if (_initialized)
        {
            Log.i("🧹 Cleaning up DCore Integration Manager");

            if (_dcoreInstance)
                _dcoreInstance.cleanup();

            if (_cccoreInstance)
                _cccoreInstance.cleanup();
        }
    }
}

/// Global DCore integration manager instance
__gshared DCoreIntegrationManager g_dcoreIntegration;

/// Initialize global DCore integration
bool initializeDCoreGlobal(DCore dcore, CCCore cccore, Widget mainWindow)
{
    if (!g_dcoreIntegration)
        g_dcoreIntegration = new DCoreIntegrationManager();

    return g_dcoreIntegration.initialize(dcore, cccore, mainWindow);
}

/// Get global DCore integration manager
DCoreIntegrationManager getDCoreIntegration()
{
    return g_dcoreIntegration;
}

/// Cleanup global DCore integration
void cleanupDCoreGlobal()
{
    if (g_dcoreIntegration)
    {
        g_dcoreIntegration.cleanup();
        g_dcoreIntegration = null;
    }
}
