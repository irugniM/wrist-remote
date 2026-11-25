import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Math;

// Drawing that works on every watch: round, semi-round and rectangular
// screens of any size, with or without the Instinct subscreen, with
// buttons or touch only. Every line is fitted into the space the screen
// has at its height (stepping the font down if needed), and button hints
// match the watch's controls. White on black, so it suits 1-bit, MIP and
// AMOLED screens alike.
module Ui {

    const C = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
    const L = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

    var sub as Graphics.BoundingBox or Null = null;
    var round as Boolean = true;
    var buttons as Boolean = true;    // has UP and DOWN buttons
    var touchOnly as Boolean = false;  // touch screen and no UP/DOWN buttons

    function init() as Void {
        sub = (WatchUi has :getSubscreen) ? WatchUi.getSubscreen() : null;
        var ds = System.getDeviceSettings();
        round = ds.screenShape == System.SCREEN_SHAPE_ROUND || ds.screenShape == System.SCREEN_SHAPE_SEMI_ROUND;
        if (ds has :inputButtons) {
            var b = ds.inputButtons;
            buttons = (b & System.BUTTON_INPUT_UP) != 0 && (b & System.BUTTON_INPUT_DOWN) != 0;
        }
        touchOnly = ds.isTouchScreen && !buttons;
    }

    function y(dc as Graphics.Dc, f as Float) as Number {
        return (dc.getHeight() * f).toNumber();
    }

    // Distance kept from the screen edge, scaled to the screen.
    function margin(dc as Graphics.Dc) as Number {
        var m = dc.getWidth() / 40;
        return m < 4 ? 4 : m;
    }

    // [left, right] free for a line centred at yy and halfH tall: inside
    // the round edge (measured at the line's top or bottom, whichever is
    // nearer the edge) and left of the subscreen if they share a height.
    function range(dc as Graphics.Dc, yy as Number, halfH as Number) as Array<Number> {
        var w = dc.getWidth();
        var m = margin(dc);
        var left = m;
        var right = w - m;
        if (round) {
            var r = w / 2;
            var cy = dc.getHeight() / 2;
            var dy = (yy - halfH - cy).abs();
            var dy2 = (yy + halfH - cy).abs();
            if (dy2 > dy) { dy = dy2; }
            var half = dy < r ? Math.sqrt(r * r - dy * dy).toNumber() : 0;
            left = r - half + m;
            right = r + half - m;
        }
        var s = sub;
        if (s != null && yy - halfH < s.y + s.height + 4 && s.x - 12 < right) {
            right = s.x - 12;
        }
        return [left, right];
    }

    // Centre x for something w wide on the line at yy.
    function place(dc as Graphics.Dc, yy as Number, halfH as Number, w as Number) as Number {
        var rg = range(dc, yy, halfH);
        var s = sub;
        // Centre on the screen, or in the space left of the subscreen when
        // the line shares its height.
        var x = dc.getWidth() / 2;
        if (s != null && yy - halfH < s.y + s.height + 4) { x = (rg[0] + rg[1]) / 2; }
        if (x - w / 2 < rg[0]) { x = rg[0] + w / 2; }   // never past the left edge
        return x;
    }

    // The largest font, from `font` down, at which s fits on the line.
    function fit(dc as Graphics.Dc, yy as Number, font as Graphics.FontType, s as String) as Graphics.FontType {
        var fonts = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        var start = fonts.indexOf(font);
        if (start < 0) { return font; }
        for (var i = start; i < fonts.size(); i++) {
            var f = fonts[i] as Graphics.FontType;
            var rg = range(dc, yy, dc.getFontHeight(f) / 2);
            if (dc.getTextWidthInPixels(s, f) <= rg[1] - rg[0]) { return f; }
        }
        return Graphics.FONT_XTINY;
    }

    // Body text font for this screen: the largest small font that takes
    // no more than 8% of the height, so up to six lines fit with room
    // between them (the Instinct keeps its smallest font).
    var _body as Graphics.FontType or Null = null;
    var _bumped as Boolean = false;

    function body(dc as Graphics.Dc) as Graphics.FontType {
        if (_body == null) {
            var limit = dc.getHeight() * 8 / 100;
            _body = Graphics.FONT_XTINY;
            var options = [Graphics.FONT_SMALL, Graphics.FONT_TINY];
            for (var i = 0; i < options.size(); i++) {
                if (dc.getFontHeight(options[i] as Graphics.FontType) <= limit) { _body = options[i]; break; }
            }
            _bumped = _body != Graphics.FONT_XTINY;
        }
        return _body as Graphics.FontType;
    }

