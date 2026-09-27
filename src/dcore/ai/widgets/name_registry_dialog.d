/**
 * name_registry_dialog.d — dlangui Dialog for reviewing NameScanner candidates
 * and browsing / managing the NameRegistry.
 *
 * Two-tab layout:
 *   • Candidates  – review scan results, assign categories, add or skip.
 *   • Registry    – search / filter / delete persisted NameEntry records.
 *
 * Usage:
 * ---
 *   auto dlg = new NameRegistryDialog(window, registry, candidates);
 *   dlg.show();
 * ---
 */
module dcore.ai.widgets.name_registry_dialog;

import std.conv, std.format, std.string, std.array, std.algorithm;

import dlangui;
import dlangui.dialogs.dialog;
import dlangui.core.logger;

import dcore.ai.name_registry;

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

private enum uint BG_DARK    = 0x1E1E1E;
private enum uint BG_MAIN    = 0x252526;
private enum uint BG_ROW_ALT = 0x2D2D2D;
private enum uint COL_TEXT   = 0xCCCCCC;
private enum uint COL_DIM    = 0x9B9B9B;
private enum uint COL_ACCENT = 0x9CDCFE;
private enum uint COL_TEAL   = 0x4EC9B0;

private static immutable dstring[] CATEGORY_ITEMS =
    ["Character"d, "Software"d, "Place"d, "Concept"d, "Other"d];

private static immutable dstring[] FILTER_ITEMS =
    ["All"d, "Character"d, "Software"d, "Place"d, "Concept"d, "Other"d];

// ─────────────────────────────────────────────────────────────────────────────
// NameRegistryDialog
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Modal dialog for reviewing NameScanner candidates and managing the
 * NameRegistry.
 */
class NameRegistryDialog : Dialog
{
public:

    // ── Constructor ──────────────────────────────────────────────────────────

    this(Window window, NameRegistry registry, ScanCandidate[] candidates)
    {
        super(UIString.fromRaw("Name Registry"d),
              window,
              DialogFlag.Modal | DialogFlag.Resizable);

        _registry   = registry;
        _candidates = candidates;
        _addedCount = 0;
    }

    // ── Dialog initialisation ─────────────────────────────────────────────────

    override void initialize()
    {
        super.initialize();

        // ── Root ─────────────────────────────────────────────────────────────
        auto root = new VerticalLayout("nrd_root");
        root.layoutWidth(FILL_PARENT);
        root.layoutHeight(FILL_PARENT);
        root.padding(Rect(12, 12, 12, 12));
        root.backgroundColor(BG_MAIN);

        // ── Tab widget ────────────────────────────────────────────────────────
        auto tabs = new TabWidget("nrd_tabs");
        tabs.layoutWidth(FILL_PARENT);
        tabs.layoutHeight(FILL_PARENT);
        tabs.backgroundColor(BG_MAIN);

        tabs.addTab(buildCandidatesTab(), "Candidates"d);
        tabs.addTab(buildRegistryTab(),   "Registry"d);

        root.addChild(tabs);

        // ── Status label ──────────────────────────────────────────────────────
        _statusLabel = new TextWidget("nrd_status", ""d);
        _statusLabel.fontSize(12);
        _statusLabel.textColor(COL_ACCENT);
        _statusLabel.layoutWidth(FILL_PARENT);
        _statusLabel.margins(Rect(0, 6, 0, 0));
        root.addChild(_statusLabel);

        addChild(root);
    }

private:

    // ── Fields ────────────────────────────────────────────────────────────────

    NameRegistry     _registry;
    ScanCandidate[]  _candidates;
    VerticalLayout   _candidateContainer;
    VerticalLayout   _registryContainer;
    EditLine         _searchBox;
    ComboBox         _categoryFilter;
    TextWidget       _statusLabel;
    int              _addedCount;

    // ── Tab builders ──────────────────────────────────────────────────────────

