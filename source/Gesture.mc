import Toybox.Lang;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.System;

// Wrist-flick detector for slides. Polls the accelerometer every 50 ms (the
// shortest Timer period) and fires once per flick along the x axis, with a
// cooldown so the swing back doesn't count as a second flick.
class FlickDetector {

    const THRESHOLD_MG = 1500;
    const COOLDOWN_MS = 900;
    const PERIOD_MS = 50;

    var enabled as Boolean = false;
    var lastPeak as Number = 0;          // shown on screen to help tune
    var hasAccel as Boolean = true;

    hidden var _timer as Timer.Timer;
    hidden var _onFlick as Method(dir as Number) as Void;
    hidden var _lastFire as Number = 0;

    function initialize(onFlick as Method(dir as Number) as Void) {
        _timer = new Timer.Timer();
        _onFlick = onFlick;
    }

    function setEnabled(on as Boolean) as Void {
        enabled = on;
        _timer.stop();
        if (on) {
            _timer.start(method(:tick), PERIOD_MS, true);
        }
    }

    function stop() as Void {
        _timer.stop();
    }

    function tick() as Void {
        var info = Sensor.getInfo();
        var a = (info has :accel) ? info.accel : null;
        if (a == null) {
            hasAccel = false;
            return;
        }
        hasAccel = true;
        var x = (a as Array<Number>)[0];
        if (x.abs() > lastPeak.abs() || System.getTimer() - _lastFire > 2000) {
            lastPeak = x;
        }
        var now = System.getTimer();
        if (x.abs() >= THRESHOLD_MG && now - _lastFire >= COOLDOWN_MS) {
            _lastFire = now;
            _onFlick.invoke(x > 0 ? 1 : -1);
        }
    }
}
