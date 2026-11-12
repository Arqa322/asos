# Huilo — кастомный образ Arch Linux + Hyprland

Live/установочный ISO на базе **Arch Linux** (профиль `archiso`) с готовым рабочим окружением:

| Компонент | Что внутри |
|---|---|
| **Рабочий стол** | Hyprland, Waybar, rofi (меню), swaync (уведомления), swayosd, Kitty, Hyprlock/Hypridle, Thunar, PipeWire, NetworkManager, Bluetooth, собственная тема **Huilo Dusk**, раскладка EN/RU (`Alt+Shift`) |
| **ИИ-помощник** | `ии` в терминале (`SUPER+I`): вопрос своими словами → понятный ответ и готовые команды, которые выполняются только после подтверждения; локальная модель (Ollama) или Claude |
| **Обход DPI** | [zapret](https://github.com/bol-van/zapret) (`nfqws` + nftables) со **всеми стратегиями [Flowseal](https://github.com/Flowseal/zapret-discord-youtube)** (`general`, `ALT`…`ALT13`, `SIMPLE FAKE`, `FAKE TLS AUTO` …), Game Filter и IPSet Filter как в оригинале. Служба включена сразу. |
| **Atom game pack** | Steam, Lutris, Wine-staging (+mono/gecko, winetricks), Prism Launcher, GameMode, MangoHud, Gamescope, Mesa/Vulkan 64+32 бит (AMD/Intel/Nouveau), ntsync, сетевые твики (BBR), `huilo-game` + список игровых доменов/IP для zapret (Steam, Epic, EA, Ubisoft, Battle.net, Riot, Roblox, Minecraft, FACEIT, Twitch…) |
| **Офис** | LibreOffice (рус.), Thunderbird, Zathura (PDF), Xournal++, Mousepad, Qalculate, KeePassXC, GIMP, Simple Scan |
| **Сисадмин** | мониторинг (htop, btop, nvtop, glances, iotop, sysstat, lm_sensors, inxi, hwinfo), сеть (nmap, Wireshark, termshark, tcpdump, mtr, iperf3, dig, nethogs, iftop, bandwhich, arp-scan, socat), удалённый доступ (OpenSSH, sshfs, Remmina, FreeRDP, TigerVNC, FileZilla, PuTTY), диски и восстановление (GParted, testdisk/photorec, ddrescue, Clonezilla, partclone, fsarchiver, smartmontools, nvme-cli, LVM, mdadm, LUKS, btrfs/xfs/f2fs/ntfs/exfat, chntpw), бэкапы (rsync, rclone, restic, borg), виртуализация и контейнеры (Docker + compose/buildx, QEMU, libvirt, virt-manager), IaC (Ansible, OpenTofu, kubectl, Helm, k9s), безопасность (Lynis, ClamAV), Memtest86+, CLI (tmux, neovim, jq/yq, ripgrep, fd, fzf, bat, eza, ncdu, dust, duf…) |
| **Arduino** | Arduino IDE 2 (+ предустановленное ядро AVR и популярные библиотеки — работает офлайн), arduino-cli, PlatformIO Core, esptool, avrdude, dfu-util, stlink, OpenOCD, flashrom (CH341A), mpremote (MicroPython), PulseView/sigrok (логические анализаторы), терминалы tio/picocom/minicom/CuteCom/moserial, VS Code (Code-OSS); адреса плат ESP32, ESP8266, RP2040, STM32 уже прописаны; udev-правила и группа `uucp` — платы прошиваются без root; `huilo-arduino` |
| **NanoPi** | кросс-компилятор aarch64 (gcc/g++/gdb) + toolchain-файлы CMake/Meson, qemu-user-static (запуск и chroot в aarch64-образы), rkdeveloptool (Rockchip maskrom), xfel/sunxi-tools (Allwinner FEL), u-boot-tools, dtc, Raspberry Pi Imager, caligula, android-tools, avahi/mDNS (`nanopi.local`); `huilo-nanopi`: таблица плат, поиск в сети, UART-консоль, запись образа на microSD с проверкой, раздача интернета по кабелю, sysroot |
| **Установка** | `sudo huilo-install` — переносит live-систему со всеми настройками на диск (UEFI → systemd-boot, BIOS → GRUB; ext4 или Btrfs с подтомами) |

## Структура репозитория

```
build.sh                    сборка ISO (нативно на Arch или через Docker)
scripts/fetch-zapret.sh     загрузка nfqws (bol-van/zapret) и стратегий/списков Flowseal
scripts/build-aur.sh        сборка AUR-пакетов (Arduino IDE, rkdeveloptool …) в локальный репозиторий
scripts/fetch-arduino.sh    предустановка ядер и библиотек Arduino в /etc/skel
scripts/check-packages.py   проверка списков пакетов по актуальным репозиториям Arch (без сборки)
scripts/pkg-select.sh       необязательные группы пакетов (--without / --minimal)
scripts/make-wallpapers.py  генератор обоев и картинок экрана загрузки
scripts/make-theme.py       сборка конфигов оформления из theme/palette.toml
scripts/install-online.sh   установка Huilo с официального ISO Arch (без сборки образа)
scripts/update-installed.sh обновление установленной системы (huilo-update)
scripts/tests/              тесты (ИИ-помощник, проверщик конфига Hyprland)
theme/                      палитра Huilo Dusk и шаблоны конфигов
assets/huilo-photo.jpg      фото проекта (только экран загрузки)
docs/                       схема устройства системы и руководство по изменениям
archiso/                    профиль archiso
  profiledef.sh             параметры образа
  packages.x86_64           список пакетов (разбит по категориям)
  packages.aur              пакеты из AUR
  pacman.conf               core + extra + multilib
  syslinux/, efiboot/       меню загрузки BIOS / UEFI
  airootfs/                 файлы, попадающие в систему
    etc/skel/.config/       конфиги Hyprland, Waybar, rofi, swaync, swayosd, Kitty, GTK/Qt, MangoHud
    etc/zapret/             конфиг zapret и пользовательские списки
    etc/systemd/system/     zapret.service, live-службы
    etc/udev/rules.d/       права на USB-устройства Arduino/ESP/STM32/Rockchip/Allwinner
    usr/local/bin/          huilo-zapret, huilo-menu, huilo-ai, huilo-theme, huilo-install, huilo-arduino …
    usr/share/rofi/themes/  темы меню (генерируются из палитры)
    usr/share/huilo/atom/    Atom game pack: hostlist + ipset игр
    usr/share/huilo/embedded/ toolchain-файлы aarch64 и примеры
vm/                         создание ВМ VirtualBox (Windows PowerShell / bash)
.github/workflows/          проверки и сборка ISO в GitHub Actions
CHANGELOG.md                список изменений
```

Как всё устроено (схемы сборки и работы системы, технологии, зависимости) — [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Как вносить изменения, не ломая установленные системы, и как обновлять README — [docs/MAINTAINING.md](docs/MAINTAINING.md).

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

**В GitHub Actions:** вкладка *Actions → Build Huilo ISO → Run workflow*. ISO будет в артефактах сборки;
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
| `HUILO_WITHOUT` | — | то же, что `--without` |

Перед долгой сборкой можно за минуту проверить списки пакетов (работает на любой ОС с Python 3):

```bash
python3 scripts/check-packages.py
```

Скрипт скачивает базы репозиториев Arch и проверяет: все пакеты существуют, зависимости разрешаются,
нет конфликтов пакетов и файлов, зависимости AUR-пакетов есть в официальных репозиториях.
Эта же проверка запускается в GitHub Actions перед сборкой ISO.

> Образ большой (~6–7 ГБ) из‑за LibreOffice, Steam/Wine и инструментов. Для сборки нужно **не меньше 40 ГБ** свободного
> места (build.sh проверяет это заранее): при нехватке места pacman оставляет недокачанные пакеты и сообщает об ошибке
> подписи — обновление ключей в этом случае не помогает. В live-образе и в ВМ на 20 ГБ ISO не собрать.
> Лишнее можно закомментировать в `archiso/packages.x86_64`.

Запись на флешку: `sudo dd if=out/huilo-*.iso of=/dev/sdX bs=4M status=progress oflag=sync` или Ventoy / Rufus (режим DD).

## Установка без лишних программ

Пакеты разбиты на ядро системы (Hyprland, браузер, сеть, звук, драйверы, CLI) и необязательные группы:

| Группа | Что внутри |
|---|---|
| `office` | LibreOffice, Zathura, Xournal++, KeePassXC, калькулятор |
| `communication` | Thunderbird, Telegram, Discord, qBittorrent |
| `media` | OBS Studio, GIMP |
| `vscode` | VS Code (Code - OSS) |
| `ai` | Ollama — локальная модель для ИИ-помощника (сама модель скачивается в `ии setup`), glow |
| `games` | Atom game pack: Steam, Lutris, Wine, GameMode, MangoHud, 32-битные драйверы |
| `arduino` | Arduino IDE 2, arduino-cli, PlatformIO, esptool, OpenOCD, PulseView … |
| `nanopi` | кросс-компилятор aarch64, qemu-user, rkdeveloptool, xfel … |
| `monitoring`, `nettools`, `disktools`, `virt`, `security` | инструменты сисадмина (алиас `sysadmin` — все пять) |
| `zapret` | обход DPI |
| `aur` | AUR-помощник yay |

Алиасы: `sysadmin`, `embedded` (= arduino + nanopi), `minimal` (= все группы, остаётся только ядро — ~170 пакетов вместо ~330).

```bash
sudo ./build.sh --without office,games,sysadmin     # ISO без офиса, игр и инструментов админа
sudo ./build.sh --minimal                           # только ядро
./build.sh --list-groups
bash i.sh --without games,vscode                     # онлайн-установщик (или спросит сам)
```

В установщике с ISO (`huilo-install`) группы отмечаются галочками. На установленной системе:

```bash
huilo-groups list                  # что установлено
sudo huilo-groups add office       # доставить группу
sudo huilo-groups remove games     # удалить группу вместе с ненужными зависимостями
```

## Оформление и меню

Собственная тема **Huilo Dusk**: глубокие «чернильные» фоны, тёплый белый текст и янтарный акцент — одна палитра
для всего, от меню загрузки до терминала. Цвета задаются в одном файле `theme/palette.toml`
(как поменять — [docs/MAINTAINING.md](docs/MAINTAINING.md#3-оформление-тема)).

* **Панель** — «плавающие острова» сверху: рабочие столы точками (активный — янтарная капсула), часы и дата,
  zapret, ошибки системы, раскладка, нагрузка (раскрывается при наведении), сеть, Bluetooth, звук, батарея,
  «не гасить экран», уведомления, питание.
* **Меню** (rofi): `SUPER+D` — приложения рядом с превью текущих обоев, `SUPER+Space` — **меню Huilo** со всеми
  настройками и утилитами, `SUPER+BackSpace` — питание плитками, `SUPER+W` — обои сеткой превью, `SUPER+C` — буфер
  обмена, `SUPER+.` — эмодзи, `SUPER+=` — калькулятор, Wi-Fi — по клику на значок сети.
* **Уведомления** (swaync): аккуратные карточки, критические — с красной полосой; `SUPER+N` — центр уведомлений
  с переключателями Wi-Fi, Bluetooth, zapret, ночного света, эквалайзером, громкостью и плеером.
* **Громкость и яркость** — индикатор-капсула на экране (swayosd), включая Caps Lock.
* **Окна** — скруглённые углы, янтарная градиентная рамка у активного, тени, размытие под панелью и меню, мягкие
  анимации. Настройки звука, Bluetooth, сети и утилиты Huilo открываются по центру плавающими окнами.
  В виртуальной машине размытие и тени сами выключаются.
* **Приложения** — GTK в стиле libadwaita (adw-gtk3) с янтарным акцентом, Qt через qt6ct в тех же цветах,
  шрифт Inter, иконки Papirus, курсор Capitaine. `huilo-theme night toggle` — тёплый «ночной свет».
* **Обои** — шесть оригинальных 4K-обоев, сгенерированных `scripts/make-wallpapers.py` в палитре Huilo (горы
  в сумерках — по умолчанию, северное сияние, поток, волны, туманность, эмблема). `SUPER+W` — выбор,
  `SUPER+Shift+W` — следующие, `huilo-wallpaper random`. Свои картинки — в `~/Изображения/Wallpapers`.
  Экран блокировки — текущие обои с размытием, крупные часы и дата.
* **Терминал** — kitty в цветах Huilo, приглашение starship, fastfetch (`ff`) с логотипом Huilo при открытии
  (отключить: `touch ~/.config/huilo/no-fastfetch`), история на 50 000 команд, fzf (`Ctrl+R`). Текстовые меню
  скриптов (zapret, установщик) и текстовая консоль tty — в той же палитре. Свои настройки kitty — `~/.config/kitty/user.conf`.

## ИИ-помощник

Для тех, кто впервые видит Linux. Спросите обычными словами — помощник ответит по-русски, коротко, и предложит
готовые команды. **Ничего не выполняется без вашего «да»**; опасные команды (удаление, форматирование, запуск
скриптов из интернета) помечены красным, и для них нужно напечатать слово «выполнить».

```bash
ии                          # разговор: спрашивайте, выполняйте предложенное, просите объяснить результат
ии как установить телеграм  # один вопрос
ии почему нет звука
sudo pacman -Syu 2>&1 | ии  # объяснить вывод команды или ошибку
ии объясни                  # что делала предыдущая команда
ии setup                    # выбрать «мозг»
```

Также: `SUPER+I`, пункт «ИИ-помощник» в меню Huilo (`SUPER+Space`) и в приложениях. Если набрать несуществующую
команду, терминал подскажет спросить помощника.

| «Мозг» | Плюсы | Что нужно |
|---|---|---|
| **Локальный** (Ollama, модель Qwen 3) | бесплатно, приватно, работает без интернета | группа `ai` (есть в образе), один раз скачать модель 1–5 ГБ (`ии setup` выберет размер по памяти) |
| **Claude** (Anthropic) | умнее и быстрее на слабом ПК | интернет и API-ключ с console.anthropic.com; вопросы уходят в Anthropic; доступен не во всех странах |

Настройки — `~/.config/huilo/ai.conf` (`BACKEND=local|claude|auto`, `LOCAL_MODEL=…`, `CLAUDE_MODEL=…`), ключ —
`~/.config/huilo/ai.key` (виден только вам). Без группы `ai`: `./build.sh --without ai`.

## Журналы и уведомления об ошибках

* `huilo-logwatch` запускается вместе с рабочим столом и следит за системным журналом. При серьёзной ошибке
  показывает всплывающее уведомление, при критической (упавшая программа, ошибка диска, нехватка памяти, сбой ядра) —
  красное, которое висит до закрытия. В уведомлении кнопки «Собрать журналы» и «Подробнее». На панели появляется
  значок с числом ошибок: ЛКМ — список, ПКМ — сбросить, СКМ — собрать журналы. Повторы и известный безобидный шум
  отфильтрованы; свои исключения — `~/.config/huilo/logwatch-ignore`.
* `huilo-logs` собирает подробный отчёт в архив `~/huilo-logs-*.tar.gz`: сводка, ошибки и предупреждения журнала,
  прошлая загрузка, ядро, упавшие службы, аварийные дампы, время загрузки, железо, диски, сеть, графика и сеанс,
  звук, zapret, история pacman. `huilo-logs --redact` маскирует имена, IP/MAC-адреса и серийные номера — для отправки
  другим людям. `sudo huilo-logs` добавляет данные, доступные только root (SMART, dmidecode, dmesg).

## Эквалайзер

EasyEffects с плагинами LSP — общесистемный эквалайзер для всего звука. Готовые пресеты: `Balanced` (по умолчанию),
`Bass`, `Bright`, `Voice`, `Games` (шаги и звуки окружения), `Night`, `Flat`; усиление в каждом компенсировано, клиппинга нет.

```bash
huilo-eq                 # окно эквалайзера (SUPER+Alt+M, или средняя кнопка мыши на значке звука)
huilo-eq menu            # выбор пресета (SUPER+Shift+M)
huilo-eq preset bass     # balanced | bass | bright | voice | games | night | flat
huilo-eq off / on        # выключить / включить эффекты
```

## Экран загрузки

После BIOS/UEFI показывается фото проекта (`assets/huilo-photo.jpg`): в меню загрузки BIOS (syslinux) и на экране
загрузки системы (Plymouth, тема `huilo`, с янтарной полосой прогресса и вводом пароля для зашифрованных дисков).
Фото используется **только на экране загрузки** — в обоях его нет. Картинки пересобираются
`python3 scripts/make-wallpapers.py`.

## Live-режим

* Автовход: пользователь **`huilo`**, пароль **`huilo`** (sudo без пароля), графический сеанс стартует сам.
* Пункт меню *safe graphics: sway without 3D* — упрощённый рабочий стол без 3D-ускорения,
  *console only* — загрузка без графики (`huilo.nogui`).
* `SUPER+Space` — меню Huilo, `SUPER+D` — приложения, `SUPER+I` — ИИ-помощник, `SUPER+Z` — меню zapret,
  `SUPER+F1` — шпаргалка по всем горячим клавишам.

## Графический сеанс и безопасный режим

Конфиг Hyprland — `~/.config/hypr/hyprland.lua` (Hyprland 0.57+ использует Lua; старый `hyprland.conf` больше не читается).
Свои настройки — в `~/.config/hypr/user.lua`, он подключается последним. В виртуальной машине конфиг сам отключает
аппаратный курсор и размытие.

Сеанс запускает `huilo-session`. Вместо бесконечного цикла падений (логотип Hyprland → чёрный экран) он пробует режимы
по очереди, запоминает рабочий и при неудаче оставляет вас в консоли с подсказкой:

| Режим | Когда |
|---|---|
| `hyprland` / `hyprland-vm` | обычный запуск (на железе / в ВМ) |
| `hyprland-legacy` | + старый (не atomic) режим вывода |
| `hyprland-software` | + программная отрисовка (llvmpipe), медленно, но без 3D |
| `sway-software` | **безопасный режим**: sway без GPU — работает везде, те же клавиши, `foot` как терминал |

```bash
huilo-doctor                       # диагностика графики: драйвер, есть ли 3D, журналы, отчёт в ~/huilo-doctor.txt
huilo-session --status             # текущий/запомненный режим
huilo-session --set sway-software  # принудительно (или параметр ядра huilo.session=sway-software)
huilo-session --reset              # снова автовыбор
```

Hyprland официально не поддерживает виртуальные машины. Лучше всего он работает в VMware Workstation с 3D-ускорением
и в QEMU/KVM с virtio-gpu + virgl. В VirtualBox нужен контроллер VMSVGA с включённым 3D-ускорением, и даже тогда
результат зависит от видеокарты ПК — если Hyprland не поднимется, Huilo сам перейдёт в безопасный режим.

## Обновление уже установленной системы

Без переустановки — новые скрипты, тема, конфиги (изменённые вами файлы сохраняются как `*.bak-<дата>`, личные
`~/.config/hypr/user.lua` и `~/.config/kitty/user.conf` не трогаются), безопасный режим, пункт загрузки:

```bash
huilo-update            # на системе, где Huilo уже есть
```

или, если команды `huilo-update` ещё нет (старая установка, ASOS):

```bash
curl -fsSL https://raw.githubusercontent.com/Arqa322/Huilo/claude/arch-hyprland-custom-image-hl6sdl/scripts/update-installed.sh | sudo bash
```

Если на tty1 цикл падений — переключитесь на текстовую консоль (`Ctrl+Alt+F2`, в VirtualBox — `Host+F2`, по умолчанию
Host = правый Ctrl), войдите и выполните команду выше. В VirtualBox её можно не набирать: после входа запустите на ПК
`.\create-vm.ps1 -TypeUpdate` (или `./create-vm.sh --type-update`) — скрипт введёт её в ВМ сам.

## zapret / Flowseal

Служба `zapret.service` запускает `nfqws` с выбранной стратегией Flowseal. Windows-файлы `*.bat`
конвертируются на лету: фильтры `--wf-tcp/--wf-udp` превращаются в правила nftables (NFQUEUE 200),
остальные параметры передаются в `nfqws` без изменений, поэтому новые стратегии Flowseal работают
после простой пересборки образа.

```bash
huilo-zapret                 # статус
huilo-zapret menu            # TUI-меню (то же по клику на значок в Waybar или SUPER+Z)
huilo-zapret list            # список стратегий
sudo huilo-zapret set general-alt2
sudo huilo-zapret game all   # Game Filter: off | all | tcp | udp
sudo huilo-zapret ipset any  # IPSet Filter: none | any | loaded
sudo huilo-zapret atom on    # Atom game pack: on | off
huilo-zapret check           # проверка Discord / YouTube / Steam / Roblox
sudo huilo-zapret autotest   # перебрать все стратегии и показать результат
sudo huilo-zapret show       # итоговая команда nfqws и порты
```

* Конфиг: `/etc/zapret/huilo.conf`
* Свои домены: `/etc/zapret/lists/list-general-user.txt`, исключения: `list-exclude-user.txt`,
  свои IP: `ipset-user.txt`, исключения IP: `ipset-exclude-user.txt`.
* Значок в Waybar: зелёный — работает, красный — выключен; ЛКМ — меню, ПКМ — вкл/выкл.

Если стратегия по умолчанию (`general`) не помогает у вашего провайдера — запустите `sudo huilo-zapret autotest`
и выберите стратегию с лучшим результатом.

## Atom game pack

* Включён по умолчанию: игровые домены (`/usr/share/huilo/atom/list-atom-games.txt`) добавляются
  в hostlist zapret, IP-диапазоны игровых серверов (`ipset-atom-games.txt`) — в ipset для Game Filter.
* Если онлайн-игра всё равно не подключается: `sudo huilo-zapret ipset any` (обработка всех IP на игровых портах).
* Запуск игр с GameMode + MangoHud: в параметрах запуска Steam укажите `huilo-game %command%`
  (`HUILO_HUD=0` — без оверлея, `HUILO_GAMESCOPE="-W 1920 -H 1080 -f"` — через gamescope).
  Оверлей MangoHud: `Right Shift + F12`.
* Proton GE и Heroic Games Launcher есть только в AUR/Flatpak — ставятся после установки по желанию.

## Arduino

* **Arduino IDE 2** — `SUPER+A` или из меню. Ядро AVR (Uno, Nano, Mega, Leonardo, Pro Mini) и библиотеки
  (Servo, LiquidCrystal I2C, DHT, OneWire/DallasTemperature, NeoPixel, SSD1306, IRremote, ArduinoJson,
  PubSubClient, AccelStepper, RTClib …) уже установлены, интернет не нужен.
* В «Менеджере плат» сразу видны ESP32, ESP8266, Raspberry Pi Pico и STM32 — адреса индексов прописаны.
* Права: последовательные порты принадлежат группе `uucp`, пользователь в ней состоит; ModemManager
  не перехватывает порты плат; DFU/ST-Link/maskrom доступны без `sudo` (`/etc/udev/rules.d/70-huilo-embedded.rules`).

```bash
huilo-arduino doctor                  # диагностика: группа, порты, драйверы CH340/CP210x/FTDI, ядра
huilo-arduino boards                  # подключённые платы; клоны на CH340 определяются по USB ID
huilo-arduino upload Blink            # сборка + загрузка, плата и порт определяются сами
huilo-arduino upload MySketch -b esp32:esp32:esp32s3 -p /dev/ttyACM0
huilo-arduino monitor -B 9600
huilo-arduino setup esp32 rp2040 stm32    # доустановить ядра (нужен интернет)
huilo-arduino menu                    # то же в TUI (SUPER+Shift+A)
```

Также: PlatformIO (`pio`), esptool, mpremote (MicroPython), avrdude, dfu-util, stlink, OpenOCD,
flashrom, PulseView. Пример `~/Arduino/HuiloSerialBridge` — обмен JSON между Arduino и NanoPi/ПК.

## NanoPi (FriendlyELEC) и другие ARM-платы

```bash
huilo-nanopi boards                   # платы, SoC, скорость UART, пароли по умолчанию
huilo-nanopi flash FriendlyCore-*.img.gz   # запись на microSD (.img/.gz/.xz/.zst/.zip/.7z) + проверка
huilo-nanopi find                     # найти плату в сети (mDNS + nmap)
huilo-nanopi share enp3s0             # раздать плате интернет по кабелю (ПК = 10.42.0.1)
huilo-nanopi ssh pi@nanopi.local      # вход по ключу
huilo-nanopi console                  # UART-консоль (Rockchip 1500000, Allwinner: ... 115200)
huilo-nanopi usb                      # maskrom (rkdeveloptool) / FEL (xfel, sunxi-fel)
huilo-nanopi chroot rootfs.img        # chroot в aarch64-образ через qemu (поставить пакеты до записи)
huilo-nanopi sysroot pi@nanopi.local  # библиотеки платы для кросс-сборки
huilo-nanopi menu                     # то же в TUI (SUPER+Shift+N)
```

Запись образа защищена: системный диск и live-носитель отклоняются, несъёмные диски — только с `--force`,
нужно ввести имя устройства, после записи данные сравниваются с образом.

Кросс-компиляция: `aarch64-linux-gnu-gcc`, toolchain-файлы `/usr/share/huilo/embedded/aarch64-linux-gnu.{cmake,meson}`,
готовый пример `/usr/share/huilo/embedded/examples/nanopi-hello` (`./deploy.sh pi@nanopi.local`).
Примеры описаны в `/usr/share/huilo/embedded/examples/README.md`.

## Установка с официального ISO Arch (без сборки Huilo ISO)

Скрипт `scripts/install-online.sh` ставит Arch Linux сразу со всеми настройками Huilo: пакеты всех групп
из `archiso/packages.x86_64`, конфиги, zapret + Flowseal, AUR-пакеты (Arduino IDE и др.), ядро Arduino AVR.
Группы ставятся по очереди с очисткой кэша, Btrfs со сжатием — поэтому хватает диска 20 ГБ.
В виртуальной машине автоматически добавляются гостевые дополнения и настройки курсора для Hyprland.

Загрузитесь с официального `archlinux-*.iso` и в консоли live-системы выполните:

```bash
curl -fsSL https://raw.githubusercontent.com/Arqa322/Huilo/claude/arch-hyprland-custom-image-hl6sdl/scripts/install-online.sh -o i.sh
bash i.sh
```

Установщик спросит диск, файловую систему, имя компьютера, пользователя, пароль, часовой пояс и автовход.

## Виртуальная машина VirtualBox

`vm/create-vm.ps1` (Windows) и `vm/create-vm.sh` (Linux/macOS) создают и запускают ВМ:
до 4 ядер и до 8 ГБ ОЗУ (не больше, чем позволяет ПК), диск 20 ГБ на контроллере **SATA/AHCI** (не NVMe),
EFI, VMSVGA с 3D-ускорением (нужно Hyprland), NAT, USB 3.0 для Arduino/NanoPi, общий буфер обмена.
ISO берётся из «Загрузок» (`huilo-*.iso`, затем `archlinux-*.iso`, затем самый новый `.iso`).
Для официального ISO Arch скрипт может сам ввести в ВМ команду установщика.

Windows (PowerShell):

```powershell
cd $env:USERPROFILE\Downloads
Invoke-WebRequest https://raw.githubusercontent.com/Arqa322/Huilo/claude/arch-hyprland-custom-image-hl6sdl/vm/create-vm.ps1 -OutFile create-vm.ps1 -UseBasicParsing
powershell -ExecutionPolicy Bypass -File .\create-vm.ps1
```

Linux/macOS:

```bash
curl -fsSLO https://raw.githubusercontent.com/Arqa322/Huilo/claude/arch-hyprland-custom-image-hl6sdl/vm/create-vm.sh
bash create-vm.sh
```

Параметры: `-Iso <путь>`, `-Name`, `-Cpus`, `-MemoryMB`, `-DiskGB`, `-BootWaitSeconds`, `-NoAutoType`, `-Recreate`
(в bash-версии — `--iso`, `--name`, `--cpus`, `--memory`, `--disk`, `--boot-wait`, `--no-autotype`, `--recreate`).
Существующая ВМ с тем же именем не трогается без `-Recreate` и подтверждения.

## Установка на диск

```bash
sudo huilo-install
```

Установщик спросит диск, файловую систему (Btrfs/ext4), имя компьютера, пользователя, пароль,
часовой пояс и нужен ли автовход. **Выбранный диск полностью стирается.**
После установки всё — Hyprland, zapret, Atom pack, офис и инструменты — уже настроено.

## Примечания

* NVIDIA: в образе только открытый драйвер Nouveau (Mesa/NVK). Для проприетарного после установки:
  `sudo pacman -S nvidia-open nvidia-utils lib32-nvidia-utils` и `nvidia_drm.modeset=1` в параметрах ядра.
* В виртуальной машине Hyprland требует 3D-ускорения (см. «Графический сеанс и безопасный режим»).
* AUR-пакеты собираются из PKGBUILD на момент сборки образа; если какой-то не соберётся, ISO всё равно
  будет создан, а пакет можно поставить позже: `yay -S <пакет>`.
* Старые имена команд (`asos-*`, `huilo-power`) пока работают и подсказывают новое имя: `huilo-legacy --list`.
* Лицензии: zapret — MIT (bol-van), стратегии и списки — MIT (Flowseal).

## Для разработчиков

* [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — что на чём построено: схемы сборки, загрузки и рабочего стола,
  технологии (archiso, Docker, systemd, Wayland, PipeWire, nftables …), зависимости скриптов, карта репозитория.
* [docs/MAINTAINING.md](docs/MAINTAINING.md) — как менять конфигурацию: где какой файл, тема и палитра, пакеты,
  новые команды, обновление установленных систем, правила legacy, как обновлять README и CHANGELOG, проверки.
* [CHANGELOG.md](CHANGELOG.md) — список изменений.
