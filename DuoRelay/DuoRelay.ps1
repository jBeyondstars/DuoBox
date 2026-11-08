#requires -Version 5.1
<#
    DuoRelay: a Ctrl+click in the priest's WoW (PC 1) presses the warrior's keys
    in WoW on PC 2, over the local network (UDP).

    PC 1 (-Role Sender): while the relay is ON and WoW is the foreground window,
    a real click (not a camera drag) made with a trigger's modifier sends one
    message to PC 2. Ctrl+Alt+D (toggleKey) switches the relay ON / OFF; a small
    click-through label at the top of the screen shows the state.
    PC 2 (-Role Receiver): waits delayMs (the priest's new target has to reach
    the warrior's client through the game server first), then presses the
    trigger's keys in WoW ("SHIFT-T, T" = take the partner's target, then the
    interact key), only if WoW is the foreground window.
    Panel icons (DuoBox RelayPanel.lua): while the mouse is over icon N of the
    DuoBox spell panel, the addon draws a small colour code in the top-left
    corner of the WoW window. A left press in WoW (any modifier) reads those
    pixels; when they say N, the trigger with "pixel": N is relayed (its keys:
    the spell's action-bar key on PC 2) and no other trigger fires for that press.
    Warrior commands ("moves", "camera"; priest's DuoBox options, tab DuoRelay):
    a keyboard hook TAKES Ctrl+Q / Ctrl+S / Ctrl+D (held: PC 2 holds the
    warrior's strafe / back key) and Ctrl+Z (held: PC 1's mouse turns the
    warrior's camera, PC 2 holding a mouse button) from the priest's game, which
    never sees them, only while the relay is ON, WoW is in front and the
    priest's DuoBox draws its status code in the corner (the options are ticked).

    WARNING: one click acting in two game clients is input broadcasting, which
    Blizzard's multiboxing policy forbids whatever the transport (cable, LAN,
    KVM). Not part of DuoBox's "1 key press = 1 action in 1 client" design.
    OFF at start (startEnabled). See GUIDE.md section 7.

    Run with Windows PowerShell 5.1 (Start-Relay-PC1.bat / Start-Relay-PC2.bat).
      DuoRelay.ps1 -Role Sender [-Pc2 192.168.1.20]
      DuoRelay.ps1 -Role Receiver
      DuoRelay.ps1 -SetupFirewall      (PC 2, once: lets PC 1's messages in)
      DuoRelay.ps1 -SelfTest           (no network beyond 127.0.0.1, no key press)
      DuoRelay.ps1 -PixelProbe         (PC 1: shows the panel code read in WoW, sends nothing)
      DuoRelay.ps1 -HookTest           (the keyboard hook and the camera mode on this PC, with
                                        Ctrl+F13 / Ctrl+F14 and a few pixels of mouse, sends nothing)
    Ctrl+C to quit.
#>
param(
    [ValidateSet('Sender', 'Receiver')] [string]$Role,
    [string]$Config = (Join-Path $PSScriptRoot 'DuoRelay.json'),
    [string]$Pc2,
    [switch]$SetupFirewall,
    [switch]$Elevated,
    [switch]$SelfTest,
    [switch]$PixelProbe,
    [switch]$HookTest
)

$ErrorActionPreference = 'Stop'
$Proto = 'DUORELAY1'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('RelayInput' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public static class RelayInput {
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion u; }
    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public POINT pt; }

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern short VkKeyScan(char ch);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern bool GetCursorInfo(ref CURSORINFO ci);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr hWnd, ref POINT p);
    // 1 ms timer for this process: Start-Sleep 5 then lasts 5 ms instead of ~16 (short clicks)
    [DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint ms);
    [DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint ms);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint mode);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint mode);

    // A click in the console enters "QuickEdit" selection and freezes the script: turn it off
    public static bool DisableQuickEdit() {
        IntPtr h = GetStdHandle(-10); // STD_INPUT_HANDLE
        uint mode;
        if (!GetConsoleMode(h, out mode)) return false;
        return SetConsoleMode(h, (mode & ~0x40u) | 0x80u); // -ENABLE_QUICK_EDIT_MODE, +ENABLE_EXTENDED_FLAGS
    }

    // Arrows, Insert, Home, Page Up... share their scan code with the numeric keypad's
    // keys: without the extended flag the game reads the keypad's key
    static bool Extended(ushort vk) {
        return (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E || vk == 0x5B || vk == 0x5C || vk == 0x6F
            || vk == 0x90 || vk == 0xA3 || vk == 0xA5;
    }

    // Virtual key + matching scan code, as VoiceKeys.ps1 (works for every key WoW reads)
    public static void Key(ushort vk, bool up) {
        INPUT[] i = new INPUT[1];
        i[0].type = 1;
        i[0].u.ki.wVk = vk;
        i[0].u.ki.wScan = (ushort)MapVirtualKey(vk, 0);
        i[0].u.ki.dwFlags = (up ? 0x2u : 0u) | (Extended(vk) ? 0x1u : 0u); // KEYEVENTF_KEYUP, KEYEVENTF_EXTENDEDKEY
        SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
    }

    // PC 2, warrior camera: a mouse button and relative moves, as a mouse plugged into this PC
    public static void MouseButton(bool right, bool up) {
        INPUT[] i = new INPUT[1];
        i[0].type = 0;
        i[0].u.mi.dwFlags = right ? (up ? 0x10u : 0x08u) : (up ? 0x04u : 0x02u);
        SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void MoveMouse(int dx, int dy) {
        INPUT[] i = new INPUT[1];
        i[0].type = 0;
        i[0].u.mi.dx = dx;
        i[0].u.mi.dy = dy;
        i[0].u.mi.dwFlags = 0x1u; // MOUSEEVENTF_MOVE without ABSOLUTE: relative, like a real mouse
        SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);

    // Cursor at (fx, fy) of the window's client area (0 to 1 each)
    public static bool PlaceCursor(IntPtr hwnd, double fx, double fy) {
        RECT r;
        if (!GetClientRect(hwnd, out r)) return false;
        POINT p = new POINT();
        if (!ClientToScreen(hwnd, ref p)) return false;
        return SetCursorPos(p.X + (int)((r.Right - r.Left) * fx), p.Y + (int)((r.Bottom - r.Top) * fy));
    }

    public static bool IsDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

    // Physical pixels on every screen (per-monitor aware), else on the main one
    public static void DpiAware() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch (EntryPointNotFoundException) { }
        SetProcessDPIAware();
    }

    // Colours (0xRRGGBB) at the centres of 'count' squares of 'cell' pixels in a row,
    // from the top-left corner of the window's client area (DuoBox panel code), null if unreadable
    public static int[] ReadCells(IntPtr hwnd, int cell, int count) {
        POINT p = new POINT();
        if (!ClientToScreen(hwnd, ref p)) return null;
        using (Bitmap bmp = new Bitmap(cell * count, cell))
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.CopyFromScreen(p.X, p.Y, 0, 0, bmp.Size);
            int[] rgb = new int[count];
            for (int i = 0; i < count; i++) rgb[i] = bmp.GetPixel(i * cell + cell / 2, cell / 2).ToArgb() & 0xFFFFFF;
            return rgb;
        }
    }

    // Cursor position; returns false while the cursor is hidden (not used for clicks:
    // WoW hides it whenever a button is held over the 3D world)
    // (WoW hides it while the mouse turns the camera)
    public static bool Cursor(out int x, out int y) {
        CURSORINFO ci = new CURSORINFO();
        ci.cbSize = Marshal.SizeOf(typeof(CURSORINFO));
        if (!GetCursorInfo(ref ci)) { x = 0; y = 0; return true; }
        x = ci.pt.X; y = ci.pt.Y;
        return (ci.flags & 1) != 0 && ci.hCursor != IntPtr.Zero;
    }
}

// Small always-on-top status label: click-through, never takes the focus
public class RelayOverlay : Form {
    readonly Label label = new Label();
    readonly int left, top;
    readonly bool centered;

    public RelayOverlay(int x, int y, bool center) {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.Black;
        Opacity = 0.8; // must stay below 1: the window is layered
        label.AutoSize = true;
        label.Location = new Point(0, 0);
        label.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
        label.Padding = new Padding(6, 2, 6, 2);
        Controls.Add(label);
        left = x; top = y; centered = center;
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            // TOOLWINDOW | TOPMOST | TRANSPARENT (click-through) | LAYERED | NOACTIVATE
            cp.ExStyle |= 0x80 | 0x8 | 0x20 | 0x80000 | 0x8000000;
            return cp;
        }
    }

    public void SetStatus(string text, Color color) {
        if (label.Text == text && label.ForeColor == color) return;
        label.Text = text;
        label.ForeColor = color;
        ClientSize = label.PreferredSize;
        Rectangle screen = Screen.PrimaryScreen.Bounds;
        int x = centered ? screen.X + (screen.Width - Width) / 2 : screen.X + left;
        Location = new Point(x, screen.Y + top);
    }
}

// Which physical key presses of PC 1 DuoRelay takes from the game. A chord (main key +
// exactly these modifiers) is taken at its first key down while armed; its auto-repeats and
// its release are then taken too, even if disarmed meanwhile: the game never sees any part
// of that press. A press the game got first (key down before the modifier) stays the
// game's. Modifier keys always reach the game.
public class KeyFilter {
    public const int CTRL = 1, SHIFT = 2, ALT = 4, WIN = 8;
    readonly int[] keys, mods;
    readonly bool[] armed;
    readonly bool[] down = new bool[256];
    readonly int[] taken = new int[256]; // chord index + 1 that took the key's current press, 0 = the game's

    public KeyFilter(int[] keys, int[] mods) {
        if (keys == null || mods == null || keys.Length != mods.Length) throw new ArgumentException("keys and mods");
        this.keys = (int[])keys.Clone();
        this.mods = (int[])mods.Clone();
        armed = new bool[keys.Length];
    }

    public void SetArmed(int chord, bool on) { if (chord >= 0 && chord < armed.Length) armed[chord] = on; }

    public static bool IsModifier(int vk) {
        return vk == 0x10 || vk == 0x11 || vk == 0x12 || (vk >= 0xA0 && vk <= 0xA5) || vk == 0x5B || vk == 0x5C;
    }

    // One key event; true = taken (the game never sees it). pressed / released: the chord
    // whose press starts / ends with this event, else -1
    public bool Process(int vk, bool up, int modState, out int pressed, out int released) {
        pressed = -1;
        released = -1;
        if (vk <= 0 || vk > 255 || IsModifier(vk)) return false;
        if (up) {
            down[vk] = false;
            int t = taken[vk];
            taken[vk] = 0;
            if (t == 0) return false;
            released = t - 1;
            return true;
        }
        bool repeat = down[vk];
        down[vk] = true;
        if (taken[vk] != 0) return true; // auto-repeat of a taken press
        if (repeat) return false;        // auto-repeat of the game's press
        for (int i = 0; i < keys.Length; i++) {
            if (keys[i] == vk && mods[i] == modState && armed[i]) {
                taken[vk] = i + 1;
                pressed = i;
                return true;
            }
        }
        return false;
    }

    // The same for PowerShell (its 5.1 binder fails on out parameters): { taken 0/1, pressed, released }
    public int[] Feed(int vk, bool up, int modState) {
        int pressed, released;
        bool take = Process(vk, up, modState, out pressed, out released);
        return new int[] { take ? 1 : 0, pressed, released };
    }
}

// PC 1: the low-level keyboard hook (KeyFilter) and the camera mode, on their own thread
// with a message loop. Taken keys reach neither the game's key messages nor its raw input
// (checked 2026-11-08). Camera mode, while the camera chord is held: a low-level mouse hook
// keeps the priest's cursor in place and the mouse's raw movement is summed for PC 2. A
// hook cannot hide raw mouse input (movement or buttons, checked), so the mode only starts
// while the cursor shows (the game is not turning its camera) and no mouse button is held,
// and ends as soon as a button goes down (that click is the priest's) or the cursor hides.
public static class RelayHook {
    public static readonly ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    // -HookTest only: injected keys and mouse count as real ones, and the cursor is not checked
    // (an InputLeap client hides its PC's cursor while the mouse is on the other PC)
    public static bool TestMode;
    static KeyFilter filter;
    static int cameraChord = -1;
    static readonly object gate = new object();
    static int camState; // 1 = camera mode on
    static long camDx, camDy;
    static HookWindow window;
    static IntPtr kbHook, msHook;
    delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
    static readonly HookProc kbProc = KeyboardProc, msProc = MouseProc;
    const int WM_INPUT = 0x00FF, WM_CAMERA_ON = 0x8001, WM_CAMERA_OFF = 0x8002;

    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT { public uint vkCode; public uint scanCode; public uint flags; public uint time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT { public POINT pt; public uint mouseData; public uint flags; public uint time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public POINT pt; }
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE { public ushort usUsagePage; public ushort usUsage; public uint dwFlags; public IntPtr hwndTarget; }
    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTHEADER { public uint dwType; public uint dwSize; public IntPtr hDevice; public IntPtr wParam; }
    [StructLayout(LayoutKind.Explicit)]
    struct RAWMOUSE {
        [FieldOffset(0)] public ushort usFlags;
        [FieldOffset(4)] public ushort usButtonFlags;
        [FieldOffset(6)] public ushort usButtonData;
        [FieldOffset(8)] public uint ulRawButtons;
        [FieldOffset(12)] public int lLastX;
        [FieldOffset(16)] public int lLastY;
        [FieldOffset(20)] public uint ulExtraInformation;
    }

    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr mod, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern bool GetCursorInfo(ref CURSORINFO ci);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr hRawInput, uint command, IntPtr data, ref uint size, uint headerSize);

