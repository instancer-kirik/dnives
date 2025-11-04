module dcore.ui.radialmenu;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.popup;
import dlangui.graphics.drawbuf;
import dlangui.core.signals;
import dlangui.graphics.colors;
import dlangui.core.events;
import dlangui.core.math3d;
import std.math;
import std.algorithm;
import std.array;

import dcore.ui.thememanager;
import dcore.core;

/**
 * RadialMenuItem - An item in the radial menu
 */
class RadialMenuItem {
    string id;           // Unique identifier
    string label;        // Display text
    string iconId;       // Optional icon
    string description;  // Optional longer description
    bool enabled = true; // Whether the item is enabled
    int shortcut = 0;    // Optional keyboard shortcut
    
    // Signal when item is activated
    import dcore.utils.signals : Signal;
    Signal!() onActivated;
    
    // Callback delegate
    private void delegate() _callback;
    
    /**
     * Constructor
     */
    this(string id, string label, string iconId = null, string description = null) {
        this.id = id;
        this.label = label;
        this.iconId = iconId;
        this.description = description;
        // Signal is a struct, no need to allocate
    }
    
    /**
     * Set callback function
     */
    RadialMenuItem setCallback(void delegate() callback) {
        _callback = callback;
        return this;
    }
    
    /**
     * Execute the item action
     */
    void execute() {
        if (!enabled)
            return;
            
        if (_callback)
            _callback();
            
        onActivated.emit();
    }
}

/**
 * RadialMenu - A circular menu that appears around the cursor
 *
 * Features:
 * - Items arranged in a circle around the cursor
 * - Visual feedback for selection
 * - Support for icons and text
 * - Animations for appearance/disappearance
 * - Themeable colors and appearance
 */
class RadialMenu : PopupWidget {
    // Signals
    import dcore.utils.signals : Signal;
    Signal!(string) onItemSelected;  // Item ID selected
    Signal!() onMenuClosed;          // Menu closed
    
    // Items and state
    private RadialMenuItem[] _items;
    private RadialMenuItem _selectedItem;
    private int _selectedIndex = -1;
    private bool _visible = false;
    private bool _animating = false;
    private float _animationProgress = 0.0f;
    private Point _centerPos;
    private int _radius = 100;
    private int _innerRadius = 30;
    private int _itemRadius = 25;
    
    // Appearance
    private uint _backgroundColor = 0x80000000;  // Semi-transparent black
    private uint _itemColor = 0xE0404040;        // Dark gray
    private uint _selectedItemColor = 0xE0606060; // Lighter gray
    private uint _textColor = 0xFFFFFFFF;        // White
    private uint _disabledTextColor = 0xFF808080; // Gray
    private uint _highlightColor = 0xFF00A0FF;   // Blue highlight
    
    // Theme manager
    private ThemeManager _themeManager;
    
    /**
     * Constructor
     */
    this(string id = null) {
        // Create a container widget for the radial menu
        Widget content = new Widget(id ~ "_content");
        
        // Call parent constructor with content and null window
        super(content, null);
        
        // Set custom styles for radial appearance
        styleId = "radial-menu";
        
        // Create animation timer
        _animationTimer = new Timer(16, &onAnimationTimer);
    }
    
    /**
     * Set theme manager
     */
    void setThemeManager(ThemeManager themeManager) {
        _themeManager = themeManager;
        updateThemeColors();
    }
    
    /**
     * Update colors from theme
     */
    private void updateThemeColors() {
        if (!_themeManager)
            return;
            
        dcore.ui.thememanager.Theme theme = _themeManager.getCurrentTheme();
        if (!theme)
            return;
            
        // Extract colors from theme
        _backgroundColor = theme.getUIColor("radialmenu.background", 0x80000000);
        _itemColor = theme.getUIColor("radialmenu.item", 0xE0404040);
        _selectedItemColor = theme.getUIColor("radialmenu.item.selected", 0xE0606060);
        _textColor = theme.getUIColor("radialmenu.text", 0xFFFFFFFF);
        _disabledTextColor = theme.getUIColor("radialmenu.text.disabled", 0xFF808080);
        _highlightColor = theme.getUIColor("radialmenu.highlight", 0xFF00A0FF);
    }
    
    /**
     * Add an item to the radial menu
     */
    RadialMenu addItem(RadialMenuItem item) {
        _items ~= item;
        return this;
    }
    
    /**
     * Add an item by properties
     */
    RadialMenuItem addItem(string id, string label, string iconId = null, string description = null, void delegate() callback = null) {
        RadialMenuItem item = new RadialMenuItem(id, label, iconId, description);
        if (callback)
            item.setCallback(callback);
        _items ~= item;
        return item;
    }
    
