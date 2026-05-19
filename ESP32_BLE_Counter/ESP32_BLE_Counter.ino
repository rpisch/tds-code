#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

static const char *DEVICE_NAME = "ESP32-TDS-BLE";
static const char *SERVICE_UUID = "7B6A0001-9F7A-4D2B-9A5B-0B1F2A4C1000";
static const char *COUNTER_CHARACTERISTIC_UUID = "7B6A0002-9F7A-4D2B-9A5B-0B1F2A4C1000";

BLEServer *server = nullptr;
BLECharacteristic *counterCharacteristic = nullptr;

volatile bool deviceConnected = false;
bool previousDeviceConnected = false;

uint8_t counterValue = 1;
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

void setup() {
  Serial.begin(115200);
  delay(500);

  BLEDevice::init(DEVICE_NAME);

  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *counterService = server->createService(SERVICE_UUID);

  counterCharacteristic = counterService->createCharacteristic(
    COUNTER_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );

  counterCharacteristic->addDescriptor(new BLE2902());
  counterCharacteristic->setValue(&counterValue, sizeof(counterValue));

  counterService->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();

  BLEAdvertisementData advertisementData;
  advertisementData.setFlags(0x06);
  advertisementData.setCompleteServices(BLEUUID(SERVICE_UUID));
  advertising->setAdvertisementData(advertisementData);

  BLEAdvertisementData scanResponseData;
  scanResponseData.setName(DEVICE_NAME);
  advertising->setScanResponseData(scanResponseData);

  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);

  BLEDevice::startAdvertising();

  Serial.println("ESP32 BLE counter started.");
  Serial.printf("Advertising as %s\n", DEVICE_NAME);
  Serial.printf("Service UUID: %s\n", SERVICE_UUID);
  Serial.printf("Characteristic UUID: %s\n", COUNTER_CHARACTERISTIC_UUID);
}

void loop() {
  unsigned long nowMs = millis();

  if (nowMs - lastUpdateMs >= updateIntervalMs) {
    lastUpdateMs = nowMs;

    counterCharacteristic->setValue(&counterValue, sizeof(counterValue));

    if (deviceConnected) {
      counterCharacteristic->notify();
      Serial.printf("Notified value: %u\n", counterValue);
    } else {
      Serial.printf("Updated value: %u (waiting for BLE connection)\n", counterValue);
    }

    counterValue++;
    if (counterValue > 100) {
      counterValue = 1;
    }
  }

  if (!deviceConnected && previousDeviceConnected) {
    delay(500);
    BLEDevice::startAdvertising();
    Serial.println("Restarted BLE advertising.");
    previousDeviceConnected = deviceConnected;
  }

  if (deviceConnected && !previousDeviceConnected) {
    previousDeviceConnected = deviceConnected;
  }

  delay(10);
}
