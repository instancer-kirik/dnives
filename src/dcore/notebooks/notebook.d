module dcore.notebooks.notebook;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.file;
import std.json;
import std.path;
import std.string;
import std.uuid;
import std.utf;

import dlangui.core.logger;
import dlangui.core.signals;
import dcore.utils.signals : Signal;

/**
 * Cell types supported in notebooks
 */
enum CellType {
    Markdown,    // Markdown documentation cell
    Code,        // Executable code cell
    Output,      // Output from code execution (auto-generated)
    Raw          // Raw text cell
}

/**
 * Cell execution state
 */
enum CellState {
    Idle,        // Not executed or ready to execute
    Running,     // Currently executing
    Completed,   // Successfully executed
    Error,       // Execution failed
    Stale        // Cell output is outdated due to changes in previous cells
}

/**
 * Individual cell in a notebook
 */
class NotebookCell {
    private string _id;
    private CellType _type;
    private CellState _state;
    private string _source;
    private string _output;
    private string _errorOutput;
    private SysTime _lastExecuted;
    private SysTime _lastModified;
    private int _executionCount;
    private JSONValue _metadata;

    // Signals
    Signal!() onContentChanged;
    Signal!() onStateChanged;
    Signal!(string) onOutputChanged;

    /**
     * Constructor
     */
    this(CellType type = CellType.Code, string source = "") {
        _id = randomUUID().toString();
        _type = type;
        _state = CellState.Idle;
        _source = source;
        _output = "";
        _errorOutput = "";
        _executionCount = 0;
        _metadata = JSONValue.emptyObject;
        _lastModified = Clock.currTime();
    }

    /**
     * Constructor with ID (for loading from file)
     */
    this(string id, CellType type, string source) {
        _id = id;
        _type = type;
        _state = CellState.Idle;
        _source = source;
        _output = "";
        _errorOutput = "";
        _executionCount = 0;
        _metadata = JSONValue.emptyObject;
        _lastModified = Clock.currTime();
    }

    // Properties
    @property string id() const { return _id; }
    @property CellType type() const { return _type; }
    @property void type(CellType value) {
        if (_type != value) {
            _type = value;
            _lastModified = Clock.currTime();
            onContentChanged.emit();
        }
    }

    @property CellState state() const { return _state; }
    @property void state(CellState value) {
        if (_state != value) {
            _state = value;
            onStateChanged.emit();
        }
    }

    @property string source() const { return _source; }
    @property void source(string value) {
        if (_source != value) {
            _source = value;
            _lastModified = Clock.currTime();
            // Mark as stale if it was previously executed
            if (_state == CellState.Completed) {
                _state = CellState.Stale;
            }
            onContentChanged.emit();
        }
    }

    @property string output() const { return _output; }
    @property void output(string value) {
        if (_output != value) {
            _output = value;
            onOutputChanged.emit(value);
        }
    }

    @property string errorOutput() const { return _errorOutput; }
    @property void errorOutput(string value) { _errorOutput = value; }

    @property int executionCount() const { return _executionCount; }
    @property SysTime lastExecuted() const { return _lastExecuted; }
    @property SysTime lastModified() const { return _lastModified; }

    @property JSONValue metadata() const { return _metadata; }
    @property void metadata(JSONValue value) {
        _metadata = value;
        _lastModified = Clock.currTime();
    }

    /**
     * Mark cell as executed
     */
    void markExecuted() {
        _executionCount++;
        _lastExecuted = Clock.currTime();
        _state = CellState.Completed;
        onStateChanged.emit();
    }

    /**
     * Mark cell as failed
     */
    void markFailed(string error) {
        _errorOutput = error;
        _state = CellState.Error;
        onStateChanged.emit();
    }

    /**
     * Clear output
     */
    void clearOutput() {
        _output = "";
        _errorOutput = "";
        if (_state == CellState.Completed || _state == CellState.Error) {
            _state = CellState.Idle;
        }
        onOutputChanged.emit("");
        onStateChanged.emit();
    }

