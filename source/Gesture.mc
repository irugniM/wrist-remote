import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;

// Wrist-flick detector for slides: any quick flick means "next slide".
//
// The accelerometer is read at 25 Hz in one-second batches. Gravity is
// tracked with a slow running average per axis and subtracted, so how the
// wrist is held doesn't matter; what is left is the jerk of the flick. A
// flick swings out and back, so its direction can't be told reliably from
// the sign; it only ever turns the page forward, with a cooldown so the
// swing back isn't a second flick. UP on the watch still goes back.
//
// Because samples arrive in batches, a flick is acted on up to a second
// after it happens.
class FlickDetector {

    // Sensitivity levels, cycled with hold UP: off, normal, light, firm.
    const LEVEL_NAMES = ["off", "normal", "light", "firm"];
    const LEVEL_MG = [0, 1300, 900, 1800];
    const COOLDOWN_MS = 1200;
    const RATE_HZ = 25;

    var level as Number = 0;
    var lastPeak as Number = 0;          // strongest movement in the last batch, shown on screen
    var hasAccel as Boolean = true;

    hidden var _onFlick as Method() as Void;
    hidden var _lastFire as Number = 0;
    hidden var _gx as Float = 0.0f;
    hidden var _gy as Float = 0.0f;
    hidden var _gz as Float = 0.0f;
    hidden var _primed as Boolean = false;
    hidden var _listening as Boolean = false;

    function initialize(onFlick as Method() as Void) {
        _onFlick = onFlick;
    }

    function enabled() as Boolean { return level > 0; }

    function levelName() as String { return LEVEL_NAMES[level] as String; }

    // off -> normal -> light -> firm -> off
    function cycle() as Void {
        level = (level + 1) % LEVEL_NAMES.size();
        if (level > 0) { start(); } else { stop(); }
    }

    function start() as Void {
        if (_listening) { return; }
        if (!(Sensor has :registerSensorDataListener)) {
            hasAccel = false;
            return;
        }
        var rate = RATE_HZ;
        if (Sensor has :getMaxSampleRate) {
            var max = Sensor.getMaxSampleRate();
            if (max != null && max < rate) { rate = max; }
        }
        _primed = false;
        try {
            Sensor.registerSensorDataListener(method(:onData), {
                :period => 1,
                :accelerometer => {:enabled => true, :sampleRate => rate}
            });
            _listening = true;
            hasAccel = true;
        } catch (e) {
            hasAccel = false;
        }
    }

    function stop() as Void {
        if (_listening) {
            Sensor.unregisterSensorDataListener();
            _listening = false;
        }
    }

    function off() as Void {
        stop();
        level = 0;
    }

    function onData(data as Sensor.SensorData) as Void {
        var acc = data.accelerometerData;
        if (acc == null || acc.x == null || acc.y == null || acc.z == null) { return; }
        var xs = acc.x as Array<Number>;
        var ys = acc.y as Array<Number>;
        var zs = acc.z as Array<Number>;
        var n = xs.size();
        if (n == 0 || ys.size() < n || zs.size() < n) { return; }

        var threshold = LEVEL_MG[level] as Number;
        var now = System.getTimer();
        var stepMs = 1000 / n;
        var peak = 0;
        for (var i = 0; i < n; i++) {
            var x = xs[i].toFloat();
            var y = ys[i].toFloat();
            var z = zs[i].toFloat();
            if (!_primed) {
                _gx = x; _gy = y; _gz = z;
                _primed = true;
            }
            // Movement = reading minus the gravity estimate.
            var dx = x - _gx;
            var dy = y - _gy;
            var dz = z - _gz;
            var m = Math.sqrt(dx * dx + dy * dy + dz * dz).toNumber();
            if (m > peak) { peak = m; }

            // The gravity estimate follows only slow changes (about 1 s).
            _gx += (x - _gx) * 0.04f;
            _gy += (y - _gy) * 0.04f;
            _gz += (z - _gz) * 0.04f;

            // When this sample was taken, roughly.
            var t = now - (n - 1 - i) * stepMs;
            if (threshold > 0 && m >= threshold && t - _lastFire >= COOLDOWN_MS) {
                _lastFire = t;
                _onFlick.invoke();
            }
        }
        lastPeak = peak;
    }
}
