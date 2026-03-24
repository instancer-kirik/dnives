module dlangide.ui.previewpanel;

import dlangui.widgets.layouts;
import dlangui.widgets.widget;
import dlangui.widgets.controls;
import dlangui.widgets.scroll;
import dlangui.core.events;

class PreviewPanelWidget : VerticalLayout {
    protected Widget _previewContent;
    protected VerticalLayout _deviceFrame;

    this(string ID) {
        super(ID);
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        padding(Rect(10, 10, 10, 10));
        backgroundColor = 0x1a1a1a;

        // Toolbar
        HorizontalLayout toolbar = new HorizontalLayout("PREVIEW_TOOLBAR");
        toolbar.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT).padding(Rect(5, 5, 5, 5));
        toolbar.addChild(new Button(null, "Phone"d));
        toolbar.addChild(new Button(null, "Tablet"d));
        toolbar.addChild(new Button(null, "Desktop"d));
        addChild(toolbar);

        // Frame
        _deviceFrame = new VerticalLayout("DEVICE_FRAME");
        _deviceFrame.layoutWidth(360).layoutHeight(640); // Phone size
        _deviceFrame.margin(Rect(Auto, 20, Auto, 20)); // Center it
        _deviceFrame.backgroundColor = 0x000000;
        _deviceFrame.padding(Rect(15, 60, 15, 60)); // Simulated bezel

        // Bezel circles (simulated)
        _deviceFrame.addChild((new TextWidget(null, "●"d)).margin(Rect(Auto, -45, Auto, 0)).textColor(0x333333));

        _previewContent = new VerticalLayout("PREVIEW_CONTENT");
        _previewContent.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _previewContent.backgroundColor = 0xEEEEEE;
        
        // Sample content for now
        _previewContent.addChild((new TextWidget(null, "Mobile App Preview"d)).fontSize(24).margin(Rect(20, 40, 20, 10)));
        _previewContent.addChild((new TextWidget(null, "This panel allows you to preview your UI layouts in a mobile-like frame."d)).fontSize(14).margin(Rect(20, 0, 20, 0)));

        _deviceFrame.addChild(_previewContent);

        ScrollWidget scroll = new ScrollWidget("PREVIEW_SCROLLER");
        scroll.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        scroll.contentWidget = _deviceFrame;
        addChild(scroll);
    }
}