    Widget buildCandidatesTab()
    {
        auto tab = new VerticalLayout("tab_candidates");
        tab.layoutWidth(FILL_PARENT);
        tab.layoutHeight(FILL_PARENT);
        tab.padding(Rect(8, 8, 8, 8));
        tab.backgroundColor(BG_MAIN);

        // Header
        immutable int n = cast(int) _candidates.length;
        immutable dstring headerText =
            (n.to!string ~ " new name(s) found. Assign a category and click Add, or Skip.").to!dstring;

        auto header = new TextWidget("cand_header", headerText);
        header.fontSize(12);
        header.textColor(COL_TEXT);
        header.layoutWidth(FILL_PARENT);
        header.margins(Rect(0, 0, 0, 6));
        tab.addChild(header);

        // Scroll container
        auto scroll = new ScrollWidget("cand_scroll");
        scroll.layoutWidth(FILL_PARENT);
        scroll.layoutHeight(FILL_PARENT);
        scroll.backgroundColor(BG_DARK);

        _candidateContainer = new VerticalLayout("cand_inner");
        _candidateContainer.layoutWidth(FILL_PARENT);
        _candidateContainer.layoutHeight(WRAP_CONTENT);
        _candidateContainer.backgroundColor(BG_DARK);

        foreach (size_t i, ref c; _candidates)
            _candidateContainer.addChild(buildCandidateRow(c, cast(int) i));

        scroll.contentWidget = _candidateContainer;
        tab.addChild(scroll);

        // Footer button row
        auto footer = new HorizontalLayout("cand_footer");
        footer.layoutWidth(FILL_PARENT);
        footer.margins(Rect(0, 8, 0, 0));
        footer.padding(Rect(0, 4, 0, 4));

        auto btnAddAll = new Button("btn_add_all", "Add All"d);
        btnAddAll.fontSize(11);
        btnAddAll.click = delegate(Widget src) {
            addAllCandidates();
            return true;
        };

        auto btnClose = new Button("btn_cand_close", "Close"d);
        btnClose.fontSize(11);
        btnClose.click = delegate(Widget src) {
            close(ACTION_CANCEL);
            return true;
        };

        footer.addChild(btnAddAll);
        footer.addChild(new HSpacer());
        footer.addChild(btnClose);
        tab.addChild(footer);

        return tab;
    }

    Widget buildRegistryTab()
    {
        auto tab = new VerticalLayout("tab_registry");
        tab.layoutWidth(FILL_PARENT);
        tab.layoutHeight(FILL_PARENT);
        tab.padding(Rect(8, 8, 8, 8));
        tab.backgroundColor(BG_MAIN);

        // Top bar: search + filter + refresh
        auto topBar = new HorizontalLayout("reg_topbar");
        topBar.layoutWidth(FILL_PARENT);
        topBar.margins(Rect(0, 0, 0, 6));

        _searchBox = new EditLine("reg_search");
        _searchBox.layoutWidth(FILL_PARENT);
        _searchBox.layoutWeight(1);
        _searchBox.textColor(COL_TEXT);
        _searchBox.backgroundColor(BG_DARK);
        _searchBox.margins(Rect(0, 0, 6, 0));

        _categoryFilter = new ComboBox("reg_filter", cast(dstring[]) FILTER_ITEMS);
        _categoryFilter.selectedItemIndex = 0;
        _categoryFilter.margins(Rect(0, 0, 6, 0));
        _categoryFilter.itemClick = delegate(Widget src, int index) {
            refreshRegistry();
            return true;
        };

        auto btnRefresh = new Button("reg_refresh", "Refresh"d);
        btnRefresh.fontSize(11);
        btnRefresh.click = delegate(Widget src) {
            refreshRegistry();
            return true;
        };

        topBar.addChild(_searchBox);
        topBar.addChild(_categoryFilter);
        topBar.addChild(btnRefresh);
        tab.addChild(topBar);

        // Scroll container
        auto scroll = new ScrollWidget("reg_scroll");
        scroll.layoutWidth(FILL_PARENT);
        scroll.layoutHeight(FILL_PARENT);
        scroll.backgroundColor(BG_DARK);

        _registryContainer = new VerticalLayout("reg_inner");
        _registryContainer.layoutWidth(FILL_PARENT);
        _registryContainer.layoutHeight(WRAP_CONTENT);
        _registryContainer.backgroundColor(BG_DARK);

        scroll.contentWidget = _registryContainer;
        tab.addChild(scroll);

        // Load initial contents
        refreshRegistry();

        return tab;
    }

