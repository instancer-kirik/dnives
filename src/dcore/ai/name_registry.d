/**
 * name_registry.d — Named-entity registry for chat history
 *
 * Provides two things:
 *
 *   NameScanner   – scans ImportedChatThread messages and returns candidate
 *                   names (characters, software titles, proper nouns …)
 *                   ranked by frequency.
 *
 *   NameRegistry  – persistent store (SQLite via DBManager) for confirmed
 *                   name entries with categories, aliases, and notes.
 *
 * Typical workflow
 * ────────────────
 *   1. Import threads with ChatGPTImporter.
 *   2. Call NameScanner.scan(threads) → ScanCandidate[]
 *   3. User reviews candidates, picks a category, optionally edits.
 *   4. Call NameRegistry.add / NameRegistry.save to persist.
 *   5. Later: NameRegistry.all / NameRegistry.byCategory for display.
 */
module dcore.ai.name_registry;

import std.string, std.array, std.algorithm, std.conv, std.regex,
       std.uni, std.range, std.typecons, std.exception;

import dlangui.core.logger;

import dcore.ai.chatgpt_importer : ImportedChatThread, ImportedChatMessage;
import dcore.db.dbmanager : DBManager, BindParameter;

// ─────────────────────────────────────────────────────────────────────────────
// Domain types
// ─────────────────────────────────────────────────────────────────────────────

/// Broad categories a name entry can belong to.
enum NameCategory : string {
    Character = "Character",   /// Fictional or real person / character
    Software  = "Software",    /// Application, library, tool, language
    Place     = "Place",       /// Location, world, setting
    Concept   = "Concept",     /// Coined term, lore term, jargon
    Other     = "Other",       /// Anything that doesn't fit above
}

/// One confirmed entry in the registry.
struct NameEntry {
    long         id;           /// Database row id (0 = not yet saved)
    string       name;         /// Canonical (display) name
    NameCategory category;
    string[]     aliases;      /// Alternative spellings / short names
    string       notes;        /// Free-form annotation
    string[]     sourceThreads;/// Thread IDs where this name was spotted
}

/// A candidate produced by NameScanner – not yet confirmed by the user.
struct ScanCandidate {
    string   name;
    int      frequency;        /// How many messages contained this name
    string[] threadIds;        /// Which thread IDs it appeared in
    bool     alreadyInRegistry;
}

// ─────────────────────────────────────────────────────────────────────────────
// NameScanner
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Scans ImportedChatThread messages and surfaces repeated proper-noun
 * sequences as ScanCandidates.
 *
 * The heuristic:
 *   • Split each message into sentences (rough split on '.', '!', '?').
 *   • Within each sentence, collect runs of capitalised tokens that are
 *     NOT the first token (to avoid sentence-opener false positives).
 *   • Runs of 1–4 tokens are kept; single-token runs must be ≥ 3 chars.
 *   • Count occurrences across all messages.
 *   • Apply a stopword filter to discard common English words.
 *   • Return candidates with frequency ≥ minFrequency, sorted descending.
 */
class NameScanner {
public:
    /// Minimum number of messages a candidate must appear in.
    int minFrequency = 2;

    /// Maximum tokens in a single named-entity span.
    int maxSpanTokens = 4;