    /**
     * Convert to JSON for serialization
     */
    JSONValue toJSON() const {
        JSONValue json = JSONValue.emptyObject;
        json["id"] = _id;
        json["cell_type"] = _type.to!string.toLower;
        json["source"] = _source;
        json["execution_count"] = _executionCount;
        json["metadata"] = _metadata;

        if (_output.length > 0 || _errorOutput.length > 0) {
            JSONValue outputs = JSONValue.emptyArray;

            if (_output.length > 0) {
                JSONValue outputObj = JSONValue.emptyObject;
                outputObj["output_type"] = "stream";
                outputObj["name"] = "stdout";
                outputObj["text"] = _output;
                outputs.array ~= outputObj;
            }

            if (_errorOutput.length > 0) {
                JSONValue errorObj = JSONValue.emptyObject;
                errorObj["output_type"] = "error";
                errorObj["ename"] = "ExecutionError";
                errorObj["evalue"] = _errorOutput;
                outputs.array ~= errorObj;
            }

            json["outputs"] = outputs;
        }

        return json;
    }

    /**
     * Load from JSON
     */
    static NotebookCell fromJSON(JSONValue json) {
        string id = json["id"].str;
        string typeStr = json["cell_type"].str;

        CellType type;
        switch (typeStr) {
            case "markdown": type = CellType.Markdown; break;
            case "code": type = CellType.Code; break;
            case "raw": type = CellType.Raw; break;
            default: type = CellType.Code; break;
        }

        string source = json["source"].str;
        auto cell = new NotebookCell(id, type, source);

        if ("execution_count" in json) {
            cell._executionCount = cast(int)json["execution_count"].integer;
        }

        if ("metadata" in json) {
            cell._metadata = json["metadata"];
        }

        if ("outputs" in json && json["outputs"].type == JSONType.array) {
            foreach (output; json["outputs"].array) {
                if (output["output_type"].str == "stream") {
                    cell._output = output["text"].str;
                } else if (output["output_type"].str == "error") {
                    cell._errorOutput = output["evalue"].str;
                }
            }
        }

        return cell;
    }

    /**
     * Check if this is a code cell
     */
    bool isCodeCell() const {
        return _type == CellType.Code;
    }

    /**
     * Check if this is a markdown cell
     */
    bool isMarkdownCell() const {
        return _type == CellType.Markdown;
    }
}

/**
 * Notebook section for organizing cells
 */
class NotebookSection {
    private string _id;
    private string _name;
    private int _level;
    private NotebookCell[] _cells;
    private NotebookSection _parentSection;
    private bool _isBranching;

    // Signals
    Signal!() onCellsChanged;
    Signal!(NotebookCell) onCellAdded;
    Signal!(NotebookCell) onCellRemoved;

    /**
     * Constructor
     */
    this(string name, int level = 1) {
        _id = randomUUID().toString();
        _name = name;
        _level = level;
        _isBranching = false;
    }

    // Properties
    @property string id() const { return _id; }
    @property string name() const { return _name; }
    @property void name(string value) { _name = value; }
    @property int level() const { return _level; }
    @property void level(int value) { _level = value; }
    @property bool isBranching() const { return _isBranching; }
    @property void isBranching(bool value) { _isBranching = value; }
    @property NotebookSection parentSection() { return _parentSection; }
    @property void parentSection(NotebookSection parent) { _parentSection = parent; }

    /**
     * Get all cells in this section
     */
    NotebookCell[] cells() const {
        NotebookCell[] result;
        foreach (cell; _cells) {
            result ~= cast(NotebookCell)cell;
        }
        return result;
    }

    /**
     * Get cell count
     */
    size_t cellCount() const {
        return _cells.length;
    }

    /**
     * Add a cell to this section
     */
    void addCell(NotebookCell cell, int index = -1) {
        if (index < 0 || index >= _cells.length) {
            _cells ~= cell;
        } else {
            _cells = _cells[0..index] ~ [cell] ~ _cells[index..$];
        }
        onCellAdded.emit(cell);
        onCellsChanged.emit();
    }

