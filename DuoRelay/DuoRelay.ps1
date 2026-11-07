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
    Ctrl+C to quit.
#>
param(
    [ValidateSet('Sender', 'Receiver')] [string]$Role,
    [string]$Config = (Join-Path $PSScriptRoot 'DuoRelay.json'),
    [string]$Pc2,
    [switch]$SetupFirewall,
    [switch]$Elevated,
    [switch]$SelfTest,
    [switch]$PixelProbe
)

$ErrorActionPreference = 'Stop'
$Proto = 'DUORELAY1'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('RelayInput' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
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

    // Virtual key + matching scan code, as VoiceKeys.ps1 (works for every key WoW reads)
    public static void Key(ushort vk, bool up) {
        INPUT[] i = new INPUT[1];
        i[0].type = 1;
        i[0].u.ki.wVk = vk;
        i[0].u.ki.wScan = (ushort)MapVirtualKey(vk, 0);
        i[0].u.ki.dwFlags = up ? 0x2u : 0u; // KEYEVENTF_KEYUP
        SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
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
                  HOME = 0x24; END = 0x23; PAGEUP = 0x21; PAGEDOWN = 0x22; PAUSE = 0x13; SCROLLLOCK = 0x91 }
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

# --- Configuration -----------------------------------------------------------

$Defaults = [ordered]@{
    port = 47815; pc2Address = ''; pc1Address = ''; startEnabled = $false; toggleKey = 'CTRL-ALT-D'
    processNames = @('Wow', 'WowB', 'WowClassic', 'WowClassicB'); triggers = @()
    maxClickMovePx = 30; maxClickMs = 500; delayMs = 300; minIntervalMs = 500
    overlay = $true; overlayX = -1; overlayY = 2; sounds = $false
    pixelCell = 8   # physical pixels per square of the panel code (CELL in RelayPanel.lua)
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

# --- Panel code (RelayPanel.lua) -------------------------------------------
# 4 squares A, 7-A, B, 7-B; each channel full (>= 170) or off (<= 85), 4 = red,
# 2 = green, 1 = blue; A and B 1 to 6; icon = (A - 1) * 6 + B. 0 = no code.

function ConvertFrom-PixelCells($rgb) {
    if ($null -eq $rgb -or @($rgb).Count -ne 4) { return 0 }
    $v = @()
    foreach ($c in @($rgb)) {
        $bits = 0
        foreach ($shift in 16, 8, 0) {
            $ch = ([int]$c -shr $shift) -band 0xFF
            if ($ch -ge 170) { $bits = $bits * 2 + 1 } elseif ($ch -le 85) { $bits = $bits * 2 } else { return 0 }
        }
        $v += $bits
    }
    if ($v[0] -lt 1 -or $v[0] -gt 6 -or $v[2] -lt 1 -or $v[2] -gt 6) { return 0 }
    if ($v[1] -ne 7 - $v[0] -or $v[3] -ne 7 - $v[2]) { return 0 }
    return ($v[0] - 1) * 6 + $v[2]
}

# Icon number -> the 4 colours RelayPanel.lua draws (self-test)
function ConvertTo-PixelCells([int]$n) {
    $a = [int][math]::Floor(($n - 1) / 6) + 1; $b = ($n - 1) % 6 + 1
    return ,@(foreach ($v in $a, (7 - $a), $b, (7 - $b)) {
        $(if ($v -band 4) { 0xFF0000 } else { 0 }) -bor $(if ($v -band 2) { 0xFF00 } else { 0 }) -bor $(if ($v -band 1) { 0xFF } else { 0 })
    })
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
#   PC 2 -> PC 1: ACK|sent|notfocused|busy|unknown (same seq), PONG|1 or 0 (WoW in the foreground)

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

    Disable-QuickEdit
    Write-Log ("DuoRelay PC 1 -> {0}:{1}. Relay {2} - {3} toggles it. Ctrl+C to quit." -f $address, $cfg.port,
        $(if ($st.enabled) { 'ON' } else { 'OFF' }), $toggleName) 'Green'
    foreach ($t in $Triggers.Values) { Write-Log ("  {0} -> PC 2 presses {1} ({2})" -f $t.combo, $t.keys, $t.label) 'Cyan' }
    Write-Log 'A press with these modifiers that is not relayed (relay ON) is listed with the reason.' 'DarkGray'
    if ($PixelTriggers.Count) {
        Write-Log 'Icons: DuoBox spell panel (/duo panneau), WoW in windowed or windowed fullscreen mode.' 'DarkGray'
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
            }
            $toggleWasHeld = $held

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
                if ($st.flashUntil -gt $now) { $text = $st.flashText; $color = $st.flashColor }
                elseif (-not $st.enabled) { $text = "Relais PC 2 : OFF ($toggleName)"; $color = [Drawing.Color]::Silver }
                elseif (-not $st.reachable) { $text = 'Relais PC 2 : ON - PC 2 injoignable'; $color = [Drawing.Color]::Orange }
                elseif (-not $st.pc2Focused) { $text = 'Relais PC 2 : ON - WoW pas actif sur PC 2'; $color = [Drawing.Color]::Orange }
                else { $text = 'Relais PC 2 : ON'; $color = [Drawing.Color]::LimeGreen }
                $overlay.SetStatus($text, $color)
            }
            Start-Sleep -Milliseconds 5
        }
    }
    finally {
        $udp.Close()
        [void][RelayInput]::timeEndPeriod(1)
        if ($overlay) { $overlay.Close() }
        Write-Log 'DuoRelay stopped.'
    }
}