    // Hidden window of the hook thread: raw mouse input, mouse hook on / off
    class HookWindow : NativeWindow {
        public HookWindow() { CreateHandle(new CreateParams()); }
        protected override void WndProc(ref Message m) {
            if (m.Msg == WM_INPUT) OnRawInput(m.LParam);
            else if (m.Msg == WM_CAMERA_ON) CameraHooks(true);
            else if (m.Msg == WM_CAMERA_OFF) CameraHooks(false);
            base.WndProc(ref m);
        }
    }

    // chords: main keys and KeyFilter modifier masks; cameraIndex: the camera chord, -1 = none.
    // Returns an error text, null when the hook is in place
    public static string Start(int[] keys, int[] mods, int cameraIndex) {
        filter = new KeyFilter(keys, mods);
        cameraChord = cameraIndex;
        string error = null;
        ManualResetEvent ready = new ManualResetEvent(false);
        Thread t = new Thread(() => {
            try {
                window = new HookWindow();
                kbHook = SetWindowsHookEx(13, kbProc, GetModuleHandle(null), 0); // WH_KEYBOARD_LL
                if (kbHook == IntPtr.Zero) error = "keyboard hook refused, error " + Marshal.GetLastWin32Error();
            } catch (Exception e) { error = e.Message; }
            ready.Set();
            if (error == null) Application.Run();
        });
        t.IsBackground = true;
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        if (!ready.WaitOne(5000)) return "the hook thread did not start";
        return error;
    }

    public static void SetArmed(int chord, bool on) { if (filter != null) lock (gate) filter.SetArmed(chord, on); }

    public static bool CameraOn { get { return Thread.VolatileRead(ref camState) == 1; } }

    // Raw mouse movement since the last call, in device counts
    public static int[] TakeDelta() {
        long dx = Interlocked.Exchange(ref camDx, 0), dy = Interlocked.Exchange(ref camDy, 0);
        return new int[] { (int)dx, (int)dy };
    }

    static bool Down(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

    static int ModState() {
        return (Down(0x11) ? KeyFilter.CTRL : 0) | (Down(0x10) ? KeyFilter.SHIFT : 0) | (Down(0x12) ? KeyFilter.ALT : 0)
            | ((Down(0x5B) || Down(0x5C)) ? KeyFilter.WIN : 0);
    }

    // Hook procedures never throw: an exception here would end the process in the middle of a key press
    static IntPtr KeyboardProc(int code, IntPtr wParam, IntPtr lParam) {
        try {
            if (code >= 0) {
                KBDLLHOOKSTRUCT k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                if ((k.flags & 0x10) == 0 || TestMode) { // LLKHF_INJECTED: another program's keys are never taken
                    int pressed, released;
                    bool take;
                    lock (gate) take = filter.Process((int)k.vkCode, (k.flags & 0x80) != 0, ModState(), out pressed, out released);
                    if (pressed >= 0) { if (pressed == cameraChord) StartCamera(); else Events.Enqueue("DOWN " + pressed); }
                    if (released >= 0) { if (released == cameraChord) StopCamera("released"); else Events.Enqueue("UP " + released); }
                    if (take) return (IntPtr)1;
                }
            }
        } catch (Exception e) { Events.Enqueue("CAMERR keyboard hook: " + e.Message); }
        return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
    }

    // Why the camera mode cannot start now, null when it can
    static string CameraBlocker() {
        CURSORINFO ci = new CURSORINFO();
        ci.cbSize = Marshal.SizeOf(typeof(CURSORINFO));
        if (!TestMode && GetCursorInfo(ref ci) && ((ci.flags & 1) == 0 || ci.hCursor == IntPtr.Zero)) return "cursor hidden (the game turns its camera)";
        foreach (int b in new int[] { 0x01, 0x02, 0x04, 0x05, 0x06 }) if (Down(b)) return "a mouse button is held";
        return null;
    }

    static void StartCamera() {
        string why = CameraBlocker();
        if (why != null) { Events.Enqueue("CAMNO " + why); return; }
        Interlocked.Exchange(ref camDx, 0);
        Interlocked.Exchange(ref camDy, 0);
        if (Interlocked.CompareExchange(ref camState, 1, 0) != 0) return;
        PostMessage(window.Handle, WM_CAMERA_ON, IntPtr.Zero, IntPtr.Zero);
        Events.Enqueue("CAMON");
    }

    // Any thread: ends the camera mode (the chord itself stays taken until released)
    public static void StopCamera(string reason) {
        if (Interlocked.CompareExchange(ref camState, 0, 1) != 1) return;
        if (window != null) PostMessage(window.Handle, WM_CAMERA_OFF, IntPtr.Zero, IntPtr.Zero);
        Events.Enqueue("CAMOFF " + reason);
    }

    // Hook thread: mouse hook and raw mouse input only during the camera mode
    static void CameraHooks(bool on) {
        RAWINPUTDEVICE[] d = new RAWINPUTDEVICE[1];
        d[0].usUsagePage = 1;
        d[0].usUsage = 2; // mouse
        if (on && Thread.VolatileRead(ref camState) == 1 && msHook == IntPtr.Zero) {
            d[0].dwFlags = 0x100; // RIDEV_INPUTSINK: in the background too
            d[0].hwndTarget = window.Handle;
            if (!RegisterRawInputDevices(d, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
                Events.Enqueue("CAMERR raw mouse input refused, error " + Marshal.GetLastWin32Error());
            msHook = SetWindowsHookEx(14, msProc, GetModuleHandle(null), 0); // WH_MOUSE_LL
            if (msHook == IntPtr.Zero) Events.Enqueue("CAMERR mouse hook refused, error " + Marshal.GetLastWin32Error());
        } else if (!on && msHook != IntPtr.Zero) {
            UnhookWindowsHookEx(msHook);
            msHook = IntPtr.Zero;
            d[0].dwFlags = 0x1; // RIDEV_REMOVE
            d[0].hwndTarget = IntPtr.Zero;
            RegisterRawInputDevices(d, 1, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE)));
        }
    }

    static IntPtr MouseProc(int code, IntPtr wParam, IntPtr lParam) {
        try {
            if (code >= 0 && Thread.VolatileRead(ref camState) == 1) {
                MSLLHOOKSTRUCT m = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                if ((m.flags & 1) == 0 || TestMode) { // LLMHF_INJECTED
                    int msg = wParam.ToInt32();
                    if (msg == 0x0200) return (IntPtr)1; // WM_MOUSEMOVE: the priest's cursor stays put
                    // L / R / M / X button down: the camera mode ends, the click goes to the priest
                    if (msg == 0x0201 || msg == 0x0204 || msg == 0x0207 || msg == 0x020B) StopCamera("mouse button");
                }
            }
        } catch (Exception e) { Events.Enqueue("CAMERR mouse hook: " + e.Message); }
        return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
    }

    static void OnRawInput(IntPtr handle) {
        try { ReadRawInput(handle); } catch (Exception e) { Events.Enqueue("CAMERR raw input: " + e.Message); }
    }

    static void ReadRawInput(IntPtr handle) {
        if (Thread.VolatileRead(ref camState) != 1) return;
        uint size = 0, headerSize = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));
        GetRawInputData(handle, 0x10000003, IntPtr.Zero, ref size, headerSize); // RID_INPUT
        if (size == 0) return;
        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try {
            if (GetRawInputData(handle, 0x10000003, buffer, ref size, headerSize) != size) return;
            RAWINPUTHEADER head = (RAWINPUTHEADER)Marshal.PtrToStructure(buffer, typeof(RAWINPUTHEADER));
            if (head.dwType != 0) return; // RIM_TYPEMOUSE
            RAWMOUSE r = (RAWMOUSE)Marshal.PtrToStructure(new IntPtr(buffer.ToInt64() + headerSize), typeof(RAWMOUSE));
            if ((r.usFlags & 1) != 0) return; // MOUSE_MOVE_ABSOLUTE (tablet, remote desktop): no relative movement
            if (r.lLastX != 0) Interlocked.Add(ref camDx, r.lLastX);
            if (r.lLastY != 0) Interlocked.Add(ref camDy, r.lLastY);
        } finally {
            Marshal.FreeHGlobal(buffer);
        }
        CURSORINFO ci = new CURSORINFO();
        ci.cbSize = Marshal.SizeOf(typeof(CURSORINFO));
        if (!TestMode && GetCursorInfo(ref ci) && (ci.flags & 1) == 0) StopCamera("cursor hidden (the game turns its camera)");
    }
}
"@
}

# --- Logging ---------------------------------------------------------------

function Write-Log([string]$msg, [string]$color = 'Gray') {
    Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg) -ForegroundColor $color
}

function Disable-QuickEdit {
    if (-not [RelayInput]::DisableQuickEdit()) { Write-Log "Could not disable console QuickEdit: don't click inside this window." 'DarkYellow' }
}

# --- Keys (same format as VoiceKeys/commands.json) ---------------------------

$Modifiers = @{ SHIFT = 0x10; CTRL = 0x11; ALT = 0x12 }
$MouseButtons = @{ LEFT = 0x01; RIGHT = 0x02; MIDDLE = 0x04; X1 = 0x05; X2 = 0x06 }

function Get-VK([string]$name) {
    $n = $name.ToUpper()
    if ($n -match '^F(\d{1,2})$') {
        $f = [int]$Matches[1]
        if ($f -ge 1 -and $f -le 24) { return 0x6F + $f }
    }
    if ($n -match '^NUMPAD(\d)$') { return 0x60 + [int]$Matches[1] }
    if ($n -match '^[A-Z0-9]$') { return [int][char]$n }
    $special = @{ SPACE = 0x20; TAB = 0x09; ENTER = 0x0D; BACKSPACE = 0x08; INSERT = 0x2D; DELETE = 0x2E;
                  HOME = 0x24; END = 0x23; PAGEUP = 0x21; PAGEDOWN = 0x22; PAUSE = 0x13; SCROLLLOCK = 0x91
                  LEFT = 0x25; UP = 0x26; RIGHT = 0x27; DOWN = 0x28 }
    if ($special.ContainsKey($n)) { return $special[$n] }
    # Any other single character ("&", "^"...): the key that types it on this keyboard layout
    if ($name.Length -eq 1) {
        $scan = [RelayInput]::VkKeyScan($name[0])
        if ($scan -ne -1) {
            if (($scan -shr 8) -band 0x7) { throw "Key '$name' needs a modifier (Shift/AltGr) on this layout: use the base key instead" }
            return $scan -band 0xFF
        }
    }
    throw "Unknown key: '$name'"
}

# "CTRL-ALT-D" -> @{ mods = @(0x11, 0x12); vk = 0x44 }
function ConvertTo-Chord([string]$key) {
    $parts = $key.Trim().ToUpper() -split '-'
    $mods = @()
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        if (-not $Modifiers.ContainsKey($parts[$i])) { throw "Unknown modifier '$($parts[$i])' in '$key'" }
        $mods += $Modifiers[$parts[$i]]
    }
    return @{ mods = $mods; vk = (Get-VK $parts[-1]) }
}

# "SHIFT-T, T" -> two chords pressed one after the other
function ConvertTo-Chords([string]$key) {
    $parts = @($key -split ',' | ForEach-Object { $_.Trim() })
    if ($parts -contains '') { throw "Empty key in '$key'" }
    return ,@($parts | ForEach-Object { ConvertTo-Chord $_ })
}

function Send-Chord($chord) {
    foreach ($m in $chord.mods) { [RelayInput]::Key([uint16]$m, $false) }
    [RelayInput]::Key([uint16]$chord.vk, $false)
    Start-Sleep -Milliseconds 40
    [RelayInput]::Key([uint16]$chord.vk, $true)
    for ($i = $chord.mods.Count - 1; $i -ge 0; $i--) { [RelayInput]::Key([uint16]$chord.mods[$i], $true) }
}

function Send-Chords($chords) {
    for ($i = 0; $i -lt $chords.Count; $i++) {
        if ($i) { Start-Sleep -Milliseconds 50 }  # lets WoW handle the previous key first
        Send-Chord $chords[$i]
    }
}

# Every key of the chord held (toggle key)
function Test-ChordHeld($chord) {
    foreach ($m in $chord.mods) { if (-not [RelayInput]::IsDown($m)) { return $false } }
    return [RelayInput]::IsDown($chord.vk)
}

