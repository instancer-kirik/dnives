module dcore.ai.share_portal;

import std.string;
import std.array;
import std.format;
import std.conv;
import std.datetime;
import std.algorithm;
import std.range;

// ─────────────────────────────────────────────────────────────────────────────
// Data structures
// ─────────────────────────────────────────────────────────────────────────────

/// A single message in a conversation that may be included in a share.
struct SharedMessage
{
    string id;
    /// "user" | "assistant" | "system"
    string role;
    string content;
    string timestamp;
    /// Only messages where isSelected == true are rendered in the portal.
    bool   isSelected;
}

/// All data needed to render one shareable conversation page.
struct SharedConversation
{
    string title;
    string description;
    /// ISO-8601 date string, e.g. "2024-06-01T14:32:00Z"
    string sharedAt;
    string sourceApp = "Dnives IDE";
    SharedMessage[] messages;
}

// ─────────────────────────────────────────────────────────────────────────────
// Generator
// ─────────────────────────────────────────────────────────────────────────────

/// Produces a fully self-contained, dark-themed HTML page for a shared
/// conversation. No CDN or external resources are used.
class SharePortalGenerator
{
public:

    // ── Public API ───────────────────────────────────────────────────────────

    /// Returns the complete HTML document as a UTF-8 string.
    string generate(SharedConversation conv)
    {
        auto messages = conv.messages
            .filter!(m => m.isSelected)
            .enumerate
            .map!(t => renderMessage(t.value, cast(int) t.index))
            .array
            .join("\n");

        if (messages.length == 0)
            messages = `<p class="empty">No messages were selected for this share.</p>`;

        return format(
            "<!DOCTYPE html>\n"
            ~ "<html lang=\"en\">\n"
            ~ "<head>\n"
            ~ "  <meta charset=\"UTF-8\">\n"
            ~ "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
            ~ "  <title>%s — Shared via %s</title>\n"
            ~ "  <style>\n%s\n  </style>\n"
            ~ "</head>\n"
            ~ "<body>\n"
            ~ "  <div class=\"page-wrapper\">\n"
            ~ "    %s\n"          // header
            ~ "    <main class=\"messages\">\n%s\n    </main>\n"
            ~ "    %s\n"          // footer
            ~ "  </div>\n"
            ~ "  <script>\n%s\n  </script>\n"
            ~ "</body>\n"
            ~ "</html>",
            escapeHtml(conv.title),
            escapeHtml(conv.sourceApp),
            inlineCss(),
            renderHeader(conv),
            messages,
            renderFooter(conv.sourceApp),
            inlineJs()
        );
    }

    /// Escapes the five XML/HTML special characters.
    static string escapeHtml(string s)
    {
        auto buf = appender!string;
        buf.reserve(s.length + 16);
        foreach (char c; s)
        {
            switch (c)
            {
                case '&':  buf.put("&amp;");  break;
                case '<':  buf.put("&lt;");   break;
                case '>':  buf.put("&gt;");   break;
                case '"':  buf.put("&quot;"); break;
                case '\'': buf.put("&#39;");  break;
                default:   buf.put(c);        break;
            }
        }
        return buf.data;
    }

