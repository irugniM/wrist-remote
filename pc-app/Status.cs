// PC status sent back to the watch with each acknowledgement:
// PowerPoint slide position, system volume, and what is playing.
// Every part is best-effort: if something can't be read it is left empty.

using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Windows.Media.Control;

namespace WristRemote
{
    static class PcStatus
    {
        // "5/20" while a PowerPoint slide show is running, else "".
        public static string Slide()
        {
            try
            {
                dynamic app = Marshal.GetActiveObject("PowerPoint.Application");
                if (app.SlideShowWindows.Count < 1) return "";
                dynamic win = app.SlideShowWindows[1];
                int pos = win.View.CurrentShowPosition;
                int total = win.Presentation.Slides.Count;
                return pos + "/" + total;
            }
            catch (Exception)
            {
                return "";
            }
        }

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
