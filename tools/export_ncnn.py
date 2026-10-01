#!/usr/bin/env python3
from pathlib import Path
import argparse
import shutil
import yaml
from ultralytics import YOLO

p = argparse.ArgumentParser()
p.add_argument("model", help="Ultralytics YOLO .pt weights")
p.add_argument("--imgsz", type=int, default=416)
p.add_argument("--out", default="AScript/RavenGPT/res")
p.add_argument("--precision", type=int, choices=[16, 32], default=16)
a = p.parse_args()

src = Path(a.model)
if src.suffix.lower() != ".pt":
    raise SystemExit("NCNN export requires the original Ultralytics .pt weights.")

model = YOLO(str(src))
result = model.export(
    format="ncnn",
    imgsz=a.imgsz,
    half=(a.precision == 16),
    device="cpu",
)
folder = Path(result)
out = Path(a.out)
out.mkdir(parents=True, exist_ok=True)

param = folder / "model.ncnn.param"
bin_file = folder / "model.ncnn.bin"
if not param.exists() or not bin_file.exists():
    params = list(folder.glob("*.ncnn.param"))
    bins = list(folder.glob("*.ncnn.bin"))
    if len(params) != 1 or len(bins) != 1:
        raise SystemExit(f"Could not uniquely locate final NCNN files in {folder}")
    param, bin_file = params[0], bins[0]

shutil.copy2(param, out / "raven.param")
shutil.copy2(bin_file, out / "raven.bin")

names = model.names
if isinstance(names, dict):
    names = [names[i] for i in sorted(names)]
(out / "data.yaml").write_text(
    yaml.safe_dump({"nc": len(names), "names": names}, sort_keys=False),
    encoding="utf-8",
)

print(f"Wrote {out / 'raven.param'}")
print(f"Wrote {out / 'raven.bin'}")
print(f"Wrote {out / 'data.yaml'}")
