#!/usr/bin/env bash
# ============================================================================
#  Pre-install Arduino cores and libraries into /etc/skel so that every ASOS
#  user gets a working Arduino IDE 2 / arduino-cli setup offline:
#    ~/.arduino15        board index files (Arduino, ESP32, ESP8266, RP2040,
#                        STM32) + installed cores and their toolchains
#    ~/Arduino/libraries popular libraries
#
#  usage: fetch-arduino.sh <skel-dir>
#  env:   ARDUINO_CORES  space separated FQBN platforms   (default: arduino:avr)
#         ARDUINO_LIBS   ';' separated library names       (default: see below)
#  Needs arduino-cli on the build host (pacman -S arduino-cli).
# ============================================================================
set -euo pipefail

SKEL=${1:?usage: fetch-arduino.sh <skel-dir>}
CORES=${ARDUINO_CORES:-arduino:avr}
LIBS=${ARDUINO_LIBS:-Servo;Stepper;LiquidCrystal;LiquidCrystal I2C;DHT sensor library;OneWire;DallasTemperature;Adafruit NeoPixel;Adafruit SSD1306;IRremote;ArduinoJson;PubSubClient;Bounce2;AccelStepper;RTClib}
URLS=(
	https://espressif.github.io/arduino-esp32/package_esp32_index.json
	https://arduino.esp8266.com/stable/package_esp8266com_index.json
	https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json
	https://github.com/stm32duino/BoardManagerFiles/raw/main/package_stmicroelectronics_index.json
)

command -v arduino-cli >/dev/null || { echo "!! arduino-cli not found — skipping Arduino preinstall" >&2; exit 0; }

DATA="$SKEL/.arduino15"
USERDIR="$SKEL/Arduino"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$DATA" "$USERDIR/libraries"

{
	echo "board_manager:"
	echo "  additional_urls:"
	for u in "${URLS[@]}"; do echo "    - $u"; done
	echo "directories:"
	echo "  data: $DATA"
	echo "  downloads: $tmp/staging"
	echo "  user: $USERDIR"
	echo "updater:"
	echo "  enable_notification: false"
} >"$tmp/arduino-cli.yaml"
cli() { arduino-cli --config-file "$tmp/arduino-cli.yaml" "$@"; }

echo ":: Arduino: updating board/library indexes"
cli core update-index || echo "!! some board indexes could not be downloaded" >&2
cli lib update-index || true

for core in $CORES; do
	echo ":: Arduino: installing core $core"
	cli core install "$core" || echo "!! core $core failed — skipped" >&2
done

IFS=';' read -r -a libs <<<"$LIBS"
for lib in "${libs[@]}"; do
	[[ -n "$lib" ]] || continue
	echo ":: Arduino: installing library '$lib'"
	cli lib install "$lib" || echo "!! library '$lib' failed — skipped" >&2
done

# (per-user configs with the extra board URLs live in archiso/airootfs/etc/skel)
rm -rf "$DATA/staging" "$DATA/tmp" 2>/dev/null || true
echo ":: Arduino preinstalled into $SKEL ($(du -sh "$DATA" | cut -f1) cores, $(ls "$USERDIR/libraries" | wc -l) libraries)"
