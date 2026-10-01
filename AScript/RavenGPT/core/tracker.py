class LKBoxTracker:
    def __init__(self):
        self.cv2 = None
        self.np = None
        self.prev_gray = None
        self.points = None
        self.rect = None

    def _imports(self):
        if self.cv2 is None:
            import cv2
            import numpy as np
            self.cv2 = cv2
            self.np = np

    def reset(self):
        self.prev_gray = None
        self.points = None
        self.rect = None

    def init(self, frame_bgr, rect):
        self._imports()
        cv2, np = self.cv2, self.np
        x1, y1, x2, y2 = [int(v) for v in rect]
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        mask = np.zeros_like(gray)
        h, w = gray.shape[:2]
        x1, x2 = max(0, x1), min(w - 1, x2)
        y1, y2 = max(0, y1), min(h - 1, y2)
        if x2 <= x1 or y2 <= y1:
            self.reset(); return False
        mask[y1:y2, x1:x2] = 255
        pts = cv2.goodFeaturesToTrack(gray, mask=mask, maxCorners=40, qualityLevel=0.01, minDistance=5, blockSize=5)
        if pts is None or len(pts) < 4:
            self.reset(); return False
        self.prev_gray = gray
        self.points = pts
        self.rect = [float(x1), float(y1), float(x2), float(y2)]
        return True

    def update(self, frame_bgr):
        if self.prev_gray is None or self.points is None or self.rect is None:
            return None
        self._imports()
        cv2, np = self.cv2, self.np
        gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
        nxt, st, _ = cv2.calcOpticalFlowPyrLK(self.prev_gray, gray, self.points, None,
                                               winSize=(21,21), maxLevel=3,
                                               criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 20, 0.03))
        if nxt is None or st is None:
            self.reset(); return None
        good_new = nxt[st.reshape(-1) == 1]
        good_old = self.points[st.reshape(-1) == 1]
        if len(good_new) < 4:
            self.reset(); return None
        delta = good_new - good_old
        dx = float(np.median(delta[:,0]))
        dy = float(np.median(delta[:,1]))
        x1, y1, x2, y2 = self.rect
        self.rect = [x1 + dx, y1 + dy, x2 + dx, y2 + dy]
        self.prev_gray = gray
        self.points = good_new.reshape(-1,1,2)
        return list(self.rect)
