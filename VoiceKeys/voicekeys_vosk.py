"""
VoiceKeys (Vosk engine): offline voice commands for DuoBox.

Listens to the microphone with a Vosk model restricted to the phrases of
commands.json, and presses ONE key per recognized phrase in the foreground
window.

Compliance rules, hard-coded on purpose:
  - 1 phrase = 1 key (+ modifiers), never a sequence or a loop;
  - the key only goes to the active window of THIS PC (SendInput),
    never to a background window or another machine;
  - by default nothing is sent unless WoW is the foreground window.

Usage:
  python voicekeys_vosk.py              listen (Ctrl+C to quit)
  python voicekeys_vosk.py --selftest   check config, model and keys, no mic
  python voicekeys_vosk.py --devices    list audio input devices
"""

import argparse
import array
import collections
import ctypes
import math
import json
import os
import queue
import sys
import time
import winsound
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLE_RATE = 16000

# --- Windows keyboard ----------------------------------------------------------

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

ULONG_PTR = ctypes.c_size_t


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ULONG_PTR)]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ULONG_PTR)]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("u", _INPUTUNION)]


KEYEVENTF_KEYUP = 0x2
MODIFIERS = {"SHIFT": 0x10, "CTRL": 0x11, "ALT": 0x12}
SPECIAL = {"SPACE": 0x20, "TAB": 0x09, "ENTER": 0x0D, "BACKSPACE": 0x08, "INSERT": 0x2D, "DELETE": 0x2E,
           "HOME": 0x24, "END": 0x23, "PAGEUP": 0x21, "PAGEDOWN": 0x22}


def send_key(vk, up):
    """Virtual key + matching scan code (same as AutoHotkey's Send)."""
    inp = INPUT(type=1)
    inp.u.ki = KEYBDINPUT(wVk=vk, wScan=user32.MapVirtualKeyW(vk, 0),
                          dwFlags=KEYEVENTF_KEYUP if up else 0, time=0, dwExtraInfo=0)
    user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def key_to_vk(name):
    n = name.upper()
    if n.startswith("F") and n[1:].isdigit() and 1 <= int(n[1:]) <= 24:
        return 0x6F + int(n[1:])
    if n.startswith("NUMPAD") and n[6:].isdigit() and len(n) == 7:
        return 0x60 + int(n[6:])
    if len(n) == 1 and ("A" <= n <= "Z" or "0" <= n <= "9"):
        return ord(n)
    if n in SPECIAL:
        return SPECIAL[n]
    # Any other single character ("²", "&", "é"...): ask Windows which key types it
    # on the current keyboard layout (e.g. "²" on AZERTY)
    if len(name) == 1:
        scan = user32.VkKeyScanW(ord(name))
        if scan != -1:
            if (scan >> 8) & 0x7:
                raise ValueError(f"Key '{name}' needs a modifier (Shift/AltGr) on this layout: use the base key instead")
            return scan & 0xFF
    raise ValueError(f"Unknown key: '{name}'")


def parse_chord(key):
    """'SHIFT-CTRL-F4' -> ([0x10, 0x11], 0x73)"""
    parts = key.split("-")
    mods = []
    for m in parts[:-1]:
        if m.upper() not in MODIFIERS:
            raise ValueError(f"Unknown modifier '{m}' in '{key}'")
        mods.append(MODIFIERS[m.upper()])
    return mods, key_to_vk(parts[-1])


def send_chord(chord):
    mods, vk = chord
    for m in mods:
        send_key(m, False)
    send_key(vk, False)
    time.sleep(0.04)
    send_key(vk, True)
    for m in reversed(mods):
        send_key(m, True)


def foreground_process_name():
    hwnd = user32.GetForegroundWindow()
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    handle = kernel32.OpenProcess(0x1000, False, pid.value)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return ""
    try:
        buf = ctypes.create_unicode_buffer(1024)
        size = wintypes.DWORD(len(buf))
        if not kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return ""
        return os.path.splitext(os.path.basename(buf.value))[0]
    finally:
        kernel32.CloseHandle(handle)


