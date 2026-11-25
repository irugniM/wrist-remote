import Toybox.Lang;
import Toybox.Communications;
import Toybox.Application;
import Toybox.Attention;
import Toybox.System;
import Toybox.Math;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Sends commands to the PC through ntfy.sh and checks that the PC did them.
//
// The watch has no direct route to the PC: makeWebRequest goes out through
// the phone's Garmin Connect app and must use HTTPS, so a public relay sits
// in the middle. The topic name is long and random and acts as the shared
// secret; the PC app only acts on a fixed list of command words.
//
// Each command is sent as "word#id". The PC answers on "<topic>a" with
// "id|ok|slide|volume|playing" or "id|err|reason". The watch polls that
// channel a few times (1.5, 3 and 5.5 s after sending) and reports:
//   done (two short taps), PC error, or PC no answer (one long buzz).
class RelayClient {

    const URL = "https://ntfy.sh/";
    const TOPIC_CHARS = "abcdefghijkmnpqrstuvwxyz23456789";   // no l/1/o/0 to avoid misreading
    const TOPIC_LEN = 16;
    const POLL_AT_MS = [1500, 3000, 5500];

    // Status for the UI
    var lastCommand as String = "";
    var lastResult as String = "";      // "", sending, waiting, done, pcerr, noanswer, or a send error
    var lastError as String = "";       // PC's reason when lastResult == pcerr
    var lastMs as Number = 0;           // send -> PC answer
    var slide as String = "";           // "5/20" during a PowerPoint show
    var volume as String = "";          // "46" or "m46" (muted)
    var playing as String = "";         // "Artist - Title"

    // Optional hook run whenever the status changes (menus use it).
    var onDone as Method() as Void or Null = null;

    hidden var _busy as Boolean = false;
    hidden var _queue as Array<String> = [] as Array<String>;
    hidden var _counter as Number = 0;
    hidden var _pendingId as String = "";
    hidden var _sentAt as Number = 0;
    hidden var _pollIdx as Number = 0;
    hidden var _pollTimer as Timer.Timer;

    function initialize() {
        _pollTimer = new Timer.Timer();
    }

    // Random topic, made once and kept in storage.
    function topic() as String {
        var t = Application.Storage.getValue("topic");
        if (t instanceof String && t.length() == TOPIC_LEN + 3) { return t; }
        Math.srand(Time.now().value() ^ System.getTimer());
        var s = "wr-";
        for (var i = 0; i < TOPIC_LEN; i++) {
            var k = Math.rand().abs() % TOPIC_CHARS.length();
            s += TOPIC_CHARS.substring(k, k + 1);
        }
        Application.Storage.setValue("topic", s);
        return s;
    }

    // Pair-screen form: "wr-abcd efgh jkmn pqrs"
    function topicGrouped() as String {
        var t = topic();
        var body = t.substring(3, t.length()) as String;
        var out = "wr-";
        for (var i = 0; i < body.length(); i += 4) {
            out += (i > 0 ? " " : "") + body.substring(i, i + 4);
        }
        return out;
    }

    function phoneConnected() as Boolean {
        var s = System.getDeviceSettings();
        return (s has :phoneConnected) ? s.phoneConnected : true;
    }

    // ---------- sending ----------

    // Queue a command. One web request is in flight at a time; the queue is
    // capped so a lost connection can't build a backlog.
    function send(cmd as String) as Void {
        lastCommand = cmd;
        if (!phoneConnected()) {
            lastResult = "no phone";
            buzz(false);
            changed();
            return;
        }
        if (_queue.size() >= 3) { _queue = _queue.slice(1, null); }
        _queue.add(cmd);
        lastResult = "sending";
        changed();
        pump();
    }

