#!/usr/bin/env python3
from pathlib import Path
import argparse, shutil, yaml
from ultralytics import YOLO

p = argparse.ArgumentParser()
p.add_argument("model", help="Ultralytics YOLO .pt weights")
p.add_argument("--imgsz", type=int, default=416)
p.add_argument("--out", default="AScript/RavenGPT/res")
p.add_argument("--quantize", type=int, choices=[16,32], default=16)
a = p.parse_args()

src = Path(a.model)
if src.suffix.lower() != ".pt":
    raise SystemExit("NCNN export requires the original Ultralytics .pt weights. If you only have ONNX, recover the matching .pt training weights first.")
model = YOLO(str(src))
result = model.export(format="ncnn", imgsz=a.imgsz, quantize=a.quantize, device="cpu")
folder = Path(result)
out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
param = next(folder.glob("*.param"))
bin_file = next(folder.glob("*.bin"))
shutil.copy2(param, out / "raven.param")
shutil.copy2(bin_file, out / "raven.bin")
names = model.names
if isinstance(names, dict): names = [names[i] for i in sorted(names)]
(out / "data.yaml").write_text(yaml.safe_dump({"names": names, "nc": len(names)}, sort_keys=False), encoding="utf-8")
print(f"Wrote {out/'raven.param'}")
print(f"Wrote {out/'raven.bin'}")
print(f"Wrote {out/'data.yaml'}")