# Exactly these modifiers held: Ctrl+click does not fire on Ctrl+Shift+click
function Test-Modifiers($mods) {
    foreach ($vk in $Modifiers.Values) {
        if ([RelayInput]::IsDown($vk) -ne ($mods -contains $vk)) { return $false }
    }
    return $true
}

# Chord modifiers -> KeyFilter mask (CTRL 1, SHIFT 2, ALT 4)
function Get-ModMask($mods) {
    $mask = 0
    foreach ($m in @($mods)) {
        if ($m -eq 0x11) { $mask = $mask -bor 1 } elseif ($m -eq 0x10) { $mask = $mask -bor 2 } elseif ($m -eq 0x12) { $mask = $mask -bor 4 }
    }
    return $mask
}

# --- Configuration -----------------------------------------------------------

$Defaults = [ordered]@{
    port = 47815; pc2Address = ''; pc1Address = ''; startEnabled = $false; toggleKey = 'CTRL-ALT-D'
    processNames = @('Wow', 'WowB', 'WowClassic', 'WowClassicB'); triggers = @()
    maxClickMovePx = 30; maxClickMs = 500; delayMs = 300; minIntervalMs = 500
    overlay = $true; overlayX = -1; overlayY = 2; sounds = $false
    pixelCell = 8   # physical pixels per square of the panel code (CELL in RelayPanel.lua)
    moves = @(); camera = $null
    maxHoldMs = 30000; maxCameraMs = 60000   # a move / a camera turn held longer is released on PC 2
    streamTimeoutMs = 400                     # PC 2 releases what PC 1 stopped confirming (every 100 ms)
}
# Per-PC settings (IP addresses), written by the script, not in git
$LocalConfig = [IO.Path]::ChangeExtension($Config, '.local.json')

function Read-Json([string]$path) { Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }

function Import-RelayConfig {
    $c = Read-Json $Config
    if (Test-Path -LiteralPath $LocalConfig) {
        foreach ($p in (Read-Json $LocalConfig).PSObject.Properties) {
            $c | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
        }
    }
    foreach ($k in $Defaults.Keys) {
        if ($null -eq $c.$k) { $c | Add-Member -NotePropertyName $k -NotePropertyValue $Defaults[$k] -Force }
    }
    return $c
}

function Save-LocalSetting([string]$name, $value) {
    $local = if (Test-Path -LiteralPath $LocalConfig) { Read-Json $LocalConfig } else { [pscustomobject]@{} }
    $local | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    [IO.File]::WriteAllText($LocalConfig, ($local | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Write-Log ("Saved {0} = {1} in {2}" -f $name, $value, (Split-Path $LocalConfig -Leaf)) 'DarkGray'
}

function ConvertTo-Trigger($t) {
    $name = ([string]$t.name).Trim()
    if ($name -notmatch '^[A-Za-z0-9_-]+$') { throw "Trigger name '$name': letters, digits, - and _ only" }
    # Optional per-trigger wait on PC 2 (pickup: the addon's message has to arrive first)
    $delay = if ($null -ne $t.delayMs) { [int]$t.delayMs } else { [int]$cfg.delayMs }
    if ($null -ne $t.pixel) {
        # Icon of the DuoBox panel: a left click on it, recognised by the code drawn in the corner
        $code = 0
        if (-not [int]::TryParse([string]$t.pixel, [ref]$code) -or $code -lt 1 -or $code -gt 36) {
            throw "Trigger '$name': pixel '$($t.pixel)' must be 1 to 36 (icon number in the DuoBox panel)"
        }
        if ($t.button -or $t.modifier) { throw "Trigger '$name': a pixel trigger takes no button / modifier (a left click on the icon)" }
        return [pscustomobject]@{
            name = $name; label = [string]$t.label; keys = [string]$t.keys; chords = (ConvertTo-Chords $t.keys); delayMs = $delay
            combo = "click on icon $code"; pixel = $code; buttonVk = 0; mods = @(); state = @{ wasDown = $false; armed = $false }; drag = $false
        }
    }
    $button = ([string]$t.button).Trim().ToUpper()
    if (-not $MouseButtons.ContainsKey($button)) { throw "Trigger '$name': unknown button '$($t.button)' (LEFT, RIGHT, MIDDLE, X1, X2)" }
    $mods = @()
    foreach ($m in (([string]$t.modifier).Trim().ToUpper() -split '-' | Where-Object { $_ })) {
        if (-not $Modifiers.ContainsKey($m)) { throw "Trigger '$name': unknown modifier '$m' (CTRL, ALT, SHIFT, e.g. CTRL-SHIFT)" }
        $mods += $Modifiers[$m]
    }
    if ($mods.Count -eq 0) { throw "Trigger '$name': a modifier is required, otherwise every click would be relayed" }
    return [pscustomobject]@{
        name = $name; label = [string]$t.label; keys = [string]$t.keys; chords = (ConvertTo-Chords $t.keys); delayMs = $delay
        combo = ('{0}+{1} click' -f ([string]$t.modifier).ToUpper(), $button.ToLower()); pixel = 0
        buttonVk = $MouseButtons[$button]; mods = $mods; state = @{ wasDown = $false; armed = $false }
        drag = ($button -eq 'LEFT' -or $button -eq 'RIGHT') # the buttons that turn the camera when dragged
    }
}

# Config list -> @{ all = name -> trigger (ordered); pixel = icon number -> trigger }
function Import-Triggers($list) {
    $all = [ordered]@{}; $pixel = @{}
    foreach ($t in @($list)) {
        $trigger = ConvertTo-Trigger $t
        if ($all.Contains($trigger.name)) { throw "Duplicate trigger name '$($trigger.name)'" }
        if ($trigger.pixel) {
            if ($pixel.ContainsKey($trigger.pixel)) { throw "Triggers '$($pixel[$trigger.pixel].name)' and '$($trigger.name)' have the same pixel $($trigger.pixel)" }
            $pixel[$trigger.pixel] = $trigger
        }
        $all[$trigger.name] = $trigger
    }
    return @{ all = $all; pixel = $pixel }
}

# "moves": a key chord held on PC 1, taken from the priest's game -> one key held on PC 2
function ConvertTo-Move($m) {
    $name = ([string]$m.name).Trim()
    if ($name -notmatch '^[A-Za-z0-9_-]+$') { throw "Move '$name': letters, digits, - and _ only" }
    $chord = ConvertTo-Chord ([string]$m.key)
    if ([KeyFilter]::IsModifier($chord.vk)) { throw "Move '$name': key '$($m.key)' ends with a modifier" }
    $hold = ConvertTo-Chord ([string]$m.hold)
    if (@($hold.mods).Count) { throw "Move '$name': hold '$($m.hold)' must be one key without modifier (it stays down on PC 2)" }
    return [pscustomobject]@{
        name = $name; label = [string]$m.label; key = ([string]$m.key).Trim().ToUpper(); vk = $chord.vk
        mask = (Get-ModMask $chord.mods); hold = ([string]$m.hold).Trim().ToUpper(); holdVk = $hold.vk
    }
}

function Import-Moves($list) {
    $all = [ordered]@{}
    foreach ($m in @($list)) {
        if ($null -eq $m) { continue }
        $move = ConvertTo-Move $m
        if ($all.Contains($move.name)) { throw "Duplicate move name '$($move.name)'" }
        $all[$move.name] = $move
    }
    return $all
}

# "camera": the chord held on PC 1 while the mouse turns the warrior's camera; $null = none
function ConvertTo-Camera($c) {
    if ($null -eq $c -or -not ([string]$c.key).Trim()) { return $null }
    $chord = ConvertTo-Chord ([string]$c.key)
    if ([KeyFilter]::IsModifier($chord.vk)) { throw "camera: key '$($c.key)' ends with a modifier" }
    $speed = 1.0
    if ($null -ne $c.speed -and -not [double]::TryParse([string]$c.speed, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$speed)) { throw "camera: speed '$($c.speed)' is not a number" }
    if ($speed -le 0 -or $speed -gt 10) { throw "camera: speed $speed must be above 0 and at most 10" }
    return [pscustomobject]@{ key = ([string]$c.key).Trim().ToUpper(); vk = $chord.vk; mask = (Get-ModMask $chord.mods)
                              label = [string]$c.label; speed = $speed }
}

# The same chord twice (move, camera, toggle key) would make one press do two things
function Test-CommandKeys($moves, $camera, [string]$toggleKey) {
    $seen = @{}
    $toggle = ConvertTo-Chord $toggleKey
    $seen["$($toggle.vk)/$(Get-ModMask $toggle.mods)"] = "toggleKey $toggleKey"
    $all = @($moves.Values | ForEach-Object { @{ what = "move $($_.name)"; vk = $_.vk; mask = $_.mask; key = $_.key } })
    if ($camera) { $all += @{ what = 'camera'; vk = $camera.vk; mask = $camera.mask; key = $camera.key } }
    foreach ($c in $all) {
        $id = "$($c.vk)/$($c.mask)"
        if ($seen.ContainsKey($id)) { throw "$($c.what) and $($seen[$id]) use the same key $($c.key)" }
        $seen[$id] = "$($c.what) ($($c.key))"
    }
}

# --- Panel code (RelayPanel.lua) -------------------------------------------
# 4 squares A, 7-A, B, 7-B; each channel full (>= 170) or off (<= 85), 4 = red,
# 2 = green, 1 = blue; A and B 1 to 6; icon = (A - 1) * 6 + B. 0 = no code.
# Status code, drawn whenever no icon code is: 0 (black), 7 (white), S, 7-S;
# S = camera (0 off, 1 camera only, 2 camera + the warrior turns) + 3 * moves (0/1).

# The 4 squares' colours -> their values 0-7, $null if one is not a full / off colour
function Get-CellValues($rgb) {
    if ($null -eq $rgb -or @($rgb).Count -ne 4) { return $null }
    $v = @()
    foreach ($c in @($rgb)) {
        $bits = 0
        foreach ($shift in 16, 8, 0) {
            $ch = ([int]$c -shr $shift) -band 0xFF
            if ($ch -ge 170) { $bits = $bits * 2 + 1 } elseif ($ch -le 85) { $bits = $bits * 2 } else { return $null }
        }
        $v += $bits
    }
    return ,$v
}

function ConvertFrom-PixelCells($rgb) {
    $v = Get-CellValues $rgb
    if ($null -eq $v) { return 0 }
    if ($v[0] -lt 1 -or $v[0] -gt 6 -or $v[2] -lt 1 -or $v[2] -gt 6) { return 0 }
    if ($v[1] -ne 7 - $v[0] -or $v[3] -ne 7 - $v[2]) { return 0 }
    return ($v[0] - 1) * 6 + $v[2]
}

# Status code -> S (1 to 5), 0 if the squares are not a status code
function ConvertFrom-StatusCells($rgb) {
    $v = Get-CellValues $rgb
    if ($null -eq $v) { return 0 }
    if ($v[0] -ne 0 -or $v[1] -ne 7 -or $v[2] -lt 1 -or $v[2] -gt 5 -or $v[3] -ne 7 - $v[2]) { return 0 }
    return $v[2]
}

# Values 0-7 -> the colours drawn (self-test)
function ConvertTo-Cells($values) {
    return ,@(foreach ($v in $values) {
        $(if ($v -band 4) { 0xFF0000 } else { 0 }) -bor $(if ($v -band 2) { 0xFF00 } else { 0 }) -bor $(if ($v -band 1) { 0xFF } else { 0 })
    })
}

# Icon number -> the 4 colours RelayPanel.lua draws (self-test)
function ConvertTo-PixelCells([int]$n) {
    $a = [int][math]::Floor(($n - 1) / 6) + 1; $b = ($n - 1) % 6 + 1
    return ConvertTo-Cells @($a, (7 - $a), $b, (7 - $b))
}

function ConvertTo-StatusCells([int]$s) { return ConvertTo-Cells @(0, 7, $s, (7 - $s)) }

# Status S -> what the priest's options ask for
function Get-StatusParts([int]$s) {
    $cam = $s % 3
    return @{ moves = ($s -ge 3); camera = ($cam -ne 0); button = $(if ($cam -eq 2) { 'R' } else { 'L' }) }
}

function Format-Status([int]$s) {
    if ($s -le 0) { return 'none' }
    $p = Get-StatusParts $s
    $parts = @()
    if ($p.camera) { $parts += $(if ($p.button -eq 'R') { 'camera + the warrior turns' } else { 'camera only' }) }
    if ($p.moves) { $parts += 'moves' }
    return $parts -join ', '
}

# Colours of the code squares in the foreground window (WoW), $null if unreadable
function Read-PanelCells {
    try { return [RelayInput]::ReadCells([RelayInput]::GetForegroundWindow(), [int]$cfg.pixelCell, 4) }
    catch { Write-Log ("Screen read failed: {0}" -f $_.Exception.Message) 'DarkYellow'; return $null }
}

function Format-Cells($rgb) {
    if ($null -eq $rgb) { return 'unreadable' }
    return (@($rgb) | ForEach-Object { '#{0:X6}' -f $_ }) -join ' '
}

# --- Protocol ----------------------------------------------------------------
# One ASCII datagram: DUORELAY1|<seq>|<kind>|<arg>
#   PC 1 -> PC 2: CLICK|<trigger name>, PING|
#     moves: DOWN|<move name> at the press, KEEP|<name> every 100 ms while held, UP|<name> (sent twice)
#     camera: CAM|<L or R>_<dx>_<dy> (raw mouse counts, at least every 100 ms), CAMEND| (sent twice)
#   PC 2 -> PC 1: ACK|sent|held|notfocused|busy|unknown (same seq; CLICK and DOWN only),
#                 PONG|1 or 0 (WoW in the foreground)
#   PC 2 releases a held key or the camera button when PC 1 stops confirming it (streamTimeoutMs).

function New-RelayMessage([long]$seq, [string]$kind, [string]$arg = '') { return "$Proto|$seq|$kind|$arg" }

function ConvertFrom-RelayMessage([string]$text) {
    $p = $text -split '\|'
    if ($p.Count -ne 4 -or $p[0] -ne $Proto) { return $null }
    $seq = [long]0
    if (-not [long]::TryParse($p[1], [ref]$seq)) { return $null }
    if ($p[2] -cnotmatch '^[A-Z]+$' -or $p[3] -notmatch '^[A-Za-z0-9_-]*$') { return $null }
    return [pscustomobject]@{ seq = $seq; kind = $p[2]; arg = $p[3] }
}

function New-RelaySocket([Net.IPAddress]$address, [int]$port) {
    $udp = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new($address, $port))
    # Windows turns an ICMP "port unreachable" (PC 2 not listening) into an error
    # on the next receive (SIO_UDP_CONNRESET): ignore it
    [void]$udp.Client.IOControl([int]-1744830452, [byte[]](0, 0, 0, 0), $null)
    return $udp
}

function Send-Relay($udp, [Net.IPEndPoint]$to, [string]$msg) {
    $b = [Text.Encoding]::ASCII.GetBytes($msg)
    try { [void]$udp.Send($b, $b.Length, $to); return $true }
    catch { Write-Log ("Send to {0} failed: {1}" -f $to, $_.Exception.Message) 'DarkYellow'; return $false }
}

# PC 2 only accepts PC 1 (pc1Address) or, without it, a private network address
function Test-AllowedSender([Net.IPAddress]$addr) {
    if ($cfg.pc1Address) { return $addr.ToString() -eq [string]$cfg.pc1Address }
    $b = $addr.GetAddressBytes()
    if ($b.Count -ne 4) { return $false }
    return $b[0] -eq 10 -or $b[0] -eq 127 -or ($b[0] -eq 192 -and $b[1] -eq 168) -or
        ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 169 -and $b[1] -eq 254)
}

