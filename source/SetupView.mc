import Toybox.Lang;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Communications;

// Step 1 for new users: the watch app does nothing without the free
// Windows app, so say so and send its download link to the phone
// (Garmin Connect shows it as a notification that opens the page).
class SetupView extends WatchUi.View {

    const URL = "https://github.com/irugniM/wrist-remote/releases/latest";

    var sent as String = "";            // "", "sent", "no phone"

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        Ui.init();
    }

    function sendLink() as Void {
        if (!Relay.get().phoneConnected()) {
            sent = "no phone";
        } else {
            Communications.openWebPage(URL, null, null);
            sent = "sent";
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        Ui.clear(dc);
        Ui.pill(dc, 0.17, Graphics.FONT_XTINY, "SETUP");
        var hasSub = Ui.sub != null;
        var o = hasSub ? 0.0 : -0.12;
        if (hasSub) { Ui.startLabel(dc, "link", 0.0); }
        Ui.text(dc, 0.46 + o, Graphics.FONT_XTINY, "Needs a free");
        Ui.text(dc, 0.56 + o, Graphics.FONT_XTINY, "Windows PC app");
        Ui.text(dc, 0.68 + o, Graphics.FONT_XTINY, Ui.startWord() + " sends the");
        Ui.text(dc, 0.77 + o, Graphics.FONT_XTINY, "link to your phone");
        // Bottom of a round screen is narrow: short words only.
        if (sent.equals("sent")) {
            Ui.status(dc, 0.88, "sent", 1);
        } else if (sent.equals("no phone")) {
            Ui.status(dc, 0.88, "no phone", 2);
        }
    }
}

class SetupDelegate extends WatchUi.BehaviorDelegate {

    hidden var _v as SetupView;

    function initialize(v as SetupView) {
        BehaviorDelegate.initialize();
        _v = v;
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _v.sendLink();
            return true;
        }
        return false;
    }

    // A tap is START on touch-only watches.
    function onSelect() as Boolean {
        if (Ui.touchOnly) { _v.sendLink(); }
        return true;
    }
}