    // ── Row builders ──────────────────────────────────────────────────────────

    Widget buildCandidateRow(ScanCandidate c, int rowIndex)
    {
        immutable uint rowBg = (rowIndex % 2 == 0) ? BG_MAIN : BG_ROW_ALT;

        auto row = new HorizontalLayout("cand_row_" ~ rowIndex.to!string);
        row.layoutWidth(FILL_PARENT);
        row.layoutHeight(WRAP_CONTENT);
        row.padding(Rect(4, 3, 4, 3));
        row.backgroundColor(rowBg);

        // Name label
        auto lblName = new TextWidget(
            "cand_name_" ~ rowIndex.to!string,
            c.name.to!dstring);
        lblName.fontSize(12);
        lblName.textColor(c.alreadyInRegistry ? COL_DIM : COL_TEXT);
        lblName.layoutWidth(FILL_PARENT);
        lblName.layoutWeight(1);
        row.addChild(lblName);

        // Frequency badge
        auto lblFreq = new TextWidget(
            "cand_freq_" ~ rowIndex.to!string,
            ("×" ~ c.frequency.to!string).to!dstring);
        lblFreq.fontSize(11);
        lblFreq.textColor(COL_DIM);
        lblFreq.minWidth(40);
        lblFreq.maxWidth(40);
        row.addChild(lblFreq);

        if (c.alreadyInRegistry)
        {
            // Already saved — show greyed-out note instead of controls
            auto lblAlready = new TextWidget(
                "cand_already_" ~ rowIndex.to!string,
                "Already saved"d);
            lblAlready.fontSize(11);
            lblAlready.textColor(COL_DIM);
            lblAlready.margins(Rect(6, 0, 0, 0));
            row.addChild(lblAlready);
        }
        else
        {
            // Category combo
            auto combo = new ComboBox(
                "cand_cat_" ~ rowIndex.to!string,
                cast(dstring[]) CATEGORY_ITEMS);
            combo.selectedItemIndex = cast(int)(CATEGORY_ITEMS.length - 1); // Other
            combo.margins(Rect(4, 0, 4, 0));

            // Add button
            auto btnAdd = new Button(
                "cand_add_" ~ rowIndex.to!string,
                "Add"d);
            btnAdd.fontSize(11);
            btnAdd.click = delegate(Widget src) {
                immutable int idx = combo.selectedItemIndex;
                NameCategory cat  = indexToCategory(idx);
                try
                {
                    _registry.add(c.name, cat, "", [], c.threadIds.dup);
                    _addedCount++;
                    row.visibility(Visibility.Gone);
                    setStatus(("Added '" ~ c.name ~ "'.").to!dstring);
                    Log.i("NameRegistryDialog: added candidate '", c.name, "' as ", cat);
                }
                catch (Exception e)
                {
                    setStatus(("Error adding '" ~ c.name ~ "': " ~ e.msg).to!dstring);
                    Log.e("NameRegistryDialog: add error: ", e.msg);
                }
                return true;
            };

            // Skip button
            auto btnSkip = new Button(
                "cand_skip_" ~ rowIndex.to!string,
                "Skip"d);
            btnSkip.fontSize(11);
            btnSkip.click = delegate(Widget src) {
                row.visibility(Visibility.Gone);
                return true;
            };

            row.addChild(combo);
            row.addChild(btnAdd);
            row.addChild(btnSkip);
        }

        return row;
    }

