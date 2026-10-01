import time

from config import CONFIG
from core.metrics import RateMeter, EWMA
from core.detector import RavenDetector
from core.selector import select_target, aim_point
from core.tracker import LKBoxTracker
from core.controller import AimController
from core.dashboard import Dashboard
from core.preflight import run_preflight

from ascript.ios import screen


def inference_roi(width, height, cfg):
    # Slightly larger than the selectable FOV so edge targets can enter smoothly.
    radius = min(width, height) * float(cfg["fov_radius_ratio"]) * float(cfg.get("roi_padding", 1.18))
    cx, cy = width * 0.5, height * 0.5
    return [
        max(0, int(cx - radius)),
        max(0, int(cy - radius)),
        min(width, int(cx + radius)),
        min(height, int(cy + radius)),
    ]


def main():
    print("[RavenGPT] boot")
    preflight = run_preflight(CONFIG)
    print("[RavenGPT] preflight:", preflight)
    width, height = screen.size()

    detector = RavenDetector(CONFIG)
    model_loaded = detector.load()
    if model_loaded:
        print("[RavenGPT] YOLO11 NCNN ready")
    else:
        print("[RavenGPT] MODEL NOT READY:", detector.last_error)

    controller = AimController(CONFIG, (width, height))
    controller.connect()
    tracker = LKBoxTracker()

    def on_ui_change(changes):
        if "mock_hid" in changes:
            controller.reconnect_async()
        if "fov_radius_ratio" in changes:
            tracker.reset()

    dashboard = Dashboard(CONFIG, on_change=on_ui_change)
    dashboard.open()

    loop_rate = RateMeter()
    capture_ms = EWMA()
    detect_ms = EWMA()
    last_detect = 0.0
    last_ui_push = 0.0
    last_model_retry = time.perf_counter()
    last_target = None
    detection_count = 0

    try:
        while True:
            t0 = time.perf_counter()
            frame = screen.capture(format=screen.FORMAT_CV_MAT)
            capture_ms.add((time.perf_counter() - t0) * 1000.0)
            if frame is None:
                time.sleep(0.01)
                continue

            now = time.perf_counter()

            # If the user imports weights while the script is open, retry periodically.
            if not model_loaded and (now - last_model_retry) >= 5.0:
                last_model_retry = now
                model_loaded = detector.load()

            target = None
            should_detect = model_loaded and (
                (now - last_detect) * 1000.0 >= float(CONFIG["detect_period_ms"]) or last_target is None
            )

            if should_detect:
                roi = inference_roi(width, height, CONFIG)
                detections = detector.detect_roi(frame, roi)
                detect_ms.add(detector.last_ms)
                detection_count = len(detections)
                target = select_target(detections, width, height, CONFIG)
                last_detect = now
                if target:
                    tracker.init(frame, target["rect"])
                    last_target = target
                else:
                    tracker.reset()
                    last_target = None
            elif model_loaded and last_target is not None:
                tracked = tracker.update(frame)
                if tracked:
                    target = dict(last_target)
                    target["rect"] = tracked
                    ax, ay = aim_point(
                        tracked,
                        CONFIG["aim_part"],
                        CONFIG["aim_head_ratio"],
                        CONFIG["aim_chest_ratio"],
                    )
                    target["aim_point"] = [ax, ay]
                    last_target = target
                else:
                    last_target = None

            if target and target.get("aim_point"):
                controller.submit_target(*target["aim_point"])

            fps = loop_rate.tick()
            if (now - last_ui_push) >= float(CONFIG.get("dashboard_period_ms", 200)) / 1000.0:
                last_ui_push = now
                dashboard.push({
                    "type": "metrics",
                    "loop_fps": round(fps, 1),
                    "capture_ms": round(capture_ms.value, 1),
                    "detect_ms": round(detect_ms.value, 1),
                    "detections": detection_count,
                    "target": (target or {}).get("tag") if target else None,
                    "confidence": round(float((target or {}).get("confidence", 0)), 3) if target else 0,
                    "hid": bool(controller.connected),
                    "mock_hid": bool(CONFIG["mock_hid"]),
                    "model_loaded": bool(model_loaded),
                    "error": controller.last_error or detector.last_error,
                })
    finally:
        controller.close()
        detector.close()


if __name__ == "__main__":
    main()
