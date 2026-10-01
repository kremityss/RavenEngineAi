import time


class RavenDetector:
    def __init__(self, cfg):
        self.cfg = cfg
        self.loaded = False
        self.yolo = None
        self.last_ms = 0.0
        self.last_error = None

    def load(self):
        try:
            from ascript.ios.system import R
            from ascript.ios.screen import yolov11
            self.yolo = yolov11
            self.loaded = bool(yolov11.load(
                R.res(self.cfg["model_param"]),
                R.res(self.cfg["model_bin"]),
                yaml_path=R.res(self.cfg["model_yaml"]),
                use_gpu=True,
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
        crop = frame[y1:y2, x1:x2]
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
