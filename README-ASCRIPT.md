# RavenGPT AScript + ESP32-S3 build

This folder is the software-side deployment path for AScript iOS + YOLO11n + ESP32-S3 HID.

## Before hardware arrives
1. Export the original YOLO11 `.pt` file to NCNN with `python tools/export_ncnn.py best.pt --imgsz 416` or the GitHub Actions workflow.
2. Put `raven.param`, `raven.bin`, and `data.yaml` inside `AScript/RavenGPT/res/`.
3. Import `AScript/RavenGPT` into AScript and run `main.py` with `mock_hid=true`.
4. Confirm live capture, inference, target selection, tracker, and dashboard metrics.

## When the ESP32-S3 arrives
1. Download AScript's current iOS Bluetooth firmware package and choose the ESP32-S3 image.
2. Pass the board into Chromebook Linux, then run `tools/flash_esp32_linux.sh <firmware.bin>`.
3. Pair the `AS_iOS_*` Bluetooth device on the iPhone.
4. In AScript, switch the firmware to ABS mode. iOS caches the HID descriptor, so after that one mode switch you must forget the old REL device and pair the new ABS device once.
5. Enable AssistiveTouch. Set `mock_hid=false` in RavenGPT, enable Aim Assist, and tune sensitivity/strength for the target game.

## Architecture
- YOLO detection runs on a cropped FOV region instead of the whole screen.
- Lucas-Kanade optical flow tracks the current box between slower inference passes.
- Target selection is FOV/confidence weighted with an optional self-exclusion zone.
- The controller sends short ABS HID swipes through AScript's supported `BleDevice` API.
- The WebWindow dashboard controls aim, FOV, confidence, strength, smoothing, and hardware simulation.

## Important deployment fact
AScript's current iOS ESP32 path is Bluetooth HID. The OTG hub is useful for Chromebook flashing/debugging; it is not the live iPhone control link.
