import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Math;

// Monochrome-safe drawing that keeps text clear of the Instinct subscreen
// (same approach as Morse Quest).
module Ui {

    const C = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
    const SUB_MARGIN = 12;

    var sub as Graphics.BoundingBox or Null = null;

    function init() as Void {
        if (WatchUi has :getSubscreen) { sub = WatchUi.getSubscreen(); }
    }

    function y(dc as Graphics.Dc, f as Float) as Number {
        return (dc.getHeight() * f).toNumber();
    }

    function cx(dc as Graphics.Dc, yy as Number, halfH as Number, halfW as Number) as Number {
        var s = sub;
        if (s != null && yy - halfH < s.y + s.height + 4 && dc.getWidth() / 2 + halfW > s.x - SUB_MARGIN) {
            var left = 4;
            if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND) {
                var r = dc.getWidth() / 2;
                // Measure at the line's top or bottom, whichever is nearer
                // the edge of the round screen.
                var dy = (yy - halfH - r).abs();
                var dy2 = (yy + halfH - r).abs();
                if (dy2 > dy) { dy = dy2; }
                if (dy < r) { left = r - Math.sqrt(r * r - dy * dy).toNumber() + 4; }
            }
            // Never push text past the left edge, even if that means it gets
            // closer to the subscreen.
            var x = (left + s.x - SUB_MARGIN) / 2;
            return x - halfW < left ? left + halfW : x;
        }
        return dc.getWidth() / 2;
    }

    function clear(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
    }

    function text(dc as Graphics.Dc, f as Float, font as Graphics.FontType, s as String) as Void {
        var yy = y(dc, f);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx(dc, yy, dc.getFontHeight(font) / 2, dc.getTextWidthInPixels(s, font) / 2), yy, font, s, C);
    }

    // Status line with a small drawn icon in front:
    // kind 1 = tick (done), 2 = cross (failed), anything else = no icon.
    function status(dc as Graphics.Dc, f as Float, s as String, kind as Number) as Void {
        var font = Graphics.FONT_XTINY;
        var yy = y(dc, f);
        var tw = dc.getTextWidthInPixels(s, font);
        var icon = (kind == 1 || kind == 2) ? 14 : 0;
        var total = tw + icon;
        var x0 = cx(dc, yy, dc.getFontHeight(font) / 2, total / 2) - total / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        if (kind == 1) {
            dc.drawLine(x0, yy, x0 + 3, yy + 4);
            dc.drawLine(x0 + 3, yy + 4, x0 + 9, yy - 4);
        } else if (kind == 2) {
            dc.drawLine(x0 + 1, yy - 4, x0 + 9, yy + 4);
            dc.drawLine(x0 + 1, yy + 4, x0 + 9, yy - 4);
        }
        dc.setPenWidth(1);
        dc.drawText(x0 + icon, yy, font, s, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Button hints for UP and DOWN: a small up / down triangle (like the
    // arrows on the watch case) followed by what the button does.
    function upDown(dc as Graphics.Dc, f as Float, up as String, down as String) as Void {
        var font = Graphics.FONT_XTINY;
        var yy = y(dc, f);
        var t = 9;                                   // triangle width
        var gap = 4;
        var space = 16;
        var w1 = t + gap + dc.getTextWidthInPixels(up, font);
        var w2 = t + gap + dc.getTextWidthInPixels(down, font);
        var total = w1 + space + w2;
        var x = cx(dc, yy, dc.getFontHeight(font) / 2, total / 2) - total / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, yy + 3], [x + t, yy + 3], [x + t / 2, yy - 4]]);
        dc.drawText(x + t + gap, yy, font, up, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += w1 + space;
        dc.fillPolygon([[x, yy - 3], [x + t, yy - 3], [x + t / 2, yy + 4]]);
        dc.drawText(x + t + gap, yy, font, down, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Says what the START button does, inside the subscreen right next to
    // it. Returns false if there is no subscreen (the caller then shows it
    // elsewhere).
    function startLabel(dc as Graphics.Dc, action as String) as Boolean {
        var s = sub;
        if (s == null) { return false; }
        var x = s.x + s.width / 2;
        var yy = s.y + s.height / 2;
        var font = Graphics.FONT_XTINY;
        var h = dc.getFontHeight(font);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, yy, s.width / 2 - 2);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        // Lines sit a little low: the circle is wider below its top edge.
        dc.drawText(x, yy - h / 2 + 4, font, "START", C);
        dc.drawText(x, yy + h / 2 + 1, font, action, C);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        return true;
    }

    function pill(dc as Graphics.Dc, f as Float, font as Graphics.FontType, s as String) as Void {
        var yy = y(dc, f);
        var th = dc.getFontHeight(font);
        var w = dc.getTextWidthInPixels(s, font) + 12;
        var h = th + 2;
        var x = cx(dc, yy, th / 2 + 2, w / 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - w / 2, yy - h / 2, w, h, h / 2);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, yy, font, s, C);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }
}
