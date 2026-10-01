#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then echo "Usage: $0 /path/to/AScript-iOS-ESP32-S3.bin [PORT]"; exit 2; fi
BIN="$1"; PORT="${2:-}"
python3 -m pip install --user --upgrade esptool
if [[ -z "$PORT" ]]; then
  PORT="$(python3 - <<'PY'
import glob
c=glob.glob('/dev/ttyACM*')+glob.glob('/dev/ttyUSB*')
print(c[0] if c else '')
PY
)"
fi
[[ -n "$PORT" ]] || { echo "No ESP32 serial port found."; exit 1; }
echo "Flashing $BIN to $PORT"
python3 -m esptool --chip esp32s3 --port "$PORT" erase_flash
python3 -m esptool --chip esp32s3 --port "$PORT" --baud 460800 write_flash 0x0 "$BIN"
echo "Flash complete. Pair the AS_iOS_* Bluetooth device on iPhone, then switch to ABS mode in AScript and re-pair once."