$script:ForegroundOverride = $null   # self-test only
$script:DryRun = $false              # self-test only: no key press
$script:NoDelay = $false             # self-test only: no wait before the keys

function Test-WowForeground {
    if ($null -ne $script:ForegroundOverride) { return $script:ForegroundOverride }
    $procId = [uint32]0
    [void][RelayInput]::GetWindowThreadProcessId([RelayInput]::GetForegroundWindow(), [ref]$procId)
    try { $name = (Get-Process -Id $procId).ProcessName } catch { return $false }
    return @($cfg.processNames) -contains $name
}

# PC 2: the same, asked at most every 100 ms (the camera sends ~200 messages a second)
function Test-WowForegroundCached($state, [long]$now) {
    if ($null -ne $script:ForegroundOverride) { return $script:ForegroundOverride }
    if ($null -eq $state.fgAt -or $now - $state.fgAt -ge 100) { $state.fg = Test-WowForeground; $state.fgAt = $now }
    return $state.fg
}

# --- PC 2: warrior commands held from PC 1 (moves, camera) -------------------

$script:Actions = $null   # self-test: what would be pressed, in place of pressing it
$MinDragPx = 12           # a camera turn on PC 2 moves at least this much: a press + release that
                          # does not move is a click (interact, or walk there with Click-to-Move)

function Invoke-Key([int]$vk, [bool]$up, [string]$name) {
    if ($script:DryRun) { if ($null -ne $script:Actions) { [void]$script:Actions.Add(('{0} {1}' -f $(if ($up) { 'up' } else { 'down' }), $name)) }; return }
    [RelayInput]::Key([uint16]$vk, $up)
}

function Invoke-MouseButton([string]$button, [bool]$up) {
    if ($script:DryRun) { if ($null -ne $script:Actions) { [void]$script:Actions.Add(('mouse {0} {1}' -f $button, $(if ($up) { 'up' } else { 'down' }))) }; return }
    [RelayInput]::MouseButton($button -eq 'R', $up)
}

function Invoke-MouseMove([int]$dx, [int]$dy) {
    if ($script:DryRun) { if ($null -ne $script:Actions) { [void]$script:Actions.Add("move $dx $dy") }; return }
    [RelayInput]::MoveMouse($dx, $dy)
}

# Over the game world, above the warrior and away from the bars, before a button goes down
function Invoke-PlaceCursor {
    if ($script:DryRun) { if ($null -ne $script:Actions) { [void]$script:Actions.Add('cursor') }; return }
    [void][RelayInput]::PlaceCursor([RelayInput]::GetForegroundWindow(), 0.5, 0.3)
}

function Start-Hold($state, $mv, [long]$now) {
    $state.held[$mv.name] = @{ vk = $mv.holdVk; key = $mv.hold; last = $now }
    Invoke-Key $mv.holdVk $false $mv.hold
    Write-Log ("{0,-12} -> {1} held" -f $mv.name, $mv.hold) 'White'
}

function Stop-Hold($state, [string]$name, [string]$why) {
    $h = $state.held[$name]
    if (-not $h) { return }
    $state.held.Remove($name)
    Invoke-Key $h.vk $true $h.key
    Write-Log ("{0,-12} -> {1} released{2}" -f $name, $h.key, $(if ($why) { " ($why)" } else { '' })) $(if ($why) { 'Yellow' } else { 'DarkGray' })
}

# One CAM message: the first one places the cursor; the button goes down with the first movement
function Step-Camera($state, [string]$button, [int]$dx, [int]$dy, [long]$now) {
    $c = $state.cam
    if (-not $c) {
        if (-not (Test-WowForegroundCached $state $now)) { return }
        $c = @{ button = $button; pressed = $false; total = 0; last = $now }
        $state.cam = $c
        Invoke-PlaceCursor
        Write-Log ("camera       -> {0} held while PC 1's mouse moves" -f $(if ($button -eq 'R') { 'right button (the warrior turns too)' } else { 'left button (camera only)' })) 'White'
    }
    $c.last = $now
    if ($dx -or $dy) {
        if (-not $c.pressed) { Invoke-MouseButton $c.button $false; $c.pressed = $true }
        Invoke-MouseMove $dx $dy
        $c.total += [math]::Abs($dx) + [math]::Abs($dy)
    }
}

function Stop-Camera($state, [string]$why) {
    $c = $state.cam
    if (-not $c) { return }
    $state.cam = $null
    if ($c.pressed) {
        if ($c.total -lt $MinDragPx) { Invoke-MouseMove ($MinDragPx - $c.total) 0 } # a turn, never a click
        Invoke-MouseButton $c.button $true
    }
    Write-Log ("camera       -> released{0}" -f $(if ($why) { " ($why)" } else { '' })) $(if ($why) { 'Yellow' } else { 'DarkGray' })
}

# Called when no message waits: releases what PC 1 stopped confirming, everything when WoW left the front
function Step-StreamSafety($state, [long]$now) {
    if (-not $state.held.Count -and -not $state.cam) { return }
    $timeout = [int]$cfg.streamTimeoutMs
    $fg = Test-WowForegroundCached $state $now
    foreach ($name in @($state.held.Keys)) {
        if (-not $fg) { Stop-Hold $state $name 'WoW is no longer the foreground window' }
        elseif ($now - $state.held[$name].last -gt $timeout) { Stop-Hold $state $name "no news from PC 1 for $timeout ms" }
    }
    if ($state.cam) {
        if (-not $fg) { Stop-Camera $state 'WoW is no longer the foreground window' }
        elseif ($now - $state.cam.last -gt $timeout) { Stop-Camera $state "no news from PC 1 for $timeout ms" }
    }
}

function Stop-AllHeld($state, [string]$why) {
    foreach ($name in @($state.held.Keys)) { Stop-Hold $state $name $why }
    Stop-Camera $state $why
}

# --- PC 1: click detection -------------------------------------------------

# One poll of a trigger's mouse button. Returns $true when a click is relayed.
# $ok: pressed with the modifier, relay ON, WoW focused.
# $drag = $true (left / right buttons, which turn the camera when dragged): only a
# click released within $maxMs, the cursor moved at most $maxMove px; $s.reason
# then says why a press was dropped. The cursor is not used: WoW hides it as soon
# as a button is held over the 3D world, for a plain click too (seen 2026-11-06),
# and keeps it in place while the camera turns, so only the time tells a drag.
# $drag = $false (middle, side buttons): relayed as soon as pressed.
function Step-Click($s, [bool]$down, [bool]$ok, [int]$x, [int]$y, [long]$now, [int]$maxMove, [int]$maxMs, [bool]$drag = $true) {
    $fired = $false
    if ($down -and -not $s.wasDown) {
        $s.armed = $ok -and $drag; $s.x = $x; $s.y = $y; $s.t = $now
        $fired = $ok -and -not $drag
    } elseif ($s.armed) {
        $dist = [math]::Max([math]::Abs($x - $s.x), [math]::Abs($y - $s.y))
        if ($dist -gt $maxMove) { $s.armed = $false; $s.reason = "mouse moved $dist px (max ${maxMove}: a drag turns the camera)" }
        elseif (($now - $s.t) -gt $maxMs) { $s.armed = $false; $s.reason = "held over $maxMs ms (a camera turn?)" }
        elseif (-not $down) { $fired = $true }
    }
    if (-not $down) { $s.armed = $false }
    $s.wasDown = $down
    return $fired
}

# --- PC 2: one received datagram -> reply (or $null) -----------------------

function Invoke-RelayPacket([string]$text, $state) {
    $m = ConvertFrom-RelayMessage $text
    if (-not $m) { return $null }
    if ($m.kind -eq 'PING') {
        $fg = if (Test-WowForeground) { '1' } else { '0' }
        return New-RelayMessage $m.seq 'PONG' $fg
    }
    # Moves: DOWN starts holding the key (ACK), KEEP confirms it (or starts it if DOWN was lost), UP releases it
    if ($m.kind -eq 'DOWN' -or $m.kind -eq 'KEEP') {
        $first = $m.kind -eq 'DOWN'
        $mv = if ($null -ne $state.moves) { $state.moves[$m.arg] }
        if (-not $mv) {
            if (-not $first) { return $null }
            Write-Log ("Unknown move '{0}': same DuoRelay.json on both PCs?" -f $m.arg) 'Yellow'
            return New-RelayMessage $m.seq 'ACK' 'unknown'
        }
        $now = $state.clock.ElapsedMilliseconds
        if ($state.held.ContainsKey($mv.name)) {
            $state.held[$mv.name].last = $now
        } elseif (Test-WowForegroundCached $state $now) {
            Start-Hold $state $mv $now
        } else {
            if (-not $first) { return $null }
            Write-Log ("{0} ignored: WoW is not the foreground window on this PC." -f $mv.name) 'Yellow'
            return New-RelayMessage $m.seq 'ACK' 'notfocused'
        }
        if ($first) { return New-RelayMessage $m.seq 'ACK' 'held' }
        return $null
    }
    if ($m.kind -eq 'UP') { Stop-Hold $state $m.arg ''; return $null }
    if ($m.kind -eq 'CAM') {
        if ($m.arg -cnotmatch '^([LR])_(-?\d{1,5})_(-?\d{1,5})$') { return $null }
        Step-Camera $state $Matches[1] ([int]$Matches[2]) ([int]$Matches[3]) $state.clock.ElapsedMilliseconds
        return $null
    }
    if ($m.kind -eq 'CAMEND') { Stop-Camera $state ''; return $null }
    if ($m.kind -ne 'CLICK') { return $null }

    $t = $state.triggers[$m.arg]
    if (-not $t) {
        Write-Log ("Unknown trigger '{0}': same DuoRelay.json on both PCs?" -f $m.arg) 'Yellow'
        return New-RelayMessage $m.seq 'ACK' 'unknown'
    }
    $now = $state.clock.ElapsedMilliseconds
    if ($null -ne $state.lastFired -and ($now - $state.lastFired) -lt [int]$cfg.minIntervalMs) {
        Write-Log ("{0} ignored: less than {1} ms after the previous one." -f $t.name, $cfg.minIntervalMs) 'DarkYellow'
        return New-RelayMessage $m.seq 'ACK' 'busy'
    }
    if (-not (Test-WowForeground)) {
        Write-Log ("{0} ignored: WoW is not the foreground window on this PC." -f $t.name) 'Yellow'
        return New-RelayMessage $m.seq 'ACK' 'notfocused'
    }
    $state.lastFired = $now
    if ($t.delayMs -gt 0 -and -not $script:NoDelay) { Start-Sleep -Milliseconds $t.delayMs }
    if (-not $script:DryRun) { Send-Chords $t.chords }
    Write-Log ("{0,-12} -> {1}" -f $t.name, $t.keys) 'White'
    return New-RelayMessage $m.seq 'ACK' 'sent'
}

