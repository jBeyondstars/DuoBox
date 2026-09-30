"""Read DuoBox's visible hunter combat-exit counter; print notifications only.

Uses Windows desktop pixels, never game memory or keyboard/mouse input.
Run standalone with Start-CombatMonitor.bat, or alongside Vosk VoiceKeys.
"""

import argparse
import ctypes
import json
import os
import threading
import time
from ctypes import wintypes


CELL_SIZE = 8
MAGIC = ((255, 0, 255), (0, 255, 255), (255, 255, 0))
END_MAGIC = (0, 255, 0)
LEVELS = (32, 96, 160, 224)
MODULUS = 4096


def close_color(actual, expected):
    return all(abs(a - b) <= 18 for a, b in zip(actual, expected))


def decode_cell(rgb):
    value = 0
    for channel in rgb:
        digit = min(range(4), key=lambda i: abs(channel - LEVELS[i]))
        if abs(channel - LEVELS[digit]) > 18:
            return None
        value = value * 4 + digit
    return value


def decode_frame(pixels, width, height):
    """Find the 9-cell signal in a top-down BGRX desktop crop."""
    def rgb(x, y):
        offset = (y * width + x) * 4
        b, g, r = pixels[offset:offset + 3]
        return r, g, b

    # Every fourth row intersects an 8px-high marker; sample inside each cell.
    for y in range(2, height, 4):
        for x in range(width - 8 * CELL_SIZE):
            if not close_color(rgb(x, y), MAGIC[0]):
                continue
            if not all(close_color(rgb(x + i * CELL_SIZE, y), color)
                       for i, color in enumerate(MAGIC)):
                continue
            if not close_color(rgb(x + 8 * CELL_SIZE, y), END_MAGIC):
                continue
            values = [decode_cell(rgb(x + i * CELL_SIZE, y)) for i in range(3, 8)]
            if None in values or sum(values[:4]) % 64 != values[4]:
                continue
            return values[0] * 64 + values[1], values[2] * 64 + values[3]
    return None


class ExitTracker:
    """Require two matching reads; baseline new sessions, retain hidden-window state."""

    def __init__(self):
        self.pending = None
        self.current = None

    def observe(self, sample):
        if sample is None:
            self.pending = None
            return None
        if sample != self.pending:
            self.pending = sample
            return None
        if self.current is None or sample[0] != self.current[0]:
            self.current = sample
            return "ready", 0
        count = (sample[1] - self.current[1]) % MODULUS
        self.current = sample
        return ("exit", count) if count else None


class BitmapInfo(ctypes.Structure):
    _fields_ = [("size", wintypes.DWORD), ("width", wintypes.LONG),
                ("height", wintypes.LONG), ("planes", wintypes.WORD),
                ("bits", wintypes.WORD), ("compression", wintypes.DWORD),
                ("image_size", wintypes.DWORD), ("xppm", wintypes.LONG),
                ("yppm", wintypes.LONG), ("used", wintypes.DWORD),
                ("important", wintypes.DWORD)]