# --- Output --------------------------------------------------------------------

COLORS = {"gray": 90, "green": 92, "yellow": 93, "cyan": 96, "white": 97, "red": 91, "dim": 2}
os.system("")  # enables ANSI colors in the Windows console


def log(msg, color="gray"):
    print(f"\033[{COLORS.get(color, 0)}m[{time.strftime('%H:%M:%S')}] {msg}\033[0m", flush=True)


def beep(cfg, kind):
    if kind == "reject" and cfg.get("beepOnReject", True):
        winsound.Beep(300, 180)
    elif kind == "notFocused" and cfg.get("beepOnNotFocused", True):
        winsound.Beep(500, 70)
        winsound.Beep(500, 70)
    elif kind == "success" and cfg.get("beepOnSuccess", False):
        winsound.Beep(1200, 50)


def disable_quick_edit():
    """A click in the console enters QuickEdit selection and freezes the program: turn it off."""
    h = kernel32.GetStdHandle(-10)
    mode = wintypes.DWORD()
    if kernel32.GetConsoleMode(h, ctypes.byref(mode)):
        kernel32.SetConsoleMode(h, (mode.value & ~0x40) | 0x80)


# --- Configuration -------------------------------------------------------------

def load_config(path):
    with open(path, encoding="utf-8-sig") as f:
        cfg = json.load(f)
    by_phrase = {}
    for c in cfg["commands"]:
        chord = parse_chord(c["key"])
        for p in c["phrases"]:
            phrase = " ".join(p.lower().split())
            if phrase in by_phrase:
                raise ValueError(f"Duplicate phrase: '{phrase}'")
            by_phrase[phrase] = {"label": c["label"], "key": c["key"], "chord": chord}
    pause = [" ".join(p.lower().split()) for p in cfg.get("pausePhrases", [])]
    resume = [" ".join(p.lower().split()) for p in cfg.get("resumePhrases", [])]
    prefix = " ".join(cfg.get("prefix", "").lower().split())
    return cfg, by_phrase, pause, resume, prefix


def build_grammar(phrases, prefix):
    """Restricting Vosk to the command list is what makes it accurate on single words.
    "[unk]" absorbs everything else instead of forcing the closest command."""
    items = [f"{prefix} {p}" if prefix else p for p in phrases]
    return json.dumps(items + ["[unk]"])


def load_model(cfg):
    from vosk import Model, SetLogLevel
    SetLogLevel(-1)
    path = cfg.get("voskModel", "model")
    if not os.path.isabs(path):
        path = os.path.join(HERE, path)
    if not os.path.isdir(path):
        raise FileNotFoundError(f"Vosk model not found in '{path}': run Setup-VoiceKeys.bat")
    return Model(path)


def make_recognizer(model, grammar, cfg):
    from vosk import KaldiRecognizer
    rec = KaldiRecognizer(model, SAMPLE_RATE, grammar)
    rec.SetWords(True)
    # Shorter end-of-phrase detection = faster reaction (newer Vosk versions only)
    try:
        from vosk import EndpointerMode
        rec.SetEndpointerMode(EndpointerMode.SHORT)
    except Exception:
        pass
    return rec


def resolve_device(sd, wanted):
    """audioDevice: null = Windows default, a number = device index,
    text = first input device whose name contains it (e.g. "G435")."""
    if wanted is None or isinstance(wanted, int):
        return wanted
    if str(wanted).strip().isdigit():  # "1" written with quotes = index 1
        return int(str(wanted).strip())
    for i, d in enumerate(sd.query_devices()):
        if d["max_input_channels"] > 0 and str(wanted).lower() in d["name"].lower():
            return i
    raise ValueError(f"No input device matches '{wanted}' (see --devices). "
                     f"Edit \"audioDevice\" in commands.json (saving under Program Files may need admin rights)")


BLOCK = 2000  # samples per audio block (125 ms)


def rms(data):
    a = array.array("h", data)
    return math.sqrt(sum(x * x for x in a) / len(a)) if a else 0.0


