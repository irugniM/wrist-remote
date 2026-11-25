import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;

// Shows the relay code to type into the PC agent. START sends a test
// command the agent answers by logging it.
class PairView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        Ui.init();
    }

    // Title, START hint, what to do, the code, then whether the test worked.
    function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        var r = Relay.get();
        var t = r.topicGrouped();          // "wr-abcd efgh jkmn pqrs"
        Ui.pill(dc, 0.17, Graphics.FONT_XTINY, "PAIR");
        var hasSub = Ui.sub != null;
        // With a subscreen the text starts below it; otherwise higher up.
        var o = hasSub ? 0.0 : -0.12;
        if (hasSub) { Ui.startLabel(dc, "test", 0.0); }
        Ui.text(dc, 0.45 + o, Graphics.FONT_XTINY, "Enter this code");
        Ui.text(dc, 0.54 + o, Graphics.FONT_XTINY, "in the PC app:");
        Ui.text(dc, 0.65 + o, Graphics.FONT_SMALL, t.substring(0, 12) as String);
        Ui.text(dc, 0.75 + o, Graphics.FONT_SMALL, t.substring(13, t.length()) as String);
        if (r.lastCommand.equals("ping") && !r.lastResult.equals("")) {
            var s = r.lastResult.equals("done") ? "connected" : r.statusText();
            Ui.status(dc, 0.87, s, r.statusKind());
        } else if (r.paired()) {
            Ui.status(dc, 0.87, "paired", 1);
        }
        // With a subscreen the START circle already says "test".
        if (!hasSub) { Ui.startLabel(dc, "test", 0.76); }
    }
}

class PairDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            Relay.get().send("ping");
            return true;
        }
        return false;
    }

    // A tap is START on touch-only watches.
    function onSelect() as Boolean {
        if (Ui.touchOnly) { Relay.get().send("ping"); }
        return true;
    }
}
