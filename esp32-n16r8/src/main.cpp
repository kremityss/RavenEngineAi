#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <BLEHIDDevice.h>
#include <BLESecurity.h>
#include "usb/usb_host.h"
#include "hid_host.h"
#include "hid_usage_keyboard.h"
#include "hid_usage_mouse.h"

// Raven AScript transport service (kept compatible with the existing setup).
static const char* SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
static const char* CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
static constexpr int RGB_PIN = 48;

BLEServer* gServer = nullptr;
BLECharacteristic* gCmd = nullptr;
BLEHIDDevice* gHid = nullptr;
BLECharacteristic* gMouseIn = nullptr;
BLECharacteristic* gGamepadIn = nullptr;

volatile bool gConnected = false;
volatile bool gUsbKeyboard = false;
volatile bool gUsbMouse = false;
volatile bool gMapperEnabled = true;
volatile bool gAimToGamepad = true;

struct __attribute__((packed)) AbsMouseReport {
  uint8_t buttons;
  int16_t x;
  int16_t y;
};

struct __attribute__((packed)) GamepadReport {
  uint16_t buttons;
  int16_t lx;
  int16_t ly;
  int16_t rx;
  int16_t ry;
  uint8_t hat;
  uint8_t lt;
  uint8_t rt;
};

enum PadButton : uint16_t {
  PAD_A = 1u << 0,
  PAD_B = 1u << 1,
  PAD_X = 1u << 2,
  PAD_Y = 1u << 3,
  PAD_LB = 1u << 4,
  PAD_RB = 1u << 5,
  PAD_BACK = 1u << 6,
  PAD_START = 1u << 7,
  PAD_L3 = 1u << 8,
  PAD_R3 = 1u << 9,
};

static portMUX_TYPE gPadMux = portMUX_INITIALIZER_UNLOCKED;
static GamepadReport gPad = {0, 0, 0, 0, 0, 8, 0, 0};
static bool gPadDirty = true;
static uint32_t gLastPadNotifyUs = 0;
static uint32_t gLastMouseMs = 0;
static int gMouseGain = 1450;
static int gAssistGain = 190;
static int16_t gAssistRX = 0;
static int16_t gAssistRY = 0;
static uint32_t gAssistUntilMs = 0;

static QueueHandle_t gHidQueue = nullptr;

static void rgb(uint8_t r, uint8_t g, uint8_t b) {
  neopixelWrite(RGB_PIN, r, g, b);
}

static int16_t clampStick(long v) {
  if (v < -32767) return -32767;
  if (v > 32767) return 32767;
  return static_cast<int16_t>(v);
}

static int16_t clampCoord(long v) {
  if (v < 0) return 0;
  if (v > 32767) return 32767;
  return static_cast<int16_t>(v);
}

static void mouseReport(uint8_t buttons, long x, long y) {
  if (!gMouseIn || !gConnected) return;
  AbsMouseReport r{buttons, clampCoord(x), clampCoord(y)};
  gMouseIn->setValue(reinterpret_cast<uint8_t*>(&r), sizeof(r));
  gMouseIn->notify();
}

static void markPadDirty() {
  portENTER_CRITICAL(&gPadMux);
  gPadDirty = true;
  portEXIT_CRITICAL(&gPadMux);
}

static void neutralGamepad() {
  portENTER_CRITICAL(&gPadMux);
  gPad = {0, 0, 0, 0, 0, 8, 0, 0};
  gPadDirty = true;
  portEXIT_CRITICAL(&gPadMux);
  gAssistRX = 0;
  gAssistRY = 0;
}

static bool keyHeld(const hid_keyboard_input_report_boot_t* report, uint8_t key) {
  for (int i = 0; i < HID_KEYBOARD_KEY_MAX; ++i) {
    if (report->key[i] == key) return true;
  }
  return false;
}

