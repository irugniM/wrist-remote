// PC status sent back to the watch with each acknowledgement:
// PowerPoint slide position, system volume, and what is playing.
// Every part is best-effort: if something can't be read it is left empty.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Windows.Media.Control;

namespace WristRemote
{
    static class PcStatus
    {
        // "5/20" while a PowerPoint slide show is running, or while PowerPoint
        // is the front window in normal view; else "".
        //
        // PowerPoint can run as more than one process (a file opened in
        // Protected View starts its own), and only one of them is reachable
        // with GetActiveObject. So each PowerPoint document or slide show
        // window is also asked for its own Application object.
        public static string Slide()
        {
            var apps = PowerPointApps();
            foreach (var app in apps)
            {
                var s = ShowPosition(app);
                if (s != "") return s;
            }
            if (!PowerPointInFront()) return "";
            foreach (dynamic app in apps)
            {
                try
                {
                    if (app.Windows.Count < 1) continue;
                    dynamic w = app.ActiveWindow;
                    int index = w.View.Slide.SlideIndex;
                    int count = w.Presentation.Slides.Count;
                    return index + "/" + count;
                }
                catch (Exception) { }
            }
            return "";
        }

        static string ShowPosition(dynamic app)
        {
            try
            {
                if (app.SlideShowWindows.Count >= 1)
                {
                    dynamic win = app.SlideShowWindows[1];
                    int pos = win.View.CurrentShowPosition;
                    int total = win.Presentation.Slides.Count;
                    return pos + "/" + total;
                }
            }
            catch (Exception) { }
            try
            {
                // A show started from Protected View.
                int n = app.ProtectedViewWindows.Count;
                for (int i = 1; i <= n; i++)
                {
                    try
                    {
                        dynamic pres = app.ProtectedViewWindows[i].Presentation;
                        dynamic sw = pres.SlideShowWindow;
                        int pos = sw.View.CurrentShowPosition;
                        int total = pres.Slides.Count;
                        return pos + "/" + total;
                    }
                    catch (Exception) { }
                }
            }
            catch (Exception) { }
            return "";
        }

        static List<object> PowerPointApps()
        {
            var apps = new List<object>();
            try { apps.Add(Marshal.GetActiveObject("PowerPoint.Application")); } catch (Exception) { }
            var pids = new HashSet<uint>(System.Diagnostics.Process.GetProcessesByName("POWERPNT").Select(p => (uint)p.Id));
            if (pids.Count == 0) return apps;
            var seen = new HashSet<uint>();
            EnumWindows((top, l) =>
            {
                uint pid;
                GetWindowThreadProcessId(top, out pid);
                if (!pids.Contains(pid) || seen.Contains(pid)) return true;
                EnumChildWindows(top, (child, l2) =>
                {
                    var cls = ClassName(child);
                    if (cls != "mdiClass" && cls != "paneClassDC" && cls != "screenClass") return true;
                    var iid = new Guid("00020400-0000-0000-C000-000000000046");   // IDispatch
                    object o;
                    if (AccessibleObjectFromWindow(child, 0xFFFFFFF0 /* OBJID_NATIVEOM */, ref iid, out o) != 0 || o == null) return true;
                    try
                    {
                        dynamic d = o;
                        apps.Add((object)d.Application);
                        seen.Add(pid);
                        return false;
                    }
                    catch (Exception) { return true; }
                }, IntPtr.Zero);
                return true;
            }, IntPtr.Zero);
            return apps;
        }

        static string ClassName(IntPtr h)
        {
            var sb = new System.Text.StringBuilder(128);
            GetClassName(h, sb, sb.Capacity);
            return sb.ToString();
        }

        static bool PowerPointInFront()
        {
            try
            {
                uint pid;
                GetWindowThreadProcessId(GetForegroundWindow(), out pid);
                return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName
                    .Equals("POWERPNT", StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception) { return false; }
        }

        delegate bool EnumProc(IntPtr h, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc f, IntPtr l);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
        [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.IDispatch)] out object o);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

        // "40" (percent), "m40" when muted, or "" if it can't be read.
        public static string Volume()
        {
            try
            {
                var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                IMMDevice device;
                Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0 /* render */, 1 /* multimedia */, out device));
                var iid = typeof(IAudioEndpointVolume).GUID;
                object o;
                Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out o));
                var vol = (IAudioEndpointVolume)o;
                float level;
                bool muted;
                Marshal.ThrowExceptionForHR(vol.GetMasterVolumeLevelScalar(out level));
                Marshal.ThrowExceptionForHR(vol.GetMute(out muted));
                var pct = (int)Math.Round(level * 100);
                return (muted ? "m" : "") + pct;
            }
            catch (Exception)
            {
                return "";
            }
        }

        // "Artist - Title" (or just "Title") of the current media session, else "".
        public static async Task<string> NowPlaying()
        {
            try
            {
                var mgr = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
                var s = mgr.GetCurrentSession();
                if (s == null) return "";
                var p = await s.TryGetMediaPropertiesAsync();
                var title = (p.Title ?? "").Trim();
                var artist = (p.Artist ?? "").Trim();
                if (title.Length == 0) return "";
                return artist.Length > 0 ? artist + " - " + title : title;
            }
            catch (Exception)
            {
                return "";
            }
        }

        // ---------- Core Audio COM interop (only what is used) ----------

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
        class MMDeviceEnumeratorComObject { }

        [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator
        {
            int NotImpl1();
            [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        }

        [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice
        {
            [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        }

        [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioEndpointVolume
        {
            int NotImpl_RegisterControlChangeNotify();
            int NotImpl_UnregisterControlChangeNotify();
            int NotImpl_GetChannelCount();
            int NotImpl_SetMasterVolumeLevel();
            int NotImpl_SetMasterVolumeLevelScalar();
            int NotImpl_GetMasterVolumeLevel();
            [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
            int NotImpl_SetChannelVolumeLevel();
            int NotImpl_SetChannelVolumeLevelScalar();
            int NotImpl_GetChannelVolumeLevel();
            int NotImpl_GetChannelVolumeLevelScalar();
            int NotImpl_SetMute();
            [PreserveSig] int GetMute(out bool muted);
        }
    }
}
