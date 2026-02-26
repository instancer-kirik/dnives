module dcore.widgets.terminal;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.math;
import std.random;
import std.range;
import std.string;
import std.stdio;
import std.utf;

import dlangui;
import dlangui.core.events;
import dlangui.core.signals;
import dlangui.graphics.colors;
import dlangui.graphics.drawbuf;
import dlangui.widgets.editors;
import dlangui.widgets.controls;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.core.logger;

import core.time;

/**
 * TerminalEffect - Type of visual effect to display
 */
enum TerminalEffect {
    None,           // No effect
    Spark,          // Small spark particles
    Explosion,      // Larger explosion
    Matrix,         // Matrix-style falling characters
    Rainbow,        // Rainbow text color
    Typing,         // Typewriter effect
    Glitch,         // Glitch effect
    Fire            // Fire effect under text
}

/**
 * TerminalEffectParticle - A single particle in an effect
 */
struct TerminalEffectParticle {
    float x;
    float y;
    float vx;
    float vy;
    uint color;
    int life;
    int lifeMax;
    float size;
    dchar character;
    
    void update() {
        x += vx;
        y += vy;
        life--;
        
        // Add gravity for some effects
        vy += 0.05f;
    }
}

/**
 * TerminalWidget - Terminal emulator with visual effects
 */
class TerminalWidget : VerticalLayout {
    private EditBox _textbox;
    private string _prompt = "> ";
    private dstring _history;
    private int _maxHistoryLines = 1000;
    
    // Command execution
    private string _currentCommand;
    void delegate(string) onCommandExecuted;
    
    // Visual effects
    private TerminalEffectParticle[] _particles;
    private TerminalEffect _currentEffect = TerminalEffect.None;
    import dcore.utils.timer : Timer;
    private Timer _effectTimer;
    private Random _rnd;
    
    // Text style
    private uint _textColor = 0x00FF00;        // Default green text
    private uint _backgroundColor = 0x000F1F;   // Dark blue-black background
    private string _fontFace = "DejaVu Sans Mono";
    private int _fontSize = 14;
    
    // Rainbow effect
    private int _rainbowPhase = 0;
    private bool _rainbowEnabled = false;
    
    /**
     * Constructor
     */
    this(string id = null) {
        super(id);
        
        // Initialize random number generator
        _rnd = Random(unpredictableSeed);
        
        // Create edit box for terminal
        _textbox = new EditBox("TERMINAL_TEXT");
        _textbox.fontSize = _fontSize;
        _textbox.fontFace = _fontFace;
        _textbox.backgroundColor = _backgroundColor;
        _textbox.textColor = _textColor;
        _textbox.layoutWidth = FILL_PARENT;
        _textbox.layoutHeight = FILL_PARENT;
        _textbox.readOnly = false;
        _textbox.wordWrap = true;
        _textbox.focusable = true;
        
        // Handle key events
        _textbox.keyEvent = &onKeyEvent;
        
        // Add to layout
        addChild(_textbox);
        
        // Initialize with prompt
        clear();
        
        // Setup timer for effects
        _effectTimer = new Timer(16, &updateEffects, true);
    }
    
    /**
     * Handle key events
     */
    bool onKeyEvent(Widget source, KeyEvent event) {
        if (event.action == KeyAction.KeyDown) {
            if (event.keyCode == KeyCode.RETURN) {
                // Execute command on Enter
                executeCommand();
                return true;
            } else if (event.keyCode >= KeyCode.KEY_A && event.keyCode <= KeyCode.KEY_Z) {
                // Show effect on keypress
                randomEffect();
            }
        }
        return false;
    }
    
    /**
     * Execute the current command
     */
    void executeCommand() {
        // Get current command from last line
        dstring text = _textbox.text;
        int lastPromptPos = cast(int)text.lastIndexOf(toUTF32(_prompt));
        if (lastPromptPos < 0) return;
        
        dstring cmdLine = text[lastPromptPos + _prompt.length .. $].strip();
        string cmd = std.utf.toUTF8(cmdLine);
        
        // Add command to history
        _history ~= text;
        
        // Show command effect if it's a special command
        if (cmd == "explosion") {
            showEffect(TerminalEffect.Explosion);
        } else if (cmd == "spark") {
            showEffect(TerminalEffect.Spark);
        } else if (cmd == "matrix") {
            showEffect(TerminalEffect.Matrix);
        } else if (cmd == "rainbow") {
            toggleRainbowText();
        } else if (cmd == "glitch") {
            showEffect(TerminalEffect.Glitch);
        } else if (cmd == "fire") {
            showEffect(TerminalEffect.Fire);
        } else if (cmd.startsWith("color ")) {
            // Change text color
            try {
                string colorStr = cmd[6..$];
                setTextColor(parseHexString(colorStr));
            } catch (Exception e) {
                writeln(std.utf.toUTF8(text) ~ "\nInvalid color. Format: color RRGGBB");
            }
        } else {
            // Notify listeners
            if (onCommandExecuted)
                onCommandExecuted(cmd);
        }
        
        // Add new line with prompt
        _textbox.text = text ~ "\n" ~ toUTF32(_prompt);
        
        // Scroll to bottom
        // _textbox.scrollToEnd(); // scrollToEnd method doesn't exist
        // Scroll to bottom manually if needed
    }
    