static void applyKeyboard(const uint8_t* data, size_t len) {
  if (len < sizeof(hid_keyboard_input_report_boot_t)) return;
  const auto* kb = reinterpret_cast<const hid_keyboard_input_report_boot_t*>(data);

  int x = 0;
  int y = 0;
  if (keyHeld(kb, HID_KEY_A)) x -= 32767;
  if (keyHeld(kb, HID_KEY_D)) x += 32767;
  if (keyHeld(kb, HID_KEY_W)) y -= 32767;
  if (keyHeld(kb, HID_KEY_S)) y += 32767;
  if (x && y) {
    x = x > 0 ? 23170 : -23170;
    y = y > 0 ? 23170 : -23170;
  }

  uint16_t buttons = 0;
  if (keyHeld(kb, HID_KEY_SPACE)) buttons |= PAD_A;
  if (keyHeld(kb, HID_KEY_C)) buttons |= PAD_B;
  if (keyHeld(kb, HID_KEY_R)) buttons |= PAD_X;
  if (keyHeld(kb, HID_KEY_E)) buttons |= PAD_Y;
  if (keyHeld(kb, HID_KEY_Q)) buttons |= PAD_LB;
  if (keyHeld(kb, HID_KEY_F)) buttons |= PAD_RB;
  if (keyHeld(kb, HID_KEY_TAB)) buttons |= PAD_BACK;
  if (keyHeld(kb, HID_KEY_ESC)) buttons |= PAD_START;
  if (kb->modifier.val & (HID_LEFT_SHIFT | HID_RIGHT_SHIFT)) buttons |= PAD_L3;
  if (keyHeld(kb, HID_KEY_V)) buttons |= PAD_R3;

  uint8_t hat = 8;
  const bool up = keyHeld(kb, HID_KEY_UP);
  const bool down = keyHeld(kb, HID_KEY_DOWN);
  const bool left = keyHeld(kb, HID_KEY_LEFT);
  const bool right = keyHeld(kb, HID_KEY_RIGHT);
  if (up && right) hat = 1;
  else if (right && down) hat = 3;
  else if (down && left) hat = 5;
  else if (left && up) hat = 7;
  else if (up) hat = 0;
  else if (right) hat = 2;
  else if (down) hat = 4;
  else if (left) hat = 6;

  portENTER_CRITICAL(&gPadMux);
  gPad.lx = static_cast<int16_t>(x);
  gPad.ly = static_cast<int16_t>(y);
  const uint16_t mask = PAD_A | PAD_B | PAD_X | PAD_Y | PAD_LB | PAD_RB |
                        PAD_BACK | PAD_START | PAD_L3 | PAD_R3;
  gPad.buttons = (gPad.buttons & ~mask) | buttons;
  gPad.hat = hat;
  gPadDirty = true;
  portEXIT_CRITICAL(&gPadMux);
}

static void applyMouse(const uint8_t* data, size_t len) {
  if (len < sizeof(hid_mouse_input_report_boot_t)) return;
  const auto* m = reinterpret_cast<const hid_mouse_input_report_boot_t*>(data);

  const int16_t rx = clampStick(static_cast<long>(m->x_displacement) * gMouseGain);
  const int16_t ry = clampStick(static_cast<long>(m->y_displacement) * gMouseGain);

  portENTER_CRITICAL(&gPadMux);
  gPad.rx = rx;
  gPad.ry = ry;
  gPad.rt = m->buttons.button1 ? 255 : 0;
  gPad.lt = m->buttons.button2 ? 255 : 0;
  if (m->buttons.button3) gPad.buttons |= PAD_R3;
  else gPad.buttons &= ~PAD_R3;
  gPadDirty = true;
  portEXIT_CRITICAL(&gPadMux);
  gLastMouseMs = millis();
}

static void serviceGamepad() {
  if (!gMapperEnabled || !gGamepadIn || !gConnected) return;

  const uint32_t nowMs = millis();
  if ((uint32_t)(nowMs - gLastMouseMs) > 14) {
    portENTER_CRITICAL(&gPadMux);
    if (gPad.rx != 0 || gPad.ry != 0) {
      gPad.rx = 0;
      gPad.ry = 0;
      gPadDirty = true;
    }
    portEXIT_CRITICAL(&gPadMux);
  }

  int16_t assistX = 0;
  int16_t assistY = 0;
  if ((int32_t)(gAssistUntilMs - nowMs) > 0) {
    assistX = gAssistRX;
    assistY = gAssistRY;
  } else if (gAssistRX || gAssistRY) {
    gAssistRX = 0;
    gAssistRY = 0;
    markPadDirty();
  }

  const uint32_t nowUs = micros();
  if ((uint32_t)(nowUs - gLastPadNotifyUs) < 4500) return;

  GamepadReport out;
  bool dirty = false;
  portENTER_CRITICAL(&gPadMux);
  dirty = gPadDirty;
  out = gPad;
  gPadDirty = false;
  portEXIT_CRITICAL(&gPadMux);

  if (!dirty && !assistX && !assistY) return;
  out.rx = clampStick(static_cast<long>(out.rx) + assistX);
  out.ry = clampStick(static_cast<long>(out.ry) + assistY);
  gGamepadIn->setValue(reinterpret_cast<uint8_t*>(&out), sizeof(out));
  gGamepadIn->notify();
  gLastPadNotifyUs = nowUs;
}

