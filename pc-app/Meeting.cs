// Meeting shortcuts: the watch sends mic / camera / hand / leave, and this
// maps them to the keyboard shortcut of the chosen meeting app. Shortcuts go
// to the foreground window, so the meeting window must be in front (unless
// the meeting app has global shortcuts turned on).

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace WristRemote
{
    static class Meeting
    {
        public static readonly string[] Actions = { "mic", "camera", "hand", "leave" };

        public static readonly Dictionary<string, string> PresetNames = new Dictionary<string, string>
        {
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
                { "mic", "ctrl+d" }, { "camera", "ctrl+e" }, { "hand", "ctrl+alt+h" }, { "leave", "" } } },
        };

        static string PresetFile { get { return Path.Combine(Config.Dir, "meeting.txt"); } }
        public static string CustomFile { get { return Path.Combine(Config.Dir, "meeting-custom.txt"); } }

        public static string Preset
        {
            get
            {
                var p = File.Exists(PresetFile) ? File.ReadAllText(PresetFile).Trim() : "teams";
                return PresetNames.ContainsKey(p) ? p : "teams";
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

        // Shortcut text for an action under the current preset ("" if none).
        public static string ShortcutFor(string action)
        {
            var p = Preset;
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
            foreach (var k in keys) Native.keybd_event(k, 0, 0, UIntPtr.Zero);
            for (int i = keys.Count - 1; i >= 0; i--) Native.keybd_event(keys[i], 0, 2, UIntPtr.Zero);
        }
    }
}