    /**
     * Remove an item by ID
     */
    RadialMenu removeItem(string id) {
        _items = _items.filter!(i => i.id != id).array;
        return this;
    }
    
    /**
     * Clear all items
     */
    RadialMenu clearItems() {
        _items.length = 0;
        return this;
    }
    
    /**
     * Show menu at position
     */
    void showAtPos(Point pos) {
        // Reset animation state
        _animationProgress = 0.0f;
        _animating = true;
        _selectedIndex = -1;
        _selectedItem = null;
        
        // Calculate size based on number of items
        int size = _radius * 2 + 20;  // Some padding
        
        // Set center position
        _centerPos = Point(size / 2, size / 2);
        
        // Position popup
        Point windowPos = Point(pos.x - size / 2, pos.y - size / 2);
        
        // Show the popup
        _visible = true;
        if (window)
            window.showPopup(this, null, PopupAlign.Point, windowPos.x, windowPos.y);
        
        // Start animation
        _animationTimer.start();
    }
    
    /**
     * Handle animation timer
     */
    import dcore.utils.timer : Timer;
    private Timer _animationTimer;
    
    private bool onAnimationTimer() {
        if (!_animating)
            return true;
            
        // Update animation progress
        if (_visible) {
            // Opening animation
            _animationProgress += 0.1f;
            if (_animationProgress >= 1.0f) {
                _animationProgress = 1.0f;
                _animating = false;
            }
        } else {
            // Closing animation
            _animationProgress -= 0.1f;
            if (_animationProgress <= 0.0f) {
                _animationProgress = 0.0f;
                _animating = false;
                
                // Close the popup when animation is done
                close();
                
                onMenuClosed.emit();
                return false;  // Stop timer
            }
        }
        
        // Redraw
        invalidate();
        return true;
    }
    
    /**
     * Close the menu
     */
    void closeMenu() {
        if (!_visible)
            return;
            
        // Start closing animation
        _visible = false;
        _animating = true;
        _animationTimer.start();
    }
    
    /**
     * Override mouse move handling
     */
    override bool onMouseEvent(MouseEvent event) {
        if (event.action == MouseAction.Move) {
            return handleMouseMove(event);
        } else if (event.action == MouseAction.ButtonUp) {
            return handleMouseButton(event);
        }
        return super.onMouseEvent(event);
    }
    
    /**
     * Handle mouse move
     */
    private bool handleMouseMove(MouseEvent event) {
        // Calculate distance from center
        float dx = event.x - _centerPos.x;
        float dy = event.y - _centerPos.y;
        float distance = sqrt(dx * dx + dy * dy);
        
        // Check if mouse is in the menu ring
        if (distance >= _innerRadius && distance <= _radius) {
            // Calculate angle
            float angle = atan2(dy, dx);
            if (angle < 0)
                angle += 2 * PI;
                
            // Find item at this angle
            int itemCount = cast(int)_items.length;
            if (itemCount > 0) {
                float anglePerItem = 2 * PI / itemCount;
                int index = cast(int)(angle / anglePerItem);
                if (index >= 0 && index < itemCount) {
                    _selectedIndex = index;
                    _selectedItem = _items[index];
                    invalidate();
                    return true;
                }
            }
        } else {
            // Mouse outside the ring
            _selectedIndex = -1;
            _selectedItem = null;
            invalidate();
        }
        
        return true;
    }
    
    /**
     * Handle mouse button
     */
    private bool handleMouseButton(MouseEvent event) {
        if (event.action == MouseAction.ButtonUp && event.button == MouseButton.Left) {
            // Execute selected item if any
            if (_selectedItem) {
                _selectedItem.execute();
                onItemSelected.emit(_selectedItem.id);
                closeMenu();
                return true;
            } else {
                // Click outside items, close menu
                closeMenu();
                return true;
            }
        } else if (event.action == MouseAction.ButtonUp && event.button == MouseButton.Right) {
            // Right click to cancel
            closeMenu();
            return true;
        }
        
        return false;
    }
    