class DesktopReader:
    def __init__(self, process_names):
        if os.name != "nt":
            raise RuntimeError("Combat monitor requires Windows.")
        self.process_names = {name.lower() for name in process_names}
        self.user = ctypes.WinDLL("user32", use_last_error=True)
        self.gdi = ctypes.WinDLL("gdi32", use_last_error=True)
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.enum_callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        # Explicit pointer-sized signatures are essential on 64-bit Windows.
        signatures = [
            (self.user, "EnumWindows", [self.enum_callback, wintypes.LPARAM], wintypes.BOOL),
            (self.user, "IsWindowVisible", [wintypes.HWND], wintypes.BOOL),
            (self.user, "IsIconic", [wintypes.HWND], wintypes.BOOL),
            (self.user, "GetClientRect", [wintypes.HWND, ctypes.POINTER(wintypes.RECT)], wintypes.BOOL),
            (self.user, "ClientToScreen", [wintypes.HWND, ctypes.POINTER(wintypes.POINT)], wintypes.BOOL),
            (self.user, "GetWindowThreadProcessId", [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)], wintypes.DWORD),
            (self.user, "GetWindowTextW", [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int], ctypes.c_int),
            (self.user, "GetDC", [wintypes.HWND], wintypes.HDC),
            (self.user, "ReleaseDC", [wintypes.HWND, wintypes.HDC], ctypes.c_int),
            (self.user, "GetSystemMetrics", [ctypes.c_int], ctypes.c_int),
            (self.gdi, "CreateCompatibleDC", [wintypes.HDC], wintypes.HDC),
            (self.gdi, "CreateCompatibleBitmap", [wintypes.HDC, ctypes.c_int, ctypes.c_int], wintypes.HBITMAP),
            (self.gdi, "SelectObject", [wintypes.HDC, wintypes.HANDLE], wintypes.HANDLE),
            (self.gdi, "DeleteObject", [wintypes.HANDLE], wintypes.BOOL),
            (self.gdi, "DeleteDC", [wintypes.HDC], wintypes.BOOL),
            (self.gdi, "BitBlt", [wintypes.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                 ctypes.c_int, wintypes.HDC, ctypes.c_int, ctypes.c_int, wintypes.DWORD], wintypes.BOOL),
            (self.gdi, "GetDIBits", [wintypes.HDC, wintypes.HBITMAP, wintypes.UINT,
                                    wintypes.UINT, ctypes.c_void_p, ctypes.POINTER(BitmapInfo), wintypes.UINT], ctypes.c_int),
            (self.kernel, "OpenProcess", [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD], wintypes.HANDLE),
            (self.kernel, "QueryFullProcessImageNameW", [wintypes.HANDLE, wintypes.DWORD,
                                                       wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)], wintypes.BOOL),
            (self.kernel, "CloseHandle", [wintypes.HANDLE], wintypes.BOOL),
        ]
        for library, name, args, result in signatures:
            function = getattr(library, name)
            function.argtypes, function.restype = args, result
        # Per-thread DPI awareness keeps coordinates physical without altering VoiceKeys.
        if hasattr(self.user, "SetThreadDpiAwarenessContext"):
            self.user.SetThreadDpiAwarenessContext.argtypes = [ctypes.c_void_p]
            self.user.SetThreadDpiAwarenessContext.restype = ctypes.c_void_p
            self.user.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))

    def windows(self):
        result = []

        @self.enum_callback
        def collect(hwnd, unused):
            if not self.user.IsWindowVisible(hwnd) or self.user.IsIconic(hwnd):
                return True
            pid = wintypes.DWORD()
            self.user.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
            handle = self.kernel.OpenProcess(0x1000, False, pid.value)
            if not handle:
                return True
            try:
                path = ctypes.create_unicode_buffer(1024)
                size = wintypes.DWORD(len(path))
                if self.kernel.QueryFullProcessImageNameW(handle, 0, path, ctypes.byref(size)):
                    name = os.path.splitext(os.path.basename(path.value))[0].lower()
                    if name in self.process_names:
                        title = ctypes.create_unicode_buffer(256)
                        self.user.GetWindowTextW(hwnd, title, len(title))
                        result.append((hwnd, pid.value, title.value or name))
            finally:
                self.kernel.CloseHandle(handle)
            return True

        if not self.user.EnumWindows(collect, 0):
            raise ctypes.WinError(ctypes.get_last_error())
        return result

    def capture(self, hwnd):
        if not self.user.IsWindowVisible(hwnd) or self.user.IsIconic(hwnd):
            return None
        rect, origin = wintypes.RECT(), wintypes.POINT(0, 0)
        if not self.user.GetClientRect(hwnd, ctypes.byref(rect)):
            return None
        if not self.user.ClientToScreen(hwnd, ctypes.byref(origin)):
            return None
        width, height = min(256, rect.right), min(96, rect.bottom)
        vx, vy = self.user.GetSystemMetrics(76), self.user.GetSystemMetrics(77)
        vw, vh = self.user.GetSystemMetrics(78), self.user.GetSystemMetrics(79)
        # Do not read undefined pixels from an off-screen or partly moved window.
        if origin.x < vx or origin.y < vy:
            return None
        width = min(width, vx + vw - origin.x)
        height = min(height, vy + vh - origin.y)
        if width < 72 or height < 8:
            return None
        screen = self.user.GetDC(None)
        if not screen:
            raise ctypes.WinError(ctypes.get_last_error())
        memory = bitmap = old = None
        try:
            memory = self.gdi.CreateCompatibleDC(screen)
            bitmap = self.gdi.CreateCompatibleBitmap(screen, width, height)
            if not memory or not bitmap:
                raise ctypes.WinError(ctypes.get_last_error())
            old = self.gdi.SelectObject(memory, bitmap)
            ok = self.gdi.BitBlt(memory, 0, 0, width, height, screen,
                                 origin.x, origin.y, 0x00CC0020 | 0x40000000)
            self.gdi.SelectObject(memory, old)
            old = None
            if not ok:
                return None
            info = BitmapInfo(size=ctypes.sizeof(BitmapInfo), width=width, height=-height,
                              planes=1, bits=32)
            buffer = ctypes.create_string_buffer(width * height * 4)
            if self.gdi.GetDIBits(memory, bitmap, 0, height, buffer, ctypes.byref(info), 0) != height:
                return None
            return decode_frame(buffer.raw, width, height)
        finally:
            if old:
                self.gdi.SelectObject(memory, old)
            if bitmap:
                self.gdi.DeleteObject(bitmap)
            if memory:
                self.gdi.DeleteDC(memory)
            self.user.ReleaseDC(None, screen)