    /**
     * Parse hex color string
     */
    uint parseHexString(string hex) {
        if (hex.startsWith("#"))
            hex = hex[1..$];
            
        return to!uint(hex, 16);
    }
    
    /**
     * Show a specific effect
     */
    void showEffect(TerminalEffect effect) {
        _currentEffect = effect;
        
        // Clear existing particles
        _particles.length = 0;
        
        // Create particles based on effect type
        final switch(effect) {
            case TerminalEffect.None:
                break;
                
            case TerminalEffect.Spark:
                createSparkEffect();
                break;
                
            case TerminalEffect.Explosion:
                createExplosionEffect();
                break;
                
            case TerminalEffect.Matrix:
                createMatrixEffect();
                break;
                
            case TerminalEffect.Rainbow:
                // Handled by drawing
                break;
                
            case TerminalEffect.Typing:
                // Handled by text input
                break;
                
            case TerminalEffect.Glitch:
                createGlitchEffect();
                break;
                
            case TerminalEffect.Fire:
                createFireEffect();
                break;
        }
        
        // Start effect timer if not already running
        // if (!_effectTimer.isActive) // isActive property doesn't exist
            _effectTimer.start();
    }
    
    /**
     * Toggle rainbow text mode
     */
    void toggleRainbowText() {
        _rainbowEnabled = !_rainbowEnabled;
        
        // Start or stop effect timer based on rainbow state
        if (_rainbowEnabled) // && !_effectTimer.isActive) // isActive property doesn't exist
            _effectTimer.start();
    }
    
    /**
     * Update visual effects
     */
    bool updateEffects() {
        // Update rainbow effect
        if (_rainbowEnabled) {
            _rainbowPhase = (_rainbowPhase + 1) % 360;
            
            // Apply rainbow colors to text
            dstring text = _textbox.text;
            _textbox.textColor = rainbowColor(_rainbowPhase);
            invalidate();
        }
        
        // Update particles
        if (_particles.length > 0) {
            foreach (ref particle; _particles) {
                particle.update();
            }
            
            // Remove dead particles
            _particles = _particles.filter!(p => p.life > 0).array;
            invalidate();
        }
        
        // Stop timer if nothing to update
        if (_particles.length == 0 && !_rainbowEnabled) {
            _currentEffect = TerminalEffect.None;
            _effectTimer.stop();
        }
        
        return true;
    }
    
    /**
     * Calculate rainbow color
     */
    uint rainbowColor(int phase) {
        float frequency = 0.1;
        int r = cast(int)(sin(frequency * phase + 0) * 127 + 128);
        int g = cast(int)(sin(frequency * phase + 2) * 127 + 128);
        int b = cast(int)(sin(frequency * phase + 4) * 127 + 128);
        
        return 0xFF000000 | (r << 16) | (g << 8) | b;
    }
    
    /**
     * Create spark effect particles
     */
    void createSparkEffect() {
        int sparkCount = uniform(20, 40, _rnd);
        // Convert TextPosition to Point
        auto textPos = _textbox.caretPos;
        Point cursorPos = Point(textPos.pos, textPos.line);
        
        for (int i = 0; i < sparkCount; i++) {
            TerminalEffectParticle particle;
            particle.x = cursorPos.x + uniform(-2.0f, 2.0f, _rnd);
            particle.y = cursorPos.y + uniform(-2.0f, 2.0f, _rnd);
            particle.vx = uniform(-3.0f, 3.0f, _rnd);
            particle.vy = uniform(-8.0f, -2.0f, _rnd); // Initial upward velocity
            
            // Yellow-orange sparks
            float hue = uniform(20.0f, 60.0f, _rnd); // Hue in HSV (degrees)
            float saturation = uniform(0.7f, 1.0f, _rnd);
            float value = 1.0f;
            particle.color = hsvToRgb(hue, saturation, value);
            
            particle.life = uniform(10, 30, _rnd);
            particle.lifeMax = particle.life;
            particle.size = uniform(1.0f, 3.0f, _rnd);
            
            _particles ~= particle;
        }
    }
    