    /**
     * Remove a cell from this section
     */
    bool removeCell(NotebookCell cell) {
        auto index = _cells.countUntil(cell);
        if (index >= 0) {
            _cells = _cells[0..index] ~ _cells[index+1..$];
            onCellRemoved.emit(cell);
            onCellsChanged.emit();
            return true;
        }
        return false;
    }

    /**
     * Remove cell by index
     */
    bool removeCell(size_t index) {
        if (index < _cells.length) {
            auto cell = _cells[index];
            _cells = _cells[0..index] ~ _cells[index+1..$];
            onCellRemoved.emit(cell);
            onCellsChanged.emit();
            return true;
        }
        return false;
    }

    /**
     * Get cell by index
     */
    NotebookCell getCell(size_t index) {
        if (index < _cells.length) {
            return _cells[index];
        }
        return null;
    }

    /**
     * Move cell to different position within section
     */
    bool moveCell(size_t fromIndex, size_t toIndex) {
        if (fromIndex >= _cells.length || toIndex >= _cells.length) {
            return false;
        }

        if (fromIndex == toIndex) {
            return true;
        }

        auto cell = _cells[fromIndex];

        // Remove from old position
        _cells = _cells[0..fromIndex] ~ _cells[fromIndex+1..$];

        // Adjust toIndex if necessary
        if (toIndex > fromIndex) {
            toIndex--;
        }

        // Insert at new position
        _cells = _cells[0..toIndex] ~ [cell] ~ _cells[toIndex..$];
        onCellsChanged.emit();

        return true;
    }
}

/**
 * Main notebook class
 */
class Notebook {
    private string _id;
    private string _name;
    private string _filePath;
    private NotebookSection[] _sections;
    private JSONValue _metadata;
    private string _kernelName;
    private bool _modified;
    private SysTime _created;
    private SysTime _lastSaved;

    // Notebook format version
    private static immutable int NOTEBOOK_FORMAT_VERSION = 1;

    // Signals
    Signal!() onChanged;
    Signal!() onSaved;
    Signal!(NotebookSection) onSectionAdded;
    Signal!(NotebookSection) onSectionRemoved;
    Signal!(NotebookCell) onCellExecuted;

    /**
     * Constructor
     */
    this(string name = "Untitled Notebook") {
        _id = randomUUID().toString();
        _name = name;
        _kernelName = "d"; // Default to D language kernel
        _modified = false;
        _created = Clock.currTime();
        _metadata = JSONValue.emptyObject;

        // Create default section
        auto defaultSection = new NotebookSection("Main", 1);
        _sections ~= defaultSection;

        // Add welcome cell
        auto welcomeCell = new NotebookCell(CellType.Markdown,
            "# " ~ _name ~ "\n\nWelcome to your new D notebook!\n\n" ~
            "This is a **Markdown cell**. Double-click to edit.\n\n" ~
            "Use the toolbar to add new cells for code and documentation.");
        defaultSection.addCell(welcomeCell);
    }

    // Properties
    @property string id() const { return _id; }
    @property string name() const { return _name; }
    @property void name(string value) {
        if (_name != value) {
            _name = value;
            _modified = true;
            onChanged.emit();
        }
    }

    @property string filePath() const { return _filePath; }
    @property void filePath(string value) { _filePath = value; }

    @property string kernelName() const { return _kernelName; }
    @property void kernelName(string value) {
        if (_kernelName != value) {
            _kernelName = value;
            _modified = true;
            onChanged.emit();
        }
    }

    @property bool modified() const { return _modified; }
    @property SysTime created() const { return _created; }
    @property SysTime lastSaved() const { return _lastSaved; }

    @property JSONValue metadata() const { return _metadata; }
    @property void metadata(JSONValue value) {
        _metadata = value;
        _modified = true;
    }

    /**
     * Get all sections
     */
    NotebookSection[] sections() {
        return _sections.dup;
    }

    /**
     * Get section count
     */
    size_t sectionCount() const {
        return _sections.length;
    }