    function pump() as Void {
        if (_busy || _queue.size() == 0) { return; }
        var cmd = _queue[0];
        _queue = _queue.slice(1, null);
        _counter = (_counter + 1) % 1024;               // 2 chars from TOPIC_CHARS
        var hi = _counter / 32;
        var lo = _counter % 32;
        var id = TOPIC_CHARS.substring(hi, hi + 1) + TOPIC_CHARS.substring(lo, lo + 1);
        _pendingId = id;
        _busy = true;
        _sentAt = System.getTimer();
        _pollTimer.stop();
        Communications.makeWebRequest(
            URL,
            {"topic" => topic(), "message" => cmd + "#" + id},
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON},
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onSent)
        );
    }

    function onSent(code as Number, data as Dictionary or String or Null) as Void {
        _busy = false;
        if (code == 200) {
            lastResult = "waiting";
            _pollIdx = 0;
            schedulePoll();
        } else {
            lastResult = errorText(code);
            buzz(false);
        }
        changed();
        pump();
    }

    // ---------- confirmation ----------

    hidden function schedulePoll() as Void {
        if (_pollIdx >= POLL_AT_MS.size()) { return; }
        var wait = POLL_AT_MS[_pollIdx] - (System.getTimer() - _sentAt);
        _pollTimer.start(method(:poll), wait < 100 ? 100 : wait, false);
    }

    function poll() as Void {
        if (!lastResult.equals("waiting")) { return; }
        if (_busy) {                                    // a send is in flight; try again shortly
            _pollTimer.start(method(:poll), 300, false);
            return;
        }
        _busy = true;
        Communications.makeWebRequest(
            URL + topic() + "a/raw",
            {"poll" => "1", "since" => "20s"},
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            method(:onPolled)
        );
    }

    function onPolled(code as Number, data as Dictionary or String or Null) as Void {
        _busy = false;
        if (lastResult.equals("waiting")) {
            if (code == 200 && data instanceof String && findAck(data)) {
                changed();
            } else {
                _pollIdx++;
                if (_pollIdx >= POLL_AT_MS.size()) {
                    lastResult = "noanswer";
                    buzz(false);
                    changed();
                } else {
                    schedulePoll();
                }
            }
        }
        pump();
    }

    // Looks for "id|..." among the polled lines (newest last).
    hidden function findAck(text as String) as Boolean {
        var line = "";
        var found = "";
        for (var i = 0; i <= text.length(); i++) {
            var c = (i < text.length()) ? text.substring(i, i + 1) as String : "\n";
            if (c.equals("\n")) {
                if (line.find(_pendingId + "|") == 0) { found = line; }
                line = "";
            } else {
                line += c;
            }
        }
        if (found.equals("")) { return false; }

        var f = split(found);
        lastMs = System.getTimer() - _sentAt;
        if (f.size() > 1 && f[1].equals("ok")) {
            lastResult = "done";
            if (!paired()) { Application.Storage.setValue("paired", true); }
            if (f.size() > 4) {
                slide = f[2];
                volume = f[3];
                playing = ascii(f[4]);
            }
            buzz(true);
        } else {
            lastResult = "pcerr";
            lastError = f.size() > 2 ? f[2] : "error";
            buzz(false);
        }
        return true;
    }

    hidden function split(s as String) as Array<String> {
        var out = [] as Array<String>;
        var cur = "";
        for (var i = 0; i < s.length(); i++) {
            var c = s.substring(i, i + 1) as String;
            if (c.equals("|")) { out.add(cur); cur = ""; } else { cur += c; }
        }
        out.add(cur);
        return out;
    }

    // Watch fonts only cover basic Latin; replace anything else with "?".
    hidden function ascii(s as String) as String {
        var out = "";
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var n = chars[i].toNumber();
            out += (n >= 32 && n < 127) ? chars[i].toString() : "?";
        }
        return out;
    }

    // ---------- feedback ----------

    function statusText() as String {
        if (lastResult.equals("")) { return "ready"; }
        if (lastResult.equals("sending")) { return "sending..."; }
        if (lastResult.equals("waiting")) { return "waiting for PC..."; }
        if (lastResult.equals("done")) { return "done " + (lastMs / 1000.0f).format("%.1f") + "s"; }
        if (lastResult.equals("pcerr")) { return "PC: " + lastError; }
        if (lastResult.equals("noanswer")) { return "PC not answering"; }
        return lastResult;
    }

    // 1 = done, 2 = failed, 0 = idle or in progress (for the status icon).
    function statusKind() as Number {
        if (lastResult.equals("") || lastResult.equals("sending") || lastResult.equals("waiting")) { return 0; }
        return lastResult.equals("done") ? 1 : 2;
    }

    // True once any command has been confirmed by the PC.
    function paired() as Boolean {
        return Application.Storage.getValue("paired") == true;
    }

    function volumeText() as String {
        if (volume.equals("")) { return ""; }
        return volume.find("m") == 0 ? "muted " + volume.substring(1, volume.length()) + "%" : "vol " + volume + "%";
    }

    function errorText(code as Number) as String {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE) { return "no phone"; }
        if (code == Communications.NETWORK_REQUEST_TIMED_OUT) { return "timed out"; }
        if (code == 429) { return "too fast"; }
        if (code < 0) { return "error " + code; }
        return "http " + code;
    }

    hidden function changed() as Void {
        if (onDone != null) { (onDone as Method() as Void).invoke(); }
        WatchUi.requestUpdate();
    }

    // PC confirmed: two short taps. Failure or no answer: one long, weak buzz.
    function buzz(ok as Boolean) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate(ok
                ? [new Attention.VibeProfile(70, 50), new Attention.VibeProfile(0, 80), new Attention.VibeProfile(70, 50)]
                : [new Attention.VibeProfile(40, 600)]);
        }
    }
}

// Single shared client.
module Relay {
    var _c as RelayClient or Null = null;

    function get() as RelayClient {
        if (_c == null) { _c = new RelayClient(); }
        return _c as RelayClient;
    }
}