# --- Roles -------------------------------------------------------------------

function Start-Sender {
    $address = if ($Pc2) { $Pc2 } else { [string]$cfg.pc2Address }
    if (-not $address) { $address = (Read-Host 'IP address of PC 2 (Start-Relay-PC2.bat shows it)').Trim() }
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($address, [ref]$ip)) { throw "Invalid PC 2 address: '$address'" }
    if ($address -ne [string]$cfg.pc2Address) { Save-LocalSetting 'pc2Address' $address }
    $to = [Net.IPEndPoint]::new($ip, [int]$cfg.port)

    $toggle = ConvertTo-Chord $cfg.toggleKey
    $toggleName = ([string]$cfg.toggleKey).ToUpper() -replace '-', '+'
    $udp = New-RelaySocket ([Net.IPAddress]::Any) 0
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
    $st = @{ enabled = [bool]$cfg.startEnabled; lastPong = $null; pc2Focused = $false; reachable = $false
             flashUntil = [long]0; flashText = ''; flashColor = $null; pending = @{}; seq = [long]0 }
    $toggleWasHeld = $false
    $lastPing = [long]-100000
    $maxDelay = ($Triggers.Values | ForEach-Object { $_.delayMs } | Measure-Object -Maximum).Maximum
    $cx = 0; $cy = 0
    $leftWasDown = $false

    [RelayInput]::DpiAware() # physical pixels: overlay position, panel code
    $overlay = $null
    if ($cfg.overlay) {
        $overlay = [RelayOverlay]::new([int]$cfg.overlayX, [int]$cfg.overlayY, ([int]$cfg.overlayX -lt 0))
        $overlay.Show()
    }
    $flash = {
        param([string]$text, [Drawing.Color]$color, [int]$ms)
        $st.flashText = $text; $st.flashColor = $color; $st.flashUntil = $clock.ElapsedMilliseconds + $ms
    }
    $relay = {
        param($t)
        $st.seq++
        if (Send-Relay $udp $to (New-RelayMessage $st.seq 'CLICK' $t.name)) {
            $st.pending["$($st.seq)"] = $now
            Write-Log ("{0} -> PC 2 ({1})" -f $t.combo, $t.name) 'White'
            & $flash 'Relais -> PC 2...' ([Drawing.Color]::Gold) 3000
        }
    }
    $send = {
        param([string]$kind, [string]$arg, [int]$times = 1, [bool]$track = $false)
        for ($i = 0; $i -lt $times; $i++) {
            $st.seq++
            if ((Send-Relay $udp $to (New-RelayMessage $st.seq $kind $arg)) -and $track) { $st.pending["$($st.seq)"] = $now }
        }
    }

    # Warrior commands: chords taken from the priest's game by the keyboard hook (moves, then camera)
    $moveList = @($Moves.Values)
    $chordVks = @($moveList | ForEach-Object { [int]$_.vk })
    $chordMasks = @($moveList | ForEach-Object { [int]$_.mask })
    $camIndex = -1
    if ($Camera) { $camIndex = $chordVks.Count; $chordVks += [int]$Camera.vk; $chordMasks += [int]$Camera.mask }
    $hookOk = $false
    if ($chordVks.Count) {
        $err = [RelayHook]::Start([int[]]$chordVks, [int[]]$chordMasks, $camIndex)
        if ($err) { Write-Log "Keyboard hook not installed ($err): no warrior camera / moves." 'Red' } else { $hookOk = $true }
    }
    # status: S of the priest's DuoBox code (Get-StatusParts); held: move name -> @{ since; keep }
    $wc = @{ status = 0; pollAt = [long]0; misses = 0; held = @{}; cam = $null; button = 'L'; accX = 0.0; accY = 0.0 }
    $arm = {
        param([int]$s)
        $p = Get-StatusParts $s
        for ($i = 0; $i -lt $moveList.Count; $i++) { [RelayHook]::SetArmed($i, ($s -gt 0 -and $p.moves)) }
        if ($camIndex -ge 0) { [RelayHook]::SetArmed($camIndex, ($s -gt 0 -and $p.camera)) }
        if ($s -le 0 -or -not $p.camera) { [RelayHook]::StopCamera('option off, relay OFF or WoW not in front') }
        $wc.button = $p.button
    }
    $releaseAll = {
        param([string]$why)
        foreach ($name in @($wc.held.Keys)) { & $send 'UP' $name 2 }
        if ($wc.held.Count) { Write-Log "Moves released on PC 2 ($why)." 'DarkGray' }
        $wc.held.Clear()
        if ($wc.cam) { [RelayHook]::StopCamera($why) }
    }

    Disable-QuickEdit
    Write-Log ("DuoRelay PC 1 -> {0}:{1}. Relay {2} - {3} toggles it. Ctrl+C to quit." -f $address, $cfg.port,
        $(if ($st.enabled) { 'ON' } else { 'OFF' }), $toggleName) 'Green'
    foreach ($t in $Triggers.Values) { Write-Log ("  {0} -> PC 2 presses {1} ({2})" -f $t.combo, $t.keys, $t.label) 'Cyan' }
    Write-Log 'A press with these modifiers that is not relayed (relay ON) is listed with the reason.' 'DarkGray'
    if ($PixelTriggers.Count) {
        Write-Log 'Icons: DuoBox spell panel (/duo panneau), WoW in windowed or windowed fullscreen mode.' 'DarkGray'
    }
    if ($hookOk) {
        foreach ($mv in $moveList) { Write-Log ("  {0} held -> PC 2 holds {1} ({2})" -f $mv.key, $mv.hold, $mv.label) 'Cyan' }
        if ($Camera) { Write-Log ("  {0} held + mouse -> the warrior's camera ({1})" -f $Camera.key, $Camera.label) 'Cyan' }
        Write-Log "These keys never reach the priest's game, and only work while the priest's DuoBox asks for them (tab DuoRelay)." 'DarkGray'
    }

    [void][RelayInput]::timeBeginPeriod(1)
    try {
        while ($true) {
            if ($overlay) { [Windows.Forms.Application]::DoEvents() }
            $now = $clock.ElapsedMilliseconds

            # Relay ON / OFF
            $held = Test-ChordHeld $toggle
            if ($held -and -not $toggleWasHeld) {
                $st.enabled = -not $st.enabled
                Write-Log ("Relay {0}" -f $(if ($st.enabled) { 'ON' } else { 'OFF' })) $(if ($st.enabled) { 'Green' } else { 'Yellow' })
                if ($cfg.sounds) { if ($st.enabled) { [console]::Beep(1000, 60) } else { [console]::Beep(500, 60) } }
                $st.flashUntil = 0
                if (-not $st.enabled -and $hookOk) { & $arm 0; & $releaseAll 'relay OFF'; $wc.status = 0; $wc.pollAt = 0 }
            }
            $toggleWasHeld = $held

            # Warrior commands: the priest's DuoBox options (status code in the corner) arm the hook
            if ($hookOk -and $now -ge $wc.pollAt) {
                $wc.pollAt = $now + 250
                $s = 0
                if ($st.enabled -and (Test-WowForeground)) {
                    $cells = Read-PanelCells
                    $s = ConvertFrom-StatusCells $cells
                    if ($s) { $wc.misses = 0 }
                    elseif (ConvertFrom-PixelCells $cells) { $s = $wc.status } # an icon's code (mouse on the panel): unchanged
                    elseif ($wc.status -and ++$wc.misses -lt 2) { $s = $wc.status } # one bad read is not the option going off
                }
                if (-not $s) { $wc.misses = 0 }
                if ($s -ne $wc.status) {
                    if ($st.enabled) { Write-Log ("Warrior commands (priest's options): {0}" -f (Format-Status $s)) $(if ($s) { 'Green' } else { 'DarkGray' }) }
                    $wc.status = $s
                }
                & $arm $s
            }

            # Panel icons: a left press while the DuoBox panel's code is drawn
            $panelClick = $false
            $leftDown = [RelayInput]::IsDown(0x01)
            if ($leftDown -and -not $leftWasDown -and $st.enabled -and $PixelTriggers.Count -and (Test-WowForeground)) {
                $code = ConvertFrom-PixelCells (Read-PanelCells)
                if ($code) {
                    $panelClick = $true
                    if ($PixelTriggers.ContainsKey($code)) { & $relay $PixelTriggers[$code] }
                    else {
                        Write-Log ("Icon {0} of the panel: no trigger with ""pixel"": {0} in DuoRelay.json" -f $code) 'Yellow'
                        & $flash ("Relais : icone {0} sans touche (DuoRelay.json)" -f $code) ([Drawing.Color]::Orange) 2500
                    }
                }
            }
            $leftWasDown = $leftDown

            # Clicks
            [void][RelayInput]::Cursor([ref]$cx, [ref]$cy)
            foreach ($t in $Triggers.Values) {
                if ($t.pixel) { continue }
                $down = [RelayInput]::IsDown($t.buttonVk)
                $ok = $false
                # A press with the trigger's modifiers while the relay is ON: say why it is not relayed
                if ($down -and -not $t.state.wasDown -and $st.enabled -and (Test-Modifiers $t.mods)) {
                    $ok = Test-WowForeground
                    if (-not $ok) { Write-Log ("{0} not relayed: WoW is not the foreground window" -f $t.combo) 'DarkYellow' }
                }
                $fired = Step-Click $t.state $down $ok $cx $cy $now ([int]$cfg.maxClickMovePx) ([int]$cfg.maxClickMs) $t.drag
                if ($panelClick -and $t.buttonVk -eq 0x01) {
                    # This press is a panel icon's (Ctrl+click on an icon: no interact)
                    $fired = $false; $t.state.armed = $false; $t.state.reason = $null
                }
                if ($t.state.reason) {
                    Write-Log ("{0} not relayed: {1}" -f $t.combo, $t.state.reason) 'DarkYellow'
                    $t.state.reason = $null
                }
                if ($fired) { & $relay $t }
            }

            # Warrior commands: what the keyboard hook took from the priest's game
            $ev = $null
            while ($hookOk -and [RelayHook]::Events.TryDequeue([ref]$ev)) {
                $word, $rest = $ev -split ' ', 2
                if ($word -eq 'DOWN') {
                    $mv = $moveList[[int]$rest]
                    $wc.held[$mv.name] = @{ since = $now; keep = $now }
                    & $send 'DOWN' $mv.name 1 $true
                    Write-Log ("{0} -> PC 2 holds {1} ({2})" -f $mv.key, $mv.hold, $mv.name) 'White'
                } elseif ($word -eq 'UP') {
                    $mv = $moveList[[int]$rest]
                    $wc.held.Remove($mv.name)
                    & $send 'UP' $mv.name 2
                } elseif ($word -eq 'CAMON') {
                    $wc.cam = @{ since = $now; sent = $now }
                    $wc.accX = 0.0; $wc.accY = 0.0
                    & $send 'CAM' ("{0}_0_0" -f $wc.button)
                    Write-Log ("{0} -> PC 2: camera, {1}" -f $Camera.key, $(if ($wc.button -eq 'R') { 'right button (the warrior turns)' } else { 'left button (camera only)' })) 'White'
                } elseif ($word -eq 'CAMOFF') {
                    if ($wc.cam) {
                        $wc.cam = $null
                        & $send 'CAMEND' '' 2
                        Write-Log ("Camera PC 2: end ({0})" -f $rest) 'DarkGray'
                    }
                } elseif ($word -eq 'CAMNO') {
                    Write-Log ("{0}: camera not started, {1}" -f $Camera.key, $rest) 'DarkYellow'
                    & $flash 'Camera PC 2 : lacher les boutons de la souris avant' ([Drawing.Color]::Orange) 2000
                } elseif ($word -eq 'CAMERR') {
                    Write-Log ("Camera: {0}" -f $rest) 'Red'
                }
            }
            # Camera: the raw mouse movement summed by the hook, as often as this loop runs
            if ($wc.cam) {
                $d = [RelayHook]::TakeDelta()
                $wc.accX += $d[0] * $Camera.speed
                $wc.accY += $d[1] * $Camera.speed
                $dx = [int][math]::Truncate($wc.accX); $dy = [int][math]::Truncate($wc.accY)
                $wc.accX -= $dx; $wc.accY -= $dy
                if ($dx -or $dy -or $now - $wc.cam.sent -ge 100) {
                    & $send 'CAM' ("{0}_{1}_{2}" -f $wc.button, $dx, $dy)
                    $wc.cam.sent = $now
                }
                if ($now - $wc.cam.since -gt [int]$cfg.maxCameraMs) { [RelayHook]::StopCamera(("held over {0} ms" -f $cfg.maxCameraMs)) }
            }
            # Moves: confirmed every 100 ms (PC 2 releases a key no longer confirmed)
            foreach ($name in @($wc.held.Keys)) {
                $h = $wc.held[$name]
                if ($now - $h.since -gt [int]$cfg.maxHoldMs) {
                    $wc.held.Remove($name)
                    & $send 'UP' $name 2
                    Write-Log ("{0} held over {1} ms: PC 2 releases it (press again)" -f $name, $cfg.maxHoldMs) 'Yellow'
                } elseif ($now - $h.keep -ge 100) {
                    & $send 'KEEP' $name
                    $h.keep = $now
                }
            }

            # Replies from PC 2
            while ($udp.Available -gt 0) {
                try { $bytes = $udp.Receive([ref]$remote) } catch { break }
                if (-not $remote.Address.Equals($ip)) { continue }
                $m = ConvertFrom-RelayMessage ([Text.Encoding]::ASCII.GetString($bytes))
                if (-not $m) { continue }
                if ($m.kind -eq 'PONG') {
                    if (-not $st.reachable) { Write-Log 'PC 2 answers.' 'Green' }
                    $st.lastPong = $now; $st.reachable = $true; $st.pc2Focused = ($m.arg -eq '1')
                } elseif ($m.kind -eq 'ACK' -and $st.pending.ContainsKey("$($m.seq)")) {
                    $ms = $now - $st.pending["$($m.seq)"]
                    $st.pending.Remove("$($m.seq)")
                    switch ($m.arg) {
                        'sent'       { Write-Log ("  PC 2 pressed the keys ({0} ms)" -f $ms) 'Green'; & $flash 'Relais -> PC 2 : OK' ([Drawing.Color]::LimeGreen) 800 }
                        'held'       { Write-Log ("  PC 2 holds the key ({0} ms)" -f $ms) 'Green' }
                        'notfocused' { Write-Log '  PC 2: WoW is not the foreground window, nothing pressed' 'Red'; & $flash 'Relais : WoW pas actif sur PC 2' ([Drawing.Color]::Tomato) 2500 }
                        'busy'       { Write-Log '  PC 2: too soon after the previous click, ignored' 'Yellow'; & $flash 'Relais : trop rapide, ignore' ([Drawing.Color]::Orange) 1500 }
                        default      { Write-Log ("  PC 2: {0}" -f $m.arg) 'Red'; & $flash 'Relais : refuse par PC 2' ([Drawing.Color]::Tomato) 2500 }
                    }
                }
            }

            # No answer: PC 2 down, firewall, wrong address
            foreach ($k in @($st.pending.Keys)) {
                if ($now - $st.pending[$k] -gt 2000 + $maxDelay) {
                    $st.pending.Remove($k)
                    Write-Log '  PC 2 did not answer.' 'Red'
                    & $flash 'Relais : pas de reponse de PC 2' ([Drawing.Color]::Tomato) 2500
                }
            }
            if ($now - $lastPing -ge 2000) {
                $st.seq++
                [void](Send-Relay $udp $to (New-RelayMessage $st.seq 'PING'))
                $lastPing = $now
            }
            if ($st.reachable -and $now - $st.lastPong -gt 6000) {
                $st.reachable = $false
                Write-Log ("PC 2 ({0}) does not answer: is Start-Relay-PC2.bat running? Firewall (Setup-Firewall-PC2.bat)?" -f $address) 'Red'
            }

            if ($overlay) {
                if ($wc.cam -or $wc.held.Count) {
                    $what = if ($wc.cam) { 'Camera' } else { 'Deplacement' }
                    if (-not $st.reachable) { $text = "$what : PC 2 injoignable"; $color = [Drawing.Color]::Tomato }
                    elseif (-not $st.pc2Focused) { $text = "$what : WoW pas actif sur PC 2"; $color = [Drawing.Color]::Tomato }
                    else { $text = "$what -> PC 2"; $color = [Drawing.Color]::Gold }
                }
                elseif ($st.flashUntil -gt $now) { $text = $st.flashText; $color = $st.flashColor }
                elseif (-not $st.enabled) { $text = "Relais PC 2 : OFF ($toggleName)"; $color = [Drawing.Color]::Silver }
                elseif (-not $st.reachable) { $text = 'Relais PC 2 : ON - PC 2 injoignable'; $color = [Drawing.Color]::Orange }
                elseif (-not $st.pc2Focused) { $text = 'Relais PC 2 : ON - WoW pas actif sur PC 2'; $color = [Drawing.Color]::Orange }
                elseif ($wc.status -ge 3 -and $wc.status % 3) { $text = 'Relais PC 2 : ON (camera, deplacements)'; $color = [Drawing.Color]::LimeGreen }
                elseif ($wc.status -ge 3) { $text = 'Relais PC 2 : ON (deplacements)'; $color = [Drawing.Color]::LimeGreen }
                elseif ($wc.status) { $text = 'Relais PC 2 : ON (camera)'; $color = [Drawing.Color]::LimeGreen }
                else { $text = 'Relais PC 2 : ON'; $color = [Drawing.Color]::LimeGreen }
                $overlay.SetStatus($text, $color)
            }
            Start-Sleep -Milliseconds 5
        }
    }
    finally {
        if ($hookOk) {
            foreach ($name in @($wc.held.Keys)) { & $send 'UP' $name 2 }
            if ($wc.cam) { & $send 'CAMEND' '' 2 }
        }
        $udp.Close()
        [void][RelayInput]::timeEndPeriod(1)
        if ($overlay) { $overlay.Close() }
        Write-Log 'DuoRelay stopped.'
    }
}

