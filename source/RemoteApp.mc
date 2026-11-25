import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.System;

class RemoteApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        Relay.get().topic();     // make the pairing code on first launch
        var m = Menus.buildMain();
        return [m, new MainMenuDelegate(m)];
    }
}

module Menus {

    // The START press that launches the app can reach the first menu as a
    // select; ignore selects for a moment after launch.
    var openedAt as Number = 0;
    const LAUNCH_GUARD_MS = 800;

    function guard() as Boolean {
        return System.getTimer() - openedAt < LAUNCH_GUARD_MS;
    }

    function buildMain() as WatchUi.Menu2 {
        openedAt = System.getTimer();
        var m = new WatchUi.Menu2({:title => "Wrist Remote"});
        m.addItem(new WatchUi.MenuItem("Slides", "UP/DOWN, flick", :slides, null));
        m.addItem(new WatchUi.MenuItem("Media", "play, tracks, volume", :media, null));
        m.addItem(new WatchUi.MenuItem("Meeting", "mic, camera, hand", :meeting, null));
        m.addItem(new WatchUi.MenuItem("Lock PC", "Win+L", "lock", null));
        m.addItem(new WatchUi.MenuItem("Sleep PC", "asks first", :sleep, null));
        m.addItem(new WatchUi.MenuItem("Pair", "code for the PC", :pair, null));
        return m;
    }

    function showMedia() as Void {
        var m = new WatchUi.Menu2({:title => "Media"});
        m.addItem(new WatchUi.MenuItem("Play / pause", nowPlaying(), "playpause", null));
        m.addItem(new WatchUi.MenuItem("Next track", null, "nexttrack", null));
        m.addItem(new WatchUi.MenuItem("Previous track", null, "prevtrack", null));
        m.addItem(new WatchUi.MenuItem("Volume up", volume(), "volup", null));
        m.addItem(new WatchUi.MenuItem("Volume down", volume(), "voldown", null));
        m.addItem(new WatchUi.MenuItem("Mute", null, "mute", null));
        WatchUi.pushView(m, new CommandMenuDelegate(m), WatchUi.SLIDE_LEFT);
    }

    // Shortcuts for these come from the meeting app chosen on the PC
    // (Teams, Zoom, Google Meet, or custom). The meeting window must be in front.
    function showMeeting() as Void {
        var m = new WatchUi.Menu2({:title => "Meeting"});
        m.addItem(new WatchUi.MenuItem("Mic on/off", null, "mic", null));
        m.addItem(new WatchUi.MenuItem("Camera on/off", null, "camera", null));
        m.addItem(new WatchUi.MenuItem("Raise hand", null, "hand", null));
        m.addItem(new WatchUi.MenuItem("Leave meeting", "asks first", :leave, null));
        WatchUi.pushView(m, new CommandMenuDelegate(m), WatchUi.SLIDE_LEFT);
    }

    // Safe choice first so a stray press can't do it.
    function confirm(title as String, label as String, sub as String, cmd as String) as Void {
        var m = new WatchUi.Menu2({:title => title});
        m.addItem(new WatchUi.MenuItem("Cancel", null, :cancel, null));
        m.addItem(new WatchUi.MenuItem(label, sub, cmd, null));
        WatchUi.pushView(m, new ConfirmDelegate(), WatchUi.SLIDE_LEFT);
    }

    function nowPlaying() as String or Null {
        var p = Relay.get().playing;
        return p.equals("") ? null : p;
    }

    function volume() as String or Null {
        var v = Relay.get().volumeText();
        return v.equals("") ? null : v;
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var _m as WatchUi.Menu2;

    function initialize(m as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        _m = m;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (Menus.guard()) { return; }
        var id = item.getId();
        if (id == :slides) {
            var v = new SlidesView();
            WatchUi.pushView(v, new SlidesDelegate(v), WatchUi.SLIDE_LEFT);
        } else if (id == :media) {
            Menus.showMedia();
        } else if (id == :meeting) {
            Menus.showMeeting();
        } else if (id == :sleep) {
            Menus.confirm("Sleep PC?", "Sleep now", "PC goes to sleep", "sleep");
        } else if (id == :pair) {
            WatchUi.pushView(new PairView(), new PairDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id instanceof String) {           // "lock": send and show the result here
            var r = Relay.get();
            r.onDone = method(:refreshLock);
            r.send(id);
            refreshLock();
        }
    }

    function refreshLock() as Void {
        var i = _m.findItemById("lock");
        if (i >= 0) {
            var item = _m.getItem(i);
            if (item != null) { item.setSubLabel(Relay.get().statusText()); }
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// Menu of commands (media, meeting). Each item sends its command and stays
// open so it can be pressed again; the pressed item's sub-label shows the
// result, and media items show what's playing and the volume.
class CommandMenuDelegate extends WatchUi.Menu2InputDelegate {

    hidden var _m as WatchUi.Menu2;
    hidden var _item as WatchUi.MenuItem or Null = null;

    function initialize(m as WatchUi.Menu2) {
        Menu2InputDelegate.initialize();
        _m = m;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :leave) {
            Menus.confirm("Leave?", "Leave meeting", "uses the PC shortcut", "leave");
            return;
        }
        if (_item != null && _item != item) { restoreLabel(_item as WatchUi.MenuItem); }
        _item = item;
        var r = Relay.get();
        r.onDone = method(:refresh);
        r.send(id as String);
        refresh();
    }

    function refresh() as Void {
        var r = Relay.get();
        if (_item != null) {
            var item = _item as WatchUi.MenuItem;
            var text = r.statusText();
            var id = item.getId() as String;
            if (r.lastResult.equals("done") && (id.equals("volup") || id.equals("voldown") || id.equals("mute"))) {
                var v = r.volumeText();
                if (!v.equals("")) { text = v; }
            }
            item.setSubLabel(text);
            // Keep "Play / pause" showing the current track.
            if (!id.equals("playpause")) {
                var i = _m.findItemById("playpause");
                if (i >= 0) {
                    var p = _m.getItem(i);
                    if (p != null) { p.setSubLabel(Menus.nowPlaying()); }
                }
            }
        }
        WatchUi.requestUpdate();
    }

    // When another item is pressed, put the old one back to its normal text.
    hidden function restoreLabel(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (!(id instanceof String)) { return; }
        if (id.equals("playpause")) { item.setSubLabel(Menus.nowPlaying()); }
        else if (id.equals("volup") || id.equals("voldown")) { item.setSubLabel(Menus.volume()); }
        else { item.setSubLabel(null); }
    }

    function onBack() as Void {
        Relay.get().onDone = null;
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

class ConfirmDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof String) {
            Relay.get().send(id);
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
