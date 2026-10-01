import hashlib
import os
import ssl
import tempfile
import time
import urllib.request


MODEL_SHA256 = "5446731e6afb9605ef1c60fac66338c2006595a14f97a41e061b0215965a7132"
MODEL_PARTS = 11
MODEL_PART_URL = "https://raw.githubusercontent.com/kremityss/RavenEngineAi/main/.ravenbin_parts/part{index:02d}"\nMODEL_PARAM_URL = "https://raw.githubusercontent.com/kremityss/RavenEngineAi/main/AScript/RavenGPT/res/raven.param"\nMODEL_PARAM_SIZE = 22636
MODEL_PARAM_SHA256 = "346093c80049ed50532dbba802937186baca435ce76ae6c3fb5ded63799b1d5c"


class RavenDetector:
    def __init__(self, cfg):
        self.cfg = cfg
        self.loaded = False
        self.yolo = None
        self.last_ms = 0.0
        self.last_error = None

    def _sha256(self, path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        return h.hexdigest()

    def _bootstrap_bin(self):
        cache_dir = os.path.join(tempfile.gettempdir(), "ravengpt")
        os.makedirs(cache_dir, exist_ok=True)
        target = os.path.join(cache_dir, "raven.bin")

        if os.path.isfile(target):
            try:
                if self._sha256(target) == MODEL_SHA256:
                    return target
            except Exception:
                pass

        tmp = target + ".part"
        try:
            with open(tmp, "wb") as out:
                for i in range(MODEL_PARTS):
                    url = MODEL_PART_URL.format(index=i)
                    with self._urlopen(url, timeout=20) as response:
                        while True:
                            chunk = response.read(1024 * 256)
                            if not chunk:
                                break
                            out.write(chunk)
            if self._sha256(tmp) != MODEL_SHA256:
                raise RuntimeError("Raven model checksum mismatch after download")
            os.replace(tmp, target)
            return target
        except Exception:
            try:
                if os.path.exists(tmp):
                    os.remove(tmp)
            except Exception:
                pass
            raise

    def _bootstrap_param(self):
        cache_dir = os.path.join(tempfile.gettempdir(), "ravengpt")
        os.makedirs(cache_dir, exist_ok=True)
        target = os.path.join(cache_dir, "raven.param")
        if os.path.isfile(target) and os.path.getsize(target) == MODEL_PARAM_SIZE:
            return target
        tmp = target + ".part"
        try:
            with self._urlopen(MODEL_PARAM_URL, timeout=20) as response:
                data = response.read()
            if len(data) != MODEL_PARAM_SIZE or hashlib.sha256(data).hexdigest() != MODEL_PARAM_SHA256:
                raise RuntimeError("Raven param checksum mismatch")
            with open(tmp, "wb") as out:
                out.write(data)
            os.replace(tmp, target)
            return target
        except Exception:
            try:
                if os.path.exists(tmp):
                    os.remove(tmp)
            except Exception:
                pass
            raise

    def _resolve_model_param(self, R):
        try:
            packaged = R.res(self.cfg["model_param"])
            if packaged and os.path.isfile(packaged) and os.path.getsize(packaged) > 1024:
                return packaged
        except Exception:
            pass
        return self._bootstrap_param()

    def _resolve_model_bin(self, R):
        try:
            packaged = R.res(self.cfg["model_bin"])
            if packaged and os.path.isfile(packaged) and os.path.getsize(packaged) > 1024:
                if self._sha256(packaged) == MODEL_SHA256:
                    return packaged
        except Exception:
            pass
        return self._bootstrap_bin()

    def load(self):
        try:
            from ascript.ios.system import R
            from ascript.ios.screen import yolov11

            self.yolo = yolov11
            bin_path = self._resolve_model_bin(R)
            self.loaded = bool(yolov11.load(
                R.res(self.cfg["model_param"]),
                bin_path,
                yaml_path=R.res(self.cfg["model_yaml"]),
                nc=1,
                use_gpu=False,
            ))
            if not self.loaded:
                self.last_error = "YOLO11 NCNN load returned false"
            else:
                self.last_error = None
            return self.loaded
        except Exception as e:
            self.loaded = False
            self.last_error = str(e)
            return False

    def detect(self, frame):
        if not self.loaded:
            return []
        start = time.perf_counter()
        out = self.yolo.detect(
            img=frame,
            target_size=int(self.cfg["target_size"]),
            threshold=float(self.cfg["confidence"]),
            nms_threshold=float(self.cfg["nms"]),
        ) or []
        self.last_ms = (time.perf_counter() - start) * 1000.0
        return out

    def detect_roi(self, frame, roi):
        """Run inference only inside roi=[x1,y1,x2,y2], then restore screen coordinates."""
        if not self.loaded:
            return []

        h, w = frame.shape[:2]
        x1, y1, x2, y2 = [int(v) for v in roi]
        x1 = max(0, min(w - 2, x1))
        y1 = max(0, min(h - 2, y1))
        x2 = max(x1 + 2, min(w, x2))
        y2 = max(y1 + 2, min(h, y2))
        # Native AScript/NCNN expects a contiguous CV buffer. NumPy ROI slices
        # are commonly non-contiguous views, which can produce empty inference.
        crop = frame[y1:y2, x1:x2].copy()
        if crop is None or crop.size == 0:
            return []

        start = time.perf_counter()
        out = self.yolo.detect(
            img=crop,
            target_size=int(self.cfg["target_size"]),
            threshold=float(self.cfg["confidence"]),
            nms_threshold=float(self.cfg["nms"]),
        ) or []
        self.last_ms = (time.perf_counter() - start) * 1000.0

        adjusted = []
        for item in out:
            d = dict(item)
            rect = d.get("rect")
            if rect and len(rect) == 4:
                d["rect"] = [
                    float(rect[0]) + x1,
                    float(rect[1]) + y1,
                    float(rect[2]) + x1,
                    float(rect[3]) + y1,
                ]
            adjusted.append(d)
        return adjusted

    def close(self):
        try:
            if self.yolo:
                self.yolo.free()
        except Exception:
            pass