function New-ReceiverState {
    return @{ triggers = $Triggers; moves = $Moves; clock = [Diagnostics.Stopwatch]::StartNew(); lastFired = $null
              held = @{}; cam = $null; fg = $false; fgAt = $null }
}

function Start-Receiver {
    $udp = New-RelaySocket ([Net.IPAddress]::Any) ([int]$cfg.port)
    $state = New-ReceiverState
    $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
    $refused = @{}
    [RelayInput]::DpiAware() # screen pixels for the camera's cursor placement

    Disable-QuickEdit
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { $_.IPAddress })
    Write-Log ("DuoRelay PC 2 listening on UDP {0}. This PC's address: {1}" -f $cfg.port, ($ips -join ', ')) 'Green'
    if ($cfg.pc1Address) { Write-Log ("Accepts only PC 1 = {0}" -f $cfg.pc1Address) 'Cyan' }
    if (-not (Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)) {
        Write-Log "No firewall rule '$RuleName': run Setup-Firewall-PC2.bat once, or PC 1's messages may be blocked." 'Yellow'
    }
    foreach ($t in $Triggers.Values) { Write-Log ("  {0}: presses {1} after {2} ms ({3})" -f $t.name, $t.keys, $t.delayMs, $t.label) 'Cyan' }
    foreach ($mv in $Moves.Values) { Write-Log ("  {0}: holds {1} while PC 1 holds {2} ({3})" -f $mv.name, $mv.hold, $mv.key, $mv.label) 'Cyan' }
    if ($Camera) { Write-Log ("  camera: a mouse button held + PC 1's mouse movement while PC 1 holds {0}" -f $Camera.key) 'Cyan' }
    Write-Log 'Click the WoW window now: keys are only pressed while WoW is the foreground window. Ctrl+C to quit.' 'Cyan'

    try {
        while ($true) {
            # 50 ms at most without a look at the held keys (Ctrl+C gets through too)
            if (-not $udp.Client.Poll(50000, [Net.Sockets.SelectMode]::SelectRead)) {
                Step-StreamSafety $state $state.clock.ElapsedMilliseconds
                continue
            }
            try { $bytes = $udp.Receive([ref]$remote) }
            catch {
                $e = $_.Exception
                if ($e.InnerException) { $e = $e.InnerException }
                Write-Log ("Receive error: {0}" -f $e.Message) 'DarkYellow'
                Start-Sleep -Milliseconds 200
                continue
            }
            if (-not (Test-AllowedSender $remote.Address)) {
                $who = $remote.Address.ToString()
                if (-not $refused.ContainsKey($who)) { Write-Log "Message from $who refused (not PC 1)." 'Yellow'; $refused[$who] = $true }
                continue
            }
            $reply = Invoke-RelayPacket ([Text.Encoding]::ASCII.GetString($bytes)) $state
            if ($reply) { [void](Send-Relay $udp $remote $reply) }
            if ($udp.Available -eq 0) { Step-StreamSafety $state $state.clock.ElapsedMilliseconds } # after the queue
        }
    }
    finally {
        Stop-AllHeld $state 'DuoRelay stopped'   # no key or button left down on this PC
        $udp.Close()
        Write-Log 'DuoRelay stopped.'
    }
}

# PC 1: what the panel code reads in WoW, to check the screen reading alone (sends nothing)
function Start-PixelProbe {
    [RelayInput]::DpiAware()
    Disable-QuickEdit
    Write-Log 'Pixel probe: put the mouse over an icon of the DuoBox panel in WoW (windowed or windowed fullscreen). Ctrl+C to quit.' 'Green'
    $last = $null
    while ($true) {
        $line = if (Test-WowForeground) {
            $rgb = Read-PanelCells
            $code = ConvertFrom-PixelCells $rgb
            $status = ConvertFrom-StatusCells $rgb
            $what = if ($code) {
                $t = $PixelTriggers[$code]
                if ($t) { "icon $code -> trigger $($t.name), PC 2 would press $($t.keys)" } else { "icon $code, no trigger with ""pixel"": $code" }
            } elseif ($status) { "status $status -> warrior commands: $(Format-Status $status)" } else { 'no code' }
            '{0}  ({1})' -f $what, (Format-Cells $rgb)
        } else { 'WoW is not the foreground window' }
        if ($line -ne $last) { Write-Log $line $(if ($line -like 'icon*' -or $line -like 'status*') { 'White' } else { 'DarkGray' }); $last = $line }
        Start-Sleep -Milliseconds 200
    }
}

# The real hook on this PC, fed with injected input (the Sender never takes injected keys): Ctrl+F13 as a
# move, Ctrl+F14 as the camera chord. Nothing is sent; F13 / F14 do nothing in Windows or in WoW.
function Invoke-HookTest {
    $script:failures = 0
    function Check([bool]$cond, [string]$what) {
        if ($cond) { Write-Log "  ok    $what" 'Green' } else { Write-Log "  FAIL  $what" 'Red'; $script:failures++ }
    }
    function Get-Events {
        Start-Sleep -Milliseconds 150
        $list = @(); $e = $null
        while ([RelayHook]::Events.TryDequeue([ref]$e)) { $list += $e }
        return ($list -join ', ')
    }
    function Get-CursorX { $x = 0; $y = 0; [void][RelayInput]::Cursor([ref]$x, [ref]$y); return $x }
    $F13 = 0x7C; $F14 = 0x7D; $CTRL = 0x11
    [RelayInput]::DpiAware()
    [RelayHook]::TestMode = $true
    $err = [RelayHook]::Start([int[]]@($F13, $F14), [int[]]@(1, 1), 1)
    if ($err) { Write-Log "Hook not installed: $err" 'Red'; exit 1 }
    Write-Log 'Hook installed. Keep your hands off the keyboard and mouse for 3 s.' 'Cyan'
    Start-Sleep -Milliseconds 300
    $chord = {
        param([int]$vk, [bool]$up)
        if (-not $up) { [RelayInput]::Key($CTRL, $false); [RelayInput]::Key($vk, $false) }
        else { [RelayInput]::Key($vk, $true); [RelayInput]::Key($CTRL, $true) }
    }

    & $chord $F13 $false; & $chord $F13 $true
    $ev = Get-Events; Check ($ev -eq '') "option off: Ctrl+F13 not taken ($ev)"
    [RelayHook]::SetArmed(0, $true); [RelayHook]::SetArmed(1, $true)
    & $chord $F13 $false; [RelayInput]::Key($F13, $false); & $chord $F13 $true
    $ev = Get-Events; Check ($ev -eq 'DOWN 0, UP 0') "Ctrl+F13 taken: one press, one release ($ev)"

    & $chord $F14 $false
    $ev = Get-Events; Check ($ev -eq 'CAMON') "Ctrl+F14: camera mode on ($ev)"
    $x0 = Get-CursorX
    [void][RelayHook]::TakeDelta()
    1..3 | ForEach-Object { [RelayInput]::MoveMouse(6, 0); Start-Sleep -Milliseconds 20 }
    Start-Sleep -Milliseconds 150
    $d = [RelayHook]::TakeDelta(); $x1 = Get-CursorX
    Check ($d[0] -eq 18 -and $d[1] -eq 0) "raw movement summed for PC 2 ($($d[0]), $($d[1]))"
    Check ($x1 -eq $x0) "this PC's cursor stays in place ($x0 -> $x1)"
    & $chord $F14 $true
    $ev = Get-Events; Check ($ev -eq 'CAMOFF released') "Ctrl+F14 released: camera mode off ($ev)"
    [RelayInput]::MoveMouse(3, 0); Start-Sleep -Milliseconds 100
    $x2 = Get-CursorX
    [RelayInput]::MoveMouse(-3, 0)
    Check ($x2 -ne $x1) "the cursor moves again ($x1 -> $x2)"
    [RelayHook]::TestMode = $false

    if ($script:failures) { Write-Log ("Hook test: {0} failure(s)." -f $script:failures) 'Red'; exit 1 }
    Write-Log 'Hook test OK.' 'Green'
}

