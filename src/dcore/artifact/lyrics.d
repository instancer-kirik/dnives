module dcore.artifact.lyrics;

import std.algorithm;
import std.array;
import std.ascii : isAlpha, toLower;
import std.conv;
import std.format;
import std.json;
import std.regex;
import std.string;
import std.utf;

import dcore.artifact.artifact;
import dcore.artifact.kind;
import dcore.artifact.transform;

/**
 * LyricSection - A run of lyric lines under one `[Header]` line.
 */
struct LyricSection {
    string name;       // "Verse 1", "Chorus", … ("" before the first header)
    int    headerLine; // 0-based line of the header, -1 if implicit
    string[] lines;    // non-empty lyric lines, timestamps stripped
}

/**
 * LyricsArtifact - Text-backed lyrics with section structure.
 *
 * A section header is a line consisting solely of `[Name]` where Name has no
 * ':' (so LRC tags like `[ar:Artist]` and `[00:12.34]` are not headers).
 * Metadata keys: "sections" (array of {name, line, lineCount}), "lineCount".
 */
class LyricsArtifact : TextArtifact {
    private LyricSection[] _sections;

    this(string id, string name, string sourcePath = null) {
        super(id, "lyrics", name, sourcePath);
    }

    @property const(LyricSection)[] sections() {
        document();
        return _sections;
    }

    override void refreshMetadata() {
        if (_document is null)
            return;
        _sections = parseSections(_document.getText().toUTF8);

        JSONValue[] arr;
        int total = 0;
        foreach (s; _sections) {
            JSONValue j = parseJSON("{}");
            j["name"] = s.name;
            j["line"] = s.headerLine;
            j["lineCount"] = cast(int)s.lines.length;
            arr ~= j;
            total += cast(int)s.lines.length;
        }
        metadata["sections"] = JSONValue(arr);
        metadata["lineCount"] = total;
        metadataChanged();
    }
}

private auto lrcTimestamp = ctRegex!(`^(\[\d+:\d+(?:[.:]\d+)?\])+`);

LyricSection[] parseSections(string text) {
    LyricSection[] result;
    LyricSection current = LyricSection("", -1, []);

    foreach (i, raw; text.lineSplitter.array) {
        string line = raw.strip;
        if (line.length >= 2 && line[0] == '[' && line[$ - 1] == ']'
                && !line[1 .. $ - 1].canFind(':') && !line[1 .. $ - 1].canFind('[')) {
            if (current.headerLine >= 0 || current.lines.length)
                result ~= current;
            current = LyricSection(line[1 .. $ - 1].strip, cast(int)i, []);
            continue;
        }
        line = line.replaceFirst(lrcTimestamp, "").strip;
        if (line.length == 0 || (line[0] == '[' && line[$ - 1] == ']'))
            continue;
        current.lines ~= line;
    }
    if (current.headerLine >= 0 || current.lines.length)
        result ~= current;
    return result;
}

/// Rough English syllable count: vowel groups, minus a trailing silent 'e'.
int countSyllables(string word) {
    int count = 0;
    bool prevVowel = false;
    string w = word.filter!(c => c < 0x80 && isAlpha(cast(char)c))
                   .map!(c => cast(char)toLower(cast(char)c)).to!string;
    foreach (c; w) {
        bool v = "aeiouy".canFind(c);
        if (v && !prevVowel)
            count++;
        prevVowel = v;
    }
    if (w.length > 2 && w[$ - 1] == 'e' && !"aeiouy".canFind(w[$ - 2]) && count > 1)
        count--;
    return w.length ? max(count, 1) : 0;
}

// ---------------------------------------------------------------------------
// Transforms
// ---------------------------------------------------------------------------

/// Section outline: one line per section with its line count.
Transform lyricsOutlineTransform() {
    return new InProcessTransform("lyrics.outline", "Lyrics Section Outline", ["lyrics"],
        (Artifact[] inputs) {
            Artifact[] outs;
            foreach (a; inputs) {
                auto lyr = cast(LyricsArtifact)a;
                if (lyr is null)
                    continue;
                string text;
                foreach (s; lyr.sections)
                    text ~= format("%s (%d lines)\n", s.name.length ? s.name : "(intro)", s.lines.length);
                auto o = new TextArtifact(a.id ~ ":outline", "text", a.name ~ " outline");
                o.setText(text);
                outs ~= o;
            }
            return outs;
        });
}

/// Syllables per line, grouped by section.
Transform lyricsSyllableTransform() {
    return new InProcessTransform("lyrics.syllables", "Lyrics Syllable Count", ["lyrics"],
        (Artifact[] inputs) {
            Artifact[] outs;
            foreach (a; inputs) {
                auto lyr = cast(LyricsArtifact)a;
                if (lyr is null)
                    continue;
                string text;
                foreach (s; lyr.sections) {
                    text ~= "[" ~ (s.name.length ? s.name : "(intro)") ~ "]\n";
                    foreach (l; s.lines)
                        text ~= format("%3d  %s\n", l.split.map!countSyllables.sum, l);
                }
                auto o = new TextArtifact(a.id ~ ":syllables", "text", a.name ~ " syllables");
                o.setText(text);
                outs ~= o;
            }
            return outs;
        });
}

void registerLyricsKind() {
    registerArtifactKind(ArtifactKind("lyrics", "Lyrics", [".lyrics", ".lyr", ".lrc"], true,
        (id, name, path) => cast(Artifact)new LyricsArtifact(id, name, path)));
}

Transform[] lyricsTransforms() {
    return [lyricsOutlineTransform(), lyricsSyllableTransform()];
}
