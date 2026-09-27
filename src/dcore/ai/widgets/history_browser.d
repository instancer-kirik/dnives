module dcore.ai.widgets.history_browser;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.format;
import std.range;
import std.string;
import std.typecons;

import dlangui;
import dlangui.dialogs.dialog;
import dlangui.core.logger;
import dlangui.widgets.controls;
import dlangui.widgets.editors;
import dlangui.widgets.layouts;
import dlangui.widgets.lists;
import dlangui.widgets.widget;

import dcore.ai.ai_backend;
import dcore.search.fuzzysearch;

// ---------------------------------------------------------------------------
// Data types shared with callers
// ---------------------------------------------------------------------------

struct ThreadEntry {
    string id;
    string title;
    string source;       // "local" | "imported_chatgpt"
    int    messageCount;
    DateTime lastActivity;
}

struct MessageHit {
    string threadId;
    string threadTitle;
    string messageId;
    string snippet;
    AIMessage.Role role;
    int score;
}

// ---------------------------------------------------------------------------
// HistoryBrowserDialog
// ---------------------------------------------------------------------------

/**
 * HistoryBrowserDialog — modal-less dialog for searching and browsing all
 * chat threads and their messages.
 *
 * Build the index once with buildIndex(threads), wire the two delegates,
 * then call show().  Delegates are invoked immediately on item click so the
 * user can browse multiple threads without closing the dialog.
 */
class HistoryBrowserDialog : Dialog
{
public:
    /// Called whenever the user selects a thread row.
    void delegate(string threadId) onThreadSelected;
    /// Called whenever the user selects a message row.
    void delegate(string threadId, string messageId) onMessageSelected;

    this(Window window)
    {
        super(UIString.fromRaw("Chat History Browser"d),
              window,
              DialogFlag.Resizable);

        FuzzyOptions opts;
        opts.maxResults       = MAX_MSG_RESULTS;
        opts.consecutiveBonus = 20;
        opts.separatorBonus   = 25;
        opts.camelBonus       = 20;
        _matcher = new FuzzyMatcher(opts);
    }

    /** Rebuild the in-memory index from the caller's thread map. */
    void buildIndex(T)(T threads)
    {
        _allThreads   = [];
        _messageIndex = [];

        foreach (id, ref t; threads) {
            _allThreads ~= ThreadEntry(
                id, t.title, t.source,
                cast(int) t.messages.length,
                t.lastActivity
            );
            foreach (ref m; t.messages) {
                if (m.content.strip.empty) continue;
                string raw     = m.content.strip;
                string snippet = raw.length > SNIPPET_LEN
                    ? raw[0 .. SNIPPET_LEN] ~ "…" : raw;
                snippet = snippet.replace("\n", " ").replace("\r", "");
                _messageIndex ~= MessageHit(id, t.title, m.id, snippet, m.role, 0);
            }
        }

        _allThreads.sort!((a, b) {
            if (a.lastActivity == b.lastActivity) return a.title < b.title;
            return a.lastActivity > b.lastActivity;
        })();
    }

    // ── Dialog initialisation ─────────────────────────────────────────────