class NoiseGate:
    """Cuts the microphone stream into phrases: only audio louder than the voice
    (plus a short pre-roll and hang-over) reaches Vosk, and the phrase is closed as
    soon as it gets quiet again.

    Quiet audio is never fed, not even as digital silence: Vosk then never saw the
    end of a phrase, glued clicks and noises together for 20-30 s, was forced to
    conclude and matched them to the closest command ("heal", confidence 1.00,
    0.0 s, with no one speaking).
    """

    def __init__(self, threshold, hangover_blocks=4, preroll_blocks=2):
        self.threshold = threshold
        self.hangover = hangover_blocks            # stays open 0.5 s after the last loud block
        self.preroll = collections.deque(maxlen=preroll_blocks)  # so word onsets are not cut
        self.open_left = 0
        self.voiced_blocks = 0                     # audio fed in the current phrase

    def process(self, data):
        """Returns (blocks to feed to the recognizer, True when the phrase just ended)."""
        if rms(data) >= self.threshold:
            out = list(self.preroll) if self.open_left == 0 else []
            self.preroll.clear()
            self.open_left = self.hangover
            self.voiced_blocks += 1
            return out + [data], False
        if self.open_left > 0:
            self.open_left -= 1
            self.voiced_blocks += 1
            return [data], self.open_left == 0
        self.preroll.append(data)
        return [], False

    def take_voiced_seconds(self):
        """Length of the current phrase, then resets it."""
        seconds = self.voiced_blocks * BLOCK / SAMPLE_RATE
        self.voiced_blocks = 0
        return seconds


def recognize(rec, gate, data):
    """Feeds one audio block. Returns the phrase that just ended as
    (text, confidence, voiced seconds), or None."""
    blocks, ended = gate.process(data) if gate else ([data], False)
    results = []
    for block in blocks:
        if rec.AcceptWaveform(block):
            results.append(rec.Result())
    if ended:
        results.append(rec.FinalResult())  # the gate closed: end of the phrase
    if not results:
        return None
    voiced = gate.take_voiced_seconds() if gate else 0.0
    phrases = [r for r in map(result_text_and_conf, results) if r[0]]
    if not phrases:
        return None
    text, conf = phrases[-1]
    return text, conf, voiced


