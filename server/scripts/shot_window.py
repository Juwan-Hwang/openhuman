"""Capture the OpenHuman client window to PNG (DPI-aware, ctypes only)."""

import ctypes
import ctypes.wintypes as wt
import os
import sys
import time

from PIL import Image

try:  # per-monitor DPI awareness so the capture is not bitmap-stretched
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:  # noqa: BLE001
    ctypes.windll.user32.SetProcessDPIAwareness()

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)


def find_windows_of_pid(target_pid):
    found = []

    def cb(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        pid = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == target_pid:
            length = user32.GetWindowTextLengthW(hwnd)
            buf = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buf, length + 1)
            found.append((hwnd, buf.value))
        return True

    user32.EnumWindows(EnumWindowsProc(cb), 0)
    return found


def capture(hwnd, path):
    rect = wt.RECT()
    # WINDOW_RECT with DWM extended frame bounds for accurate size
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    w, h = rect.right - rect.left, rect.bottom - rect.top
    if w < 80 or h < 80:
        return None, (w, h)

    user32.ShowWindow(hwnd, 3)  # SW_MAXIMIZE alternative: 3 = maximized
    user32.SetForegroundWindow(hwnd)
    time.sleep(1.2)

    hwnd_dc = user32.GetWindowDC(hwnd)
    mfc_dc = gdi32.CreateCompatibleDC(hwnd_dc)
    bitmap = gdi32.CreateCompatibleBitmap(hwnd_dc, w, h)
    gdi32.SelectObject(mfc_dc, bitmap)
    gdi32.BitBlt(mfc_dc, 0, 0, w, h, hwnd_dc, 0, 0, 0x00CC0020)  # SRCCOPY

    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [
            ("biSize", ctypes.c_uint32),
            ("biWidth", ctypes.c_int32),
            ("biHeight", ctypes.c_int32),
            ("biPlanes", ctypes.c_uint16),
            ("biBitCount", ctypes.c_uint16),
            ("biCompression", ctypes.c_uint32),
            ("biSizeImage", ctypes.c_uint32),
            ("biXPelsPerMeter", ctypes.c_int32),
            ("biYPelsPerMeter", ctypes.c_int32),
            ("biClrUsed", ctypes.c_uint32),
            ("biClrImportant", ctypes.c_uint32),
        ]

    class BITMAPINFO(ctypes.Structure):
        _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", ctypes.c_uint32 * 3)]

    bi = BITMAPINFO()
    bi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bi.bmiHeader.biWidth = w
    bi.bmiHeader.biHeight = -h  # top-down
    bi.bmiHeader.biPlanes = 1
    bi.bmiHeader.biBitCount = 32
    bi.bmiHeader.biCompression = 0

    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mfc_dc, bitmap, 0, h, buf, ctypes.byref(bi), 0)

    img = Image.frombuffer("RGB", (w, h), buf, "raw", "BGRX", 0, 1)
    img.save(path)

    gdi32.DeleteObject(bitmap)
    gdi32.DeleteDC(mfc_dc)
    user32.ReleaseDC(hwnd, hwnd_dc)
    return path, (w, h)


def main():
    pid = int(sys.argv[1])
    out = sys.argv[2]
    wins = find_windows_of_pid(pid)
    if not wins:
        print("no window for pid", pid)
        return 1
    hwnd, title = wins[0]
    print("hwnd", hwnd, "title", repr(title))
    path, size = capture(hwnd, out)
    if path:
        print("saved", path, "size", size, "bytes", os.path.getsize(path))
        return 0
    print("window too small", size)
    return 1


if __name__ == "__main__":
    sys.exit(main())
