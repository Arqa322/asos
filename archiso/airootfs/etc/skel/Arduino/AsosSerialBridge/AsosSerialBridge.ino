// ASOS example: Arduino <-> NanoPi (or PC) serial bridge
//
// Every second sends one JSON line:  {"uptime":12,"a0":512,"led":0}
// Accepts commands terminated by '\n':  LED ON | LED OFF | PING
//
// Flash:   asos-arduino upload AsosSerialBridge
// Talk:    asos-arduino monitor          (on the PC)
//          python3 /usr/share/asos/embedded/examples/serial-bridge.py /dev/ttyACM0   (on NanoPi/PC)

const unsigned long BAUD = 115200;
const unsigned long PERIOD_MS = 1000;

bool ledOn = false;
String rx;

void sendTelemetry() {
  Serial.print(F("{\"uptime\":"));
  Serial.print(millis() / 1000);
  Serial.print(F(",\"a0\":"));
  Serial.print(analogRead(A0));
  Serial.print(F(",\"led\":"));
  Serial.print(ledOn ? 1 : 0);
  Serial.println(F("}"));
}

void handleCommand(String cmd) {
  cmd.trim();
  cmd.toUpperCase();
  if (cmd == "LED ON") {
    ledOn = true;
  } else if (cmd == "LED OFF") {
    ledOn = false;
  } else if (cmd != "PING") {
    Serial.print(F("{\"error\":\"unknown command\",\"cmd\":\""));
    Serial.print(cmd);
    Serial.println(F("\"}"));
    return;
  }
  digitalWrite(LED_BUILTIN, ledOn ? HIGH : LOW);
  Serial.print(F("{\"ack\":\""));
  Serial.print(cmd);
  Serial.println(F("\"}"));
}

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(BAUD);
  rx.reserve(32);
}

void loop() {
  static unsigned long last = 0;
  if (millis() - last >= PERIOD_MS) {
    last = millis();
    sendTelemetry();
  }
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') {
      handleCommand(rx);
      rx = "";
    } else if (rx.length() < 31) {
      rx += c;
    }
  }
}