    /**
     * Create explosion effect particles
     */
    void createExplosionEffect() {
        int particleCount = uniform(100, 200, _rnd);
        // Convert TextPosition to Point
        auto textPos = _textbox.caretPos;
        Point cursorPos = Point(textPos.pos, textPos.line);
        
        for (int i = 0; i < particleCount; i++) {
            TerminalEffectParticle particle;
            
            // Random angle and distance from center
            float angle = uniform(0.0f, 2.0f * PI, _rnd);
            float speed = uniform(2.0f, 10.0f, _rnd);
            
            particle.x = cursorPos.x;
            particle.y = cursorPos.y;
            particle.vx = cos(angle) * speed;
            particle.vy = sin(angle) * speed;
            
            // Fire colors (red, orange, yellow)
            float hue = uniform(0.0f, 60.0f, _rnd); // Hue in HSV (degrees)
            float saturation = uniform(0.7f, 1.0f, _rnd);
            float value = uniform(0.7f, 1.0f, _rnd);
            particle.color = hsvToRgb(hue, saturation, value);
            
            particle.life = uniform(20, 60, _rnd);
            particle.lifeMax = particle.life;
            particle.size = uniform(2.0f, 5.0f, _rnd);
            
            _particles ~= particle;
        }
    }
    
    /**
     * Create matrix effect particles
     */
    void createMatrixEffect() {
        // Rect rect = _textbox.contentRect; // contentRect property doesn't exist
        Rect rect = _textbox.pos; // Use widget position instead
        int cols = rect.width / 10; // Approximate character width
        
        for (int i = 0; i < cols; i++) {
            int streamerLength = uniform(5, 20, _rnd);
            int xPos = i * 10 + uniform(-2, 2, _rnd);
            
            for (int j = 0; j < streamerLength; j++) {
                TerminalEffectParticle particle;
                particle.x = xPos;
                particle.y = uniform(-100, rect.height, _rnd);
                particle.vx = 0;
                particle.vy = uniform(1.0f, 5.0f, _rnd);
                
                // Matrix green with varying brightness
                float brightness = 1.0f - (cast(float)j / streamerLength * 0.8f);
                particle.color = 0xFF000000 | 
                                 (cast(uint)(30 * brightness) << 16) | 
                                 (cast(uint)(255 * brightness) << 8) | 
                                 (cast(uint)(30 * brightness));
                
                // Random matrix-like character
                auto possibleChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+=-";
                particle.character = possibleChars[uniform(0, possibleChars.length, _rnd)];
                
                particle.life = uniform(50, 150, _rnd);
                particle.lifeMax = particle.life;
                
                _particles ~= particle;
            }
        }
    }
    
    /**
     * Create glitch effect particles
     */
    void createGlitchEffect() {
        // Create random text blocks that move
        // Rect rect = _textbox.contentRect; // contentRect property doesn't exist
        Rect rect = _textbox.pos; // pos is already a Rect
        int blockCount = uniform(5, 15, _rnd);
        
        for (int i = 0; i < blockCount; i++) {
            TerminalEffectParticle particle;
            particle.x = uniform(0, rect.width, _rnd);
            particle.y = uniform(0, rect.height, _rnd);
            particle.vx = uniform(-5.0f, 5.0f, _rnd);
            particle.vy = uniform(-2.0f, 2.0f, _rnd);
            
            // Glitch colors (bright)
            uint[] glitchColors = [
                0xFFFF0000, // Red
                0xFF00FF00, // Green
                0xFF0000FF, // Blue
                0xFFFFFF00, // Yellow
                0xFF00FFFF, // Cyan
                0xFFFF00FF  // Magenta
            ];
            particle.color = glitchColors[uniform(0, glitchColors.length, _rnd)];
            
            // Random glitchy character
            auto glitchChars = "▓▒░█▇▆▅▃▂▁◢◣◤◥■□▪▫●○◐◑◒◓◴◵◶◷";
            particle.character = glitchChars[uniform(0, glitchChars.length, _rnd)];
            
            particle.life = uniform(10, 30, _rnd);
            particle.lifeMax = particle.life;
            particle.size = uniform(10.0f, 30.0f, _rnd);
            
            _particles ~= particle;
        }
    }
    
