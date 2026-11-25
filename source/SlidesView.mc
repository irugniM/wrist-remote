import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

// Slides remote: UP previous, DOWN next, START black screen,
// hold UP (menu) cycles wrist-flick gestures: off, normal, light, firm.
class SlidesView extends WatchUi.View {

    var flick as FlickDetector;

    function initialize() {
        View.initialize();
        flick = new FlickDetector(method(:onFlick));
    }

    function onLayout(dc as Graphics.Dc) as Void {
        Ui.init();
    }

    function onHide() as Void {
        flick.off();
    }

    function onFlick() as Void {
        Relay.get().send("next");
    }

    // Layout, top to bottom: title, the slide number (or the last page turn)
    // big, whether the PC did it, back / next, what START does, and the
    // flick setting. On the Instinct the START hint sits in the subscreen.
    function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        var r = Relay.get();
        var sub = Ui.sub != null;
        var big = r.slide.equals("") ? label(r.lastCommand) : r.slide;
        var f;
        if (!flick.enabled()) { f = Ui.holdWord() + ": flicks"; }
        else if (!flick.hasAccel) { f = "no motion sensor"; }
        else { f = "flicks: " + flick.levelName(); }

        if (sub) {
            Ui.pill(dc, 0.17, Graphics.FONT_XTINY, "SLIDES");
            Ui.startLabel(dc, "black", 0.0);
            Ui.text(dc, 0.48, Graphics.FONT_LARGE, big);
            Ui.status(dc, 0.63, r.statusText(), r.statusKind());
            Ui.upDown(dc, 0.75, "back", "next");
            Ui.text(dc, 0.86, Graphics.FONT_XTINY, f);
        } else {
            Ui.pill(dc, 0.17, Graphics.FONT_XTINY, "SLIDES");
            Ui.text(dc, 0.38, Graphics.FONT_LARGE, big);
            Ui.status(dc, 0.53, r.statusText(), r.statusKind());
            Ui.upDown(dc, 0.65, "back", "next");
            Ui.startLabel(dc, "black", 0.75);
            Ui.text(dc, 0.85, Graphics.FONT_XTINY, f);
        }
    }

    static function label(cmd as String) as String {
        if (cmd.equals("next")) { return "Next"; }
        if (cmd.equals("prev")) { return "Back"; }
        if (cmd.equals("black")) { return "Black"; }
        return "Ready";
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

    // A tap is START on touch-only watches; elsewhere ignore stray taps.
    function onSelect() as Boolean {
        if (Ui.touchOnly) { Relay.get().send("black"); }
        return true;
    }

    function onMenu() as Boolean {           // hold UP (or the menu gesture)
        _v.flick.cycle();
        WatchUi.requestUpdate();
        return true;
    }

    function onHold(evt as WatchUi.ClickEvent) as Boolean {   // long press on touch-only watches
        if (!Ui.touchOnly) { return false; }
        return onMenu();
    }
}
