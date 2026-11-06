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

    WARNING: one click acting in two game clients is input broadcasting, which
    Blizzard's multiboxing policy forbids whatever the transport (cable, LAN,
    KVM). Not part of DuoBox's "1 key press = 1 action in 1 client" design.
    OFF at start (startEnabled). See GUIDE.md section 7.

    Run with Windows PowerShell 5.1 (Start-Relay-PC1.bat / Start-Relay-PC2.bat).
      DuoRelay.ps1 -Role Sender [-Pc2 192.168.1.20]
      DuoRelay.ps1 -Role Receiver
      DuoRelay.ps1 -SetupFirewall      (PC 2, once: lets PC 1's messages in)
      DuoRelay.ps1 -SelfTest           (no network beyond 127.0.0.1, no key press)
    Ctrl+C to quit.
#>
param(
    [ValidateSet('Sender', 'Receiver')] [string]$Role,
    [string]$Config = (Join-Path $PSScriptRoot 'DuoRelay.json'),
    [string]$Pc2,
    [switch]$SetupFirewall,
    [switch]$Elevated,
    [switch]$SelfTest
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

    // Cursor position; returns false while the cursor is hidden
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
    maxClickMovePx = 6; maxClickMs = 500; delayMs = 300; minIntervalMs = 500
    overlay = $true; overlayX = -1; overlayY = 2; sounds = $false
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
    $button = ([string]$t.button).Trim().ToUpper()
    if (-not $MouseButtons.ContainsKey($button)) { throw "Trigger '$name': unknown button '$($t.button)' (LEFT, RIGHT, MIDDLE, X1, X2)" }
    $mods = @()
    foreach ($m in (([string]$t.modifier).Trim().ToUpper() -split '-' | Where-Object { $_ })) {
        if (-not $Modifiers.ContainsKey($m)) { throw "Trigger '$name': unknown modifier '$m' (CTRL, ALT, SHIFT, e.g. CTRL-SHIFT)" }
        $mods += $Modifiers[$m]
    }
    if ($mods.Count -eq 0) { throw "Trigger '$name': a modifier is required, otherwise every click would be relayed" }
    # Optional per-trigger wait on PC 2 (pickup: the addon's message has to arrive first)
    $delay = if ($null -ne $t.delayMs) { [int]$t.delayMs } else { [int]$cfg.delayMs }
    return [pscustomobject]@{
        name = $name; label = [string]$t.label; keys = [string]$t.keys; chords = (ConvertTo-Chords $t.keys); delayMs = $delay
        combo = ('{0}+{1} click' -f ([string]$t.modifier).ToUpper(), $button.ToLower())
        buttonVk = $MouseButtons[$button]; mods = $mods; state = @{ wasDown = $false; armed = $false }
    }
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

# One poll of a trigger's mouse button. Returns $true when a real click ends:
# pressed while $ok (modifier held, relay ON, WoW focused), released within
# $maxMs, cursor moved at most $maxMove px and not hidden meanwhile (a camera
# drag hides it; a cursor already hidden at the press is not taken as a drag).
function Step-Click($s, [bool]$down, [bool]$ok, [int]$x, [int]$y, [bool]$visible, [long]$now, [int]$maxMove, [int]$maxMs) {
    $fired = $false
    if ($down -and -not $s.wasDown) {
        $s.armed = $ok; $s.x = $x; $s.y = $y; $s.t = $now; $s.shown = $visible
    } elseif ($s.armed) {
        $moved = [math]::Abs($x - $s.x) -gt $maxMove -or [math]::Abs($y - $s.y) -gt $maxMove
        if ($moved -or ($s.shown -and -not $visible) -or ($now - $s.t) -gt $maxMs) { $s.armed = $false }
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

    $overlay = $null
    if ($cfg.overlay) {
        [void][RelayInput]::SetProcessDPIAware()
        $overlay = [RelayOverlay]::new([int]$cfg.overlayX, [int]$cfg.overlayY, ([int]$cfg.overlayX -lt 0))
        $overlay.Show()
    }
    $flash = {
        param([string]$text, [Drawing.Color]$color, [int]$ms)
        $st.flashText = $text; $st.flashColor = $color; $st.flashUntil = $clock.ElapsedMilliseconds + $ms
    }

    Disable-QuickEdit
    Write-Log ("DuoRelay PC 1 -> {0}:{1}. Relay {2} - {3} toggles it. Ctrl+C to quit." -f $address, $cfg.port,
        $(if ($st.enabled) { 'ON' } else { 'OFF' }), $toggleName) 'Green'
    foreach ($t in $Triggers.Values) { Write-Log ("  {0} -> PC 2 presses {1} ({2})" -f $t.combo, $t.keys, $t.label) 'Cyan' }

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

            # Clicks
            $visible = [RelayInput]::Cursor([ref]$cx, [ref]$cy)
            foreach ($t in $Triggers.Values) {
                $down = [RelayInput]::IsDown($t.buttonVk)
                $ok = $false
                if ($down -and -not $t.state.wasDown -and $st.enabled) { $ok = (Test-Modifiers $t.mods) -and (Test-WowForeground) }
                if (Step-Click $t.state $down $ok $cx $cy $visible $now ([int]$cfg.maxClickMovePx) ([int]$cfg.maxClickMs)) {
                    $st.seq++
                    if (Send-Relay $udp $to (New-RelayMessage $st.seq 'CLICK' $t.name)) {
                        $st.pending["$($st.seq)"] = $now
                        Write-Log ("{0} -> PC 2 ({1})" -f $t.combo, $t.name) 'White'
                        & $flash 'Relais -> PC 2...' ([Drawing.Color]::Gold) 3000
                    }
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
        param($steps)  # each: down, ok, x, y, visible, t
        $s = @{ wasDown = $false; armed = $false }; $r = $false
        foreach ($p in $steps) { $r = Step-Click $s $p[0] $p[1] $p[2] $p[3] $p[4] $p[5] 6 500 }
        return $r
    }
    Check (& $run @(@($true, $true, 100, 100, $true, 0), @($true, $false, 101, 100, $true, 40), @($false, $false, 102, 101, $true, 80))) 'short click fires on release'
    Check (-not (& $run @(@($true, $false, 100, 100, $true, 0), @($false, $false, 100, 100, $true, 80)))) 'no modifier / relay OFF: nothing'
    Check (-not (& $run @(@($true, $true, 100, 100, $true, 0), @($true, $true, 130, 100, $true, 40), @($false, $false, 100, 100, $true, 80)))) 'drag (cursor moved): nothing'
    Check (-not (& $run @(@($true, $true, 100, 100, $true, 0), @($true, $true, 100, 100, $false, 40), @($false, $false, 100, 100, $true, 80)))) 'camera turn (cursor hidden): nothing'
    Check (-not (& $run @(@($true, $true, 100, 100, $true, 0), @($false, $false, 100, 100, $true, 900)))) 'long press: nothing'
    Check (& $run @(@($true, $true, 100, 100, $false, 0), @($false, $false, 100, 100, $false, 80))) 'cursor always hidden: click still fires'

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
$Triggers = [ordered]@{}
foreach ($t in @($cfg.triggers)) {
    $trigger = ConvertTo-Trigger $t
    if ($Triggers.Contains($trigger.name)) { throw "Duplicate trigger name '$($trigger.name)'" }
    $Triggers[$trigger.name] = $trigger
}
$RuleName = "DuoRelay (UDP $($cfg.port))"

if ($SelfTest) { Invoke-SelfTest; return }
if ($SetupFirewall) { Install-FirewallRule; return }
if (-not $Triggers.Count) { throw "No trigger in $Config" }
switch ($Role) {
    'Sender'   { Start-Sender }
    'Receiver' { Start-Receiver }
    default    { throw 'Give -Role Sender (PC 1), -Role Receiver (PC 2), -SetupFirewall or -SelfTest' }
}
