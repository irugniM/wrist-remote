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

    // Layout, top to bottom: title, START hint in the subscreen, the slide
    // number (or the last page turn) big, whether the PC did it, the page
    // buttons, and the flick setting.
    function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        var r = Relay.get();
        Ui.pill(dc, 0.17, Graphics.FONT_XTINY, "SLIDES");
        var hasSub = Ui.startLabel(dc, "black");

        var big = r.slide.equals("") ? label(r.lastCommand) : r.slide;
        Ui.text(dc, 0.48, Graphics.FONT_LARGE, big);
        Ui.status(dc, 0.63, r.statusText(), r.statusKind());
        Ui.upDown(dc, 0.75, "back", "next");
        if (!hasSub) { Ui.text(dc, 0.94, Graphics.FONT_XTINY, "START black"); }

        var f;
        if (!flick.enabled()) { f = "hold UP: flicks"; }
        else if (!flick.hasAccel) { f = "no motion sensor"; }
        else { f = "flicks: " + flick.levelName(); }
        Ui.text(dc, 0.86, Graphics.FONT_XTINY, f);
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

    function onSelect() as Boolean { return true; }

    function onMenu() as Boolean {           // hold UP
        _v.flick.cycle();
        WatchUi.requestUpdate();
        return true;
    }
}
