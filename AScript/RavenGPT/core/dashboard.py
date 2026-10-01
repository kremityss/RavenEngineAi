import json
import threading

class Dashboard:
    def __init__(self, cfg, on_change=None):
        self.cfg = cfg
        self.on_change = on_change
        self.ui = None
        self.ready = False
        self._lock = threading.Lock()

    def open(self):
        from ascript.ios.ui import WebWindow
        from ascript.ios.system import R

        def tunnel(key, value):
            if key == "__onload__":
                self.ready = True
                self.push({"type":"config", "config":self.cfg})
                return
            if key == "config":
                try:
                    changes = json.loads(value)
                    for k, v in changes.items():
                        if k in self.cfg:
                            self.cfg[k] = v
                    if self.on_change:
                        self.on_change(changes)
                except Exception as e:
                    print("[RavenGPT UI]", e)

        self.ui = WebWindow(R.ui("index.html"), tunnel)
        self.ui.show()

    def push(self, payload):
        if not self.ui or not self.ready:
            return
        try:
            data = json.dumps(payload, separators=(",",":"))
            with self._lock:
                self.ui.call("ravenUpdate(" + data + ")")
        except Exception:
            pass
