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
                var dy = (yy - r).abs();
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