    /**
     * Add a new section
     */
    void addSection(NotebookSection section, int index = -1) {
        if (index < 0 || index >= _sections.length) {
            _sections ~= section;
        } else {
            _sections = _sections[0..index] ~ [section] ~ _sections[index..$];
        }

        _modified = true;
        onSectionAdded.emit(section);
        onChanged.emit();
    }

    /**
     * Remove a section
     */
    bool removeSection(NotebookSection section) {
        auto index = _sections.countUntil(section);
        if (index >= 0) {
            _sections = _sections[0..index] ~ _sections[index+1..$];
            _modified = true;
            onSectionRemoved.emit(section);
            onChanged.emit();
            return true;
        }
        return false;
    }

    /**
     * Get section by index
     */
    NotebookSection getSection(size_t index) {
        if (index < _sections.length) {
            return _sections[index];
        }
        return null;
    }

    /**
     * Get all cells across all sections
     */
    NotebookCell[] getAllCells() {
        NotebookCell[] allCells;
        foreach (section; _sections) {
            allCells ~= section.cells();
        }
        return allCells;
    }

    /**
     * Get all code cells
     */
    NotebookCell[] getCodeCells() {
        return getAllCells().filter!(cell => cell.isCodeCell()).array;
    }

    /**
     * Add a cell to the first section
     */
    void addCell(NotebookCell cell, int index = -1) {
        if (_sections.length == 0) {
            auto defaultSection = new NotebookSection("Main", 1);
            _sections ~= defaultSection;
        }

        _sections[0].addCell(cell, index);
        _modified = true;
        onChanged.emit();
    }

    /**
     * Create and add a new cell
     */
    NotebookCell createCell(CellType type, string source = "", int sectionIndex = 0, int cellIndex = -1) {
        auto cell = new NotebookCell(type, source);

        if (sectionIndex >= 0 && sectionIndex < _sections.length) {
            _sections[sectionIndex].addCell(cell, cellIndex);
        } else {
            addCell(cell, cellIndex);
        }

        return cell;
    }

    /**
     * Save notebook to file
     */
    bool save(string filePath = "") {
        if (filePath.length > 0) {
            _filePath = filePath;
        }

        if (_filePath.length == 0) {
            Log.w("Cannot save notebook: no file path specified");
            return false;
        }

        try {
            auto json = toJSON();
            auto jsonStr = json.toPrettyString();
            std.file.write(_filePath, jsonStr);

            _modified = false;
            _lastSaved = Clock.currTime();
            onSaved.emit();

            Log.i("Notebook saved to: ", _filePath);
            return true;
        } catch (Exception e) {
            Log.e("Failed to save notebook: ", e.msg);
            return false;
        }
    }

    /**
     * Load notebook from file
     */
    static Notebook load(string filePath) {
        try {
            auto content = cast(string)std.file.read(filePath);
            auto json = parseJSON(content);

            auto notebook = fromJSON(json);
            notebook._filePath = filePath;
            notebook._modified = false;
            notebook._lastSaved = Clock.currTime();

            Log.i("Notebook loaded from: ", filePath);
            return notebook;
        } catch (Exception e) {
            Log.e("Failed to load notebook from ", filePath, ": ", e.msg);
            return null;
        }
    }

    /**
     * Convert notebook to JSON
     */
    JSONValue toJSON() const {
        JSONValue json = JSONValue.emptyObject;

        json["notebook_format_version"] = NOTEBOOK_FORMAT_VERSION;
        json["id"] = _id;
        json["name"] = _name;
        json["kernel_name"] = _kernelName;
        json["metadata"] = _metadata;
        json["created"] = _created.toISOExtString();

        // Serialize sections and cells
        JSONValue sectionsJson = JSONValue.emptyArray;
        foreach (section; _sections) {
            JSONValue sectionJson = JSONValue.emptyObject;
            sectionJson["id"] = section.id;
            sectionJson["name"] = section.name;
            sectionJson["level"] = section.level;
            sectionJson["is_branching"] = section.isBranching;

            JSONValue cellsJson = JSONValue.emptyArray;
            foreach (cell; section.cells()) {
                cellsJson.array ~= cell.toJSON();
            }
            sectionJson["cells"] = cellsJson;

            sectionsJson.array ~= sectionJson;
        }
        json["sections"] = sectionsJson;

        return json;
    }

