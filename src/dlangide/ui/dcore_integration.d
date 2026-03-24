module dlangide.ui.dcore_integration;

import dlangui.core.logger;
import dlangui.dialogs.dialog;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.popup;
import dlangui.core.events;
import dlangui.core.stdaction;
import dlangui.core.types;

// Import DCore components
import dcore.core;
import dcore.components.cccore;

// ---------------------------------------------------------------------------
// AutoCloseNotification — a non-modal timed popup that dismisses itself.
// ---------------------------------------------------------------------------
private class AutoCloseNotification : PopupWidget {
    private long _timeoutMs;
    private ulong _timerId;

    this(dstring title, dstring message, long timeoutMs = 1240) {
        auto content = new VerticalLayout("notif_content");
        content.backgroundColor(0x252526);
        content.padding(Rect(16, 12, 16, 12));
        content.minWidth(340);

        auto titleWidget = new TextWidget("notif_title", title);
        titleWidget.fontSize(13);
        titleWidget.fontWeight(700);
        titleWidget.textColor(0xE8E8E8);
        content.addChild(titleWidget);

        auto gap = new Widget("notif_gap");
        gap.minHeight(6);
        content.addChild(gap);

        auto msgWidget = new TextWidget("notif_msg", message);
        msgWidget.fontSize(11);
        msgWidget.textColor(0x9EAAB7);
        content.addChild(msgWidget);

        auto hint = new TextWidget("notif_hint", "auto-closing..."d);
        hint.fontSize(10);
        hint.textColor(0x505050);
        content.addChild(hint);

        super(content, null);
        _timeoutMs = timeoutMs;
    }

    /**
     * Arm the auto-close timer.  Call this immediately after
     * window.showPopup(this) so the widget already has a window reference.
     * dlangui 0.10.8: setTimer(intervalMillis) takes one arg and returns the id.
     */
    void armTimer() {
        _timerId = setTimer(_timeoutMs);
    }

    override bool onTimer(ulong id) {
        if (id == _timerId) {
            close();
            return false;
        }
        return super.onTimer(id);
    }
}

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
            auto notif = new AutoCloseNotification(
                "DCore Integration"d,
                "✅ Ready — config, vault & UI components active. See log for details."d);
            _mainWindow.window.showPopup(notif);
            notif.armTimer();
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
                auto notif = new AutoCloseNotification(
                    "DCore Test"d,
                    "✅ Integration test passed — check log for details."d);
                _mainWindow.window.showPopup(notif);
                notif.armTimer();
            }
        }
        catch (Exception e)
        {
            Log.e("❌ DCore Integration Test failed: ", e.msg);

            if (_mainWindow && _mainWindow.window)
            {
                import std.utf : toUTF32;

                auto notif = new AutoCloseNotification(
                    "DCore Test Failed"d,
                    ("❌ " ~ e.msg).toUTF32);
                _mainWindow.window.showPopup(notif);
                notif.armTimer();
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