    override void initialize()
    {
        super.initialize();

        auto root = new VerticalLayout("hb_root");
        root.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        root.padding(Rect(8, 8, 8, 8));
        root.backgroundColor(0x1C1C1E);

        // ── Search bar ───────────────────────────────────────────────────
        auto searchRow = new HorizontalLayout("hb_search_row");
        searchRow.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        searchRow.padding(Rect(0, 0, 0, 6));

        _searchBox = new EditLine("hb_search");
        _searchBox.layoutWidth(FILL_PARENT);
        _searchBox.fontSize(12);
        _searchBox.tooltipText("Filter threads or search message content"d);
        _searchBox.contentChange = delegate(EditableContent src) {
            _runSearch(src.text.to!string.strip);
        };
        searchRow.addChild(_searchBox);

        auto clearBtn = new Button("hb_clear", "✕"d); // already dstring
        clearBtn.fontSize(10);
        clearBtn.minWidth(24);
        clearBtn.tooltipText("Clear"d);
        clearBtn.click = delegate(Widget w) {
            _searchBox.text = ""d;
            _runSearch("");
            return true;
        };
        searchRow.addChild(clearBtn);
        root.addChild(searchRow);

        // ── Mode toggles ─────────────────────────────────────────────────
        auto modeRow = new HorizontalLayout("hb_mode_row");
        modeRow.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        modeRow.padding(Rect(0, 0, 0, 4));

        _threadsBtn = new Button("hb_threads_btn", "Threads"d);
        _threadsBtn.layoutWidth(FILL_PARENT).layoutWeight(1);
        _threadsBtn.fontSize(11);
        _threadsBtn.backgroundColor(0x3A7BFF);
        _threadsBtn.click = delegate(Widget w) { _setMode(false); return true; };
        modeRow.addChild(_threadsBtn);

        _msgsBtn = new Button("hb_msgs_btn", "Messages"d);
        _msgsBtn.layoutWidth(FILL_PARENT).layoutWeight(1);
        _msgsBtn.fontSize(11);
        _msgsBtn.backgroundColor(0x3A3A3C);
        _msgsBtn.click = delegate(Widget w) { _setMode(true); return true; };
        modeRow.addChild(_msgsBtn);
        root.addChild(modeRow);

        // ── Count label ──────────────────────────────────────────────────
        _countLabel = new TextWidget("hb_count", ""d);
        _countLabel.fontSize(10);
        _countLabel.textColor(0x8A8A8E);
        _countLabel.padding(Rect(0, 0, 0, 4));
        root.addChild(_countLabel);

        // ── Results list ─────────────────────────────────────────────────
        _resultList = new ListWidget("hb_results");
        _resultList.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _resultList.fontSize(11);
        _resultList.ownAdapter = new StringListAdapter();

        _resultList.itemClick = delegate(Widget w, int idx) {
            _onResultClick(idx);
            return true;
        };
        root.addChild(_resultList);

        // ── Close button ─────────────────────────────────────────────────
        auto closeRow = new HorizontalLayout("hb_close_row");
        closeRow.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        closeRow.padding(Rect(0, 8, 0, 0));

        auto spacer = new Widget("hb_spacer");
        spacer.layoutWidth(FILL_PARENT).layoutWeight(1);
        closeRow.addChild(spacer);

        auto closeBtn = new Button("hb_close_btn", "Close"d);
        closeBtn.fontSize(11);
        closeBtn.click = delegate(Widget w) {
            close(new Action(ACTION_CANCEL.id));
            return true;
        };
        closeRow.addChild(closeBtn);
        root.addChild(closeRow);

        addChild(root);

        // Populate with current (unfiltered) threads
        _runSearch("");
    }

private:
    // ── Index ─────────────────────────────────────────────────────────────
    ThreadEntry[]  _allThreads;
    MessageHit[]   _messageIndex;

    // ── Search engine ─────────────────────────────────────────────────────
    FuzzyMatcher _matcher;

    // ── Widgets ───────────────────────────────────────────────────────────
    EditLine   _searchBox;
    Button     _threadsBtn;
    Button     _msgsBtn;
    TextWidget _countLabel;
    ListWidget _resultList;

    // ── Result ID maps (parallel to list rows) ────────────────────────────
    string[] _resultThreadIds;
    string[] _resultMsgIds;
    string[] _resultMsgThreadIds;

    bool _messageMode = false;

    enum MAX_THREAD_RESULTS = 300;
    enum MAX_MSG_RESULTS    = 100;
    enum SNIPPET_LEN        = 100;

    // ── Mode ──────────────────────────────────────────────────────────────

    void _setMode(bool msgMode)
    {
        _messageMode = msgMode;
        _threadsBtn.backgroundColor = msgMode ? 0x3A3A3C : 0x3A7BFF;
        _msgsBtn.backgroundColor   = msgMode ? 0x3A7BFF : 0x3A3A3C;
        _runSearch(_searchBox ? _searchBox.text.to!string.strip : "");
    }

    // ── Search ────────────────────────────────────────────────────────────

    void _runSearch(string query)
    {
        if (_messageMode) _searchMessages(query);
        else              _filterThreads(query);
    }