# PC 2, once: inbound rule for the UDP port, limited to PC 1 (or to the local subnet)
function Install-FirewallRule {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        $pc1 = [string]$cfg.pc1Address
        if (-not $pc1) {
            $pc1 = (Read-Host 'IP address of PC 1 (ipconfig on PC 1; Enter = any PC of the local network)').Trim()
            if ($pc1) {
                $ip = $null
                if (-not [Net.IPAddress]::TryParse($pc1, [ref]$ip)) { throw "Invalid PC 1 address: '$pc1'" }
                Save-LocalSetting 'pc1Address' $pc1
            }
        }
        Write-Log 'Windows will ask for administrator rights to create the firewall rule.' 'Yellow'
        $argList = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -SetupFirewall -Elevated -Config "{1}"' -f $PSCommandPath, $Config
        try { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList -Wait }
        catch { Write-Log 'Administrator rights refused: no firewall rule created.' 'Red' }
        return
    }
    try {
        Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        $rule = @{ DisplayName = $RuleName; Direction = 'Inbound'; Protocol = 'UDP'; LocalPort = [int]$cfg.port; Action = 'Allow' }
        if ($cfg.pc1Address) {
            New-NetFirewallRule @rule -RemoteAddress ([string]$cfg.pc1Address) -Profile Any | Out-Null
            Write-Log ("Firewall rule '{0}' created: UDP {1} from {2} only." -f $RuleName, $cfg.port, $cfg.pc1Address) 'Green'
        } else {
            New-NetFirewallRule @rule -RemoteAddress LocalSubnet -Profile Private, Domain | Out-Null
            Write-Log ("Firewall rule '{0}' created: UDP {1} from the local network (Private networks)." -f $RuleName, $cfg.port) 'Green'
            if (Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { "$($_.NetworkCategory)" -eq 'Public' }) {
                Write-Log 'This network is "Public": the rule does not apply. Run the setup again with PC 1''s address, or set the network to Private (Settings > Network > properties).' 'Yellow'
            }
        }
    } catch {
        Write-Log ("Firewall rule not created: {0}" -f $_.Exception.Message) 'Red'
    }
    if ($Elevated) { [void](Read-Host 'Press Enter to close') }
}

# --- Self-test ---------------------------------------------------------------

