import time

class RateMeter:
    def __init__(self, alpha=0.18):
        self.alpha = alpha
        self.last = None
        self.fps = 0.0

    def tick(self):
        now = time.perf_counter()
        if self.last is not None:
            dt = max(now - self.last, 1e-6)
            current = 1.0 / dt
            self.fps = current if self.fps == 0 else self.fps * (1 - self.alpha) + current * self.alpha
        self.last = now
        return self.fps

class EWMA:
    def __init__(self, alpha=0.20):
        self.alpha = alpha
        self.value = 0.0
        self.ready = False

    def add(self, value):
        value = float(value)
        if not self.ready:
            self.value = value
            self.ready = True
        else:
            self.value = self.value * (1 - self.alpha) + value * self.alpha
        return self.value