    void _filterThreads(string query)
    {
        _resultThreadIds = [];
        auto adapter = cast(StringListAdapter) _resultList.adapter;
        if (!adapter) return;
        adapter.clear();

        ThreadEntry[] candidates;
        if (query.empty) {
            candidates = _allThreads.dup;
        } else {
            struct Scored { ThreadEntry e; int s; }
            Scored[] scored;
            foreach (ref t; _allThreads) {
                auto m = _matcher.match(query, t.title);
                if (m.score > int.min) scored ~= Scored(t, m.score);
            }
            scored.sort!((a, b) => a.s > b.s)();
            foreach (ref s; scored) candidates ~= s.e;
        }

        if (candidates.length > MAX_THREAD_RESULTS)
            candidates = candidates[0 .. MAX_THREAD_RESULTS];

        foreach (ref t; candidates) {
            _resultThreadIds ~= t.id;
            adapter.add(_fmtThread(t));
        }
        _updateCount(candidates.length, _allThreads.length, "threads");
    }

    void _searchMessages(string query)
    {
        _resultMsgIds       = [];
        _resultMsgThreadIds = [];
        auto adapter = cast(StringListAdapter) _resultList.adapter;
        if (!adapter) return;
        adapter.clear();

        // Thread order map for stable sort when query is empty
        int[string] threadOrder;
        foreach (i, ref t; _allThreads) threadOrder[t.id] = cast(int) i;

        MessageHit[] hits;
        if (query.empty) {
            hits = _messageIndex.dup;
            hits.sort!((a, b) =>
                threadOrder.get(a.threadId, int.max) <
                threadOrder.get(b.threadId, int.max))();
        } else {
            foreach (ref m; _messageIndex) {
                int ss = _matcher.match(query, m.snippet).score;
                int ts = _matcher.match(query, m.threadTitle).score;
                if (ss <= int.min && ts <= int.min) continue;
                int score = ss;
                if (ts > int.min) score = max(score, ts + 20);
                auto h = m; h.score = score;
                hits ~= h;
            }
            hits.sort!((a, b) => a.score > b.score)();
        }

        if (hits.length > MAX_MSG_RESULTS) hits = hits[0 .. MAX_MSG_RESULTS];

        foreach (ref h; hits) {
            _resultMsgIds       ~= h.messageId;
            _resultMsgThreadIds ~= h.threadId;
            adapter.add(_fmtMsg(h));
        }
        _updateCount(hits.length, _messageIndex.length, "messages");
    }

    // ── Click ─────────────────────────────────────────────────────────────

    void _onResultClick(int idx)
    {
        if (_messageMode) {
            if (idx < 0 || idx >= cast(int) _resultMsgIds.length) return;
            if (onMessageSelected)
                onMessageSelected(_resultMsgThreadIds[idx], _resultMsgIds[idx]);
        } else {
            if (idx < 0 || idx >= cast(int) _resultThreadIds.length) return;
            if (onThreadSelected)
                onThreadSelected(_resultThreadIds[idx]);
        }
    }

    // ── Formatting ────────────────────────────────────────────────────────

    string _fmtThread(ref ThreadEntry t)
    {
        string icon = (t.source == "imported_chatgpt") ? "↓" : "·";
        string date = _shortDate(t.lastActivity);
        return format("%s  %-40s  %3d msgs  %s",
                      icon, t.title.length > 40 ? t.title[0..40] ~ "…" : t.title,
                      t.messageCount, date);
    }

    string _fmtMsg(ref MessageHit h)
    {
        string role;
        final switch (h.role) {
            case AIMessage.Role.User:      role = "You "; break;
            case AIMessage.Role.Assistant: role = "AI  "; break;
            case AIMessage.Role.System:    role = "Sys "; break;
            case AIMessage.Role.Tool:      role = "Tool"; break;
        }
        string title = h.threadTitle.length > 25
            ? h.threadTitle[0..25] ~ "…" : h.threadTitle;
        return format("[%s] %-26s  %s", role, title, h.snippet);
    }

    string _shortDate(DateTime dt)
    {
        auto now = cast(DateTime) Clock.currTime();
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day)
            return format("%02d:%02d", dt.hour, dt.minute);
        if (dt.year == now.year)
            return format("%02d/%02d", dt.month, dt.day);
        return format("%04d/%02d/%02d", dt.year, dt.month, dt.day);
    }

    void _updateCount(size_t shown, size_t total, string noun)
    {
        if (!_countLabel) return;
        string s = (shown == total)
            ? format("%d %s", shown, noun)
            : format("%d / %d %s", shown, total, noun);
        _countLabel.text = s.to!dstring;
    }
}