function Invoke-SelfTest {
    $script:failures = 0
    function Check([bool]$cond, [string]$what) {
        if ($cond) { Write-Log "  ok    $what" 'Green' } else { Write-Log "  FAIL  $what" 'Red'; $script:failures++ }
    }

    Write-Log ("Config: {0} trigger(s), toggle {1}, port {2}, delay {3} ms" -f $Triggers.Count, $cfg.toggleKey, $cfg.port, $cfg.delayMs)
    Check ($Triggers.Count -gt 0) 'at least one trigger'
    foreach ($t in $Triggers.Values) { Check ($t.chords.Count -gt 0) ("{0}: {1} -> {2}" -f $t.name, $t.combo, $t.keys) }
    Check ((ConvertTo-Chord $cfg.toggleKey).vk -gt 0) "toggle key $($cfg.toggleKey)"
    $threw = $false; try { [void](ConvertTo-Trigger ([pscustomobject]@{ name = 'x'; button = 'LEFT'; modifier = ''; keys = 'T' })) } catch { $threw = $true }
    Check $threw 'a trigger without modifier is refused'

    # Click detection
    $run = {
        param($steps)  # each: down, ok, x, y, t
        $s = @{ wasDown = $false; armed = $false }; $r = $false
        foreach ($p in $steps) { $r = Step-Click $s $p[0] $p[1] $p[2] $p[3] $p[4] 6 500 }
        return $r
    }
    Check (& $run @(@($true, $true, 100, 100, 0), @($true, $false, 101, 100, 40), @($false, $false, 102, 101, 80))) 'short click fires on release'
    Check (-not (& $run @(@($true, $false, 100, 100, 0), @($false, $false, 100, 100, 80)))) 'no modifier / relay OFF: nothing'
    Check (-not (& $run @(@($true, $true, 100, 100, 0), @($true, $true, 130, 100, 40), @($false, $false, 100, 100, 80)))) 'drag (cursor moved): nothing'
    Check (-not (& $run @(@($true, $true, 100, 100, 0), @($true, $true, 100, 100, 300), @($false, $false, 100, 100, 900)))) 'long press (camera turn, cursor kept in place): nothing'
    $s = @{ wasDown = $false; armed = $false }
    [void](Step-Click $s $true $true 100 100 0 6 500); [void](Step-Click $s $true $true 109 100 20 6 500)
    Check ($s.reason -eq 'mouse moved 9 px (max 6: a drag turns the camera)') "dropped press says why: '$($s.reason)'"

    # Side / middle buttons: relayed at the press, whatever the mouse does next
    $s = @{ wasDown = $false; armed = $false }
    $first = Step-Click $s $true $true 100 100 0 6 500 $false
    $later = @((Step-Click $s $true $true 140 100 900 6 500 $false), (Step-Click $s $false $false 140 100 950 6 500 $false))
    Check ($first -and -not ($later -contains $true) -and -not $s.reason) 'side button: relayed once, at the press'
    Check (-not (Step-Click @{ wasDown = $false; armed = $false } $true $false 100 100 0 6 500 $false)) 'side button without modifier: nothing'
    $drags = @($Triggers.Values | Where-Object { $_.drag } | ForEach-Object { $_.name }) -join ','
    Check ($drags -eq 'interact,pickup' -and -not $Triggers['follow'].drag) "drag filter only on left / right buttons ($drags)"

    # Panel code: same scheme as RelayPanel.lua (tests/test_relay_panel.py checks icon 10 there too)
    $roundTrip = @(1..36 | Where-Object { (ConvertFrom-PixelCells (ConvertTo-PixelCells $_)) -ne $_ })
    Check ($roundTrip.Count -eq 0) "panel code: icons 1-36 read back ($($roundTrip -join ','))"
    Check ((ConvertFrom-PixelCells @(0x00FF00, 0xFF00FF, 0xFF0000, 0x00FFFF)) -eq 10) 'panel code: green, magenta, red, cyan = icon 10'
    Check ((ConvertFrom-PixelCells @(0x2828D2, 0xC8D23C, 0x3C3CF0, 0xF0E655)) -eq 1) 'panel code: colours shifted by the screen still read'
    $bad = [ordered]@{
        'nothing drawn (game picture)' = @(0x203040, 0x605040, 0x101010, 0x8090A0)
        'black and white' = @(0x000000, 0xFFFFFF, 0x000000, 0xFFFFFF)
        'half channel' = @(0x0000FF, 0xFFFF80, 0x0000FF, 0xFFFF00)
        'wrong complement' = @(0x0000FF, 0xFF00FF, 0x0000FF, 0xFFFF00)
        'three squares' = @(0x0000FF, 0xFFFF00, 0x0000FF)
    }
    foreach ($k in $bad.Keys) { Check ((ConvertFrom-PixelCells $bad[$k]) -eq 0) "panel code refused: $k" }
    Check ((ConvertFrom-PixelCells $null) -eq 0) 'panel code refused: screen unreadable'

    # Pixel triggers: no modifier, at once, never in the mouse button loop
    $px = Import-Triggers @(
        [pscustomobject]@{ name = 'a'; button = 'LEFT'; modifier = 'CTRL'; keys = 'T' },
        [pscustomobject]@{ name = 'b'; pixel = 2; keys = 'F4'; delayMs = 0 })
    Check ($px.pixel[2].name -eq 'b' -and $px.pixel[2].delayMs -eq 0 -and -not $px.pixel[2].drag -and $px.all['a'].pixel -eq 0) 'pixel trigger parsed'
    foreach ($case in @(@{ name = 'c'; pixel = 0; keys = 'T' }, @{ name = 'c'; pixel = 37; keys = 'T' }, @{ name = 'c'; pixel = 'x'; keys = 'T' },
                        @{ name = 'c'; pixel = 3; keys = 'T'; modifier = 'CTRL' })) {
        $threw = $false; try { [void](ConvertTo-Trigger ([pscustomobject]$case)) } catch { $threw = $true }
        Check $threw ("pixel trigger refused: pixel {0}{1}" -f $case.pixel, $(if ($case.modifier) { ' with a modifier' } else { '' }))
    }
    $threw = $false
    try { [void](Import-Triggers @([pscustomobject]@{ name = 'a'; pixel = 1; keys = 'T' }, [pscustomobject]@{ name = 'b'; pixel = 1; keys = 'E' })) } catch { $threw = $true }
    Check $threw 'two triggers with the same pixel refused'
    $icons = @($PixelTriggers.Keys | Sort-Object | ForEach-Object { "$_=$($PixelTriggers[$_].keys)" }) -join ' '
    Write-Log ("  info  panel icons in the config: {0}" -f $(if ($icons) { $icons } else { 'none' }))

    # Status code of the priest's options: same scheme as RelayPanel.lua (tests/test_relay_panel.py: status 4 too)
    $statusTrip = @(1..5 | Where-Object { (ConvertFrom-StatusCells (ConvertTo-StatusCells $_)) -ne $_ })
    Check ($statusTrip.Count -eq 0) "status code: 1-5 read back ($($statusTrip -join ','))"
    Check ((ConvertFrom-StatusCells @(0x000000, 0xFFFFFF, 0xFF0000, 0x00FFFF)) -eq 4) 'status code: black, white, red, cyan = 4 (camera only + moves)'
    $crossed = @(1..36 | Where-Object { ConvertFrom-StatusCells (ConvertTo-PixelCells $_) }) +
               @(1..5 | Where-Object { ConvertFrom-PixelCells (ConvertTo-StatusCells $_) })
    Check ($crossed.Count -eq 0) 'status and icon codes never read as each other'
    Check ((ConvertFrom-StatusCells @(0x000000, 0xFFFFFF, 0x000000, 0xFFFFFF)) -eq 0) 'status code refused: black and white'
    Check ((ConvertFrom-StatusCells (ConvertTo-Cells @(0, 7, 6, 1))) -eq 0) 'status code refused: S = 6'
    $p = Get-StatusParts 5; Check ($p.moves -and $p.camera -and $p.button -eq 'R') 'status 5 = moves + camera, right button (the warrior turns)'
    $p = Get-StatusParts 1; Check (-not $p.moves -and $p.camera -and $p.button -eq 'L') 'status 1 = camera only, left button'
    $p = Get-StatusParts 3; Check ($p.moves -and -not $p.camera) 'status 3 = moves only'

    # Keys taken from the priest's game (KeyFilter, used by the keyboard hook)
    $Q = 0x51; $S = 0x53; $Z = 0x5A; $CTRL = 1
    $f = [KeyFilter]::new([int[]]@($Q, $S, $Z), [int[]]@($CTRL, $CTRL, $CTRL))
    $kf = {
        param([int]$vk, [bool]$up, [int]$mods)
        $o = $f.Feed($vk, $up, $mods)
        return '{0}{1}{2}' -f $(if ($o[0]) { 'T' } else { '-' }), $(if ($o[1] -ge 0) { "+$($o[1])" } else { '' }), $(if ($o[2] -ge 0) { "/$($o[2])" } else { '' })
    }
    $seq = @((& $kf $Q $false $CTRL), (& $kf $Q $true $CTRL)) -join ' '
    Check ($seq -eq '- -') "option off (disarmed): Ctrl+Q goes to the game ($seq)"
    0..2 | ForEach-Object { $f.SetArmed($_, $true) }
    $seq = @((& $kf 0xA2 $false 0), (& $kf $Q $false $CTRL), (& $kf $Q $false $CTRL), (& $kf $Q $true $CTRL), (& $kf 0xA2 $true $CTRL)) -join ' '
    Check ($seq -eq '- T+0 T T/0 -') "Ctrl+Q taken at the press, its repeat and its release too; Ctrl itself not ($seq)"
    $seq = @((& $kf $Q $false 0), (& $kf $Q $false $CTRL), (& $kf $Q $true $CTRL)) -join ' '
    Check ($seq -eq '- - -') "Q pressed before Ctrl stays the game's, repeats and release included ($seq)"
    $seq = @((& $kf $Q $false 3), (& $kf $Q $true 3)) -join ' '
    Check ($seq -eq '- -') "Ctrl+Shift+Q is not Ctrl+Q ($seq)"
    $seq = @((& $kf $S $false $CTRL), (& $kf $Q $false $CTRL), (& $kf $S $true 0), (& $kf $Q $true 0)) -join ' '
    Check ($seq -eq 'T+1 T+0 T/1 T/0') "two moves held together, Ctrl let go first ($seq)"
    $a = & $kf $Q $false $CTRL; $f.SetArmed(0, $false); $b = & $kf $Q $false $CTRL; $c = & $kf $Q $true $CTRL
    Check ("$a $b $c" -eq 'T+0 T T/0') "a taken press stays taken after the option goes off, until released ($a $b $c)"
    $seq = @((& $kf $Q $false $CTRL), (& $kf $Q $true $CTRL)) -join ' '
    Check ($seq -eq '- -') "then Ctrl+Q goes to the game again ($seq)"
    $seq = @((& $kf $Z $false $CTRL), (& $kf $Z $true $CTRL)) -join ' '
    Check ($seq -eq 'T+2 T/2') "camera chord Ctrl+Z ($seq)"
    Check ([KeyFilter]::IsModifier(0xA2) -and [KeyFilter]::IsModifier(0x10) -and -not [KeyFilter]::IsModifier($Q)) 'modifier keys are never taken'

    # Moves and camera in the config
    $mvList = @($Moves.Values | ForEach-Object { "$($_.key)->$($_.hold)" }) -join ', '
    Check ($Moves.Count -ge 1 -and @($Moves.Values | Where-Object { $_.holdVk -le 0 }).Count -eq 0) "moves: $mvList"
    Check ((Get-VK 'RIGHT') -eq 0x27 -and (Get-VK 'down') -eq 0x28) 'arrow keys RIGHT, DOWN'
    if ($Camera) { Check ($Camera.vk -gt 0 -and $Camera.speed -gt 0) "camera: $($Camera.key), speed $($Camera.speed)" }
    $bad = [ordered]@{
        'a held key with a modifier' = { Import-Moves @([pscustomobject]@{ name = 'a'; key = 'CTRL-Q'; hold = 'SHIFT-Q' }) }
        'two moves with one name' = { Import-Moves @([pscustomobject]@{ name = 'a'; key = 'CTRL-Q'; hold = 'Q' }, [pscustomobject]@{ name = 'a'; key = 'CTRL-E'; hold = 'E' }) }
        'a move on the toggle key' = { Test-CommandKeys (Import-Moves @([pscustomobject]@{ name = 'a'; key = 'CTRL-ALT-D'; hold = 'Q' })) $null 'CTRL-ALT-D' }
        'the camera on a move key' = { Test-CommandKeys (Import-Moves @([pscustomobject]@{ name = 'a'; key = 'CTRL-Q'; hold = 'Q' })) (ConvertTo-Camera ([pscustomobject]@{ key = 'ctrl-q' })) 'CTRL-ALT-D' }
        'camera speed 0' = { ConvertTo-Camera ([pscustomobject]@{ key = 'CTRL-Z'; speed = 0 }) }
    }
    foreach ($k in $bad.Keys) { $threw = $false; try { [void](& $bad[$k]) } catch { $threw = $true }; Check $threw "refused: $k" }

    # PC 2: held moves and camera, dry run (the actions are listed, nothing is pressed)
    $script:DryRun = $true
    $script:Actions = [Collections.Generic.List[string]]::new()
    $script:ForegroundOverride = $true
    $rs = New-ReceiverState
    $rs.moves = Import-Moves @([pscustomobject]@{ name = 'left'; key = 'CTRL-Q'; hold = 'Q' }, [pscustomobject]@{ name = 'right'; key = 'CTRL-D'; hold = 'RIGHT' },
                               [pscustomobject]@{ name = 'back'; key = 'CTRL-S'; hold = 'S' })
    $msg = { param([string]$kind, [string]$arg) Invoke-RelayPacket (New-RelayMessage 1 $kind $arg) $rs }
    $acts = { $r = $script:Actions -join ', '; $script:Actions.Clear(); return $r }
    $later = { $rs.clock.ElapsedMilliseconds + [int]$cfg.streamTimeoutMs + 50 }
    try {
        $r = & $msg 'DOWN' 'left'
        Check ($r -like '*|ACK|held' -and (& $acts) -eq 'down Q') 'DOWN -> the key held, ACK held'
        $r = & $msg 'KEEP' 'left'
        Check ($null -eq $r -and (& $acts) -eq '') 'KEEP -> nothing more, no reply'
        [void](& $msg 'UP' 'left')
        Check ((& $acts) -eq 'up Q' -and $rs.held.Count -eq 0) 'UP -> released'
        [void](& $msg 'UP' 'left')
        Check ((& $acts) -eq '') 'second UP (sent twice) -> nothing'
        [void](& $msg 'KEEP' 'right')
        Check ((& $acts) -eq 'down RIGHT') 'KEEP without DOWN (lost) -> held'
        Step-StreamSafety $rs (& $later)
        Check ((& $acts) -eq 'up RIGHT') 'no KEEP for streamTimeoutMs -> released'
        $script:ForegroundOverride = $false
        $r = & $msg 'DOWN' 'back'
        Check ($r -like '*|ACK|notfocused' -and (& $acts) -eq '') 'WoW not focused -> nothing held'
        $script:ForegroundOverride = $true
        [void](& $msg 'DOWN' 'back'); [void](& $acts)
        $script:ForegroundOverride = $false
        Step-StreamSafety $rs $rs.clock.ElapsedMilliseconds
        Check ((& $acts) -eq 'up S') 'WoW leaves the front -> released at once'
        $script:ForegroundOverride = $true
        $r = & $msg 'DOWN' 'nope'
        Check ($r -like '*|ACK|unknown') 'unknown move -> refused'
        [void](& $msg 'CAM' 'L_0_0')
        Check ((& $acts) -eq 'cursor') 'camera start: cursor placed, no button yet'
        [void](& $msg 'CAM' 'L_5_0'); [void](& $msg 'CAM' 'L_0_-3')
        Check ((& $acts) -eq 'mouse L down, move 5 0, move 0 -3') 'first movement: left button down, then relative moves'
        [void](& $msg 'CAMEND' '')
        Check ((& $acts) -eq "move $($MinDragPx - 8) 0, mouse L up") "short turn topped up to $MinDragPx px (never a click), then released"
        [void](& $msg 'CAM' 'R_0_0'); [void](& $msg 'CAMEND' '')
        Check ((& $acts) -eq 'cursor') 'camera without movement: no button at all'
        [void](& $msg 'CAM' 'R_40_2'); [void](& $acts)
        Step-StreamSafety $rs (& $later)
        Check ((& $acts) -eq 'mouse R up') 'no CAM for streamTimeoutMs -> the button released'
        [void](& $msg 'CAM' 'X_1_1'); [void](& $msg 'CAM' 'L_1'); [void](& $msg 'CAM' 'l_1_1')
        Check ((& $acts) -eq '' -and -not $rs.cam) 'malformed CAM messages ignored'
        [void](& $msg 'DOWN' 'left'); [void](& $msg 'CAM' 'L_20_0'); [void](& $acts)
        Stop-AllHeld $rs 'test'
        Check ((& $acts) -eq 'up Q, mouse L up') 'quitting releases everything'
    } catch {
        Check $false ("PC 2 moves / camera: {0}" -f $_.Exception.Message)
    } finally {
        $script:DryRun = $false; $script:Actions = $null; $script:ForegroundOverride = $null
    }

    # Messages
    $m = ConvertFrom-RelayMessage (New-RelayMessage 42 'CLICK' 'interact')
    Check ($m -and $m.seq -eq 42 -and $m.kind -eq 'CLICK' -and $m.arg -eq 'interact') 'message round trip'
    foreach ($bad in 'hello', "$Proto|x|CLICK|a", "$Proto|1|CLICK|a b", "$Proto|1|click|a", "$Proto|1|CLICK") {
        Check ($null -eq (ConvertFrom-RelayMessage $bad)) "refused: '$bad'"
    }
    $saved = $cfg.pc1Address; $cfg.pc1Address = ''
    Check ((Test-AllowedSender ([Net.IPAddress]::Parse('192.168.1.5'))) -and (Test-AllowedSender ([Net.IPAddress]::Parse('127.0.0.1')))) 'private sender accepted'
    Check (-not (Test-AllowedSender ([Net.IPAddress]::Parse('8.8.8.8'))) -and -not (Test-AllowedSender ([Net.IPAddress]::Parse('172.32.0.1')))) 'public sender refused'
    $cfg.pc1Address = '192.168.1.5'
    Check (-not (Test-AllowedSender ([Net.IPAddress]::Parse('192.168.1.6')))) 'pc1Address set: other PCs refused'
    $cfg.pc1Address = $saved

    # Per-trigger delay: its own delayMs, or the global one
    $own = ConvertTo-Trigger ([pscustomobject]@{ name = 'a'; button = 'RIGHT'; modifier = 'CTRL'; keys = 'T'; delayMs = 500 })
    $inherit = ConvertTo-Trigger ([pscustomobject]@{ name = 'b'; button = 'LEFT'; modifier = 'CTRL'; keys = 'T' })
    Check ($own.delayMs -eq 500 -and $inherit.delayMs -eq [int]$cfg.delayMs) 'trigger delay: its own, else the global one'

    # Loopback: PC 1 socket -> PC 2 socket -> reply, no key pressed, no wait
    $script:DryRun = $true
    $script:NoDelay = $true
    $loop = [Net.IPAddress]::Loopback
    $rx = New-RelaySocket $loop 0; $tx = New-RelaySocket $loop 0
    $rx.Client.ReceiveTimeout = 2000; $tx.Client.ReceiveTimeout = 2000
    $rxEnd = [Net.IPEndPoint]::new($loop, $rx.Client.LocalEndPoint.Port)
    $state = New-ReceiverState
    $first = @($Triggers.Keys)[0]
    $exchange = {
        param([string]$msg)
        [void](Send-Relay $tx $rxEnd $msg)
        $from = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        $reply = Invoke-RelayPacket ([Text.Encoding]::ASCII.GetString($rx.Receive([ref]$from))) $state
        if (-not $reply) { return $null }
        [void](Send-Relay $rx $from $reply)
        $back = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        return ConvertFrom-RelayMessage ([Text.Encoding]::ASCII.GetString($tx.Receive([ref]$back)))
    }
    try {
        $script:ForegroundOverride = $true
        $r = & $exchange (New-RelayMessage 1 'PING'); Check ($r -and $r.kind -eq 'PONG' -and $r.arg -eq '1' -and $r.seq -eq 1) 'PING -> PONG (WoW focused)'
        $r = & $exchange (New-RelayMessage 2 'CLICK' $first); Check ($r -and $r.kind -eq 'ACK' -and $r.arg -eq 'sent' -and $r.seq -eq 2) 'CLICK -> keys pressed'
        $r = & $exchange (New-RelayMessage 3 'CLICK' $first); Check ($r -and $r.arg -eq 'busy') 'second CLICK at once -> busy'
        $state.lastFired = $null; $script:ForegroundOverride = $false
        $r = & $exchange (New-RelayMessage 4 'CLICK' $first); Check ($r -and $r.arg -eq 'notfocused') 'WoW not focused -> nothing pressed'
        $r = & $exchange (New-RelayMessage 5 'PING'); Check ($r -and $r.arg -eq '0') 'PONG reports WoW not focused'
        $r = & $exchange (New-RelayMessage 6 'CLICK' 'nope'); Check ($r -and $r.arg -eq 'unknown') 'unknown trigger -> refused'
    } catch {
        Check $false ("loopback: {0}" -f $_.Exception.Message)
    } finally {
        $rx.Close(); $tx.Close()
        $script:ForegroundOverride = $null; $script:DryRun = $false; $script:NoDelay = $false
    }

    if ($script:failures) { Write-Log ("Self-test: {0} failure(s)." -f $script:failures) 'Red'; exit 1 }
    Write-Log 'Self-test OK.' 'Green'
}

# --- Main --------------------------------------------------------------------

$cfg = Import-RelayConfig
$imported = Import-Triggers $cfg.triggers
$Triggers = $imported.all          # name -> trigger
$PixelTriggers = $imported.pixel   # panel icon number -> trigger
$Moves = Import-Moves $cfg.moves   # name -> move (key taken on PC 1, key held on PC 2)
$Camera = ConvertTo-Camera $cfg.camera
Test-CommandKeys $Moves $Camera ([string]$cfg.toggleKey)
$RuleName = "DuoRelay (UDP $($cfg.port))"

if ($SelfTest) { Invoke-SelfTest; return }
if ($HookTest) { Invoke-HookTest; return }
if ($SetupFirewall) { Install-FirewallRule; return }
if ($PixelProbe) { Start-PixelProbe; return }
if (-not $Triggers.Count) { throw "No trigger in $Config" }
switch ($Role) {
    'Sender'   { Start-Sender }
    'Receiver' { Start-Receiver }
    default    { throw 'Give -Role Sender (PC 1), -Role Receiver (PC 2), -SetupFirewall or -SelfTest' }
}