    /**
     * Load notebook from JSON
     */
    static Notebook fromJSON(JSONValue json) {
        string id = json["id"].str;
        string name = json["name"].str;
        string kernelName = ("kernel_name" in json) ? json["kernel_name"].str : "d";

        auto notebook = new Notebook(name);
        notebook._id = id;
        notebook._kernelName = kernelName;

        if ("metadata" in json) {
            notebook._metadata = json["metadata"];
        }

        if ("created" in json) {
            try {
                notebook._created = SysTime.fromISOExtString(json["created"].str);
            } catch (Exception e) {
                Log.w("Failed to parse notebook creation time: ", e.msg);
            }
        }

        // Clear default section
        notebook._sections.length = 0;

        // Load sections
        if ("sections" in json && json["sections"].type == JSONType.array) {
            foreach (sectionJson; json["sections"].array) {
                string sectionId = sectionJson["id"].str;
                string sectionName = sectionJson["name"].str;
                int level = cast(int)(("level" in sectionJson) ? sectionJson["level"].integer : 1);
                bool isBranching = ("is_branching" in sectionJson) ? sectionJson["is_branching"].boolean : false;

                auto section = new NotebookSection(sectionName, level);
                section._id = sectionId;
                section._isBranching = isBranching;

                // Load cells
                if ("cells" in sectionJson && sectionJson["cells"].type == JSONType.array) {
                    foreach (cellJson; sectionJson["cells"].array) {
                        auto cell = NotebookCell.fromJSON(cellJson);
                        section.addCell(cell);
                    }
                }

                notebook._sections ~= section;
            }
        }

        return notebook;
    }

    /**
     * Export to LiveMD format (Elixir LiveBook compatible)
     */
    string toLiveMD() const {
        string content = "# " ~ _name ~ "\n\n";

        foreach (section; _sections) {
            // Add section header
            string headerLevel = "#".replicate(section.level + 1);
            content ~= headerLevel ~ " " ~ section.name ~ "\n\n";

            if (section.isBranching) {
                content ~= "<!-- livebook:{\"branch_parent_index\":0} -->\n\n";
            }

            foreach (cell; section.cells()) {
                switch (cell.type) {
                    case CellType.Markdown:
                        content ~= cell.source ~ "\n\n";
                        break;

                    case CellType.Code:
                        content ~= "```" ~ _kernelName ~ "\n";
                        content ~= cell.source ~ "\n";
                        content ~= "```\n\n";
                        break;

                    case CellType.Raw:
                        content ~= "```\n";
                        content ~= cell.source ~ "\n";
                        content ~= "```\n\n";
                        break;

                    default:
                        break;
                }
            }
        }

        return content;
    }

    /**
     * Mark notebook as modified
     */
    void markModified() {
        if (!_modified) {
            _modified = true;
            onChanged.emit();
        }
    }

    /**
     * Get notebook statistics
     */
    struct NotebookStats {
        size_t totalCells;
        size_t markdownCells;
        size_t codeCells;
        size_t rawCells;
        size_t executedCells;
        size_t sections;
    }

    NotebookStats getStats() const {
        NotebookStats stats;
        stats.sections = _sections.length;

        foreach (section; _sections) {
            foreach (cell; section.cells()) {
                stats.totalCells++;

                switch (cell.type) {
                    case CellType.Markdown:
                        stats.markdownCells++;
                        break;
                    case CellType.Code:
                        stats.codeCells++;
                        if (cell.executionCount > 0) {
                            stats.executedCells++;
                        }
                        break;
                    case CellType.Raw:
                        stats.rawCells++;
                        break;
                    default:
                        break;
                }
            }
        }

        return stats;
    }
}
