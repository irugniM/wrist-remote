import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Timer;

// Slides remote: UP previous, DOWN next, START black screen,
// hold UP (menu) turns wrist-flick gestures on or off.
class SlidesView extends WatchUi.View {

    var flick as FlickDetector;
    hidden var _refresh as Timer.Timer;

    function initialize() {
        View.initialize();
        flick = new FlickDetector(method(:onFlick));
        _refresh = new Timer.Timer();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        Ui.init();
    }

    function onShow() as Void {
        // Redraw twice a second while gestures are on so the peak readout moves.
        _refresh.start(method(:redraw), 500, true);
    }

    function onHide() as Void {
        _refresh.stop();
        flick.stop();
        flick.enabled = false;
    }

    function redraw() as Void {
        if (flick.enabled) { WatchUi.requestUpdate(); }
    }

    function onFlick(dir as Number) as Void {
        Relay.get().send(dir > 0 ? "next" : "prev");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        var r = Relay.get();
        Ui.pill(dc, 0.17, Graphics.FONT_XTINY, "SLIDES");
        // Big line: slide position once the PC reports it, else the last command.
        var big = r.slide.equals("") ? label(r.lastCommand) : r.slide;
        Ui.text(dc, 0.40, Graphics.FONT_MEDIUM, big);
        Ui.text(dc, 0.55, Graphics.FONT_XTINY, r.statusText());
        if (!flick.enabled) {
            Ui.text(dc, 0.66, Graphics.FONT_XTINY, "flick: off");
        } else if (!flick.hasAccel) {
            Ui.text(dc, 0.66, Graphics.FONT_XTINY, "flick: no sensor");
        } else {
            Ui.text(dc, 0.66, Graphics.FONT_XTINY, "flick: on  " + flick.lastPeak.abs() + "mg");
        }
        Ui.text(dc, 0.78, Graphics.FONT_XTINY, "UP prev  DOWN next");
        Ui.text(dc, 0.88, Graphics.FONT_XTINY, "START black");
    }

    static function label(cmd as String) as String {
        if (cmd.equals("next")) { return "NEXT"; }
        if (cmd.equals("prev")) { return "PREV"; }
        if (cmd.equals("black")) { return "BLACK"; }
        return "ready";
    }
}
class SlidesDelegate extends WatchUi.BehaviorDelegate {

    hidden var _v as SlidesView;

    function initialize(v as SlidesView) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onPreviousPage() as Boolean {   // UP
        Relay.get().send("prev");
        return true;
    }

    function onNextPage() as Boolean {       // DOWN
        Relay.get().send("next");
        return true;
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            Relay.get().send("black");
            return true;
        }
        return false;
    }

    function onSelect() as Boolean { return true; }

    function onMenu() as Boolean {           // hold UP
        _v.flick.setEnabled(!_v.flick.enabled);
        WatchUi.requestUpdate();
        return true;
    }
}