    /// Scans `content` for fenced code blocks (```lang\n…\n```) and renders
    /// them via renderCodeBlock; plain-text segments are wrapped in <p> tags.
    /// Uses simple character-level scanning — no regex.
    string parseAndRenderContent(string content)
    {
        auto buf    = appender!string;
        size_t pos  = 0;
        size_t len  = content.length;

        while (pos < len)
        {
            // Search for the opening fence "```"
            ptrdiff_t fenceStart = indexOf(content[pos .. $], "```");
            if (fenceStart < 0)
            {
                // No more fences — flush remaining text
                string tail = content[pos .. $].strip();
                if (tail.length > 0)
                    buf.put(textToParagraphs(tail));
                break;
            }

            size_t absStart = pos + fenceStart;

            // Flush plain text before the fence
            string before = content[pos .. absStart].strip();
            if (before.length > 0)
                buf.put(textToParagraphs(before));

            // Skip past the opening "```"
            size_t afterFence = absStart + 3;

            // Extract optional language tag (runs until '\n')
            size_t langEnd = afterFence;
            while (langEnd < len && content[langEnd] != '\n')
                langEnd++;

            string lang = content[afterFence .. langEnd].strip();

            // Code body starts after the newline
            size_t codeStart = (langEnd < len) ? langEnd + 1 : langEnd;

            // Find closing fence "```"
            ptrdiff_t closingRel = indexOf(content[codeStart .. $], "```");
            if (closingRel < 0)
            {
                // Unclosed fence — treat the rest as a code block
                string code = content[codeStart .. $];
                buf.put(renderCodeBlock(lang, code));
                pos = len;
                break;
            }

            size_t codeEnd   = codeStart + closingRel;
            string code      = content[codeStart .. codeEnd];

            // Strip a single trailing newline from the code body
            if (code.length > 0 && code[$ - 1] == '\n')
                code = code[0 .. $ - 1];

            buf.put(renderCodeBlock(lang, code));

            pos = codeEnd + 3; // skip past closing "```"

            // Skip an optional newline immediately after the closing fence
            if (pos < len && content[pos] == '\n')
                pos++;
        }

        return buf.data;
    }

private:

    // ── Private rendering helpers ────────────────────────────────────────────

    /// Renders one message bubble.
    string renderMessage(SharedMessage msg, int index)
    {
        string roleClass = roleToClass(msg.role);
        string roleChip  = roleToChip(msg.role);
        string renderedContent = parseAndRenderContent(msg.content);

        return format(
            "      <article class=\"message message-%s\" id=\"msg-%s\" data-index=\"%d\">\n"
            ~ "        <div class=\"message-meta\">\n"
            ~ "          <span class=\"role-chip role-%s\">%s</span>\n"
            ~ "          <span class=\"timestamp\">%s</span>\n"
            ~ "        </div>\n"
            ~ "        <div class=\"message-body\">\n%s\n        </div>\n"
            ~ "      </article>",
            roleClass,
            escapeHtml(msg.id),
            index,
            roleClass,
            roleChip,
            escapeHtml(msg.timestamp),
            renderedContent
        );
    }

    /// Renders a fenced code block with language label and copy button.
    string renderCodeBlock(string lang, string code)
    {
        string displayLang = (lang.length > 0) ? escapeHtml(lang) : "plain";
        return format(
            "          <div class=\"code-block\">\n"
            ~ "            <div class=\"code-header\">\n"
            ~ "              <span class=\"code-lang\">%s</span>\n"
            ~ "              <button class=\"copy-btn\" onclick=\"copyCode(this)\">Copy</button>\n"
            ~ "            </div>\n"
            ~ "            <pre><code class=\"lang-%s\">%s</code></pre>\n"
            ~ "          </div>",
            displayLang,
            displayLang,
            escapeHtml(code)
        );
    }

    /// Renders the page header containing conversation metadata.
    string renderHeader(SharedConversation conv)
    {
        size_t selectedCount = conv.messages.count!(m => m.isSelected);
        return format(
            "<header class=\"site-header\">\n"
            ~ "      <div class=\"header-inner\">\n"
            ~ "        <div class=\"header-brand\">%s</div>\n"
            ~ "        <h1 class=\"conv-title\">%s</h1>\n"
            ~ "        %s\n"
            ~ "        <div class=\"conv-meta\">\n"
            ~ "          <span class=\"meta-item\"><span class=\"meta-label\">Shared</span> %s</span>\n"
            ~ "          <span class=\"meta-item\"><span class=\"meta-label\">Messages</span> %d</span>\n"
            ~ "        </div>\n"
            ~ "      </div>\n"
            ~ "    </header>",
            escapeHtml(conv.sourceApp),
            escapeHtml(conv.title),
            conv.description.length > 0
                ? format("<p class=\"conv-desc\">%s</p>", escapeHtml(conv.description))
                : "",
            escapeHtml(conv.sharedAt),
            selectedCount
        );
    }

    /// Renders the page footer.
    string renderFooter(string sourceApp)
    {
        return format(
            "<footer class=\"site-footer\">\n"
            ~ "      <span>Shared via <strong>%s</strong></span>\n"
            ~ "    </footer>",
            escapeHtml(sourceApp)
        );
    }

