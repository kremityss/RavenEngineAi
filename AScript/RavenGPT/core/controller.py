import math
import threading
import time


class AimController:
    def __init__(self, cfg, screen_size):
        self.cfg = cfg
        self.w, self.h = screen_size
        self.device = None
        self.connected = False
        self.last_error = None
        self.last_command = None
        self._lock = threading.Lock()
        self._pending = None
        self._running = True
        self._connect_lock = threading.Lock()
        self._worker = threading.Thread(target=self._run, daemon=True)
        self._worker.start()

    def connect(self):
        with self._connect_lock:
            self.disconnect()
            if self.cfg.get("mock_hid", True):
                self.connected = True
                self.last_error = None
                return True
            try:
                from ascript.ios.esp32hid import BleDevice
                self.device = BleDevice(screen_width=self.w, screen_height=self.h)
                ok = bool(self.device.connect())
                if not ok:
                    self.connected = False
                    self.last_error = "ESP32 BLE connection failed"
                    return False
                if self.device.get_mode() != BleDevice.MODE_ABS:
                    self.last_error = "ESP32 is paired in REL mode. Switch to ABS, forget the old BLE device, then re-pair."
                    self.connected = False
                    return False
                self.connected = True
                self.last_error = None
                return True
            except Exception as e:
                self.connected = False
                self.last_error = str(e)
                return False

    def reconnect_async(self):
        threading.Thread(target=self.connect, daemon=True).start()

    def disconnect(self):
        old = self.device
        self.device = None
        self.connected = bool(self.cfg.get("mock_hid", True))
        if old:
            try:
                old.disconnect()
            except Exception:
                pass

    def submit_target(self, aim_x, aim_y):
        if not self.cfg.get("aim_enabled"):
            return
        cx, cy = self.w * 0.5, self.h * 0.5
        ex, ey = aim_x - cx, aim_y - cy
        if math.hypot(ex, ey) < float(self.cfg["deadzone_px"]):
            return

        strength = float(self.cfg["strength"])
        sx = float(self.cfg["sensitivity_x"])
        sy = float(self.cfg["sensitivity_y"])
        dx = ex * sx * strength
        dy = ey * sy * strength
        limit = float(self.cfg["max_step_px"])
        dx = max(-limit, min(limit, dx))
        dy = max(-limit, min(limit, dy))

        smoothing = max(0.0, min(0.95, float(self.cfg["smoothing"])))
        if self.last_command is not None:
            pdx, pdy = self.last_command
            dx = pdx * smoothing + dx * (1.0 - smoothing)
            dy = pdy * smoothing + dy * (1.0 - smoothing)
        self.last_command = (dx, dy)
        with self._lock:
            self._pending = (dx, dy)

    def _run(self):
        while self._running:
            cmd = None
            with self._lock:
                if self._pending is not None:
                    cmd = self._pending
                    self._pending = None
            if cmd is None:
                time.sleep(0.005)
                continue

            dx, dy = cmd
            ax = int(self.w * float(self.cfg["look_anchor_x"]))
            ay = int(self.h * float(self.cfg["look_anchor_y"]))
            bx = int(max(1, min(self.w - 2, ax + dx)))
            by = int(max(1, min(self.h - 2, ay + dy)))

            if self.cfg.get("mock_hid", True):
                self.connected = True
                continue
            try:
                if self.device and self.device.is_connected():
                    self.device.swipe(
                        ax, ay, bx, by,
                        int(self.cfg["swipe_ms"]),
                        easing_mode=2,
                        easing_power=2,
                    )
                    self.connected = True
                else:
                    self.connected = False
                    self.last_error = "ESP32 BLE disconnected"
            except Exception as e:
                self.last_error = str(e)
                self.connected = False

    def close(self):
        self._running = False
        self.disconnect()
