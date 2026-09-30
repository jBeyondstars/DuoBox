"""Protocol/state tests: python -m unittest discover -s VoiceKeys -p test_combat_monitor.py"""

import ctypes
import os
from pathlib import Path
import unittest
from ctypes import wintypes
from unittest.mock import patch

from combat_monitor import BitmapInfo, CombatMonitor, DesktopReader, ExitTracker, MAGIC, END_MAGIC, LEVELS, decode_frame

try:
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None


def colors(session, counter):
    values = [session // 64, session % 64, counter // 64, counter % 64]
    values.append(sum(values) % 64)
    return [*MAGIC, *[(LEVELS[v // 16], LEVELS[v // 4 % 4], LEVELS[v % 4])
                      for v in values], END_MAGIC]


def image(cell_colors, x=12, y=12, width=120, height=40):
    pixels = bytearray(width * height * 4)
    for i, (r, g, b) in enumerate(cell_colors):
        for row in range(y, y + 8):
            for col in range(x + i * 8, x + (i + 1) * 8):
                offset = (row * width + col) * 4
                pixels[offset:offset + 4] = bytes((b, g, r, 0))
    return pixels, width, height


class ProtocolTests(unittest.TestCase):
    def test_scan_offset_and_boundaries(self):
        for session, counter in [(0, 0), (4095, 4095), (1957, 2077), (1, 64)]:
            for x, y in [(0, 0), (12, 12), (48, 32), (7, 5)]:
                with self.subTest(session=session, counter=counter, x=x, y=y):
                    self.assertEqual(decode_frame(*image(colors(session, counter), x, y)),
                                     (session, counter))

    def test_small_capture_color_variation(self):
        cells = [tuple(max(0, min(255, c + 10)) for c in rgb) for rgb in colors(100, 245)]
        self.assertEqual(decode_frame(*image(cells)), (100, 245))

    def test_bad_checksum_is_ignored(self):
        cells = colors(123, 4)
        cells[7] = (32, 32, 96)
        self.assertIsNone(decode_frame(*image(cells)))

    def test_obscured_marker_and_bad_data_are_ignored(self):
        for index, replacement in [(1, (0, 0, 0)), (8, (0, 0, 0)), (4, (70, 70, 70))]:
            cells = colors(123, 4)
            cells[index] = replacement
            self.assertIsNone(decode_frame(*image(cells)))
        self.assertIsNone(decode_frame(bytes(120 * 40 * 4), 120, 40))


@unittest.skipIf(LuaRuntime is None, "Optional developer Lua runtime (lupa)")
class AddonProtocolTests(unittest.TestCase):
    def test_addon_colors_and_actual_combat_event(self):
        source = (Path(__file__).resolve().parent.parent / "DuoBox.lua").read_text(encoding="utf-8")
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.compile(source)
        signal = "local combatSignal = CreateFrame" + source.split("local combatSignal = CreateFrame", 1)[1].split("-- Small status frame", 1)[0]
        exit_branch = source.split('elseif event == "PLAYER_REGEN_ENABLED" then', 1)[1].split('elseif event == "UI_SCALE_CHANGED"', 1)[0]
        feature_flags = "local FEATURES =" + source.split("local FEATURES =", 1)[1].split("local defaults =", 1)[0]
        prelude = feature_flags + '''
local DB = { combatMonitor = true }
local class = "HUNTER"
local modifierUpdates = 0
local function ApplyModifierBindings() modifierUpdates = modifierUpdates + 1 end
UIParent = {GetEffectiveScale = function() return 0.75 end}
function UnitClass() return class, class end
function CreateFrame()
  local frame = {shown = false}
  return setmetatable(frame, {__index = function(self, key)
    if key == "CreateTexture" then return function()
      local cell = {}
      return setmetatable(cell, {__index = function(_, method)
        if method == "SetColorTexture" then return function(t, r, g, b) t.rgb = {r, g, b} end end
        return function() end
      end})
    end
    elseif key == "Show" then return function(t) t.shown = true end
    elseif key == "Hide" then return function(t) t.shown = false end
    elseif key == "SetScale" then return function(t, value) t.scale = value end
    end
    return function() end
  end})
end
'''
        api = lua.execute(prelude + signal + '''
return {
 feature = function(enabled) FEATURES.combatMonitor = enabled end,
 set = function(session, count, playerClass, enabled)
   combatSession, combatExits, class, DB.combatMonitor = session, count, playerClass, enabled
   UpdateCombatSignal()
 end,
 exit = function() ''' + exit_branch + ''' end,
 frame = combatSignal,
 count = function() return combatExits end,
 modifierUpdates = function() return modifierUpdates end
}
''')
        api["set"](1957, 4, "HUNTER", True)
        self.assertFalse(api["frame"]["shown"])
        api["exit"]()
        self.assertEqual(api["count"](), 4)
        self.assertEqual(api["modifierUpdates"](), 1)
        api["feature"](True)
        for session, count in [(0, 0), (4095, 4095), (1957, 2077), (64, 63)]:
            api["set"](session, count, "HUNTER", True)
            cells = api["frame"]["cells"]
            actual_colors = [tuple(round(cells[i]["rgb"][j] * 255) for j in range(1, 4)) for i in range(1, 10)]
            self.assertEqual(decode_frame(*image(actual_colors)), (session, count))
        self.assertAlmostEqual(api["frame"]["scale"], 1 / .75)
        api["set"](1957, 4095, "HUNTER", True)
        api["exit"]()
        self.assertEqual(api["count"](), 0)
        self.assertEqual(api["modifierUpdates"](), 2)
        api["set"](1957, 4, "PRIEST", True)
        self.assertFalse(api["frame"]["shown"])
        api["exit"]()
        self.assertEqual(api["count"](), 4)
        self.assertEqual(api["modifierUpdates"](), 3)
        api["set"](1957, 4, "HUNTER", False)
        self.assertFalse(api["frame"]["shown"])
        api["exit"]()
        self.assertEqual(api["count"](), 4)


class TrackerTests(unittest.TestCase):
    def confirm(self, tracker, sample):
        tracker.observe(sample)
        return tracker.observe(sample)

    def test_first_read_is_baseline_and_no_duplicate(self):
        tracker = ExitTracker()
        self.assertEqual(self.confirm(tracker, (10, 12)), ("ready", 0))
        self.assertIsNone(tracker.observe((10, 12)))
        self.assertEqual(self.confirm(tracker, (10, 13)), ("exit", 1))
        self.assertIsNone(tracker.observe((10, 13)))

    def test_missing_samples_preserve_counter(self):
        tracker = ExitTracker()
        self.confirm(tracker, (10, 12))
        self.assertIsNone(tracker.observe(None))
        self.assertEqual(self.confirm(tracker, (10, 15)), ("exit", 3))

    def test_session_reload_is_baseline(self):
        tracker = ExitTracker()
        self.confirm(tracker, (10, 300))
        self.assertEqual(self.confirm(tracker, (11, 0)), ("ready", 0))
        self.assertEqual(self.confirm(tracker, (11, 1)), ("exit", 1))

    def test_counter_wrap(self):
        tracker = ExitTracker()
        self.confirm(tracker, (10, 4095))
        self.assertEqual(self.confirm(tracker, (10, 0)), ("exit", 1))

    def test_unconfirmed_and_interrupted_reads_do_not_notify(self):
        tracker = ExitTracker()
        self.confirm(tracker, (10, 1))
        self.assertIsNone(tracker.observe((10, 200)))
        self.assertIsNone(tracker.observe((10, 1)))
        self.assertIsNone(tracker.observe((10, 2)))
        self.assertIsNone(tracker.observe(None))
        self.assertIsNone(tracker.observe((10, 2)))
        self.assertEqual(tracker.observe((10, 2)), ("exit", 1))


class MonitorTests(unittest.TestCase):
    def test_terminal_notifications_and_reconnect(self):
        samples = iter([(10, 0), (10, 0), (10, 1), (10, 1), (10, 1),
                        None, (10, 3), (10, 3), (11, 0), (11, 0)])
        messages = []
        monitor = CombatMonitor({"combatMonitor": {"enabled": True}},
                                lambda message, color: messages.append(message))

        class Reader:
            def __init__(self, names):
                pass

            def windows(self):
                return [(123, 456, "World of Warcraft")]

            def capture(self, hwnd):
                try:
                    return next(samples)
                except StopIteration:
                    monitor.stop_event.set()
                    return None

        with patch("combat_monitor.DesktopReader", Reader):
            monitor.run()
        exits = [message for message in messages if message.startswith("HUNTER : sortie de combat")]
        baselines = [message for message in messages if "compteur initialise" in message]
        self.assertEqual(len(exits), 3)
        self.assertEqual(len(baselines), 2)
        self.assertIsNone(monitor.error)

    def test_disabled_monitor_starts_no_thread(self):
        for config in [{}, {"combatMonitor": {}}, {"combatMonitor": {"enabled": False}}]:
            with self.subTest(config=config), CombatMonitor(config) as monitor:
                self.assertIsNone(monitor.thread)


@unittest.skipUnless(os.name == "nt", "Windows GDI capture")
class WindowsCaptureTests(unittest.TestCase):
    def test_actual_gdi_capture_of_synthetic_signal(self):
        # A memory DC replaces the desktop, exercising native BitBlt/GetDIBits
        # without opening a window, reading the game or requiring a microphone.
        reader = DesktopReader(["WowB"])
        pixels, width, height = image(colors(1957, 2077))
        real_user = reader.user
        screen = real_user.GetDC(None)
        memory = reader.gdi.CreateCompatibleDC(screen)
        bitmap = reader.gdi.CreateCompatibleBitmap(screen, width, height)
        previous = reader.gdi.SelectObject(memory, bitmap)
        try:
            info = BitmapInfo(size=ctypes.sizeof(BitmapInfo), width=width, height=-height, planes=1, bits=32)
            buffer = ctypes.create_string_buffer(bytes(pixels))
            write = reader.gdi.SetDIBitsToDevice
            write.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int, wintypes.DWORD,
                              wintypes.DWORD, ctypes.c_int, ctypes.c_int, wintypes.UINT,
                              wintypes.UINT, ctypes.c_void_p, ctypes.POINTER(BitmapInfo), wintypes.UINT]
            write.restype = ctypes.c_int
            self.assertEqual(write(memory, 0, 0, width, height, 0, 0, 0, height, buffer,
                                   ctypes.byref(info), 0), height)

            class SyntheticDesktop:
                def IsWindowVisible(self, hwnd):
                    return True

                def IsIconic(self, hwnd):
                    return False

                def GetClientRect(self, hwnd, pointer):
                    rect = ctypes.cast(pointer, ctypes.POINTER(wintypes.RECT)).contents
                    rect.right, rect.bottom = width, height
                    return True

                def ClientToScreen(self, hwnd, pointer):
                    return True

                def GetSystemMetrics(self, index):
                    return {76: 0, 77: 0, 78: width, 79: height}[index]

                def GetDC(self, hwnd):
                    return memory

                def ReleaseDC(self, hwnd, dc):
                    return 1

            reader.user = SyntheticDesktop()
            self.assertEqual(reader.capture(123), (1957, 2077))
        finally:
            reader.gdi.SelectObject(memory, previous)
            reader.gdi.DeleteObject(bitmap)
            reader.gdi.DeleteDC(memory)
            real_user.ReleaseDC(None, screen)


if __name__ == "__main__":
    unittest.main()
