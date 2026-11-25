// Meeting shortcuts: the watch sends mic / camera / hand / leave, and this
// maps them to the keyboard shortcut of the meeting app. In Auto mode (the
// default) the app finds the meeting window itself (Teams, Zoom, or a
// browser tab showing Google Meet), brings it to the front for the
// shortcut, then gives focus back to the window that had it.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WristRemote
{
    static class Meeting
    {
        public static readonly string[] Actions = { "mic", "camera", "hand", "leave" };

        public static readonly Dictionary<string, string> PresetNames = new Dictionary<string, string>
        {
            { "auto", "Auto (find the meeting window)" },
            { "teams", "Microsoft Teams" },
            { "zoom", "Zoom" },
            { "meet", "Google Meet" },
            { "custom", "Custom (edit file)" },
        };

        static readonly Dictionary<string, Dictionary<string, string>> Presets = new Dictionary<string, Dictionary<string, string>>
        {
            { "teams", new Dictionary<string, string> {
                { "mic", "ctrl+shift+m" }, { "camera", "ctrl+shift+o" }, { "hand", "ctrl+shift+k" }, { "leave", "ctrl+shift+h" } } },
            { "zoom", new Dictionary<string, string> {
                { "mic", "alt+a" }, { "camera", "alt+v" }, { "hand", "alt+y" }, { "leave", "alt+q" } } },
            { "meet", new Dictionary<string, string> {
                { "mic", "ctrl+d" }, { "camera", "ctrl+e" }, { "hand", "ctrl+alt+h" }, { "leave", "ctrl+w" } } },
        };

        static string PresetFile { get { return Path.Combine(Config.Dir, "meeting.txt"); } }
        public static string CustomFile { get { return Path.Combine(Config.Dir, "meeting-custom.txt"); } }

        public static string Preset
        {
            get
            {
                var p = File.Exists(PresetFile) ? File.ReadAllText(PresetFile).Trim() : "auto";
                return PresetNames.ContainsKey(p) ? p : "auto";
            }
            set { Directory.CreateDirectory(Config.Dir); File.WriteAllText(PresetFile, value); }
        }

        public static void EnsureCustomFile()
        {
            if (File.Exists(CustomFile)) return;
            Directory.CreateDirectory(Config.Dir);
            File.WriteAllText(CustomFile,
                "# Wrist Remote custom meeting shortcuts\r\n" +
                "# One per line: action = keys. Actions: mic, camera, hand, leave.\r\n" +
                "# Keys: ctrl, shift, alt, win plus a letter, digit, F1-F12, space, enter, esc, tab.\r\n" +
                "# Leave a value empty to disable that button.\r\n" +
                "mic = ctrl+shift+m\r\n" +
                "camera = ctrl+shift+o\r\n" +
                "hand = ctrl+shift+k\r\n" +
                "leave = ctrl+shift+h\r\n");
        }

        // Shortcut text for an action under a preset ("" if none).
        public static string ShortcutFor(string action, string p)
        {
            if (p != "custom")
            {
                string s;
                return Presets[p].TryGetValue(action, out s) ? s : "";
            }
            EnsureCustomFile();
            foreach (var raw in File.ReadAllLines(CustomFile))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                var eq = line.IndexOf('=');
                if (eq < 0) continue;
                if (line.Substring(0, eq).Trim().ToLowerInvariant() == action)
                    return line.Substring(eq + 1).Trim().ToLowerInvariant();
            }
            return "";
        }

        // Parses "ctrl+shift+m" into virtual-key codes (modifiers first).
        // Returns null if any part is not understood.
        public static List<byte> Parse(string shortcut)
        {
            var keys = new List<byte>();
            foreach (var part in shortcut.Split('+').Select(x => x.Trim()).Where(x => x.Length > 0))
            {
                byte vk;
                if (!TryKey(part, out vk)) return null;
                keys.Add(vk);
            }
            return keys.Count > 0 ? keys : null;
        }

        static bool TryKey(string k, out byte vk)
        {
            vk = 0;
            switch (k)
            {
                case "ctrl": case "control": vk = 0x11; return true;
                case "shift": vk = 0x10; return true;
                case "alt": vk = 0x12; return true;
                case "win": vk = 0x5B; return true;
                case "space": vk = 0x20; return true;
                case "enter": vk = 0x0D; return true;
                case "esc": case "escape": vk = 0x1B; return true;
                case "tab": vk = 0x09; return true;
            }
            if (k.Length == 1 && k[0] >= 'a' && k[0] <= 'z') { vk = (byte)char.ToUpperInvariant(k[0]); return true; }
            if (k.Length == 1 && k[0] >= '0' && k[0] <= '9') { vk = (byte)k[0]; return true; }
            if (k.Length >= 2 && k[0] == 'f')
            {
                int n;
                if (int.TryParse(k.Substring(1), out n) && n >= 1 && n <= 12) { vk = (byte)(0x70 + n - 1); return true; }
            }
            return false;
        }

        // Presses the keys together, then releases in reverse order.
        public static void Press(List<byte> keys)
        {
            foreach (var k in keys) { Native.keybd_event(k, 0, 0, UIntPtr.Zero); Thread.Sleep(15); }
            Thread.Sleep(30);
            for (int i = keys.Count - 1; i >= 0; i--) { Native.keybd_event(keys[i], 0, 2, UIntPtr.Zero); Thread.Sleep(10); }
        }

        // ---------- finding and focusing the meeting window ----------

        static readonly string[] ZoomMeetingClasses =
            { "ConfMultiTabContentWndClass", "ZPContentViewWndClass", "ZPFloatVideoWndClass", "ZPActiveSpeakerWndClass" };

        static readonly string[] Browsers = { "chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "arc" };

        // Which meeting app a top-level window belongs to, or null.
        static string Kind(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero || !W.IsWindowVisible(hwnd)) return null;
            var title = Title(hwnd);
            if (title.Length == 0) return null;
            var proc = ProcessName(hwnd);
            if (proc == "ms-teams" || proc == "teams") return "teams";
            if (proc == "zoom")
            {
                // Zoom Workplace titles both its main window and the meeting
                // window "Zoom Workplace", so tell them apart by window class.
                var cls = ClassName(hwnd);
                return Array.IndexOf(ZoomMeetingClasses, cls) >= 0
                    || title.IndexOf("Zoom Meeting", StringComparison.OrdinalIgnoreCase) >= 0
                    || title.IndexOf("Zoom Webinar", StringComparison.OrdinalIgnoreCase) >= 0 ? "zoom" : null;
            }
            if (Array.IndexOf(Browsers, proc) >= 0)
            {
                // A browser window's title is its active tab's title, e.g. "Meet - abc-defg-hij - Google Chrome".
                if (title.StartsWith("Meet - ", StringComparison.Ordinal) || title.IndexOf("Google Meet", StringComparison.Ordinal) >= 0) return "meet";
                if (title.IndexOf("Microsoft Teams", StringComparison.Ordinal) >= 0) return "teams";
            }
            return null;
        }

        // The meeting window: the foreground window if it is one, else the
        // topmost one (Teams windows titled Meeting or Call first).
        public static IntPtr Find(out string kind)
        {
            kind = null;
            var fg = W.GetForegroundWindow();
            var k = Kind(fg);
            if (k != null) { kind = k; return fg; }
            IntPtr best = IntPtr.Zero;
            string bestKind = null;
            int bestScore = 0;
            W.EnumWindows((h, l) =>
            {
                var kk = Kind(h);
                if (kk == null) return true;
                var t = Title(h);
                int score = (kk != "teams" || t.IndexOf("Meeting", StringComparison.OrdinalIgnoreCase) >= 0
                    || t.IndexOf("Call", StringComparison.OrdinalIgnoreCase) >= 0) ? 2 : 1;
                if (score > bestScore) { best = h; bestKind = kk; bestScore = score; }
                return bestScore < 2;            // windows come top to bottom; stop at the first good one
            }, IntPtr.Zero);
            kind = bestKind;
            return best;
        }

        // Brings hwnd to the front, presses the keys, then gives focus back
        // to the window that had it. False if the window couldn't be focused.
        public static bool PressIn(IntPtr hwnd, List<byte> keys, Action then = null)
        {
            var before = W.GetForegroundWindow();
            if (before != hwnd && !Focus(hwnd)) return false;
            Press(keys);
            if (then != null) then();
            if (before != hwnd && before != IntPtr.Zero)
            {
                Thread.Sleep(250);
                Focus(before);
            }
            return true;
        }

        // Zoom's Alt+Q asks again: "Leave meeting", and for the host also
        // "End meeting for all". Click "Leave meeting" through UI Automation;
        // never anything else. Returns false if the button didn't show up.
        public static bool ClickZoomLeave()
        {
            var zoomPids = System.Diagnostics.Process.GetProcessesByName("Zoom").Select(p => p.Id).ToList();
            if (zoomPids.Count == 0) return false;
            // The "Leave meeting" button, matched by UI Automation itself
            // (asking every button for its name one by one took seconds).
            var leaveButton = new System.Windows.Automation.AndCondition(
                new System.Windows.Automation.PropertyCondition(System.Windows.Automation.AutomationElement.ControlTypeProperty,
                    System.Windows.Automation.ControlType.Button),
                new System.Windows.Automation.PropertyCondition(System.Windows.Automation.AutomationElement.NameProperty,
                    "Leave meeting", System.Windows.Automation.PropertyConditionFlags.IgnoreCase));
            var deadline = DateTime.UtcNow.AddSeconds(4);
            int round = 0;
            while (DateTime.UtcNow < deadline)
            {
                Thread.Sleep(round++ == 0 ? 150 : 200);
                try
                {
                    // The dialog Alt+Q opens normally takes the foreground: look there first.
                    var fg = W.GetForegroundWindow();
                    uint fgPid;
                    W.GetWindowThreadProcessId(fg, out fgPid);
                    if (fg != IntPtr.Zero && zoomPids.Contains((int)fgPid)
                        && TryInvoke(System.Windows.Automation.AutomationElement.FromHandle(fg), leaveButton)) return true;

                    // Then Zoom's other top-level windows, smallest (most dialog-like) first.
                    if (round % 3 != 0) continue;
                    var wins = new List<System.Windows.Automation.AutomationElement>();
                    foreach (var pid in zoomPids)
                        foreach (System.Windows.Automation.AutomationElement w in System.Windows.Automation.AutomationElement.RootElement.FindAll(
                            System.Windows.Automation.TreeScope.Children,
                            new System.Windows.Automation.PropertyCondition(System.Windows.Automation.AutomationElement.ProcessIdProperty, pid)))
                            wins.Add(w);
                    foreach (var w in wins.OrderBy(x => x.Current.BoundingRectangle.Width * x.Current.BoundingRectangle.Height))
                        if (TryInvoke(w, leaveButton)) return true;
                }
                catch (Exception) { }
            }
            return false;
        }

        static bool TryInvoke(System.Windows.Automation.AutomationElement root, System.Windows.Automation.Condition cond)
        {
            var b = root.FindFirst(System.Windows.Automation.TreeScope.Descendants, cond);
            if (b == null) return false;
            object pat;
            if (!b.TryGetCurrentPattern(System.Windows.Automation.InvokePattern.Pattern, out pat)) return false;
            ((System.Windows.Automation.InvokePattern)pat).Invoke();
            return true;
        }

        static bool Focus(IntPtr hwnd)
        {
            if (W.IsIconic(hwnd)) W.ShowWindow(hwnd, 9 /* SW_RESTORE */);
            // Windows lets only the app that last had input change the
            // foreground window; a lone Alt tap counts as input.
            W.keybd_event(0x12, 0, 0, UIntPtr.Zero);
            W.keybd_event(0x12, 0, 2, UIntPtr.Zero);
            W.SetForegroundWindow(hwnd);
            for (int i = 0; i < 10 && W.GetForegroundWindow() != hwnd; i++) Thread.Sleep(30);
            Thread.Sleep(120);                   // let the app take keyboard focus
            return W.GetForegroundWindow() == hwnd;
        }

        static string Title(IntPtr h)
        {
            var sb = new StringBuilder(256);
            W.GetWindowText(h, sb, sb.Capacity);
            return sb.ToString();
        }

        static string ClassName(IntPtr h)
        {
            var sb = new StringBuilder(256);
            W.GetClassName(h, sb, sb.Capacity);
            return sb.ToString();
        }

        static string ProcessName(IntPtr h)
        {
            try
            {
                uint pid;
                W.GetWindowThreadProcessId(h, out pid);
                return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant();
            }
            catch (Exception) { return ""; }
        }

        static class W
        {
            public delegate bool EnumProc(IntPtr h, IntPtr l);
            [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
            [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
            [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
            [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
            [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
            [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
            [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
            [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
            [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        }
    }
}
