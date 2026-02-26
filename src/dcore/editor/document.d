module dcore.editor.document;

import dlangui.core.signals;
import dlangui.core.logger;

import std.algorithm;
import std.array;
import std.conv;
import std.string;
import std.utf;

/**
 * Document - Text document model for the editor
 *
 * Responsible for:
 * - Managing text content
 * - Tracking lines and positions
 * - Undo/redo functionality
 * - Text change events
 */
class Document {
    // Signals
    import dcore.utils.signals : Signal;
    Signal!() onTextChanged;
    Signal!(int, int, int) onLinesChanged; // startLine, removedLines, addedLines
    
    // Document content
    private dstring[] _lines;
    private string _eol = "\n";
    
    // Undo/redo stack
    private struct EditOperation {
        enum OperationType {
            Insert,
            Delete,
            Replace
        }
        
        OperationType type;
        int position;
        dstring textBefore;
        dstring textAfter;
        int[] selectionBefore;
        int[] selectionAfter;
    }
    
    private EditOperation[] _undoStack;
    private EditOperation[] _redoStack;
    private bool _undoRedoEnabled = true;
    private bool _inUndoRedo = false;
    
    // Change tracking
    private bool _modified = false;
    
    /**
     * Constructor
     */
    this() {
        clear();
    }
    
    /**
     * Clear document
     */
    void clear() {
        _lines = [""];
        clearUndoRedo();
        _modified = false;
        onTextChanged.emit();
    }
    
    /**
     * Set text content
     */
    void setText(dstring content) {
        // Split content into lines
        _lines = splitLines(content);
        
        // Ensure at least one line
        if (_lines.length == 0)
            _lines = [""];
            
        clearUndoRedo();
        _modified = false;
        onTextChanged.emit();
        onLinesChanged.emit(0, 0, cast(int)_lines.length);
    }
    
    /**
     * Set text content (UTF-8 string)
     */
    void setText(string content) {
        setText(content.toUTF32);
    }
    
    /**
     * Get text content
     */
    dstring getText() {
        return join(_lines, dchar('\n'));
    }
    
    /**
     * Get line count
     */
    @property int lineCount() {
        return cast(int)_lines.length;
    }
    
    /**
     * Get line content
     */
    dstring getLine(int lineIndex) {
        if (lineIndex < 0 || lineIndex >= _lines.length)
            return "";
        return _lines[lineIndex];
    }
    
    /**
     * Get all lines
     */
    dstring[] getLines() {
        return _lines.dup;
    }
    
    /**
     * Insert text at position
     */
    void insertText(int position, dstring text) {
        if (position < 0)
            position = 0;
            
        // Calculate line and column
        int line, column;
        positionToLineColumn(position, line, column);
        
        // If inserting at end of document
        if (line >= _lines.length) {
            line = cast(int)_lines.length - 1;
            column = cast(int)_lines[line].length;
        }
        
        if (text.indexOf('\n') < 0) {
            // Simple case - inserting within a line
            dstring lineText = _lines[line];
            dstring newLine = lineText[0..column] ~ text ~ lineText[column..$];
            
            // Save for undo
            if (_undoRedoEnabled && !_inUndoRedo) {
                EditOperation op;
                op.type = EditOperation.OperationType.Insert;
                op.position = position;
                op.textBefore = "";
                op.textAfter = text;
                _undoStack ~= op;
                _redoStack.length = 0;
            }
            
            // Update line
            _lines[line] = newLine;
            _modified = true;
            
            onTextChanged.emit();
        } else {
            // Complex case - inserting across multiple lines
            dstring[] newLines = splitLines(text);
            
            // Get current line
            dstring currentLine = _lines[line];
            
            // First line: combine start of current line with first new line
            dstring firstLine = currentLine[0..column] ~ newLines[0];
            
            // Last line: combine last new line with end of current line
            dstring lastLine = newLines[$-1] ~ currentLine[column..$];
            
            // Save for undo
            if (_undoRedoEnabled && !_inUndoRedo) {
                EditOperation op;
                op.type = EditOperation.OperationType.Insert;
                op.position = position;
                op.textBefore = "";
                op.textAfter = text;
                _undoStack ~= op;
                _redoStack.length = 0;
            }
            
            // Construct new set of lines
            dstring[] updatedLines;
            updatedLines ~= firstLine;
            
            // Add all middle lines
            if (newLines.length > 2) {
                foreach (newLine; newLines[1..$-1]) {
                    updatedLines ~= newLine;
                }
            }
            
            updatedLines ~= lastLine;
            
            // Replace the original line with our updated lines
            auto linesRemoved = 1;
            auto linesAdded = cast(int)updatedLines.length;
            
            _lines = _lines[0..line] ~ updatedLines ~ _lines[line+1..$];
            _modified = true;
            
            onTextChanged.emit();
            onLinesChanged.emit(line, linesRemoved, linesAdded);
        }
    }
    