    // Screens ask for FONT_XTINY for body text and FONT_SMALL for emphasis;
    // on bigger screens both move up.
    function scaled(dc as Graphics.Dc, font as Graphics.FontType) as Graphics.FontType {
        if (font == Graphics.FONT_XTINY) { return body(dc); }
        body(dc);
        if (_bumped && font == Graphics.FONT_SMALL) { return Graphics.FONT_MEDIUM; }
        return font;
    }

    // Icon size that matches the body font on this watch.
    function unit(dc as Graphics.Dc) as Number {
        var u = dc.getFontHeight(body(dc)) / 2;
        return u < 8 ? 8 : u;
    }

    function clear(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
    }

    function text(dc as Graphics.Dc, f as Float, font as Graphics.FontType, s as String) as Void {
        var yy = y(dc, f);
        var ft = fit(dc, yy, scaled(dc, font), s);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(place(dc, yy, dc.getFontHeight(ft) / 2, dc.getTextWidthInPixels(s, ft)), yy, ft, s, C);
    }

    // Status line with a small drawn icon in front:
    // kind 1 = tick (done), 2 = cross (failed), anything else = no icon.
    function status(dc as Graphics.Dc, f as Float, s as String, kind as Number) as Void {
        var font = body(dc);
        var yy = y(dc, f);
        var u = unit(dc);
        var icon = (kind == 1 || kind == 2) ? u + u / 2 : 0;
        var total = dc.getTextWidthInPixels(s, font) + icon;
        var x0 = place(dc, yy, dc.getFontHeight(font) / 2, total) - total / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(u > 12 ? 3 : 2);
        var h = u / 2;
        if (kind == 1) {
            dc.drawLine(x0, yy, x0 + h * 2 / 3, yy + h);
            dc.drawLine(x0 + h * 2 / 3, yy + h, x0 + u, yy - h);
        } else if (kind == 2) {
            dc.drawLine(x0 + 1, yy - h, x0 + u, yy + h);
            dc.drawLine(x0 + 1, yy + h, x0 + u, yy - h);
        }
        dc.setPenWidth(1);
        dc.drawText(x0 + icon, yy, font, s, L);
    }

    // How to go back and forward: up / down triangles (like the arrows on
    // the watch case) on watches with UP and DOWN, "swipe" on touch-only ones.
    function upDown(dc as Graphics.Dc, f as Float, up as String, down as String) as Void {
        if (!buttons) {
            text(dc, f, Graphics.FONT_XTINY, "swipe: " + up + " / " + down);
            return;
        }
        var font = body(dc);
        var yy = y(dc, f);
        var t = unit(dc);                               // triangle width
        var a = t * 4 / 5;                              // triangle height / 2
        var gap = t / 2;
        var space = t * 2;
        var w1 = t + gap + dc.getTextWidthInPixels(up, font);
        var w2 = t + gap + dc.getTextWidthInPixels(down, font);
        var total = w1 + space + w2;
        var x = place(dc, yy, dc.getFontHeight(font) / 2, total) - total / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, yy + a / 2 + 1], [x + t, yy + a / 2 + 1], [x + t / 2, yy - a]]);
        dc.drawText(x + t + gap, yy, font, up, L);
        x += w1 + space;
        dc.fillPolygon([[x, yy - a / 2 - 1], [x + t, yy - a / 2 - 1], [x + t / 2, yy + a]]);
        dc.drawText(x + t + gap, yy, font, down, L);
    }

    // Name of the "do it" control: the START button, or a tap on touch-only watches.
    function startWord() as String {
        return touchOnly ? "tap" : "START";
    }

    // Says what START does. On the Instinct it goes in the subscreen right
    // next to the button; elsewhere it is a line of text at f.
    function startLabel(dc as Graphics.Dc, action as String, f as Float) as Void {
        var s = sub;
        if (s == null) {
            text(dc, f, Graphics.FONT_XTINY, startWord() + ": " + action);
            return;
        }
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
    }

    // "hold UP" on watches with an UP button, otherwise a long press.
    function holdWord() as String {
        return buttons ? "hold UP" : "hold";
    }

    function pill(dc as Graphics.Dc, f as Float, font as Graphics.FontType, s as String) as Void {
        font = scaled(dc, font);
        var yy = y(dc, f);
        var th = dc.getFontHeight(font);
        var pad = th * 2 / 3;
        var w = dc.getTextWidthInPixels(s, font) + pad;
        var h = th + 2;
        var x = place(dc, yy, h / 2 + 1, w);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - w / 2, yy - h / 2, w, h, h / 2);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, yy, font, s, C);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }
}