static void sendReply(const String& s) {
  if (!gCmd) return;
  gCmd->setValue(s.c_str());
  if (gConnected) gCmd->notify();
}

static int parseNums(const String& s, long* out, int maxn) {
  int n = 0;
  String cur = "";
  for (size_t i = 0; i <= s.length() && n < maxn; ++i) {
    const char c = i < s.length() ? s[i] : '&';
    if ((c >= '0' && c <= '9') || c == '-') cur += c;
    else if (cur.length()) {
      out[n++] = cur.toInt();
      cur = "";
    }
  }
  return n;
}

static void handleAimSlide(long x0, long y0, long x1, long y1, long dur) {
  if (!gAimToGamepad || !gMapperEnabled) {
    const int frames = max(2L, min(20L, dur / 8));
    mouseReport(1, x0, y0);
    for (int i = 1; i <= frames; ++i) {
      const float t = static_cast<float>(i) / static_cast<float>(frames);
      mouseReport(1,
                  x0 + static_cast<long>((x1 - x0) * t),
                  y0 + static_cast<long>((y1 - y0) * t));
      delay(max(1L, dur / frames));
    }
    mouseReport(0, x1, y1);
    return;
  }

  gAssistRX = clampStick((x1 - x0) * gAssistGain);
  gAssistRY = clampStick((y1 - y0) * gAssistGain);
  gAssistUntilMs = millis() + static_cast<uint32_t>(dur);
  markPadDirty();
}

static void handleCommand(String raw) {
  raw.trim();
  if (!raw.length()) return;
  rgb(0, 40, 255);
  String low = raw;
  low.toLowerCase();

  if (low == "state" || low == "mapstate") {
    String j = "{\"mode\":\"abs\",\"connected\":";
    j += gConnected ? "true" : "false";
    j += ",\"mapper\":";
    j += gMapperEnabled ? "true" : "false";
    j += ",\"aim_output\":\"";
    j += gAimToGamepad ? "gamepad" : "abs";
    j += "\",\"usb_keyboard\":";
    j += gUsbKeyboard ? "true" : "false";
    j += ",\"usb_mouse\":";
    j += gUsbMouse ? "true" : "false";
    j += ",\"mouse_gain\":";
    j += String(gMouseGain);
    j += "}";
    sendReply(j);
  } else if (low == "getmode") {
    sendReply("abs");
  } else if (low.startsWith("setmode")) {
    sendReply("abs");
  } else if (low == "mapper on") {
    gMapperEnabled = true;
    markPadDirty();
    sendReply("ok");
  } else if (low == "mapper off") {
    gMapperEnabled = false;
    neutralGamepad();
    sendReply("ok");
  } else if (low == "aimout pad" || low == "aimout gamepad") {
    gAimToGamepad = true;
    sendReply("ok");
  } else if (low == "aimout abs") {
    gAimToGamepad = false;
    sendReply("ok");
  } else if (low.startsWith("mapsens")) {
    long v[2] = {};
    const int n = parseNums(raw, v, 2);
    if (n >= 1) {
      gMouseGain = max(100L, min(5000L, v[n - 1]));
      sendReply("ok");
    } else sendReply("err");
  } else if (low.startsWith("assistgain")) {
    long v[2] = {};
    const int n = parseNums(raw, v, 2);
    if (n >= 1) {
      gAssistGain = max(20L, min(500L, v[n - 1]));
      sendReply("ok");
    } else sendReply("err");
  } else if (low.startsWith("mouseclr")) {
    mouseReport(0, 0, 0);
    sendReply("ok");
  } else if (low.startsWith("moveto")) {
    long v[4] = {};
    const int n = parseNums(raw, v, 4);
    if (n >= 2) {
      mouseReport(0, v[n - 2], v[n - 1]);
      sendReply("ok");
    } else sendReply("err");
  } else if (low.startsWith("slide") || low.indexOf("&") >= 0) {
    long v[12] = {};
    const int n = parseNums(raw, v, 12);
    if (n >= 4) {
      long dur = n >= 5 ? v[4] : 60;
      dur = max(5L, min(500L, dur));
      handleAimSlide(v[0], v[1], v[2], v[3], dur);
      sendReply("ok");
    } else sendReply("err");
  } else {
    sendReply("unknown");
  }

  if (gConnected) rgb(0, 0, 255);
  else rgb(0, 0, 80);
}

class CmdCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    std::string v = c->getValue();
    handleCommand(String(v.c_str()));
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    gConnected = true;
    rgb(0, 0, 255);
    markPadDirty();
  }

  void onDisconnect(BLEServer* s) override {
    gConnected = false;
    rgb(0, 0, 80);
    delay(100);
    s->getAdvertising()->start();
  }
};

typedef struct {
  hid_host_device_handle_t handle;
  hid_host_driver_event_t event;
  void* arg;
} HidEvt;

static void hidInterfaceCallback(hid_host_device_handle_t handle,
                                 const hid_host_interface_event_t event,
                                 void*) {
  hid_host_dev_params_t p = {};
  if (hid_host_device_get_params(handle, &p) != ESP_OK) return;

  if (event == HID_HOST_INTERFACE_EVENT_INPUT_REPORT) {
    uint8_t data[64] = {};
    size_t len = 0;
    if (hid_host_device_get_raw_input_report_data(
          handle, data, sizeof(data), &len) != ESP_OK) return;

    if (p.sub_class == HID_SUBCLASS_BOOT_INTERFACE &&
        p.proto == HID_PROTOCOL_KEYBOARD) {
      gUsbKeyboard = true;
      if (gMapperEnabled) applyKeyboard(data, len);
    } else if (p.sub_class == HID_SUBCLASS_BOOT_INTERFACE &&
               p.proto == HID_PROTOCOL_MOUSE) {
      gUsbMouse = true;
      if (gMapperEnabled) applyMouse(data, len);
    }
  } else if (event == HID_HOST_INTERFACE_EVENT_DISCONNECTED) {
    if (p.proto == HID_PROTOCOL_KEYBOARD) gUsbKeyboard = false;
    if (p.proto == HID_PROTOCOL_MOUSE) gUsbMouse = false;
    hid_host_device_close(handle);
    neutralGamepad();
  }
}

static void openHid(hid_host_device_handle_t handle) {
  hid_host_dev_params_t p = {};
  if (hid_host_device_get_params(handle, &p) != ESP_OK) return;

  hid_host_device_config_t cfg = {};
  cfg.callback = hidInterfaceCallback;
  cfg.callback_arg = nullptr;
  if (hid_host_device_open(handle, &cfg) != ESP_OK) return;

  if (p.sub_class == HID_SUBCLASS_BOOT_INTERFACE) {
    hid_class_request_set_protocol(handle, HID_REPORT_PROTOCOL_BOOT);
    if (p.proto == HID_PROTOCOL_KEYBOARD) {
      hid_class_request_set_idle(handle, 0, 0);
    }
  }
  hid_host_device_start(handle);
}

static void hidDriverCallback(hid_host_device_handle_t handle,
                              const hid_host_driver_event_t event,
                              void* arg) {
  if (!gHidQueue) return;
  HidEvt e{handle, event, arg};
  xQueueSend(gHidQueue, &e, 0);
}

static void hidTask(void*) {
  gHidQueue = xQueueCreate(12, sizeof(HidEvt));
  HidEvt e = {};
  while (true) {
    if (xQueueReceive(gHidQueue, &e, pdMS_TO_TICKS(50))) {
      if (e.event == HID_HOST_DRIVER_EVENT_CONNECTED) openHid(e.handle);
    }
  }
}

static void usbTask(void* notifyTask) {
  usb_host_config_t cfg = {};
  cfg.skip_phy_setup = false;
  cfg.intr_flags = ESP_INTR_FLAG_LEVEL1;
  if (usb_host_install(&cfg) != ESP_OK) {
    vTaskDelete(nullptr);
    return;
  }

  xTaskNotifyGive(static_cast<TaskHandle_t>(notifyTask));
  while (true) {
    uint32_t flags = 0;
    if (usb_host_lib_handle_events(portMAX_DELAY, &flags) == ESP_OK) {
      if (flags & USB_HOST_LIB_EVENT_FLAGS_NO_CLIENTS) {
        usb_host_device_free_all();
      }
    }
  }
}

