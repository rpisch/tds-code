#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

static const char *DEVICE_NAME = "ESP32-TDS-BLE";
static const char *SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
static const char *COUNTER_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

BLEServer *server = nullptr;
BLECharacteristic *counterCharacteristic = nullptr;

volatile bool deviceConnected = false;
bool previousDeviceConnected = false;

int32_t counterValue = 1;
unsigned long lastUpdateMs = 0;
const unsigned long updateIntervalMs = 1000;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    deviceConnected = true;
    Serial.println("BLE central connected.");
  }

  void onDisconnect(BLEServer *server) override {
    deviceConnected = false;
    Serial.println("BLE central disconnected.");
  }
};

class CounterCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();

    Serial.print("Received write from iPhone, byte count: ");
    Serial.println(value.length());
  }
};

void updateCounterCharacteristic(bool shouldNotify) {
  counterCharacteristic->setValue((uint8_t *)&counterValue, sizeof(counterValue));

  if (shouldNotify) {
    counterCharacteristic->notify();
    Serial.printf("Notified value: %ld\n", (long)counterValue);
  } else {
    Serial.printf("Updated value: %ld (waiting for BLE connection)\n", (long)counterValue);
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);

  BLEDevice::init(DEVICE_NAME);

  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *counterService = server->createService(SERVICE_UUID);

  counterCharacteristic = counterService->createCharacteristic(
    COUNTER_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
      BLECharacteristic::PROPERTY_WRITE |
      BLECharacteristic::PROPERTY_NOTIFY
  );

  counterCharacteristic->addDescriptor(new BLE2902());
  counterCharacteristic->setCallbacks(new CounterCallbacks());
  updateCounterCharacteristic(false);

  counterService->start();

  BLEAdvertising *advertising = server->getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();

  Serial.println("ESP32 BLE counter started.");
  Serial.printf("Advertising as %s\n", DEVICE_NAME);
  Serial.printf("Service UUID: %s\n", SERVICE_UUID);
  Serial.printf("Characteristic UUID: %s\n", COUNTER_CHARACTERISTIC_UUID);
}

void loop() {
  unsigned long nowMs = millis();

  if (nowMs - lastUpdateMs >= updateIntervalMs) {
    lastUpdateMs = nowMs;

    updateCounterCharacteristic(deviceConnected);

    counterValue++;
    if (counterValue > 100) {
      counterValue = 1;
    }
  }

  if (!deviceConnected && previousDeviceConnected) {
    delay(500);
    server->startAdvertising();
    Serial.println("Restarted BLE advertising.");
    previousDeviceConnected = deviceConnected;
  }

  if (deviceConnected && !previousDeviceConnected) {
    previousDeviceConnected = deviceConnected;
  }

  delay(10);
}