    /**
     * Override drawing to implement radial menu
     */
    override void onDraw(DrawBuf buf) {
        // Calculate sizes based on animation
        float scale = _animationProgress;
        int currentRadius = cast(int)(_radius * scale);
        int currentInnerRadius = cast(int)(_innerRadius * scale);
        int currentItemRadius = cast(int)(_itemRadius * scale);
        
        // Draw background
        drawCircle(buf, _centerPos.x, _centerPos.y, currentRadius, _backgroundColor);
        
        // Draw inner circle
        drawCircle(buf, _centerPos.x, _centerPos.y, currentInnerRadius, _backgroundColor);
        
        // Draw items
        int itemCount = cast(int)_items.length;
        if (itemCount > 0) {
            float anglePerItem = 2 * PI / itemCount;
            
            for (int i = 0; i < itemCount; i++) {
                RadialMenuItem item = _items[i];
                
                // Calculate item position
                float angle = i * anglePerItem;
                float itemDistance = (_innerRadius + _radius) / 2 * scale;
                int x = cast(int)(_centerPos.x + cos(angle) * itemDistance);
                int y = cast(int)(_centerPos.y + sin(angle) * itemDistance);
                
                // Draw item circle
                uint itemBgColor = (i == _selectedIndex) ? _selectedItemColor : _itemColor;
                drawCircle(buf, x, y, currentItemRadius, itemBgColor);
                
                // Draw item text/icon if animation is advanced enough
                if (scale > 0.5f) {
                    // Scale label alpha with animation
                    float textAlpha = min(1.0f, (scale - 0.5f) * 2.0f);
                    uint textColor = item.enabled ? _textColor : _disabledTextColor;
                    textColor = (textColor & 0x00FFFFFF) | (cast(uint)(0xFF * textAlpha) << 24);
                    
                    // Draw icon or first letter of label
                    FontRef font = FontManager.instance.getFont(14, 700, false, FontFamily.SansSerif, "Arial");
                    if (item.iconId && drawableCache.get(item.iconId)) {
                        // Draw icon
                        DrawableRef icon = drawableCache.get(item.iconId);
                        icon.drawTo(buf, Rect(x - 12, y - 12, x + 12, y + 12));
                    } else if (item.label.length > 0) {
                        // Draw first letter of label
                        dstring letter = item.label[0..1].toUTF32;
                        Point textSize = font.textSize(letter);
                        font.drawText(buf, x - textSize.x / 2, y - textSize.y / 2, letter, textColor, 0);
                    }
                    
                    // Draw label for selected item
                    if (i == _selectedIndex && item.label.length > 0) {
                        dstring label = item.label.toUTF32;
                        FontRef labelFont = FontManager.instance.getFont(12, 400, false, FontFamily.SansSerif, "Arial");
                        Point labelSize = labelFont.textSize(label);
                        labelFont.drawText(buf, _centerPos.x - labelSize.x / 2, _centerPos.y + _radius + 10, 
                                          label, textColor, 0);
                                          
                        // Draw description if available
                        if (item.description && item.description.length > 0) {
                            dstring desc = item.description.toUTF32;
                            FontRef descFont = FontManager.instance.getFont(10, 400, true, FontFamily.SansSerif, "Arial");
                            Point descSize = descFont.textSize(desc);
                            descFont.drawText(buf, _centerPos.x - descSize.x / 2, _centerPos.y + _radius + 30,
                                             desc, textColor, 0);
                        }
                    }
                }
            }
        }
    }
    
    /**
     * Draw a filled circle
     */
    private void drawCircle(DrawBuf buf, int centerX, int centerY, int radius, uint color) {
        // Simple circle drawing using the midpoint circle algorithm
        int x = radius;
        int y = 0;
        int err = 0;
        
        while (x >= y) {
            // Fill horizontal lines to create a filled circle
            buf.fillRect(Rect(centerX - x, centerY + y, centerX + x, centerY + y + 1), color);
            buf.fillRect(Rect(centerX - x, centerY - y, centerX + x, centerY - y + 1), color);
            buf.fillRect(Rect(centerX - y, centerY + x, centerX + y, centerY + x + 1), color);
            buf.fillRect(Rect(centerX - y, centerY - x, centerX + y, centerY - x + 1), color);
            
            if (err <= 0) {
                y += 1;
                err += 2 * y + 1;
            }
            
            if (err > 0) {
                x -= 1;
                err -= 2 * x + 1;
            }
        }
    }
    
    /**
     * Handle key event
     */
    override bool onKeyEvent(KeyEvent event) {
        if (event.action == KeyAction.KeyDown) {
            if (event.keyCode == KeyCode.ESCAPE) {
                // Escape closes the menu
                closeMenu();
                return true;
            } else if (event.keyCode >= KeyCode.KEY_1 && event.keyCode <= KeyCode.KEY_9) {
                // Number keys for quick selection
                int index = event.keyCode - KeyCode.KEY_1;
                if (index >= 0 && index < _items.length) {
                    RadialMenuItem item = _items[index];
                    item.execute();
                    onItemSelected.emit(item.id);
                    closeMenu();
                    return true;
                }
            }
        }
        
        return super.onKeyEvent(event);
    }
}