def terminal_log(message, color="gray"):
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


class CombatMonitor:
    def __init__(self, config, log=terminal_log):
        settings = config.get("combatMonitor", {})
        self.enabled = settings.get("enabled", True)
        interval = settings.get("pollIntervalMs", 100)
        if not isinstance(interval, (int, float)) or not 50 <= interval <= 5000:
            raise ValueError("combatMonitor.pollIntervalMs must be between 50 and 5000.")
        self.interval = interval / 1000
        self.process_names = config.get("processNames", ["WowB", "Wow", "WowClassic", "WowClassicB"])
        self.log = log
        self.stop_event = threading.Event()
        self.thread = None
        self.error = None

    def run(self):
        try:
            reader = DesktopReader(self.process_names)
            self.log("Combat : attente du signal hunter. /duo combatlog on ; garder les carres en haut a gauche visibles.", "cyan")
            states, windows, refresh = {}, [], 0
            while not self.stop_event.is_set():
                now = time.monotonic()
                if now >= refresh:
                    windows = reader.windows()
                    refresh = now + 1
                visible_keys = set()
                for hwnd, pid, title in windows:
                    key = (hwnd, pid)
                    visible_keys.add(key)
                    state = states.setdefault(key, {"tracker": ExitTracker(), "last_seen": None, "lost": False})
                    sample = reader.capture(hwnd)
                    event = state["tracker"].observe(sample)
                    if sample is not None:
                        if state["lost"]:
                            self.log(f"Combat : signal hunter retrouve ({title}, PID {pid}).", "cyan")
                        state["last_seen"], state["lost"] = now, False
                    if event:
                        kind, count = event
                        if kind == "ready":
                            self.log(f"Combat : hunter detecte ({title}, PID {pid}), compteur initialise.", "cyan")
                        else:
                            for _ in range(count):
                                self.log(f"HUNTER : sortie de combat ({title}, PID {pid}).", "green")
                for key, state in states.items():
                    if key not in visible_keys:
                        state["tracker"].observe(None)
                    if state["last_seen"] is not None and now - state["last_seen"] > 2 and not state["lost"]:
                        state["lost"] = True
                        self.log(f"Combat : signal hunter non visible (PID {key[1]}). Garder les carres visibles.", "yellow")
                self.stop_event.wait(self.interval)
        except Exception as error:
            self.error = error
            self.log(f"Combat : lecture arretee : {error}", "red")

    def __enter__(self):
        if self.enabled:
            self.thread = threading.Thread(target=self.run, name="DuoBoxCombatMonitor", daemon=True)
            self.thread.start()
        return self

    def __exit__(self, *unused):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=2)


def main():
    parser = argparse.ArgumentParser(description="DuoBox hunter combat-exit notifications (read-only)")
    parser.add_argument("--config", default=os.path.join(os.path.dirname(__file__), "commands.json"))
    args = parser.parse_args()
    with open(args.config, encoding="utf-8-sig") as source:
        config = json.load(source)
    with CombatMonitor(config) as monitor:
        if not monitor.enabled:
            terminal_log("Combat : desactive dans commands.json.")
            return
        try:
            while monitor.thread.is_alive():
                monitor.thread.join(timeout=0.5)
        except KeyboardInterrupt:
            terminal_log("Combat : surveillance arretee.")
    if monitor.error:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