    /**
     * Create fire effect particles
     */
    void createFireEffect() {
        // Rect rect = _textbox.contentRect; // contentRect property doesn't exist
        Rect rect = _textbox.pos; // pos is already a Rect
        // Point cursorPos = _textbox.caretPos; // caretPos returns TextPosition, not Point
        auto textPos = _textbox.caretPos;
        Point cursorPos = Point(textPos.pos, textPos.line);
        
        int fireWidth = 200;
        int particleCount = uniform(50, 100, _rnd);
        
        for (int i = 0; i < particleCount; i++) {
            TerminalEffectParticle particle;
            particle.x = cursorPos.x + uniform(-fireWidth/2, fireWidth/2, _rnd);
            particle.y = cursorPos.y + uniform(0, 10, _rnd);
            particle.vx = uniform(-1.0f, 1.0f, _rnd);
            particle.vy = uniform(-6.0f, -1.0f, _rnd);
            
            // Fire gradient from yellow to red
            float t = uniform(0.0f, 1.0f, _rnd);
            if (t < 0.33) {
                // Yellow
                particle.color = 0xFFFFFF00;
            } else if (t < 0.66) {
                // Orange
                particle.color = 0xFFFF8000;
            } else {
                // Red
                particle.color = 0xFFFF0000;
            }
            
            particle.life = uniform(20, 50, _rnd);
            particle.lifeMax = particle.life;
            particle.size = uniform(2.0f, 5.0f, _rnd);
            
            _particles ~= particle;
        }
    }
    
    /**
     * Show a random effect
     */
    void randomEffect() {
        // Don't override current effect if one is active
        if (_currentEffect != TerminalEffect.None && _particles.length > 0)
            return;
            
        auto effects = [
            TerminalEffect.Spark,
            TerminalEffect.Matrix
        ];
        
        showEffect(effects[uniform(0, effects.length, _rnd)]);
    }
    
    /**
     * Draw the widget
     */
    override void onDraw(DrawBuf buf) {
        // Draw the base widget
        super.onDraw(buf);
        
        // No particles to draw
        if (_particles.length == 0)
            return;
            
        // Draw particles based on effect type
        Rect rc = _textbox.pos;
        
        foreach (particle; _particles) {
            // Calculate opacity based on life
            ubyte alpha = cast(ubyte)(255 * (cast(float)particle.life / particle.lifeMax));
            uint color = (particle.color & 0x00FFFFFF) | (alpha << 24);
            
            switch (_currentEffect) {
                case TerminalEffect.Spark:
                case TerminalEffect.Explosion:
                case TerminalEffect.Fire:
                    // Draw particle as a small rect or circle
                    int size = cast(int)particle.size;
                    buf.fillRect(
                        Rect(
                            cast(int)(rc.left + particle.x), 
                            cast(int)(rc.top + particle.y),
                            cast(int)(rc.left + particle.x + size),
                            cast(int)(rc.top + particle.y + size)
                        ),
                        color
                    );
                    break;
                    
                case TerminalEffect.Matrix:
                case TerminalEffect.Glitch:
                    // Draw character
                    dchar[] charArray = [particle.character];
                    // drawText method doesn't exist on DrawBuf
                    // Skip text drawing for now
                    // buf.drawText(
                    //     Point(cast(int)(rc.left + particle.x), cast(int)(rc.top + particle.y)),
                    //     charArray,
                    //     _fontFace,
                    //     _fontSize,
                    //     color
                    // );
                    break;
                    
                default:
                    break;
            }
        }
    }
    
    /**
     * Add text to terminal
     */
    void write(string text) {
        _textbox.text = _textbox.text ~ toUTF32(text);
        // _textbox.scrollToEnd(); // scrollToEnd method doesn't exist
    }
    
    /**
     * Add text to terminal with newline
     */
    void writeln(string text) {
        write(text ~ "\n" ~ _prompt);
    }
    
    /**
     * Clear terminal
     */
    void clear() {
        _textbox.text = toUTF32(_prompt);
    }
    
    /**
     * Set terminal prompt
     */
    void setPrompt(string prompt) {
        _prompt = prompt;
    }
    
    /**
     * Get text content
     */
    dstring getText() {
        return _textbox.text;
    }
    
    /**
     * Set text color
     */
    void setTextColor(uint color) {
        _textColor = color;
        _textbox.textColor = color;
    }
    
    /**
     * Set background color
     */
    void setBackgroundColor(uint color) {
        _backgroundColor = color;
        _textbox.backgroundColor = color;
    }
    
    /**
     * Convert HSV to RGB
     */
    uint hsvToRgb(float h, float s, float v) {
        if (s <= 0.0) {
            uint grey = cast(uint)(v * 255);
            return 0xFF000000 | (grey << 16) | (grey << 8) | grey;
        }
        
        h = h / 60.0f;
        int i = cast(int)h;
        float f = h - i;
        float p = v * (1 - s);
        float q = v * (1 - s * f);
        float t = v * (1 - s * (1 - f));
        
        float r, g, b;
        switch (i % 6) {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            case 5: r = v; g = p; b = q; break;
            default: r = v; g = t; b = p; break;
        }
        
        return 0xFF000000 | 
               (cast(uint)(r * 255) << 16) | 
               (cast(uint)(g * 255) << 8) | 
               (cast(uint)(b * 255));
    }
}