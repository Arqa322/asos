#!/usr/bin/env python3
"""Huilo example: talk to the HuiloSerialBridge Arduino sketch from a NanoPi (or the PC).

    python3 serial-bridge.py [/dev/ttyACM0] [115200]

Prints the JSON telemetry the Arduino sends every second; type "on"/"off" + Enter
to switch the Arduino LED. Needs pyserial (NanoPi: sudo apt install python3-serial).
"""
import json
import sys
import threading

import serial  # pyserial

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyACM0"
baud = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
ser = serial.Serial(port, baud, timeout=1)
print(f"connected to {port} @ {baud}; type on/off, Ctrl+C to quit")


def reader():
    while True:
        line = ser.readline().decode(errors="replace").strip()
        if not line:
            continue
        try:
            data = json.loads(line)
        except ValueError:
            print("raw:", line)
            continue
        print("arduino:", data)


threading.Thread(target=reader, daemon=True).start()
try:
    for cmd in sys.stdin:
        cmd = cmd.strip().lower()
        if cmd in ("on", "off"):
            ser.write(f"LED {cmd.upper()}\n".encode())
except KeyboardInterrupt:
    pass
