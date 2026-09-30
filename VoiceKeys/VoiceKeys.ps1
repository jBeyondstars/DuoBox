#requires -Version 5.1
<#
    VoiceKeys: a tiny "VoiceAttack" for DuoBox.
    Recognizes a closed list of phrases (Windows offline speech engine)
    and presses ONE key per phrase in the foreground window.

    Compliance rules, hard-coded on purpose:
      - 1 phrase = 1 key (+ modifiers), never a sequence or a loop;
      - the key only goes to the active window of THIS PC (SendInput),
        never to a background window or another machine;
      - by default nothing is sent unless WoW is the foreground window.

    Run with Windows PowerShell 5.1 (see Lancer-VoiceKeys.bat).
    Ctrl+C to quit.
#>
param(
    [string]$Config = (Join-Path $PSScriptRoot 'commands.json'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class VKInput {
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion u; }

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
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

    const uint KEYEVENTF_KEYUP = 0x2;

    // Virtual key + matching scan code (same as AutoHotkey's Send): games receive
    // the key code directly, which works for F13-F24 (a scan code alone does not in WoW)
    public static void Key(ushort vk, bool up) {
        INPUT[] i = new INPUT[1];
        i[0].type = 1;
        i[0].u.ki.wVk = vk;
        i[0].u.ki.wScan = (ushort)MapVirtualKey(vk, 0);
        i[0].u.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
        SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@

$Modifiers = @{ SHIFT = 0x10; CTRL = 0x11; ALT = 0x12 }

function Get-VK([string]$name) {
    $n = $name.ToUpper()
    if ($n -match '^F(\d{1,2})$') {
        $f = [int]$Matches[1]
        if ($f -ge 1 -and $f -le 24) { return 0x6F + $f }
    }
    if ($n -match '^NUMPAD(\d)$') { return 0x60 + [int]$Matches[1] }
    if ($n -match '^[A-Z0-9]$') { return [int][char]$n }
    $special = @{ SPACE = 0x20; TAB = 0x09; ENTER = 0x0D; BACKSPACE = 0x08; INSERT = 0x2D; DELETE = 0x2E;
                  HOME = 0x24; END = 0x23; PAGEUP = 0x21; PAGEDOWN = 0x22 }
    if ($special.ContainsKey($n)) { return $special[$n] }
    throw "Unknown key: '$name'"
}

# "SHIFT-CTRL-F13" -> @{ mods = @(0x10, 0x11); vk = 0x7C }
function ConvertTo-Chord([string]$key) {
    $parts = $key.ToUpper() -split '-'
    $mods = @()
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        if (-not $Modifiers.ContainsKey($parts[$i])) { throw "Unknown modifier '$($parts[$i])' in '$key'" }
        $mods += $Modifiers[$parts[$i]]
    }
    return @{ mods = $mods; vk = (Get-VK $parts[-1]) }
}

function Send-Chord($chord) {
    foreach ($m in $chord.mods) { [VKInput]::Key([uint16]$m, $false) }
    [VKInput]::Key([uint16]$chord.vk, $false)
    Start-Sleep -Milliseconds 40
    [VKInput]::Key([uint16]$chord.vk, $true)
    [array]::Reverse($chord.mods)
    foreach ($m in $chord.mods) { [VKInput]::Key([uint16]$m, $true) }
    [array]::Reverse($chord.mods)
}

function Get-ForegroundProcessName {
    $h = [VKInput]::GetForegroundWindow()
    $procId = [uint32]0
    [void][VKInput]::GetWindowThreadProcessId($h, [ref]$procId)
    try { return (Get-Process -Id $procId).ProcessName } catch { return '' }
}

# Audible feedback: low tone = not understood, double tone = WoW not focused, high tone = sent
function Invoke-Beep([string]$kind) {
    switch ($kind) {
        'reject'     { if ($cfg.beepOnReject -ne $false) { [console]::Beep(300, 180) } }
        'notFocused' { if ($cfg.beepOnNotFocused -ne $false) { [console]::Beep(500, 70); [console]::Beep(500, 70) } }
        'success'    { if ($cfg.beepOnSuccess -eq $true) { [console]::Beep(1200, 50) } }
    }
}

function Disable-QuickEdit {
    if (-not [VKInput]::DisableQuickEdit()) { Write-Log "Could not disable console QuickEdit: don't click inside this window." 'DarkYellow' }
}

function Write-Log([string]$msg, [string]$color = 'Gray') {
    Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg) -ForegroundColor $color
}

# --- Configuration ---------------------------------------------------------

$cfg = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$prefix = ([string]$cfg.prefix).Trim().ToLower()

$byPhrase = @{}
foreach ($c in $cfg.commands) {
    $chord = ConvertTo-Chord $c.key
    foreach ($p in $c.phrases) {
        $phrase = $p.Trim().ToLower()
        if ($byPhrase.ContainsKey($phrase)) { throw "Duplicate phrase: '$phrase'" }
        $byPhrase[$phrase] = @{ label = $c.label; key = $c.key; chord = $chord }
    }
}
$pause = @($cfg.pausePhrases | ForEach-Object { $_.Trim().ToLower() })
$resume = @($cfg.resumePhrases | ForEach-Object { $_.Trim().ToLower() })

# --- Speech engine ---------------------------------------------------------

$installed = @([System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers())
$recognizer = $installed | Where-Object { $_.Culture.Name -eq $cfg.language } | Select-Object -First 1
if (-not $recognizer) {
    if ($installed.Count -eq 0) { throw "No Windows speech recognizer installed." }
    $recognizer = $installed[0]
    Write-Log ("No '{0}' speech recognizer installed, falling back to '{1}' (English words will be recognized less reliably)." -f $cfg.language, $recognizer.Culture.Name) 'Yellow'
    Write-Log "Install it: Settings > Time & language > Language & region > add 'English (United States)' with speech recognition." 'Yellow'
}
$culture = $recognizer.Culture

$engine = [System.Speech.Recognition.SpeechRecognitionEngine]::new($recognizer)

$choices = [System.Speech.Recognition.Choices]::new()
foreach ($p in @($byPhrase.Keys) + $pause + $resume) { $choices.Add($p) }
$gb = [System.Speech.Recognition.GrammarBuilder]::new()
$gb.Culture = $culture
if ($prefix) { $gb.Append($prefix) }
$gb.Append($choices)
$grammar = [System.Speech.Recognition.Grammar]::new($gb)
$grammar.Name = 'commands'
$grammar.Priority = 127   # wins ties against dictation
$grammar.Weight = 1.0
$engine.LoadGrammar($grammar)

# Catch-all grammar: speech outside the list lands here instead of being
# matched to the closest command (reduces false triggers).
# Command words also exist in dictation, so a dictation result whose text is
# exactly a command is still accepted (see the main loop).
if ($cfg.rejectOtherSpeech) {
    try {
        $dict = [System.Speech.Recognition.DictationGrammar]::new()
        $dict.Name = 'other'
        $dict.Priority = 0
        $dict.Weight = 0.3
        $engine.LoadGrammar($dict)
    } catch {
        Write-Log "Dictation unavailable, filtering of unlisted speech is disabled." 'Yellow'
    }
}

if ($SelfTest) {
    Write-Log ("Self-test OK: engine '{0}', {1} phrases, prefix '{2}'." -f $recognizer.Description, $byPhrase.Count, $prefix) 'Green'
    foreach ($p in ($byPhrase.Keys | Sort-Object)) { Write-Log ("  '{0}' -> {1} ({2})" -f $p, $byPhrase[$p].key, $byPhrase[$p].label) }
    # Simulate each phrase (text, no microphone) to see which grammar captures it
    try {
        $engine.SetInputToNull()
        Write-Log 'Simulated recognition (grammar / confidence):'
        foreach ($p in ($byPhrase.Keys | Sort-Object)) {
            $res = $engine.EmulateRecognize(($(if ($prefix) { "$prefix " } else { '' }) + $p))
            if ($res) { Write-Log ("  '{0}' -> {1} ({2:N2})" -f $p, $res.Grammar.Name, $res.Confidence) }
            else { Write-Log ("  '{0}' -> not recognized" -f $p) 'DarkYellow' }
        }
    } catch { Write-Log ("Simulation unavailable: {0}" -f $_.Exception.Message) 'DarkYellow' }
    $engine.Dispose()
    return
}

Disable-QuickEdit
$engine.SetInputToDefaultAudioDevice()
Register-ObjectEvent -InputObject $engine -EventName SpeechRecognized -SourceIdentifier 'VoiceKeys.Recognized' | Out-Null
Register-ObjectEvent -InputObject $engine -EventName AudioSignalProblemOccurred -SourceIdentifier 'VoiceKeys.Audio' | Out-Null
Register-ObjectEvent -InputObject $engine -EventName RecognizeCompleted -SourceIdentifier 'VoiceKeys.Completed' | Out-Null
$lastAudioWarn = 0

Write-Log ("VoiceKeys ready ({0}, {1} phrases). Ctrl+C to quit." -f $culture.Name, $byPhrase.Count) 'Green'
if ($prefix) { Write-Log "Start every command with '$prefix'." 'Cyan' }
Write-Log ("Pause: '{0}'  -  Resume: '{1}'" -f ($pause -join "', '"), ($resume -join "', '")) 'Cyan'

$listening = $true
$lastFired = @{}
$engine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)

try {
    while ($true) {
        $ev = Wait-Event -Timeout 1
        if (-not $ev) { continue }
        Remove-Event -EventIdentifier $ev.EventIdentifier

        # Microphone too quiet / too loud / noisy: tell the user (at most every 3 s)
        # NoSignal is also reported during silence with a noise gate / mic muting: log it rarely
        if ($ev.SourceIdentifier -eq 'VoiceKeys.Audio') {
            $now = [Environment]::TickCount
            $delay = if ("$($ev.SourceEventArgs.AudioSignalProblem)" -eq 'NoSignal') { 30000 } else { 3000 }
            if ($now - $lastAudioWarn -gt $delay) {
                Write-Log ("Mic: {0}" -f $ev.SourceEventArgs.AudioSignalProblem) 'DarkYellow'
                $lastAudioWarn = $now
            }
            continue
        }
        # Recognition stopped (mic unplugged, device change...): restart it
        if ($ev.SourceIdentifier -eq 'VoiceKeys.Completed') {
            Write-Log 'Listening stopped by Windows, restarting...' 'Yellow'
            Start-Sleep -Milliseconds 500
            try {
                $engine.SetInputToDefaultAudioDevice()
                $engine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)
            } catch {
                Write-Log ("Restart failed: {0}" -f $_.Exception.Message) 'Red'
            }
            continue
        }
        if ($ev.SourceIdentifier -ne 'VoiceKeys.Recognized') { continue }
        $r = $ev.SourceEventArgs.Result

        # Normalize: lowercase, no punctuation (dictation adds "Shield." etc.)
        $text = ($r.Text.ToLower() -replace '[\.\,\!\?;:]', '').Trim()
        if ($prefix) {
            if ($text.StartsWith($prefix)) { $text = $text.Substring($prefix.Length).Trim() }
            elseif ($r.Grammar.Name -ne 'commands') { $text = '' }
        }
        $known = $byPhrase.ContainsKey($text) -or ($pause -contains $text) -or ($resume -contains $text)

        if ($r.Grammar.Name -ne 'commands' -and -not $known) {
            if ($cfg.showIgnored) { Write-Log ("(not a command) '{0}'" -f $r.Text) 'DarkGray' }
            continue
        }
        $conf = [math]::Round($r.Confidence, 2)
        # An exact command word found by dictation is a strong signal: lower threshold
        $threshold = $cfg.minConfidence
        if ($r.Grammar.Name -ne 'commands') {
            $threshold = if ($null -ne $cfg.dictationMinConfidence) { $cfg.dictationMinConfidence } else { 0.3 }
        }

        if ($r.Confidence -lt $threshold) {
            Write-Log ("? '{0}' (confidence {1} < {2})" -f $text, $conf, $threshold) 'DarkYellow'
            if ($listening) { Invoke-Beep 'reject' }
            continue
        }
        if ($pause -contains $text) { $listening = $false; Write-Log 'Listening PAUSED.' 'Yellow'; continue }
        if ($resume -contains $text) { $listening = $true; Write-Log 'Listening RESUMED.' 'Green'; continue }
        if (-not $listening) { continue }

        $cmd = $byPhrase[$text]
        if (-not $cmd) { continue }

        $now = [Environment]::TickCount
        if ($lastFired.ContainsKey($text) -and ($now - $lastFired[$text]) -lt $cfg.cooldownMs) { continue }

        if ($cfg.onlyWhenWowFocused) {
            $fg = Get-ForegroundProcessName
            if ($cfg.processNames -notcontains $fg) {
                Write-Log ("'{0}' ignored: WoW is not the foreground window ({1})." -f $text, $fg) 'DarkYellow'
                Invoke-Beep 'notFocused'
                continue
            }
        }

        $lastFired[$text] = $now
        Send-Chord $cmd.chord
        Invoke-Beep 'success'
        Write-Log ("{0,-16} -> {1,-10} ({2})" -f $cmd.label, $cmd.key, $conf) 'White'
    }
}
finally {
    $engine.RecognizeAsyncCancel()
    foreach ($id in 'VoiceKeys.Recognized', 'VoiceKeys.Audio', 'VoiceKeys.Completed') {
        Unregister-Event -SourceIdentifier $id -ErrorAction SilentlyContinue
    }
    $engine.Dispose()
    Write-Log 'VoiceKeys stopped.'
}
