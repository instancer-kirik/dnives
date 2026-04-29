module dcore.compat.splitter;

import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.core.events;
import dlangui.core.types;

/**
 * Simple horizontal splitter implementation as compatibility layer
 * for missing dlangui.widgets.splitter module
 */
class HSplitter : HorizontalLayout {
    private int _splitterPosition = -1;
    private bool _dragging = false;
    private int _dragStartPos = 0;
    private int _dragStartSplitterPos = 0;
    private static immutable int SPLITTER_WIDTH = 6;

    this(string ID = null) {
        super(ID);
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
    }

    override Widget addChild(Widget child) {
        auto result = super.addChild(child);
        if (childCount == 2) {
            // Set default split position when we have 2 children
            if (_splitterPosition == -1) {
                _splitterPosition = 200; // Default left panel width
            }
        }
        return result;
    }

    override void measure(int parentWidth, int parentHeight) {
        super.measure(parentWidth, parentHeight);
        updateSplitterPosition();
    }

    private void updateSplitterPosition() {
        if (childCount != 2) return;

        Widget leftChild = child(0);
        Widget rightChild = child(1);

        if (_splitterPosition == -1) {
            _splitterPosition = _pos.width / 2;
        }

        // Clamp splitter position
        int minLeft = 100;
        int maxLeft = _pos.width - 100 - SPLITTER_WIDTH;
        if (_splitterPosition < minLeft) _splitterPosition = minLeft;
        if (_splitterPosition > maxLeft) _splitterPosition = maxLeft;

        // Update child layouts
        leftChild.layoutWidth = _splitterPosition;
        rightChild.layoutWidth = _pos.width - _splitterPosition - SPLITTER_WIDTH;
    }

    override void layout(Rect rc) {
        if (visibility == Visibility.Gone) {
            return;
        }
        _pos = rc;
        _needLayout = false;

        if (childCount != 2) {
            super.layout(rc);
            return;
        }

        updateSplitterPosition();

        Widget leftChild = child(0);
        Widget rightChild = child(1);

        Rect leftRect = Rect(rc.left, rc.top, rc.left + _splitterPosition, rc.bottom);
        Rect rightRect = Rect(rc.left + _splitterPosition + SPLITTER_WIDTH, rc.top, rc.right, rc.bottom);

        leftChild.layout(leftRect);
        rightChild.layout(rightRect);
    }

    override bool onMouseEvent(MouseEvent event) {
        if (childCount != 2) return super.onMouseEvent(event);

        // Mouse coordinates are relative to this widget, so use _splitterPosition directly
        int splitterLeft = _splitterPosition;
        int splitterRight = splitterLeft + SPLITTER_WIDTH;

        if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Left) {
            if (event.x >= splitterLeft && event.x <= splitterRight) {
                _dragging = true;
                _dragStartPos = event.x;
                _dragStartSplitterPos = _splitterPosition;
                event.track(this);
                return true;
            }
        }

        if (event.action == MouseAction.ButtonUp && event.button == MouseButton.Left) {
            if (_dragging) {
                _dragging = false;
                event.track(null);
                return true;
            }
        }

        if (event.action == MouseAction.Move) {
            if (_dragging) {
                int delta = event.x - _dragStartPos;
                _splitterPosition = _dragStartSplitterPos + delta;
                requestLayout();
                return true;
            } else if (event.x >= splitterLeft && event.x <= splitterRight) {
                // Change cursor to resize cursor when over splitter
                return true;
            }
        }

        return super.onMouseEvent(event);
    }
}

/**
 * Simple vertical splitter implementation as compatibility layer
 */
class VSplitter : VerticalLayout {
    private int _splitterPosition = -1;
    private bool _dragging = false;
    private int _dragStartPos = 0;
    private int _dragStartSplitterPos = 0;
    private static immutable int SPLITTER_HEIGHT = 6;

    this(string ID = null) {
        super(ID);
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
    }

    override Widget addChild(Widget child) {
        auto result = super.addChild(child);
        if (childCount == 2) {
            // Set default split position when we have 2 children
            if (_splitterPosition == -1) {
                _splitterPosition = 150; // Default top panel height
            }
        }
        return result;
    }

    override void measure(int parentWidth, int parentHeight) {
        super.measure(parentWidth, parentHeight);
        updateSplitterPosition();
    }

    private void updateSplitterPosition() {
        if (childCount != 2) return;

        Widget topChild = child(0);
        Widget bottomChild = child(1);

        if (_splitterPosition == -1) {
            _splitterPosition = _pos.height / 2;
        }

        // Clamp splitter position
        int minTop = 50;
        int maxTop = _pos.height - 50 - SPLITTER_HEIGHT;
        if (_splitterPosition < minTop) _splitterPosition = minTop;
        if (_splitterPosition > maxTop) _splitterPosition = maxTop;

        // Update child layouts
        topChild.layoutHeight = _splitterPosition;
        bottomChild.layoutHeight = _pos.height - _splitterPosition - SPLITTER_HEIGHT;
    }

    override void layout(Rect rc) {
        if (visibility == Visibility.Gone) {
            return;
        }
        _pos = rc;
        _needLayout = false;

        if (childCount != 2) {
            super.layout(rc);
            return;
        }

        updateSplitterPosition();

        Widget topChild = child(0);
        Widget bottomChild = child(1);

        Rect topRect = Rect(rc.left, rc.top, rc.right, rc.top + _splitterPosition);
        Rect bottomRect = Rect(rc.left, rc.top + _splitterPosition + SPLITTER_HEIGHT, rc.right, rc.bottom);

        topChild.layout(topRect);
        bottomChild.layout(bottomRect);
    }

    override bool onMouseEvent(MouseEvent event) {
        if (childCount != 2) return super.onMouseEvent(event);

        // Mouse coordinates are relative to this widget, so use _splitterPosition directly
        int splitterTop = _splitterPosition;
        int splitterBottom = splitterTop + SPLITTER_HEIGHT;

        if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Left) {
            if (event.y >= splitterTop && event.y <= splitterBottom) {
                _dragging = true;
                _dragStartPos = event.y;
                _dragStartSplitterPos = _splitterPosition;
                event.track(this);
                return true;
            }
        }

        if (event.action == MouseAction.ButtonUp && event.button == MouseButton.Left) {
            if (_dragging) {
                _dragging = false;
                event.track(null);
                return true;
            }
        }

        if (event.action == MouseAction.Move) {
            if (_dragging) {
                int delta = event.y - _dragStartPos;
                _splitterPosition = _dragStartSplitterPos + delta;
                requestLayout();
                return true;
            } else if (event.y >= splitterTop && event.y <= splitterBottom) {
                // Change cursor to resize cursor when over splitter
                return true;
            }
        }

        return super.onMouseEvent(event);
    }
}
