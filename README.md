# ASOS — кастомный образ Arch Linux + Hyprland

Live/установочный ISO на базе **Arch Linux** (профиль `archiso`) с готовым рабочим окружением:

| Компонент | Что внутри |
|---|---|
| **Рабочий стол** | Hyprland, Waybar, Wofi, Mako, Kitty, Hyprlock/Hypridle, Thunar, PipeWire, NetworkManager, Bluetooth, тёмная тема, раскладка EN/RU (`Alt+Shift`) |
| **Обход DPI** | [zapret](https://github.com/bol-van/zapret) (`nfqws` + nftables) со **всеми стратегиями [Flowseal](https://github.com/Flowseal/zapret-discord-youtube)** (`general`, `ALT`…`ALT13`, `SIMPLE FAKE`, `FAKE TLS AUTO` …), Game Filter и IPSet Filter как в оригинале. Служба включена сразу. |
| **Atom game pack** | Steam, Lutris, Wine-staging (+mono/gecko, winetricks), Prism Launcher, GameMode, MangoHud, Gamescope, Mesa/Vulkan 64+32 бит (AMD/Intel/Nouveau), ntsync, сетевые твики (BBR), `asos-game` + список игровых доменов/IP для zapret (Steam, Epic, EA, Ubisoft, Battle.net, Riot, Roblox, Minecraft, FACEIT, Twitch…) |
| **Офис** | LibreOffice (рус.), Thunderbird, Zathura (PDF), Xournal++, Mousepad, Qalculate, KeePassXC, GIMP, Simple Scan |
| **Сисадмин** | мониторинг (htop, btop, nvtop, glances, iotop, sysstat, lm_sensors, inxi, hwinfo), сеть (nmap, Wireshark, termshark, tcpdump, mtr, iperf3, dig, nethogs, iftop, bandwhich, arp-scan, socat), удалённый доступ (OpenSSH, sshfs, Remmina, FreeRDP, TigerVNC, FileZilla, PuTTY), диски и восстановление (GParted, testdisk/photorec, ddrescue, Clonezilla, partclone, fsarchiver, smartmontools, nvme-cli, LVM, mdadm, LUKS, btrfs/xfs/f2fs/ntfs/exfat, chntpw), бэкапы (rsync, rclone, restic, borg), виртуализация и контейнеры (Docker + compose/buildx, QEMU, libvirt, virt-manager), IaC (Ansible, OpenTofu, kubectl, Helm, k9s), безопасность (Lynis, ClamAV), Memtest86+, CLI (tmux, neovim, jq/yq, ripgrep, fd, fzf, bat, eza, ncdu, dust, duf…) |
| **Arduino** | Arduino IDE 2 (+ предустановленное ядро AVR и популярные библиотеки — работает офлайн), arduino-cli, PlatformIO Core, esptool, avrdude, dfu-util, stlink, OpenOCD, flashrom (CH341A), mpremote (MicroPython), PulseView/sigrok (логические анализаторы), терминалы tio/picocom/minicom/CuteCom/moserial, VS Code (Code-OSS); адреса плат ESP32, ESP8266, RP2040, STM32 уже прописаны; udev-правила и группа `uucp` — платы прошиваются без root; `asos-arduino` |
| **NanoPi** | кросс-компилятор aarch64 (gcc/g++/gdb) + toolchain-файлы CMake/Meson, qemu-user-static (запуск и chroot в aarch64-образы), rkdeveloptool (Rockchip maskrom), xfel/sunxi-tools (Allwinner FEL), u-boot-tools, dtc, Raspberry Pi Imager, caligula, android-tools, avahi/mDNS (`nanopi.local`); `asos-nanopi`: таблица плат, поиск в сети, UART-консоль, запись образа на microSD с проверкой, раздача интернета по кабелю, sysroot |
| **Установка** | `sudo asos-install` — переносит live-систему со всеми настройками на диск (UEFI → systemd-boot, BIOS → GRUB; ext4 или Btrfs с подтомами) |

## Структура репозитория

```
build.sh                    сборка ISO (нативно на Arch или через Docker)
scripts/fetch-zapret.sh     загрузка nfqws (bol-van/zapret) и стратегий/списков Flowseal
scripts/build-aur.sh        сборка AUR-пакетов (Arduino IDE, rkdeveloptool …) в локальный репозиторий
scripts/fetch-arduino.sh    предустановка ядер и библиотек Arduino в /etc/skel
scripts/check-packages.py   проверка списков пакетов по актуальным репозиториям Arch (без сборки)
archiso/                    профиль archiso
  profiledef.sh             параметры образа
  packages.x86_64           список пакетов (разбит по категориям)
  packages.aur              пакеты из AUR
  pacman.conf               core + extra + multilib
  syslinux/, efiboot/       меню загрузки BIOS / UEFI
  airootfs/                 файлы, попадающие в систему
    etc/skel/.config/       конфиги Hyprland, Waybar, Wofi, Mako, Kitty, MangoHud
    etc/zapret/             конфиг zapret и пользовательские списки
    etc/systemd/system/     zapret.service, live-службы
    etc/udev/rules.d/       права на USB-устройства Arduino/ESP/STM32/Rockchip/Allwinner
    usr/local/bin/          asos-zapret, asos-arduino, asos-nanopi, asos-install, asos-game …
    usr/share/asos/atom/    Atom game pack: hostlist + ipset игр
    usr/share/asos/embedded/ toolchain-файлы aarch64 и примеры
.github/workflows/          сборка ISO в GitHub Actions
```

## Сборка

**На Arch Linux:**

```bash
sudo pacman -S --needed archiso git
sudo ./build.sh
# ISO появится в ./out/
```

**В любой системе с Docker/Podman:**

```bash
./build.sh --docker
```

**В GitHub Actions:** вкладка *Actions → Build ASOS ISO → Run workflow*. ISO будет в артефактах сборки;
с галочкой *release* (или при пуше тега `v*`) — в релизе, разбитый на части по 1.9 ГБ (лимит GitHub).

Параметры сборки (переменные окружения):

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `ZAPRET_VERSION` | последняя | версия zapret, например `v72.13` |
| `FLOWSEAL_REF` | `main` | ветка/тег Flowseal, например `1.10.4` |
| `ARDUINO_CORES` | `arduino:avr` | ядра для предустановки, например `"arduino:avr esp32:esp32"` (ESP32 ≈ +1.5 ГБ) |
| `ARDUINO_LIBS` | 15 популярных | библиотеки через `;` |
| `SKIP_AUR=1` | — | не собирать AUR-пакеты (не будет Arduino IDE, rkdeveloptool, xfel, tio, yay) |
| `SKIP_ARDUINO=1` | — | не предустанавливать ядра/библиотеки Arduino |

Перед долгой сборкой можно за минуту проверить списки пакетов (работает на любой ОС с Python 3):

```bash
python3 scripts/check-packages.py
```

Скрипт скачивает базы репозиториев Arch и проверяет: все пакеты существуют, зависимости разрешаются,
нет конфликтов пакетов и файлов, зависимости AUR-пакетов есть в официальных репозиториях.
Эта же проверка запускается в GitHub Actions перед сборкой ISO.

> Образ большой (~6–7 ГБ) из‑за LibreOffice, Steam/Wine и инструментов. Для сборки нужно ~25 ГБ свободного места.
> Лишнее можно закомментировать в `archiso/packages.x86_64`.

Запись на флешку: `sudo dd if=out/asos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync` или Ventoy / Rufus (режим DD).

## Live-режим

* Автовход: пользователь **`asos`**, пароль **`asos`** (sudo без пароля), Hyprland стартует сам.
* Пункт меню *safe graphics / console only* — загрузка без графики (`asos.nogui`).
* `SUPER+F1` — шпаргалка по горячим клавишам, `SUPER+Z` — меню zapret, `SUPER+D` — приложения.

## zapret / Flowseal

Служба `zapret.service` запускает `nfqws` с выбранной стратегией Flowseal. Windows-файлы `*.bat`
конвертируются на лету: фильтры `--wf-tcp/--wf-udp` превращаются в правила nftables (NFQUEUE 200),
остальные параметры передаются в `nfqws` без изменений, поэтому новые стратегии Flowseal работают
после простой пересборки образа.

```bash
asos-zapret                 # статус
asos-zapret menu            # TUI-меню (то же по клику на значок в Waybar или SUPER+Z)
asos-zapret list            # список стратегий
sudo asos-zapret set general-alt2
sudo asos-zapret game all   # Game Filter: off | all | tcp | udp
sudo asos-zapret ipset any  # IPSet Filter: none | any | loaded
sudo asos-zapret atom on    # Atom game pack: on | off
asos-zapret check           # проверка Discord / YouTube / Steam / Roblox
sudo asos-zapret autotest   # перебрать все стратегии и показать результат
sudo asos-zapret show       # итоговая команда nfqws и порты
```

* Конфиг: `/etc/zapret/asos.conf`
* Свои домены: `/etc/zapret/lists/list-general-user.txt`, исключения: `list-exclude-user.txt`,
  свои IP: `ipset-user.txt`, исключения IP: `ipset-exclude-user.txt`.
* Значок в Waybar: зелёный — работает, красный — выключен; ЛКМ — меню, ПКМ — вкл/выкл.

Если стратегия по умолчанию (`general`) не помогает у вашего провайдера — запустите `sudo asos-zapret autotest`
и выберите стратегию с лучшим результатом.

## Atom game pack

* Включён по умолчанию: игровые домены (`/usr/share/asos/atom/list-atom-games.txt`) добавляются
  в hostlist zapret, IP-диапазоны игровых серверов (`ipset-atom-games.txt`) — в ipset для Game Filter.
* Если онлайн-игра всё равно не подключается: `sudo asos-zapret ipset any` (обработка всех IP на игровых портах).
* Запуск игр с GameMode + MangoHud: в параметрах запуска Steam укажите `asos-game %command%`
  (`ASOS_HUD=0` — без оверлея, `ASOS_GAMESCOPE="-W 1920 -H 1080 -f"` — через gamescope).
  Оверлей MangoHud: `Right Shift + F12`.
* Proton GE и Heroic Games Launcher есть только в AUR/Flatpak — ставятся после установки по желанию.

## Arduino

* **Arduino IDE 2** — `SUPER+A` или из меню. Ядро AVR (Uno, Nano, Mega, Leonardo, Pro Mini) и библиотеки
  (Servo, LiquidCrystal I2C, DHT, OneWire/DallasTemperature, NeoPixel, SSD1306, IRremote, ArduinoJson,
  PubSubClient, AccelStepper, RTClib …) уже установлены, интернет не нужен.
* В «Менеджере плат» сразу видны ESP32, ESP8266, Raspberry Pi Pico и STM32 — адреса индексов прописаны.
* Права: последовательные порты принадлежат группе `uucp`, пользователь в ней состоит; ModemManager
  не перехватывает порты плат; DFU/ST-Link/maskrom доступны без `sudo` (`/etc/udev/rules.d/70-asos-embedded.rules`).

```bash
asos-arduino doctor                  # диагностика: группа, порты, драйверы CH340/CP210x/FTDI, ядра
asos-arduino boards                  # подключённые платы; клоны на CH340 определяются по USB ID
asos-arduino upload Blink            # сборка + загрузка, плата и порт определяются сами
asos-arduino upload MySketch -b esp32:esp32:esp32s3 -p /dev/ttyACM0
asos-arduino monitor -B 9600
asos-arduino setup esp32 rp2040 stm32    # доустановить ядра (нужен интернет)
asos-arduino menu                    # то же в TUI (SUPER+Shift+A)
```

Также: PlatformIO (`pio`), esptool, mpremote (MicroPython), avrdude, dfu-util, stlink, OpenOCD,
flashrom, PulseView. Пример `~/Arduino/AsosSerialBridge` — обмен JSON между Arduino и NanoPi/ПК.

## NanoPi (FriendlyELEC) и другие ARM-платы

```bash
asos-nanopi boards                   # платы, SoC, скорость UART, пароли по умолчанию
asos-nanopi flash FriendlyCore-*.img.gz   # запись на microSD (.img/.gz/.xz/.zst/.zip/.7z) + проверка
asos-nanopi find                     # найти плату в сети (mDNS + nmap)
asos-nanopi share enp3s0             # раздать плате интернет по кабелю (ПК = 10.42.0.1)
asos-nanopi ssh pi@nanopi.local      # вход по ключу
asos-nanopi console                  # UART-консоль (Rockchip 1500000, Allwinner: ... 115200)
asos-nanopi usb                      # maskrom (rkdeveloptool) / FEL (xfel, sunxi-fel)
asos-nanopi chroot rootfs.img        # chroot в aarch64-образ через qemu (поставить пакеты до записи)
asos-nanopi sysroot pi@nanopi.local  # библиотеки платы для кросс-сборки
asos-nanopi menu                     # то же в TUI (SUPER+Shift+N)
```

Запись образа защищена: системный диск и live-носитель отклоняются, несъёмные диски — только с `--force`,
нужно ввести имя устройства, после записи данные сравниваются с образом.

Кросс-компиляция: `aarch64-linux-gnu-gcc`, toolchain-файлы `/usr/share/asos/embedded/aarch64-linux-gnu.{cmake,meson}`,
готовый пример `/usr/share/asos/embedded/examples/nanopi-hello` (`./deploy.sh pi@nanopi.local`).
Примеры описаны в `/usr/share/asos/embedded/examples/README.md`.

## Установка на диск

```bash
sudo asos-install
```

Установщик спросит диск, файловую систему (Btrfs/ext4), имя компьютера, пользователя, пароль,
часовой пояс и нужен ли автовход. **Выбранный диск полностью стирается.**
После установки всё — Hyprland, zapret, Atom pack, офис и инструменты — уже настроено.

## Примечания

* NVIDIA: в образе только открытый драйвер Nouveau (Mesa/NVK). Для проприетарного после установки:
  `sudo pacman -S nvidia-open nvidia-utils lib32-nvidia-utils` и `nvidia_drm.modeset=1` в параметрах ядра.
* В виртуальной машине Hyprland требует 3D-ускорения (VirtIO-GPU с virgl / VMware SVGA 3D).
* AUR-пакеты собираются из PKGBUILD на момент сборки образа; если какой-то не соберётся, ISO всё равно
  будет создан, а пакет можно поставить позже: `yay -S <пакет>`.
* Лицензии: zapret — MIT (bol-van), стратегии и списки — MIT (Flowseal).