    // ── Utility helpers ──────────────────────────────────────────────────────

    /// Splits plain text on blank lines and wraps each paragraph in <p>.
    static string textToParagraphs(string text)
    {
        auto buf = appender!string;
        // Split on double newlines; fall back to the whole block.
        auto paras = text.split("\n\n");
        foreach (para; paras)
        {
            string trimmed = para.strip();
            if (trimmed.length > 0)
            {
                // Replace single newlines with <br> within a paragraph
                string lined = trimmed.replace("\n", "<br>\n");
                buf.put(format("          <p>%s</p>\n", escapeHtml_lineBreakSafe(lined)));
            }
        }
        return buf.data;
    }

    /// Like escapeHtml but leaves already-emitted `<br>` tags intact.
    /// We escape first and then re-emit `&lt;br&gt;` as `<br>`.
    static string escapeHtml_lineBreakSafe(string s)
    {
        // We already embedded literal `<br>\n` in the string, so we must
        // escape everything except those tags. Easiest: escape all, then
        // unescape our known-safe `<br>` pattern.
        return escapeHtml(s).replace("&lt;br&gt;", "<br>");
    }

    static string roleToClass(string role)
    {
        switch (role)
        {
            case "user":      return "user";
            case "assistant": return "assistant";
            case "system":    return "system";
            default:          return "unknown";
        }
    }

    static string roleToChip(string role)
    {
        switch (role)
        {
            case "user":      return "YOU";
            case "assistant": return "AI";
            case "system":    return "SYS";
            default:          return role.toUpper();
        }
    }

    // ── Inline assets ────────────────────────────────────────────────────────

