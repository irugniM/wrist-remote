// Wrist Remote: Windows tray app.
//
// Listens on an ntfy.sh topic for commands from the WristRemote watch app and
// turns them into slide keys, media/volume app commands, or sleep. Only the
// fixed command words in Dispatch() are acted on; anything else is logged and
// ignored. Messages older than 30 s are ignored so nothing is replayed after
// the PC wakes up.
//
// Build (no extra install needed, uses the C# compiler that ships with Windows):
//   build.cmd

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("Wrist Remote")]
[assembly: System.Reflection.AssemblyProduct("Wrist Remote")]
[assembly: System.Reflection.AssemblyVersion("1.1.0.0")]

namespace WristRemote
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            // --config <folder>: use another settings folder (for testing).
            var i = Array.IndexOf(args, "--config");
            if (i >= 0 && i + 1 < args.Length) Config.Dir = args[i + 1];
            bool first;
            using (var mutex = new Mutex(true, "WristRemote.Tray." + Config.Dir.GetHashCode(), out first))
            {
                if (!first)
                {
                    MessageBox.Show("Wrist Remote is already running (look for its icon by the clock).",
                        "Wrist Remote", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | (SecurityProtocolType)12288; // TLS 1.2 / 1.3
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayApp());
            }
        }
    }

    static class Native
    {
        [DllImport("user32.dll")]
        public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessageW(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool DestroyIcon(IntPtr handle);

        [DllImport("user32.dll")]
        public static extern bool LockWorkStation();

        public const int WM_APPCOMMAND = 0x319;
    }

    static class Config
    {
        public static string Dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "WristRemote");
        static string TopicFile { get { return Path.Combine(Dir, "topic.txt"); } }
        static string DryRunFile { get { return Path.Combine(Dir, "dryrun.txt"); } }
        public static string LogFile { get { return Path.Combine(Dir, "log.txt"); } }
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string RunName = "WristRemote";

        public static string NormalizeTopic(string s)
        {
            s = Regex.Replace(s ?? "", @"\s", "").ToLowerInvariant();
            return Regex.IsMatch(s, "^wr-[a-z0-9]{16}$") ? s : null;
        }

        public static string Topic
        {
            get { return File.Exists(TopicFile) ? NormalizeTopic(File.ReadAllText(TopicFile)) : null; }
            set { Directory.CreateDirectory(Dir); File.WriteAllText(TopicFile, value); }
        }

        public static bool DryRun
        {
            get { return File.Exists(DryRunFile); }
            set
            {
                Directory.CreateDirectory(Dir);
                if (value) File.WriteAllText(DryRunFile, "1"); else if (File.Exists(DryRunFile)) File.Delete(DryRunFile);
            }
        }

        public static bool StartWithWindows
        {
            get
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k != null && k.GetValue(RunName) != null;
            }
            set
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (value) k.SetValue(RunName, "\"" + Application.ExecutablePath + "\"");
                    else k.DeleteValue(RunName, false);
                }
            }
        }
    }

    class TrayApp : ApplicationContext
    {
        const int MaxAgeSeconds = 30;

        readonly NotifyIcon _tray;
        readonly Control _ui;                  // hidden control: UI-thread marshalling and WM_APPCOMMAND target
        readonly ToolStripMenuItem _status, _last, _dry, _autostart, _meeting;
        CancellationTokenSource _cts;
        string _topic;
        bool _connected;

        public TrayApp()
        {
            _ui = new Control();
            _ui.CreateControl();
            var h = _ui.Handle;                // force handle creation on the UI thread

            _status = new ToolStripMenuItem("Starting...") { Enabled = false };
            _last = new ToolStripMenuItem("No commands yet") { Enabled = false };
            _dry = new ToolStripMenuItem("Log only (don't press keys)", null, (s, e) => ToggleDryRun()) { Checked = Config.DryRun };
            _autostart = new ToolStripMenuItem("Start with Windows", null, (s, e) => ToggleAutostart()) { Checked = Config.StartWithWindows };

            var menu = new ContextMenuStrip();
            menu.Items.Add(_status);
            menu.Items.Add(_last);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Change pairing code...", null, (s, e) => AskTopic(true));
            menu.Items.Add(_dry);
            menu.Items.Add(_autostart);
            _meeting = new ToolStripMenuItem("Meeting app");
            foreach (var kv in Meeting.PresetNames)
            {
                var key = kv.Key;
                _meeting.DropDownItems.Add(new ToolStripMenuItem(kv.Value, null, (s, e) => SetMeetingPreset(key)) { Tag = key });
            }
            _meeting.DropDownItems.Add(new ToolStripSeparator());
            _meeting.DropDownItems.Add("Edit custom shortcuts...", null, (s, e) => EditCustomShortcuts());
            menu.Items.Add(_meeting);
            RefreshMeetingMenu();
            menu.Items.Add("Open log", null, (s, e) => OpenLog());
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Exit", null, (s, e) => ExitThread());

            _tray = new NotifyIcon
            {
                Icon = MakeIcon(),
                Text = "Wrist Remote",
                ContextMenuStrip = menu,
                Visible = true
            };
            _tray.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) ShowMenu(); };

            _topic = Config.Topic;
            if (_topic == null && !AskTopic(false))
            {
                ExitThread();
                return;
            }
            Start();
        }

        // ---------- UI ----------

        void ShowMenu()
        {
            // Show the context menu on left click as well.
            typeof(NotifyIcon).GetMethod("ShowContextMenu",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic).Invoke(_tray, null);
        }

        bool AskTopic(bool changing)
        {
            using (var f = new PairForm(_topic))
            {
                if (f.ShowDialog() != DialogResult.OK) return false;
                _topic = f.Topic;
                Config.Topic = _topic;
                if (changing) Start();
                return true;
            }
        }

        void ToggleDryRun()
        {
            Config.DryRun = !Config.DryRun;
            _dry.Checked = Config.DryRun;
            Log(Config.DryRun ? "log-only mode on" : "log-only mode off");
            UpdateStatus();
        }

        void SetMeetingPreset(string key)
        {
            Meeting.Preset = key;
            RefreshMeetingMenu();
            Log("meeting app: " + Meeting.PresetNames[key]);
        }

        void RefreshMeetingMenu()
        {
            foreach (ToolStripItem i in _meeting.DropDownItems)
            {
                var mi = i as ToolStripMenuItem;
                if (mi != null && mi.Tag is string) mi.Checked = (string)mi.Tag == Meeting.Preset;
            }
            _meeting.Text = "Meeting app: " + Meeting.PresetNames[Meeting.Preset].Replace(" (edit file)", "");
        }

        void EditCustomShortcuts()
        {
            Meeting.EnsureCustomFile();
            SetMeetingPreset("custom");
            Process.Start("notepad.exe", "\"" + Meeting.CustomFile + "\"");
        }

        void ToggleAutostart()
        {
            Config.StartWithWindows = !Config.StartWithWindows;
            _autostart.Checked = Config.StartWithWindows;
        }

        void OpenLog()
        {
            Directory.CreateDirectory(Config.Dir);
            if (!File.Exists(Config.LogFile)) File.WriteAllText(Config.LogFile, "");
            Process.Start("notepad.exe", "\"" + Config.LogFile + "\"");
        }

        void UpdateStatus()
        {
            var code = _topic ?? "not paired";
            var state = _connected ? "Connected" : "Connecting";
            _status.Text = state + "  (" + code + ")" + (Config.DryRun ? "  log only" : "");
            var tip = "Wrist Remote: " + state.ToLowerInvariant() + (Config.DryRun ? ", log only" : "");
            _tray.Text = tip.Length > 63 ? tip.Substring(0, 63) : tip;
        }

        static Icon MakeIcon()
        {
            // Two arrowheads, like the watch app's icon.
            using (var b = new Bitmap(32, 32))
            {
                using (var g = Graphics.FromImage(b))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.Clear(Color.Transparent);
                    g.FillEllipse(new SolidBrush(Color.FromArgb(255, 20, 20, 20)), 0, 0, 31, 31);
                    using (var w = new SolidBrush(Color.White))
                    {
                        g.FillPolygon(w, new[] { new Point(5, 16), new Point(14, 9), new Point(14, 23) });
                        g.FillPolygon(w, new[] { new Point(27, 16), new Point(18, 9), new Point(18, 23) });
                    }
                }
                var hIcon = b.GetHicon();
                var icon = (Icon)Icon.FromHandle(hIcon).Clone();
                Native.DestroyIcon(hIcon);
                return icon;
            }
        }

        protected override void ExitThreadCore()
        {
            if (_cts != null) _cts.Cancel();
            _tray.Visible = false;
            _tray.Dispose();
            base.ExitThreadCore();
        }

        // ---------- listening ----------

        void Start()
        {
            if (_cts != null) _cts.Cancel();
            _cts = new CancellationTokenSource();
            var token = _cts.Token;
            var topic = _topic;
            _connected = false;
            UpdateStatus();
            Task.Run(() => ListenLoop(topic, token));
        }

        async Task ListenLoop(string topic, CancellationToken token)
        {
            var json = new JavaScriptSerializer();
            using (var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan })
            {
                while (!token.IsCancellationRequested)
                {
                    try
                    {
                        using (var resp = await client.GetAsync("https://ntfy.sh/" + topic + "/json",
                            HttpCompletionOption.ResponseHeadersRead, token))
                        using (var stream = await resp.Content.ReadAsStreamAsync())
                        using (var reader = new StreamReader(stream))
                        {
                            resp.EnsureSuccessStatusCode();
                            OnUi(() => { _connected = true; UpdateStatus(); Log("connected to relay"); });
                            string line;
                            while (!token.IsCancellationRequested && (line = await reader.ReadLineAsync()) != null)
                            {
                                if (line.Length == 0) continue;
                                var evt = json.Deserialize<Dictionary<string, object>>(line);
                                object kind, msg, time;
                                if (!evt.TryGetValue("event", out kind) || (string)kind != "message") continue;
                                if (!evt.TryGetValue("message", out msg) || !evt.TryGetValue("time", out time)) continue;
                                var age = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - Convert.ToInt64(time);
                                var cmd = ((string)msg).Trim().ToLowerInvariant();
                                if (age > MaxAgeSeconds) { OnUi(() => Log("skipped old command '" + cmd + "' (" + age + " s old)")); continue; }
                                OnUi(() => Dispatch(cmd));
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        if (token.IsCancellationRequested) break;
                        var m = ex.GetBaseException().Message;
                        OnUi(() => { _connected = false; UpdateStatus(); Log("connection problem: " + m + "; retrying in 5 s"); });
                    }
                    if (!token.IsCancellationRequested)
                    {
                        OnUi(() => { _connected = false; UpdateStatus(); });
                        try { await Task.Delay(5000, token); } catch (TaskCanceledException) { break; }
                    }
                }
            }
        }

        void OnUi(Action a)
        {
            if (!_ui.IsDisposed) _ui.BeginInvoke(a);
        }

        // ---------- commands ----------

        // Messages look like "next#k3": a command word and an id chosen by the
        // watch. After acting, the app publishes "k3|ok|slide|volume|playing"
        // (or "k3|err|reason") to the "<topic>a" channel, which the watch polls
        // to confirm the PC really did it.
        //
        // Slide keys go to the foreground window. Media and volume use
        // WM_APPCOMMAND, which Windows routes to the system volume and the
        // active media session, so keyboard remapping doesn't affect them.
        void Dispatch(string raw)
        {
            string cmd = raw, id = null;
            var hash = raw.IndexOf('#');
            if (hash > 0)
            {
                cmd = raw.Substring(0, hash);
                id = raw.Substring(hash + 1);
                if (!Regex.IsMatch(id, "^[a-z0-9]{1,8}$")) id = null;
            }

            string what;
            Action act = null;
            string error = null;
            if (Array.IndexOf(Meeting.Actions, cmd) >= 0)
            {
                var shortcut = Meeting.ShortcutFor(cmd);
                var keys = shortcut.Length > 0 ? Meeting.Parse(shortcut) : null;
                what = Meeting.PresetNames[Meeting.Preset].Replace(" (edit file)", "") + " " + cmd
                    + (shortcut.Length > 0 ? " (" + shortcut + ")" : "");
                if (shortcut.Length == 0) error = "no shortcut";
                else if (keys == null) error = "bad shortcut";
                else act = () => Meeting.Press(keys);
            }
            else
            {
                switch (cmd)
                {
                    case "ping": what = "test from watch: paired and working"; break;
                    case "next": what = "Right arrow (next slide)"; act = () => Key(0x27, true); break;
                    case "prev": what = "Left arrow (previous slide)"; act = () => Key(0x25, true); break;
                    case "black": what = "B (black screen)"; act = () => Key(0x42, false); break;
                    case "playpause": what = "play/pause"; act = () => AppCommand(14); break;
                    case "nexttrack": what = "next track"; act = () => AppCommand(11); break;
                    case "prevtrack": what = "previous track"; act = () => AppCommand(12); break;
                    case "volup": what = "volume up"; act = () => AppCommand(10); break;
                    case "voldown": what = "volume down"; act = () => AppCommand(9); break;
                    case "mute": what = "mute"; act = () => AppCommand(8); break;
                    case "lock": what = "lock PC"; act = () => Native.LockWorkStation(); break;
                    case "sleep":
                        what = "sleep";
                        act = () => Application.SetSuspendState(PowerState.Suspend, false, false);
                        break;
                    default:
                        Log("ignored unknown command '" + cmd + "'");
                        Ack(id, "err|unknown", false);
                        return;
                }
            }

            var dry = Config.DryRun && act != null;
            Log(cmd + " -> " + what + (dry ? " (log only)" : "") + (error != null ? ": " + error : ""));
            _last.Text = "Last: " + cmd + "  " + DateTime.Now.ToString("HH:mm:ss");
            if (error != null) { Ack(id, "err|" + error, false); return; }

            if (cmd == "sleep" && !dry)
            {
                // Answer first, then sleep, so the watch hears back.
                Ack(id, "ok", false);
                var t = new System.Windows.Forms.Timer { Interval = 2500 };
                t.Tick += (s, e) => { t.Stop(); t.Dispose(); act(); };
                t.Start();
                return;
            }
            if (!dry && act != null) act();
            Ack(id, "ok", cmd != "lock");
        }

        static readonly HttpClient AckClient = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };

        void Ack(string id, string result, bool withStatus)
        {
            if (id == null || _topic == null) return;
            var topic = _topic;
            Task.Run(async () =>
            {
                var body = id + "|" + result;
                if (withStatus && result == "ok")
                {
                    await Task.Delay(400);       // let the slide / volume change land first
                    var playing = await PcStatus.NowPlaying();
                    body += "|" + PcStatus.Slide() + "|" + PcStatus.Volume() + "|" + Clean(playing, 40);
                }
                try
                {
                    var resp = await AckClient.PostAsync("https://ntfy.sh/" + topic + "a",
                        new StringContent(body, System.Text.Encoding.UTF8, "text/plain"));
                    if (!resp.IsSuccessStatusCode) OnUi(() => Log("ack not sent: http " + (int)resp.StatusCode));
                }
                catch (Exception ex)
                {
                    var m = ex.GetBaseException().Message;
                    OnUi(() => Log("ack not sent: " + m));
                }
            });
        }

        static string Clean(string s, int max)
        {
            s = Regex.Replace(s ?? "", @"[|\r\n]", " ").Trim();
            return s.Length > max ? s.Substring(0, max - 3) + "..." : s;
        }
        static void Key(byte vk, bool extended)
        {
            uint ext = extended ? 1u : 0u;
            Native.keybd_event(vk, 0, ext, UIntPtr.Zero);
            Native.keybd_event(vk, 0, ext | 2u, UIntPtr.Zero);
        }

        void AppCommand(int command)
        {
            Native.SendMessageW(_ui.Handle, Native.WM_APPCOMMAND, _ui.Handle, (IntPtr)(command << 16));
        }

        // ---------- log ----------

        static void Log(string msg)
        {
            try
            {
                Directory.CreateDirectory(Config.Dir);
                var fi = new FileInfo(Config.LogFile);
                if (fi.Exists && fi.Length > 200 * 1024) File.WriteAllText(Config.LogFile, "");
                File.AppendAllText(Config.LogFile, "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + msg + Environment.NewLine);
            }
            catch (IOException) { }
        }
    }

    // Small dialog for the pairing code shown on the watch (WristRemote > Pair).
    class PairForm : Form
    {
        readonly TextBox _box;
        public string Topic { get; private set; }

        public PairForm(string current)
        {
            Text = "Wrist Remote: pair with your watch";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(420, 172);
            Font = new Font("Segoe UI", 10f);

            var label = new Label
            {
                Text = "On the watch open Wrist Remote > Pair and type the code shown there. Spaces don't matter.\nExample: wr-abcd efgh jkmn pqrs",
                Location = new Point(14, 12),
                Size = new Size(392, 66)
            };
            _box = new TextBox { Location = new Point(14, 84), Size = new Size(392, 26), Text = current ?? "wr-" };
            var ok = new Button { Text = "Pair", DialogResult = DialogResult.None, Location = new Point(230, 126), Size = new Size(84, 30) };
            var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, Location = new Point(322, 126), Size = new Size(84, 30) };
            ok.Click += (s, e) =>
            {
                var t = Config.NormalizeTopic(_box.Text);
                if (t == null)
                {
                    MessageBox.Show(this, "That doesn't look like a pairing code. It starts with wr- and has 16 more letters or digits.",
                        "Wrist Remote", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                Topic = t;
                DialogResult = DialogResult.OK;
            };
            AcceptButton = ok;
            CancelButton = cancel;
            Controls.AddRange(new Control[] { label, _box, ok, cancel });
            Shown += (s, e) => { _box.Focus(); _box.SelectionStart = _box.Text.Length; };
        }
    }
}