def calibrate(audio, cfg):
    """noiseGate: "auto" = measure the ambient noise, a number = fixed RMS threshold, 0 = off."""
    setting = cfg.get("noiseGate", "auto")
    if setting in (0, False, None):
        return 0
    if setting != "auto":
        return float(setting)
    log("Measuring background noise, stay silent for 1.5 s...", "cyan")
    levels = sorted(rms(audio.get()) for _ in range(12))
    ambient = levels[len(levels) // 2]
    threshold = max(ambient * cfg.get("noiseGateFactor", 3.0), 150.0)
    log(f"Noise gate: ambient {ambient:.0f}, threshold {threshold:.0f} (see --level to tune)", "cyan")
    return threshold


def result_text_and_conf(result_json):
    res = json.loads(result_json)
    words = res.get("result", [])
    text = " ".join(res.get("text", "").split())
    conf = min((w.get("conf", 1.0) for w in words), default=0.0)
    return text, conf


# --- Main ----------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="VoiceKeys (Vosk)")
    ap.add_argument("--config", default=os.path.join(HERE, "commands.json"))
    ap.add_argument("--selftest", action="store_true", help="check config, model and keys, no microphone")
    ap.add_argument("--devices", action="store_true", help="list audio input devices")
    ap.add_argument("--level", action="store_true", help="show the live microphone level (to tune noiseGate)")
    args = ap.parse_args()

    import sounddevice as sd

    if args.devices:
        for i, d in enumerate(sd.query_devices()):
            if d["max_input_channels"] > 0:
                default = " (default)" if i == sd.default.device[0] else ""
                print(f"{i:3}  {d['name']}{default}")
        return

    cfg, by_phrase, pause, resume, prefix = load_config(args.config)
    model = load_model(cfg)
    grammar = build_grammar(list(by_phrase) + pause + resume, prefix)
    rec = make_recognizer(model, grammar, cfg)
    min_conf = cfg.get("voskMinConfidence", 0.6)

    if args.selftest:
        log(f"Self-test OK: Vosk model loaded, {len(by_phrase)} phrases, prefix '{prefix}', min confidence {min_conf}.", "green")
        for p in sorted(by_phrase):
            log(f"  '{p}' -> {by_phrase[p]['key']} ({by_phrase[p]['label']})")
        return

    device = resolve_device(sd, cfg.get("audioDevice"))
    device_name = sd.query_devices(device if device is not None else sd.default.device[0])["name"]
    audio = queue.Queue()

    def on_audio(indata, frames, t, status):
        audio.put(bytes(indata))

    disable_quick_edit()
    log(f"VoiceKeys (Vosk) ready, {len(by_phrase)} phrases. Ctrl+C to quit.", "green")
    log(f"Microphone: {device_name}", "cyan")
    log(f"Config: {os.path.abspath(args.config)}", "dim")
    if prefix:
        log(f"Start every command with '{prefix}'.", "cyan")
    log(f"Pause: {pause}  -  Resume: {resume}", "cyan")

    listening = True
    last_fired = {}
    process_names = cfg.get("processNames", ["WowB", "Wow", "WowClassic"])
    cooldown = cfg.get("cooldownMs", 800) / 1000
    max_utterance = cfg.get("maxUtteranceSec", 4.0)

    with sd.RawInputStream(samplerate=SAMPLE_RATE, blocksize=BLOCK, device=device,
                           dtype="int16", channels=1, callback=on_audio):
        if args.level:
            log("Live microphone level (Ctrl+C to stop): speak, then stay silent.", "cyan")
            while True:
                level = rms(audio.get())
                print(f"\r{level:7.0f} {'#' * min(60, int(level / 50)):<60}", end="", flush=True)

        threshold = calibrate(audio, cfg)
        gate = NoiseGate(threshold) if threshold else None

        while True:
            phrase = recognize(rec, gate, audio.get())
            if not phrase:
                continue
            text, conf, voiced = phrase
            # Commands are short: a long "phrase" is noise or conversation
            if voiced > max_utterance:
                if cfg.get("showIgnored"):
                    log(f"(too long, {voiced:.1f} s) '{text}'", "dim")
                continue

            if prefix:
                if not text.startswith(prefix + " "):
                    if cfg.get("showIgnored"):
                        log(f"(no prefix) '{text}'", "dim")
                    continue
                text = text[len(prefix) + 1:]

            known = text in by_phrase or text in pause or text in resume
            if not known:
                if cfg.get("showIgnored"):
                    log(f"(not a command) '{text}'", "dim")
                continue
            if conf < min_conf:
                log(f"? '{text}' (confidence {conf:.2f} < {min_conf})", "yellow")
                if listening:
                    beep(cfg, "reject")
                continue

            if text in pause:
                listening = False
                log("Listening PAUSED.", "yellow")
                continue
            if text in resume:
                listening = True
                log("Listening RESUMED.", "green")
                continue
            if not listening:
                continue

            now = time.monotonic()
            if now - last_fired.get(text, 0) < cooldown:
                continue

            if cfg.get("onlyWhenWowFocused", True):
                fg = foreground_process_name()
                if fg not in process_names:
                    log(f"'{text}' ignored: WoW is not the foreground window ({fg}).", "yellow")
                    beep(cfg, "notFocused")
                    continue

            last_fired[text] = now
            cmd = by_phrase[text]
            send_chord(cmd["chord"])
            beep(cfg, "success")
            log(f"{cmd['label']:<16} -> {cmd['key']:<10} (conf {conf:.2f}, {voiced:.1f} s)", "white")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("VoiceKeys stopped.")
    except Exception as e:
        log(f"Error: {e}", "red")
        sys.exit(1)
