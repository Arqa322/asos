# ASOS: примеры для Arduino и NanoPi

## 1. Мост Arduino ↔ NanoPi (UART / USB)

Скетч: `~/Arduino/AsosSerialBridge` — раз в секунду шлёт JSON с показаниями `A0`,
принимает команды `LED ON`, `LED OFF`, `PING`.

```bash
asos-arduino upload AsosSerialBridge       # плата и порт определяются автоматически
asos-arduino monitor                       # проверить на ПК
```

Подключение к NanoPi:

* **USB-кабель** (проще всего): Arduino появится на плате как `/dev/ttyACM0` или `/dev/ttyUSB0`.
* **Пины UART**: GND–GND, TX Arduino → RX NanoPi, RX Arduino ← TX NanoPi.
  ⚠ Uno/Nano работают на **5 В**, NanoPi — на **3.3 В**: на линию TX Arduino → RX NanoPi
  поставьте делитель (например 1 кОм + 2 кОм) или преобразователь уровней.

На NanoPi:

```bash
sudo apt install python3-serial            # FriendlyCore / Debian / Ubuntu
python3 serial-bridge.py /dev/ttyACM0      # скопируйте файл: scp serial-bridge.py pi@nanopi.local:
```

## 2. Кросс-компиляция для NanoPi

```bash
cp -r /usr/share/asos/embedded/examples/nanopi-hello ~/ && cd ~/nanopi-hello
./deploy.sh                    # собрать aarch64 и запустить в qemu на ПК
./deploy.sh pi@nanopi.local    # + скопировать на плату и запустить там
```

По умолчанию пример линкуется статически: glibc кросс-компилятора Arch новее, чем в
образах Ubuntu/Debian на платах. Для динамической линковки с библиотеками платы:

```bash
asos-nanopi sysroot pi@nanopi.local        # скопирует /lib, /usr/lib, /usr/include
ASOS_SYSROOT=~/sysroots/nanopi ./deploy.sh pi@nanopi.local
```

## 3. Полезные команды

| Задача | Команда |
|---|---|
| диагностика портов и прав | `asos-arduino doctor` |
| ядра ESP32 / RP2040 / STM32 | `asos-arduino setup esp32 rp2040 stm32` |
| PlatformIO | `pio project init -b uno && pio run -t upload` |
| MicroPython на ESP32 | `esptool erase-flash && esptool write-flash 0x1000 firmware.bin` (S3/C3: адрес `0x0`), затем `mpremote` |
| найти NanoPi в сети | `asos-nanopi find` |
| UART-консоль NanoPi | `asos-nanopi console` (Rockchip 1500000, Allwinner 115200) |
| записать образ на microSD | `asos-nanopi flash FriendlyCore-*.img.gz` |
| интернет плате по кабелю | `asos-nanopi share enp3s0` |
| chroot в образ платы | `asos-nanopi chroot rootfs.img` |
| логический анализатор | `pulseview` (fx2lafw / клоны Saleae) |
| SPI-флеш (CH341A) | `flashrom -p ch341a_spi -r backup.bin` |