    Widget buildEntryRow(NameEntry e, int rowIndex)
    {
        immutable uint rowBg = (rowIndex % 2 == 0) ? BG_MAIN : BG_ROW_ALT;

        auto row = new HorizontalLayout("reg_row_" ~ rowIndex.to!string);
        row.layoutWidth(FILL_PARENT);
        row.layoutHeight(WRAP_CONTENT);
        row.padding(Rect(4, 3, 4, 3));
        row.backgroundColor(rowBg);

        // Name
        auto lblName = new TextWidget(
            "reg_name_" ~ rowIndex.to!string,
            e.name.to!dstring);
        lblName.fontSize(12);
        lblName.textColor(COL_TEXT);
        lblName.layoutWidth(FILL_PARENT);
        lblName.layoutWeight(1);
        row.addChild(lblName);

        // Category
        auto lblCat = new TextWidget(
            "reg_cat_" ~ rowIndex.to!string,
            e.category.to!string.to!dstring);
        lblCat.fontSize(11);
        lblCat.textColor(COL_TEAL);
        lblCat.minWidth(90);
        lblCat.maxWidth(90);
        row.addChild(lblCat);

        // Delete button
        immutable long entryId = e.id;
        auto btnDel = new Button(
            "reg_del_" ~ rowIndex.to!string,
            "✕"d);
        btnDel.fontSize(11);
        btnDel.click = delegate(Widget src) {
            try
            {
                _registry.remove(entryId);
                refreshRegistry();
                setStatus(("Removed '" ~ e.name ~ "'.").to!dstring);
                Log.i("NameRegistryDialog: removed entry id=", entryId);
            }
            catch (Exception ex)
            {
                setStatus(("Error removing entry: " ~ ex.msg).to!dstring);
                Log.e("NameRegistryDialog: remove error: ", ex.msg);
            }
            return true;
        };
        row.addChild(btnDel);

        return row;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// Rebuild the registry scroll contents, applying search / filter.
    void refreshRegistry()
    {
        if (_registryContainer is null)
            return;

        _registryContainer.removeAllChildren();

        try
        {
            // Fetch from registry
            immutable int filterIdx = (_categoryFilter !is null)
                                      ? _categoryFilter.selectedItemIndex
                                      : 0;
            immutable string searchTerm = (_searchBox !is null)
                                          ? _searchBox.text.to!string
                                          : "";

            NameEntry[] entries;
            if (searchTerm.strip.length > 0)
            {
                entries = _registry.search(searchTerm.strip);
            }
            else if (filterIdx > 0)
            {
                // filterIdx 1..5 maps to Character..Other
                NameCategory cat = indexToCategory(filterIdx - 1);
                entries = _registry.byCategory(cat);
            }
            else
            {
                entries = _registry.all();
            }

            if (entries.length == 0)
            {
                auto lbl = new TextWidget("reg_empty", "No entries found."d);
                lbl.fontSize(12);
                lbl.textColor(COL_DIM);
                lbl.padding(Rect(8, 8, 8, 8));
                _registryContainer.addChild(lbl);
            }
            else
            {
                foreach (size_t i, ref entry; entries)
                        _registryContainer.addChild(buildEntryRow(entry, cast(int) i));
            }

            setStatus((entries.length.to!string ~ " entry/entries shown.").to!dstring);
        }
        catch (Exception e)
        {
            setStatus(("Failed to load registry: " ~ e.msg).to!dstring);
            Log.e("NameRegistryDialog: refreshRegistry error: ", e.msg);
        }
    }

    /// Add every not-yet-added (visible) candidate as NameCategory.Other.
    void addAllCandidates()
    {
        int added = 0;
        foreach (size_t i, ref c; _candidates)
        {
            if (c.alreadyInRegistry) continue;

            // Skip rows that have been manually hidden (Added or Skipped).
            auto row = _candidateContainer.childById(
                "cand_row_" ~ (cast(int) i).to!string);
            if (row !is null && row.visibility == Visibility.Gone)
                continue;

            try
            {
                _registry.add(c.name, NameCategory.Other, "", [], c.threadIds.dup);
                if (row !is null)
                    row.visibility(Visibility.Gone);
                added++;
                _addedCount++;
            }
            catch (Exception e)
            {
                Log.e("NameRegistryDialog: addAll error for '", c.name, "': ", e.msg);
            }
        }

        setStatus(("Added " ~ added.to!string ~ " candidate(s) as Other.").to!dstring);
        Log.i("NameRegistryDialog: addAll added ", added, " candidates");
    }

    /// Update the status label text.
    void setStatus(dstring msg)
    {
        if (_statusLabel !is null)
            _statusLabel.text = msg;
    }

    /// Map a zero-based CATEGORY_ITEMS index to its NameCategory value.
    static NameCategory indexToCategory(int index)
    {
        switch (index)
        {
            case 0:  return NameCategory.Character;
            case 1:  return NameCategory.Software;
            case 2:  return NameCategory.Place;
            case 3:  return NameCategory.Concept;
            default: return NameCategory.Other;
        }
    }
}