    /**
     * Delete text range
     */
    void deleteText(int start, int end) {
        if (start > end) {
            auto temp = start;
            start = end;
            end = temp;
        }
        
        if (start < 0)
            start = 0;
        
        // Calculate lines and columns
        int startLine, startColumn, endLine, endColumn;
        positionToLineColumn(start, startLine, startColumn);
        positionToLineColumn(end, endLine, endColumn);
        
        // Get deleted text for undo
        dstring deletedText = getTextRange(start, end);
        
        if (startLine == endLine) {
            // Deleting within a single line
            dstring line = _lines[startLine];
            dstring newLine = line[0..startColumn] ~ line[endColumn..$];
            
            // Save for undo
            if (_undoRedoEnabled && !_inUndoRedo) {
                EditOperation op;
                op.type = EditOperation.OperationType.Delete;
                op.position = start;
                op.textBefore = deletedText;
                op.textAfter = "";
                _undoStack ~= op;
                _redoStack.length = 0;
            }
            
            // Update line
            _lines[startLine] = newLine;
            _modified = true;
            
            onTextChanged.emit();
        } else {
            // Deleting across multiple lines
            dstring firstLinePart = _lines[startLine][0..startColumn];
            dstring lastLinePart = _lines[endLine][endColumn..$];
            
            // Save for undo
            if (_undoRedoEnabled && !_inUndoRedo) {
                EditOperation op;
                op.type = EditOperation.OperationType.Delete;
                op.position = start;
                op.textBefore = deletedText;
                op.textAfter = "";
                _undoStack ~= op;
                _redoStack.length = 0;
            }
            
            // Create merged line
            dstring mergedLine = firstLinePart ~ lastLinePart;
            
            // Update lines array
            auto linesRemoved = endLine - startLine + 1;
            auto linesAdded = 1;
            
            _lines = _lines[0..startLine] ~ [mergedLine] ~ _lines[endLine+1..$];
            _modified = true;
            
            onTextChanged.emit();
            onLinesChanged.emit(startLine, linesRemoved, linesAdded);
        }
    }
    
    /**
     * Replace text range
     */
    void replaceText(int start, int end, dstring newText) {
        if (start > end) {
            auto temp = start;
            start = end;
            end = temp;
        }
        
        if (start < 0)
            start = 0;
            
        // Get text being replaced for undo
        dstring oldText = getTextRange(start, end);
        
        // Save for undo
        if (_undoRedoEnabled && !_inUndoRedo) {
            EditOperation op;
            op.type = EditOperation.OperationType.Replace;
            op.position = start;
            op.textBefore = oldText;
            op.textAfter = newText;
            _undoStack ~= op;
            _redoStack.length = 0;
        }
        
        // Delete then insert
        deleteText(start, end);
        insertText(start, newText);
    }
    
    /**
     * Undo last edit
     */
    bool undo() {
        if (_undoStack.length == 0)
            return false;
            
        // Get last operation
        EditOperation op = _undoStack[$-1];
        _undoStack.length = _undoStack.length - 1;
        
        // Disable undo recording during undo operation
        _inUndoRedo = true;
        
        // Perform the inverse operation
        switch (op.type) {
            case EditOperation.OperationType.Insert:
                deleteText(op.position, op.position + cast(int)op.textAfter.length);
                break;
                
            case EditOperation.OperationType.Delete:
                insertText(op.position, op.textBefore);
                break;
                
            case EditOperation.OperationType.Replace:
                replaceText(op.position, op.position + cast(int)op.textAfter.length, op.textBefore);
                break;
                
            default:
                break;
        }
        
        // Add to redo stack
        _redoStack ~= op;
        
        // Re-enable undo recording
        _inUndoRedo = false;
        
        return true;
    }
    