static bool startUsbHost() {
  TaskHandle_t current = xTaskGetCurrentTaskHandle();
  if (xTaskCreatePinnedToCore(
        usbTask, "raven_usb", 4096, current, 4, nullptr, 0) != pdTRUE) {
    return false;
  }

  if (ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(1500)) == 0) return false;

  hid_host_driver_config_t cfg = {};
  cfg.create_background_task = true;
  cfg.task_priority = 5;
  cfg.stack_size = 4096;
  cfg.core_id = 0;
  cfg.callback = hidDriverCallback;
  cfg.callback_arg = nullptr;
  if (hid_host_install(&cfg) != ESP_OK) return false;

  return xTaskCreatePinnedToCore(
           hidTask, "raven_hid", 4096, nullptr, 3, nullptr, 0) == pdTRUE;
}

void setup() {
  Serial.begin(115200);
  delay(250);
  rgb(255, 0, 0);
  delay(90);
  rgb(0, 255, 0);
  delay(90);
  rgb(0, 0, 255);
  delay(90);
  rgb(0, 0, 40);

  Serial.printf("Flash=%u bytes PSRAM=%u bytes psramFound=%s\n",
                ESP.getFlashChipSize(),
                ESP.getPsramSize(),
                psramFound() ? "yes" : "no");

  const uint64_t mac = ESP.getEfuseMac();
  char name[32];
  snprintf(name, sizeof(name), "Raven_KBM_%04X%08X",
           static_cast<uint16_t>(mac >> 32),
           static_cast<uint32_t>(mac));

  BLEDevice::init(name);
  BLEDevice::setEncryptionLevel(ESP_BLE_SEC_ENCRYPT);
  gServer = BLEDevice::createServer();
  gServer->setCallbacks(new ServerCallbacks());

  gHid = new BLEHIDDevice(gServer);
  gMouseIn = gHid->inputReport(1);
  gGamepadIn = gHid->inputReport(2);
  gHid->manufacturer()->setValue("RavenGPT");
  gHid->pnp(0x02, 0x303A, 0x1001, 0x0101);
  gHid->hidInfo(0x00, 0x01);

  static const uint8_t reportMap[] = {
    // Report 1: existing absolute mouse used by Raven/AScript.
    0x05,0x01,0x09,0x02,0xA1,0x01,0x85,0x01,0x09,0x01,0xA1,0x00,
    0x05,0x09,0x19,0x01,0x29,0x03,0x15,0x00,0x25,0x01,0x95,0x03,0x75,0x01,0x81,0x02,
    0x95,0x01,0x75,0x05,0x81,0x03,0x05,0x01,0x09,0x30,0x09,0x31,
    0x16,0x00,0x00,0x26,0xFF,0x7F,0x75,0x10,0x95,0x02,0x81,0x02,0xC0,0xC0,

    // Report 2: standard BLE gamepad for the USB keyboard/mouse mapper.
    0x05,0x01,0x09,0x05,0xA1,0x01,0x85,0x02,
    0x05,0x09,0x19,0x01,0x29,0x10,0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x10,0x81,0x02,
    0x05,0x01,0x09,0x30,0x09,0x31,0x09,0x33,0x09,0x34,
    0x16,0x01,0x80,0x26,0xFF,0x7F,0x75,0x10,0x95,0x04,0x81,0x02,
    0x09,0x39,0x15,0x00,0x25,0x07,0x35,0x00,0x46,0x3B,0x01,0x65,0x14,
    0x75,0x04,0x95,0x01,0x81,0x42,0x65,0x00,0x75,0x04,0x95,0x01,0x81,0x03,
    0x05,0x02,0x09,0xC5,0x09,0xC4,0x15,0x00,0x26,0xFF,0x00,0x75,0x08,0x95,0x02,0x81,0x02,
    0xC0
  };

  gHid->reportMap(const_cast<uint8_t*>(reportMap), sizeof(reportMap));
  gHid->startServices();

  BLEService* svc = gServer->createService(SERVICE_UUID);
  gCmd = svc->createCharacteristic(
    CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  gCmd->addDescriptor(new BLE2902());
  gCmd->setCallbacks(new CmdCallbacks());
  gCmd->setValue("ready");
  svc->start();

  BLESecurity* sec = new BLESecurity();
  sec->setAuthenticationMode(ESP_LE_AUTH_BOND);
  sec->setCapability(ESP_IO_CAP_NONE);

  BLEAdvertising* adv = gServer->getAdvertising();
  adv->setAppearance(HID_GAMEPAD);
  adv->addServiceUUID(gHid->hidService()->getUUID());
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->start();

  const bool usbOk = startUsbHost();
  rgb(0, 0, 80);
  Serial.printf("READY Raven KBM + AScript ABS | USB host=%s\n",
                usbOk ? "yes" : "no");
}

void loop() {
  serviceGamepad();
  delay(1);
}