function Start-Receiver {
    $udp = New-RelaySocket ([Net.IPAddress]::Any) ([int]$cfg.port)
    $udp.Client.ReceiveTimeout = 1000   # lets Ctrl+C through every second
    $state = @{ triggers = $Triggers; clock = [Diagnostics.Stopwatch]::StartNew(); lastFired = $null }
    $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
    $refused = @{}

    Disable-QuickEdit
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { $_.IPAddress })
    Write-Log ("DuoRelay PC 2 listening on UDP {0}. This PC's address: {1}" -f $cfg.port, ($ips -join ', ')) 'Green'
    if ($cfg.pc1Address) { Write-Log ("Accepts only PC 1 = {0}" -f $cfg.pc1Address) 'Cyan' }
    if (-not (Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)) {
        Write-Log "No firewall rule '$RuleName': run Setup-Firewall-PC2.bat once, or PC 1's messages may be blocked." 'Yellow'
    }
    foreach ($t in $Triggers.Values) { Write-Log ("  {0}: presses {1} after {2} ms ({3})" -f $t.name, $t.keys, $t.delayMs, $t.label) 'Cyan' }
    Write-Log 'Click the WoW window now: keys are only pressed while WoW is the foreground window. Ctrl+C to quit.' 'Cyan'

    try {
        while ($true) {
            try { $bytes = $udp.Receive([ref]$remote) }
            catch {
                $e = $_.Exception
                if ($e.InnerException) { $e = $e.InnerException }
                if ($e -is [Net.Sockets.SocketException] -and $e.SocketErrorCode -eq [Net.Sockets.SocketError]::TimedOut) { continue }
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
        }
    }
    finally {
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
            $what = if ($code) {
                $t = $PixelTriggers[$code]
                if ($t) { "icon $code -> trigger $($t.name), PC 2 would press $($t.keys)" } else { "icon $code, no trigger with ""pixel"": $code" }
            } else { 'no code' }
            '{0}  ({1})' -f $what, (Format-Cells $rgb)
        } else { 'WoW is not the foreground window' }
        if ($line -ne $last) { Write-Log $line $(if ($line -like 'icon*') { 'White' } else { 'DarkGray' }); $last = $line }
        Start-Sleep -Milliseconds 200
    }
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
    $state = @{ triggers = $Triggers; clock = [Diagnostics.Stopwatch]::StartNew(); lastFired = $null }
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
$RuleName = "DuoRelay (UDP $($cfg.port))"

if ($SelfTest) { Invoke-SelfTest; return }
if ($SetupFirewall) { Install-FirewallRule; return }
if ($PixelProbe) { Start-PixelProbe; return }
if (-not $Triggers.Count) { throw "No trigger in $Config" }
switch ($Role) {
    'Sender'   { Start-Sender }
    'Receiver' { Start-Receiver }
    default    { throw 'Give -Role Sender (PC 1), -Role Receiver (PC 2), -SetupFirewall or -SelfTest' }
}
