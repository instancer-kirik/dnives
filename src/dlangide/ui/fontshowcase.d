module dlangide.ui.fontshowcase;

import dlangui.widgets.layouts;
import dlangui.widgets.widget;
import dlangui.widgets.scroll;
import dlangui.widgets.controls;
import dlangui.widgets.lists;
import dlangui.graphics.fonts;
import dlangui.core.i18n;
import std.utf : toUTF32;
import std.conv : to;

class FontShowcaseWidget : VerticalLayout {
    this(string ID) {
        super(ID);
        layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        padding(Rect(10, 10, 10, 10));
        backgroundColor = 0x202020; // Dark background

        // Title
        addChild((new TextWidget(null, "Font Showcase"d)).fontSize(20).fontWeight(700).margins(Rect(0, 0, 0, 10)));

        // Scrollable list of fonts
        ScrollWidget scroll = new ScrollWidget("FONT_SCROLLER");
        scroll.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        VerticalLayout list = new VerticalLayout("FONT_LIST");
        list.layoutWidth(FILL_PARENT);

        FontFaceProps[] faces = FontManager.instance.getFaces();
        foreach(face; faces) {
            VerticalLayout item = new VerticalLayout(null);
            item.layoutWidth(FILL_PARENT).padding(Rect(10, 10, 10, 10)).margins(Rect(0, 2, 0, 2));
            item.backgroundColor = 0x303030;

            // Font Name
            item.addChild(new TextWidget(null, toUTF32(face.face)).fontSize(12).textColor(0xAAAAAA));
            
            // Preview Text
            TextWidget preview = new TextWidget(null, "The quick brown fox jumps over the lazy dog. 1234567890"d);
            preview.fontFace = face.face;
            preview.fontSize = 24;
            preview.layoutWidth(FILL_PARENT);
            item.addChild(preview);

            list.addChild(item);
        }

        scroll.contentWidget = list;
        addChild(scroll);
    }
}