    /**
     * Redo last undone edit
     */
    bool redo() {
        if (_redoStack.length == 0)
            return false;
            
        // Get last operation
        EditOperation op = _redoStack[$-1];
        _redoStack.length = _redoStack.length - 1;
        
        // Disable undo recording during redo operation
        _inUndoRedo = true;
        
        // Perform the operation
        switch (op.type) {
            case EditOperation.OperationType.Insert:
                insertText(op.position, op.textAfter);
                break;
                
            case EditOperation.OperationType.Delete:
                deleteText(op.position, op.position + cast(int)op.textBefore.length);
                break;
                
            case EditOperation.OperationType.Replace:
                replaceText(op.position, op.position + cast(int)op.textBefore.length, op.textAfter);
                break;
                
            default:
                break;
        }
        
        // Add to undo stack
        _undoStack ~= op;
        
        // Re-enable undo recording
        _inUndoRedo = false;
        
        return true;
    }
    
    /**
     * Clear undo/redo stacks
     */
    void clearUndoRedo() {
        _undoStack.length = 0;
        _redoStack.length = 0;
    }
    
    /**
     * Enable/disable undo/redo
     */
    void setUndoRedoEnabled(bool enabled) {
        _undoRedoEnabled = enabled;
    }
    
    /**
     * Get modified state
     */
    @property bool modified() {
        return _modified;
    }
    
    /**
     * Reset modified state
     */
    void resetModified() {
        _modified = false;
    }
    
    /**
     * Convert position to line and column
     */
    void positionToLineColumn(int position, out int line, out int column) {
        line = 0;
        column = 0;
        
        if (position <= 0)
            return;
            
        int currentPos = 0;
        foreach (lineIndex, lineText; _lines) {
            int lineLength = cast(int)lineText.length + 1; // +1 for newline
            
            if (currentPos + lineLength > position) {
                line = cast(int)lineIndex;
                column = position - currentPos;
                return;
            }
            
            currentPos += lineLength;
        }
        
        // If position is beyond the document, set to end
        line = cast(int)_lines.length - 1;
        column = cast(int)_lines[line].length;
    }
    
    /**
     * Convert line and column to position
     */
    int lineColumnToPosition(int line, int column) {
        if (line < 0)
            line = 0;
            
        if (line >= _lines.length)
            line = cast(int)_lines.length - 1;
            
        if (column < 0)
            column = 0;
            
        if (column > _lines[line].length)
            column = cast(int)_lines[line].length;
            
        int position = 0;
        for (int i = 0; i < line; i++) {
            position += cast(int)_lines[i].length + 1; // +1 for newline
        }
        
        position += column;
        return position;
    }
    
    /**
     * Get text range
     */
    dstring getTextRange(int start, int end) {
        if (start > end) {
            auto temp = start;
            start = end;
            end = temp;
        }
        
        if (start < 0)
            start = 0;
            
        // Calculate lines and columns
        int startLine, startColumn, endLine, endColumn;
        positionToLineColumn(start, startLine, startColumn);
        positionToLineColumn(end, endLine, endColumn);
        
        if (startLine == endLine) {
            // Range within a single line
            return _lines[startLine][startColumn..endColumn];
        } else {
            // Range across multiple lines
            dstring result = _lines[startLine][startColumn..$] ~ dchar('\n');
            
            // Add intermediate lines
            for (int i = startLine + 1; i < endLine; i++) {
                result ~= _lines[i] ~ dchar('\n');
            }
            
            // Add last line part
            result ~= _lines[endLine][0..endColumn];
            
            return result;
        }
    }
    
    /**
     * Split text into lines
     */
    private dstring[] splitLines(dstring text) {
        if (text.length == 0)
            return [""];
            
        dstring[] result;
        
        size_t start = 0;
        for (size_t i = 0; i < text.length; i++) {
            if (text[i] == '\n') {
                result ~= text[start..i];
                start = i + 1;
            }
        }
        
        // Add last line
        if (start <= text.length)
            result ~= text[start..$];
            
        if (result.length == 0)
            result = [""];
            
        return result;
    }
}