import math


def rect_center(rect):
    x1, y1, x2, y2 = rect
    return (x1 + x2) * 0.5, (y1 + y2) * 0.5


def aim_point(rect, part, head_ratio=0.20, chest_ratio=0.42):
    x1, y1, x2, y2 = rect
    x = (x1 + x2) * 0.5
    h = max(1.0, y2 - y1)
    ratio = head_ratio if part == "head" else chest_ratio
    return x, y1 + h * ratio


def in_self_exclusion(rect, width, height, normalized_box):
    if not normalized_box:
        return False
    cx, cy = rect_center(rect)
    x1, y1, x2, y2 = normalized_box
    return x1 * width <= cx <= x2 * width and y1 * height <= cy <= y2 * height


def select_target(detections, width, height, cfg):
    cx, cy = width * 0.5, height * 0.5
    radius = min(width, height) * float(cfg["fov_radius_ratio"])
    wanted = set(str(x).lower() for x in cfg.get("target_tags", []) if str(x).strip())
    best = None
    best_score = 1e18

    for d in detections:
        rect = d.get("rect")
        if not rect or len(rect) != 4:
            continue
        conf = float(d.get("confidence", 0.0))
        if conf < float(cfg["confidence"]):
            continue
        tag = str(d.get("tag") or "").lower()
        if wanted and tag not in wanted:
            continue
        if cfg.get("self_filter") and in_self_exclusion(rect, width, height, cfg.get("self_exclusion")):
            continue

        ax, ay = aim_point(rect, cfg["aim_part"], cfg["aim_head_ratio"], cfg["aim_chest_ratio"])
        distance = math.hypot(ax - cx, ay - cy)
        if distance > radius:
            continue

        x1, y1, x2, y2 = rect
        area = max(1.0, (x2 - x1) * (y2 - y1))
        size_bonus = min(area / max(width * height, 1), 0.25)
        score = distance / max(radius, 1) - conf * 0.22 - size_bonus * 0.15
        if score < best_score:
            best_score = score
            best = dict(d)
            best["aim_point"] = [ax, ay]
            best["distance"] = distance
            best["score"] = score
    return best