    static string inlineCss()
    {
        return q"CSS
/* ── Reset & base ─────────────────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

html { font-size: 16px; }

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
               "Helvetica Neue", Arial, sans-serif;
  background: #0f1117;
  color: #e2e8f0;
  line-height: 1.65;
  min-height: 100vh;
}

/* ── Layout ────────────────────────────────────────────────────────────── */
.page-wrapper {
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  max-width: 860px;
  margin: 0 auto;
  padding: 0 1rem;
}

main.messages {
  flex: 1;
  padding: 2rem 0;
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
}

/* ── Header ────────────────────────────────────────────────────────────── */
.site-header {
  padding: 2.25rem 0 1.5rem;
  border-bottom: 1px solid #2d3148;
}

.header-brand {
  font-size: 0.75rem;
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: #6366f1;
  margin-bottom: 0.75rem;
}

.conv-title {
  font-size: 1.75rem;
  font-weight: 700;
  color: #f1f5f9;
  margin-bottom: 0.5rem;
  line-height: 1.3;
}

.conv-desc {
  color: #94a3b8;
  font-size: 0.9375rem;
  margin-bottom: 0.875rem;
}

.conv-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  font-size: 0.8125rem;
  color: #64748b;
}

.meta-label {
  font-weight: 600;
  color: #475569;
  margin-right: 0.3em;
}

/* ── Message bubbles ───────────────────────────────────────────────────── */
.message {
  background: #1a1d27;
  border-radius: 12px;
  padding: 1.125rem 1.375rem;
  border-left: 3px solid transparent;
  transition: border-color 0.15s;
}

.message-user      { border-left-color: #3b82f6; }
.message-assistant { border-left-color: #10b981; }
.message-system    { border-left-color: #f59e0b; }
.message-unknown   { border-left-color: #6366f1; }

.message-meta {
  display: flex;
  align-items: center;
  gap: 0.625rem;
  margin-bottom: 0.75rem;
}

/* ── Role chips ────────────────────────────────────────────────────────── */
.role-chip {
  display: inline-block;
  font-size: 0.6875rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  padding: 0.2em 0.65em;
  border-radius: 4px;
  text-transform: uppercase;
}

.role-user      { background: rgba(59,130,246,0.18); color: #60a5fa; }
.role-assistant { background: rgba(16,185,129,0.18); color: #34d399; }
.role-system    { background: rgba(245,158,11,0.18); color: #fbbf24; }
.role-unknown   { background: rgba(99,102,241,0.18); color: #a5b4fc; }

.timestamp {
  font-size: 0.75rem;
  color: #475569;
}

/* ── Message body ──────────────────────────────────────────────────────── */
.message-body p {
  margin-bottom: 0.625rem;
  color: #cbd5e1;
  font-size: 0.9375rem;
}

.message-body p:last-child { margin-bottom: 0; }

/* ── Code blocks ───────────────────────────────────────────────────────── */
.code-block {
  background: #0d1117;
  border: 1px solid #2d3148;
  border-radius: 8px;
  margin: 0.875rem 0;
  overflow: hidden;
}

.code-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.4rem 0.875rem;
  background: #161b22;
  border-bottom: 1px solid #2d3148;
}

.code-lang {
  font-size: 0.75rem;
  font-weight: 600;
  color: #64748b;
  text-transform: lowercase;
  letter-spacing: 0.04em;
}

.copy-btn {
  background: transparent;
  border: 1px solid #2d3148;
  border-radius: 4px;
  color: #64748b;
  cursor: pointer;
  font-size: 0.7rem;
  font-weight: 600;
  letter-spacing: 0.06em;
  padding: 0.2em 0.6em;
  text-transform: uppercase;
  transition: color 0.15s, border-color 0.15s, background 0.15s;
}

.copy-btn:hover  { color: #e2e8f0; border-color: #475569; background: #1e2535; }
.copy-btn.copied { color: #34d399; border-color: #34d399; }

pre {
  overflow-x: auto;
  padding: 1rem 1.125rem;
}

pre code {
  font-family: "JetBrains Mono", "Fira Code", "Cascadia Code",
               "Source Code Pro", Consolas, "Courier New", monospace;
  font-size: 0.84rem;
  line-height: 1.7;
  color: #c9d1d9;
  white-space: pre;
}

/* ── Empty state ───────────────────────────────────────────────────────── */
p.empty {
  color: #475569;
  font-style: italic;
  text-align: center;
  padding: 3rem 0;
}

/* ── Footer ────────────────────────────────────────────────────────────── */
.site-footer {
  border-top: 1px solid #2d3148;
  padding: 1.125rem 0;
  text-align: center;
  font-size: 0.8125rem;
  color: #475569;
}

.site-footer strong { color: #6366f1; }

/* ── Responsive ────────────────────────────────────────────────────────── */
@media (max-width: 600px) {
  .conv-title { font-size: 1.35rem; }
  .message    { padding: 0.875rem 1rem; }
}
CSS";
    }

    static string inlineJs()
    {
        return q"JS
(function () {
  'use strict';

  // ── Copy-to-clipboard for code blocks ──────────────────────────────────
  window.copyCode = function (btn) {
    var pre  = btn.closest('.code-block').querySelector('pre');
    var text = pre ? pre.innerText : '';

    if (!navigator.clipboard) {
      // Fallback for older browsers / non-HTTPS contexts
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity  = '0';
      document.body.appendChild(ta);
      ta.focus();
      ta.select();
      try { document.execCommand('copy'); } catch (_) {}
      document.body.removeChild(ta);
      flashCopied(btn);
      return;
    }

    navigator.clipboard.writeText(text).then(function () {
      flashCopied(btn);
    }, function () {
      btn.textContent = 'Error';
    });
  };

  function flashCopied(btn) {
    var original = btn.textContent;
    btn.textContent = 'Copied!';
    btn.classList.add('copied');
    setTimeout(function () {
      btn.textContent = original;
      btn.classList.remove('copied');
    }, 2000);
  }

  // ── Highlight active message on click ──────────────────────────────────
  document.addEventListener('DOMContentLoaded', function () {
    var messages = document.querySelectorAll('.message');
    messages.forEach(function (msg) {
      msg.addEventListener('click', function () {
        messages.forEach(function (m) { m.style.opacity = '0.55'; });
        msg.style.opacity = '1';
      });
    });

    document.addEventListener('click', function (e) {
      if (!e.target.closest('.message')) {
        messages.forEach(function (m) { m.style.opacity = '1'; });
      }
    });
  });
}());
JS";
    }
}
