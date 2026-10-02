# Raven ESP32-S3 KBM Mapper

This branch is for the AScript + ESP32-S3 + Linux stack. It does not require the native Raven iOS app.

## Architecture

- iPhone: AScript captures/controls the game session.
- ESP32-S3: exposes one composite BLE HID device and keeps the Raven AScript command service.
- Linux/Chromebook: runs the model and control panel.
- USB keyboard + mouse: plug into the ESP32-S3 native USB-OTG port through a simple USB hub.

The firmware keeps two HID input reports:

1. Report 1 — Raven absolute mouse used by the existing AScript transport.
2. Report 2 — gamepad used by the keyboard/mouse controller mapper.

## Default mapper

| Input | Gamepad |
| --- | --- |
| W/A/S/D | Left stick |
| Mouse movement | Right stick |
| Left mouse | RT |
| Right mouse | LT |
| Space | A |
| C | B |
| R | X |
| E | Y |
| Q | LB |
| F | RB |
| Shift | L3 |
| V / middle mouse | R3 |
| Tab | Back/View |
| Esc | Start/Menu |
| Arrow keys | D-pad |

Diagonal WASD is normalized instead of sending full X+Y magnitude.

## Raven command service additions

The existing service/characteristic UUIDs remain unchanged.

- `mapstate` — mapper, USB keyboard/mouse, aim-output, and sensitivity state.
- `mapper on` / `mapper off` — toggle gamepad mapping.
- `mapsens <100..5000>` — mouse-to-right-stick gain.
- `assistgain <20..500>` — AScript aim contribution gain.
- `aimout pad` — mix AScript aim movement into right-stick output.
- `aimout abs` — use the old absolute-mouse AScript path.

`getmode` remains `abs` for compatibility with the current AScript bridge.

## Hardware

The USB host layer uses the ESP32-S3 native USB-OTG controller. Use a simple USB-only hub for keyboard + mouse. Complex hubs with displays, Ethernet, or large RGB power loads are more likely to exceed the S3 host/power budget.

## Build

```bash
cd esp32-n16r8
pio run
```

GitHub Actions also builds the firmware and uploads the flash files as `Raven-KBM-ESP32-S3`.