    /**
     * Run the scan.
     *
     * Params:
     *   threads          = conversation threads to search
     *   knownNames       = names already in the registry (marked alreadyInRegistry)
     *   includeAssistant = whether to scan assistant messages (default true)
     *   includeUser      = whether to scan user messages (default true)
     */
    ScanCandidate[] scan(
        const ImportedChatThread[] threads,
        const string[]             knownNames       = null,
        bool                       includeAssistant = true,
        bool                       includeUser      = true)
    {
        // name → { totalFreq, set of threadIds }
        int[string]      freq;
        bool[string][string] threadSets; // name → threadId → true

        foreach (ref thread; threads) {
            foreach (ref msg; thread.messagesLinear) {
                import dcore.ai.ai_backend : AIMessage;
                bool isUser      = (msg.role == AIMessage.Role.User);
                bool isAssistant = (msg.role == AIMessage.Role.Assistant);

                if (isUser      && !includeUser)      continue;
                if (isAssistant && !includeAssistant) continue;

                auto spans = extractSpans(msg.content);
                foreach (span; spans) {
                    freq[span]++;
                    threadSets[span][thread.id] = true;
                }
            }
        }

        // Build known-names set for quick lookup
        bool[string] knownSet;
        foreach (n; knownNames)
            knownSet[n.toLower] = true;

        // Filter, sort, convert
        ScanCandidate[] results;
        foreach (name, count; freq) {
            if (count < minFrequency) continue;
            ScanCandidate c;
            c.name              = name;
            c.frequency         = count;
            c.threadIds         = threadSets[name].keys;
            c.alreadyInRegistry = (name.toLower in knownSet) !is null;
            results ~= c;
        }

        results.sort!((a, b) => a.frequency > b.frequency);
        return results;
    }

private:
    // Common English words we don't want surfaced as names.
    static immutable string[] STOPWORDS = [
        "i", "a", "an", "the", "and", "or", "but", "in", "on", "at", "to",
        "for", "of", "with", "by", "from", "as", "is", "it", "its", "this",
        "that", "was", "are", "be", "been", "being", "have", "has", "had",
        "do", "does", "did", "will", "would", "could", "should", "may",
        "might", "shall", "can", "not", "no", "nor", "so", "yet", "both",
        "either", "neither", "than", "then", "there", "here", "where",
        "when", "while", "after", "before", "although", "because", "if",
        "unless", "until", "since", "though", "your", "my", "his", "her",
        "our", "their", "we", "he", "she", "they", "you", "who", "which",
        "what", "how", "all", "any", "each", "every", "few", "more",
        "most", "other", "some", "such", "only", "own", "same", "too",
        "very", "just", "also", "well", "now", "new", "old", "first",
        "last", "one", "two", "three", "like", "use", "using", "used",
        "yes", "ok", "okay", "sure", "right", "good", "great", "let",
        "need", "want", "make", "made", "look", "come", "go", "get",
        "see", "say", "said", "know", "think", "think", "way", "thing",
        "time", "day", "year", "re", "ll", "ve", "don", "doesn", "didn",
        "won", "can", "couldn", "wouldn", "shouldn", "isn", "aren",
        "wasn", "weren", "haven", "hasn", "hadn", "im",
    ];

    static bool isStopword(string token) {
        string lower = token.toLower;
        return STOPWORDS.canFind(lower);
    }

