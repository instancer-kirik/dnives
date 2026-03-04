module dlangide.ui.homescreen;

import dlangui.widgets.layouts;
import dlangui.widgets.widget;
import dlangui.widgets.scroll;
import dlangui.widgets.controls;
import dlangide.ui.frame;
import dlangide.ui.commands;
import dlangui.core.i18n;

import std.path;
import std.utf : toUTF32;

immutable string HELP_PAGE_URL = "https://github.com/buggins/dlangide/wiki";
immutable string HELP_DONATION_URL = "https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=H2ADZV8S6TDHQ";


class HomeScreen : ScrollWidget {
    protected IDEFrame _frame;
    protected HorizontalLayout _content;
    protected VerticalLayout _startItems;
    protected VerticalLayout _recentItems;

    this(string ID, IDEFrame frame) {
        super(ID);
        import dlangide.ui.frame;
        _frame = frame;

        // ── Root horizontal split ─────────────────────────────────────
        _content = new HorizontalLayout("HOME_SCREEN_BODY");
        _content.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        // Comfortable padding: 36px in GUI mode, 1 char in console mode
        int pad = BACKEND_GUI ? 36 : 1;
        int sectionGap = BACKEND_GUI ? 16 : 1;

        // ── Left column ───────────────────────────────────────────────
        VerticalLayout col1 = new VerticalLayout("HOME_COL1");
        col1.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT)
            .padding(Rect(pad, pad, pad / 2, pad));

        // ── Right column ──────────────────────────────────────────────
        VerticalLayout col2 = new VerticalLayout("HOME_COL2");
        col2.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT)
            .padding(Rect(pad / 2, pad, pad, pad));

        _content.addChild(col1);
        _content.addChild(col2);

        // ── Branding ──────────────────────────────────────────────────
        col1.addChild(
            (new TextWidget(null, "Dnives  "d ~ DLANGIDE_VERSION))
                .styleId("HOME_SCREEN_TITLE")
        );
        col1.addChild(
            (new TextWidget(null, UIString.fromId("DESCRIPTION"c)))
                .styleId("HOME_SCREEN_TITLE2")
        );
        col1.addChild(
            (new TextWidget(null, UIString.fromId("COPYRIGHT"c)))
                .styleId("HOME_SCREEN_TITLE2")
        );

        col1.addChild(makeSpacer(sectionGap));

        // ── Start section ─────────────────────────────────────────────
        col1.addChild(
            (new TextWidget(null, UIString.fromId("START_WITH"c)))
                .styleId("HOME_SCREEN_SECTION")
        );
        col1.addChild(makeSpacer(sectionGap / 2));

        _startItems = new VerticalLayout("HOME_START_ITEMS");
        _startItems.layoutWidth(FILL_PARENT);
        _startItems.addChild(new ImageTextButton(ACTION_FILE_OPEN_WORKSPACE));
        _startItems.addChild(new ImageTextButton(ACTION_FILE_OPEN_DIRECTORY));
        _startItems.addChild(new ImageTextButton(ACTION_FILE_NEW_WORKSPACE));
        _startItems.addChild(new ImageTextButton(ACTION_FILE_NEW_PROJECT));
        col1.addChild(_startItems);

        col1.addChild(makeSpacer(sectionGap));

        // ── Recent workspaces section ─────────────────────────────────
        col1.addChild(
            (new TextWidget(null, UIString.fromId("RECENT"c)))
                .styleId("HOME_SCREEN_SECTION")
        );
        col1.addChild(makeSpacer(sectionGap / 2));

        _recentItems = new VerticalLayout("HOME_RECENT_ITEMS");
        _recentItems.layoutWidth(FILL_PARENT);

        string[] recentWorkspaces = _frame.settings.recentWorkspaces;
        if (recentWorkspaces.length) {
            foreach (fn; recentWorkspaces) {
                Action a = ACTION_FILE_OPEN_WORKSPACE.clone();
                a.label = UIString.fromRaw(toUTF32(stripExtension(baseName(fn))));
                a.stringParam = fn;
                _recentItems.addChild(new LinkButton(a));
            }
        } else {
            _recentItems.addChild(
                (new TextWidget(null, UIString.fromId("NO_RECENT"c)))
                    .styleId("HOME_SCREEN_HINT")
            );
        }
        col1.addChild(_recentItems);
        col1.addChild(new VSpacer());

        // ── Right column: Useful links ────────────────────────────────
        col2.addChild(
            (new TextWidget(null, UIString.fromId("USEFUL_LINKS"c)))
                .styleId("HOME_SCREEN_TITLE")
        );
        col2.addChild(makeSpacer(sectionGap / 2));

        // D language resources
        col2.addChild(
            (new TextWidget(null, "D Language"d))
                .styleId("HOME_SCREEN_SECTION")
        );
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("D_LANG"c).value,          "http://dlang.org/"));
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DLANG_DOWNLOADS"c).value,  "https://dlang.org/download.html"));
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DLANG_TOUR"c).value,       "https://tour.dlang.org/"));
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DLANG_FORUM"c).value,      "http://forum.dlang.org/"));
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DUB_REP"c).value,          "http://code.dlang.org/"));

        col2.addChild(makeSpacer(sectionGap));

        // Project resources
        col2.addChild(
            (new TextWidget(null, "Dnives & Libraries"d))
                .styleId("HOME_SCREEN_SECTION")
        );
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DLANG_UI"c).value,        "https://github.com/buggins/dlangui"));
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DLANG_IDE"c).value,       "https://github.com/buggins/dlangide"));
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DLANG_IDE_HELP"c).value,  HELP_PAGE_URL));
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DLANG_VIBED"c).value,     "http://vibed.org/"));

        col2.addChild(makeSpacer(sectionGap));

        // Donate
        col2.addChild(
            (new TextWidget(null, UIString.fromId("DLANG_IDE_DONATE"c)))
                .styleId("HOME_SCREEN_SECTION")
        );
        col2.addChild(new UrlImageTextButton(null, UIString.fromId("DLANG_IDE_DONATE_PAYPAL"c).value, HELP_DONATION_URL));

        col2.addChild(new VSpacer());

        contentWidget = _content;
    }

    /// Returns a fixed-height vertical spacer widget for consistent section gaps.
    private static Widget makeSpacer(int height) {
        auto sp = new VSpacer();
        static if (BACKEND_GUI) {
            sp.minHeight(height).maxHeight(height);
        }
        return sp;
    }
}
