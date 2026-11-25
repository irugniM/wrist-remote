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

    function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        var r = Relay.get();
        var t = r.topicGrouped();          // "wr-abcd efgh jkmn pqrs"
        Ui.pill(dc, 0.17, Graphics.FONT_XTINY, "PAIR");
        Ui.text(dc, 0.42, Graphics.FONT_XTINY, "PC code:");
        Ui.text(dc, 0.55, Graphics.FONT_SMALL, t.substring(0, 12) as String);
        Ui.text(dc, 0.67, Graphics.FONT_SMALL, t.substring(13, t.length()) as String);
        var s = r.lastCommand.equals("ping") ? r.statusText() : "START: send test";
        Ui.text(dc, 0.83, Graphics.FONT_XTINY, s);
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

    function onSelect() as Boolean { return true; }
}