    /// Split text into rough sentences then extract capitalised spans.
    string[] extractSpans(string text) {
        string[] result;

        // Rough sentence split: split on ., !, ?, newlines.
        auto sentenceRe = regex(r"(?<=[.!?\n])\s+");
        string[] sentences = text.split(sentenceRe);

        foreach (sentence; sentences) {
            // Tokenise on whitespace/punctuation, keeping word chars + hyphens.
            auto tokenRe = regex(r"[\w'][\w'\-]*");
            string[] tokens;
            foreach (m; matchAll(sentence, tokenRe))
                tokens ~= m.hit;

            if (tokens.length == 0) continue;

            // Slide a window looking for capitalised runs, skipping token[0]
            // (to avoid sentence-initial false positives).
            int i = 1; // skip first token
            while (i < cast(int) tokens.length) {
                string tok = tokens[i];
                if (!tok.empty && tok[0].isUpper && !isStopword(tok)) {
                    // Start of a potential span
                    int spanStart = i;
                    while (i < cast(int) tokens.length
                           && i - spanStart < maxSpanTokens
                           && !tokens[i].empty
                           && tokens[i][0].isUpper
                           && !isStopword(tokens[i])) {
                        i++;
                    }
                    int spanLen = i - spanStart;
                    if (spanLen == 1 && tokens[spanStart].length < 3) continue;

                    // Emit the longest span and all valid suffixes
                    // (e.g. "Visual Studio Code" and "Studio Code" and "Code")
                    // — only the longest is most useful, so just emit that.
                    string span = tokens[spanStart .. i].join(" ");
                    result ~= span;
                } else {
                    i++;
                }
            }
        }

        // Deduplicate within this message
        result.sort();
        return result.uniq.array;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// NameRegistry
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Persistent store for confirmed NameEntry records.
 *
 * Backed by SQLite through the project's existing DBManager.
 * Call ensureSchema() once after DBManager.initialize() before using
 * any other method.
 */
class NameRegistry {
private:
    DBManager _db;

public:
    this(DBManager db) {
        _db = db;
    }

    // ── Schema ───────────────────────────────────────────────────────────────

    /// Create tables if they don't exist.  Safe to call multiple times.
    void ensureSchema() {
        _db.execute(
            "CREATE TABLE IF NOT EXISTS name_entries (
                id             INTEGER PRIMARY KEY AUTOINCREMENT,
                name           TEXT NOT NULL UNIQUE COLLATE NOCASE,
                category       TEXT NOT NULL DEFAULT 'Other',
                notes          TEXT NOT NULL DEFAULT '',
                created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )");

        _db.execute(
            "CREATE TABLE IF NOT EXISTS name_aliases (
                entry_id  INTEGER NOT NULL
                              REFERENCES name_entries(id) ON DELETE CASCADE,
                alias     TEXT NOT NULL COLLATE NOCASE,
                PRIMARY KEY (entry_id, alias)
            )");

        _db.execute(
            "CREATE TABLE IF NOT EXISTS name_threads (
                entry_id  INTEGER NOT NULL
                              REFERENCES name_entries(id) ON DELETE CASCADE,
                thread_id TEXT NOT NULL,
                PRIMARY KEY (entry_id, thread_id)
            )");

        _db.execute(
            "CREATE INDEX IF NOT EXISTS idx_name_entries_category
             ON name_entries(category)");
    }

    // ── Write ─────────────────────────────────────────────────────────────────

    /**
     * Add or update a NameEntry.  If an entry with the same name (case-
     * insensitive) already exists its category/notes are updated and
     * aliases/threads are merged.  Returns the id.
     */
    long save(ref NameEntry entry) {
        _db.transaction(() {
            // Upsert the main row
            _db.execute(
                "INSERT INTO name_entries (name, category, notes)
                 VALUES (?, ?, ?)
                 ON CONFLICT(name) DO UPDATE SET
                     category = excluded.category,
                     notes    = excluded.notes",
                [BindParameter(entry.name),
                 BindParameter(entry.category.to!string),
                 BindParameter(entry.notes)]);

            // Fetch the id (handles both insert and update paths)
            auto row = _db.queryOne(
                "SELECT id FROM name_entries WHERE name = ? COLLATE NOCASE",
                [BindParameter(entry.name)]);
            entry.id = row["id"].as!long;

            // Merge aliases
            foreach (a; entry.aliases) {
                _db.execute(
                    "INSERT OR IGNORE INTO name_aliases (entry_id, alias)
                     VALUES (?, ?)",
                    [BindParameter(entry.id), BindParameter(a)]);
            }

            // Merge source threads
            foreach (tid; entry.sourceThreads) {
                _db.execute(
                    "INSERT OR IGNORE INTO name_threads (entry_id, thread_id)
                     VALUES (?, ?)",
                    [BindParameter(entry.id), BindParameter(tid)]);
            }
        });

        return entry.id;
    }

    /// Convenience: create a minimal entry from just a name and category.
    long add(string name, NameCategory category,
             string notes = "", string[] aliases = null,
             string[] sourceThreads = null) {
        NameEntry e;
        e.name          = name;
        e.category      = category;
        e.notes         = notes;
        e.aliases       = aliases ? aliases : [];
        e.sourceThreads = sourceThreads ? sourceThreads : [];
        return save(e);
    }

    /// Delete an entry by id.
    void remove(long id) {
        _db.execute("DELETE FROM name_entries WHERE id = ?",
                    [BindParameter(id)]);
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    /// Return every entry, sorted by name.
    NameEntry[] all() {
        return loadWhere("1 = 1", []);
    }

    /// Return entries for a specific category.
    NameEntry[] byCategory(NameCategory category) {
        return loadWhere("category = ?", [BindParameter(category.to!string)]);
    }

    /// Full-text search across name, aliases, and notes.
    NameEntry[] search(string query) {
        string q = "%" ~ query ~ "%";
        // Look up matching ids first (aliases join), then load full entries.
        auto rows = _db.query(
            "SELECT DISTINCT e.id
               FROM name_entries e
               LEFT JOIN name_aliases a ON a.entry_id = e.id
              WHERE e.name  LIKE ? COLLATE NOCASE
                 OR a.alias LIKE ? COLLATE NOCASE
                 OR e.notes LIKE ?
              ORDER BY e.name COLLATE NOCASE",
            [BindParameter(q), BindParameter(q), BindParameter(q)]);

        long[] ids;
        foreach (r; rows)
            ids ~= r["id"].as!long;

        if (ids.empty) return [];
        return loadByIds(ids);
    }

    /// Return just the canonical names (useful for NameScanner.knownNames).
    string[] allNames() {
        auto rows = _db.query("SELECT name FROM name_entries ORDER BY name COLLATE NOCASE");
        return rows.map!(r => r["name"].as!string).array;
    }

    // ── Bulk import from scanner ──────────────────────────────────────────────

    /**
     * Persist a batch of scan candidates at once.
     * Candidates with alreadyInRegistry == true are skipped.
     * All are saved as category Other; caller can re-categorise later.
     */
    void importCandidates(const ScanCandidate[] candidates,
                          NameCategory defaultCategory = NameCategory.Other) {
        foreach (ref c; candidates) {
            if (c.alreadyInRegistry) continue;
            add(c.name, defaultCategory,
                "", [],
                c.threadIds.dup);
        }
    }

private:
    NameEntry[] loadWhere(string condition, BindParameter[] params) {
        auto rows = _db.query(
            "SELECT id, name, category, notes
               FROM name_entries
              WHERE " ~ condition ~
            " ORDER BY name COLLATE NOCASE",
            params);

        NameEntry[] entries;
        foreach (r; rows) {
            NameEntry e;
            e.id       = r["id"].as!long;
            e.name     = r["name"].as!string;
            e.notes    = r["notes"].as!string;
            try   { e.category = r["category"].as!string.to!NameCategory; }
            catch (Exception) { e.category = NameCategory.Other; }
            entries ~= e;
        }

        // Load aliases and thread lists
        foreach (ref e; entries) {
            auto arows = _db.query(
                "SELECT alias FROM name_aliases WHERE entry_id = ?",
                [BindParameter(e.id)]);
            foreach (ar; arows)
                e.aliases ~= ar["alias"].as!string;

            auto trows = _db.query(
                "SELECT thread_id FROM name_threads WHERE entry_id = ?",
                [BindParameter(e.id)]);
            foreach (tr; trows)
                e.sourceThreads ~= tr["thread_id"].as!string;
        }

        return entries;
    }

    NameEntry[] loadByIds(long[] ids) {
        if (ids.empty) return [];
        // Build a parameterised IN clause
        string placeholders = ids.map!(_ => "?").join(", ");
        auto params = ids.map!(id => BindParameter(id)).array;
        return loadWhere("id IN (" ~ placeholders ~ ")", params);
    }
}
