# ASOS — кастомный образ Arch Linux + Hyprland

Live/установочный ISO на базе **Arch Linux** (профиль `archiso`) с готовым рабочим окружением:

| Компонент | Что внутри |
|---|---|
| **Рабочий стол** | Hyprland, Waybar, Wofi, Mako, Kitty, Hyprlock/Hypridle, Thunar, PipeWire, NetworkManager, Bluetooth, тёмная тема, раскладка EN/RU (`Alt+Shift`) |
| **Обход DPI** | [zapret](https://github.com/bol-van/zapret) (`nfqws` + nftables) со **всеми стратегиями [Flowseal](https://github.com/Flowseal/zapret-discord-youtube)** (`general`, `ALT`…`ALT13`, `SIMPLE FAKE`, `FAKE TLS AUTO` …), Game Filter и IPSet Filter как в оригинале. Служба включена сразу. |
| **Atom game pack** | Steam, Lutris, Wine-staging (+mono/gecko, winetricks), Prism Launcher, GameMode, MangoHud, Gamescope, Mesa/Vulkan 64+32 бит (AMD/Intel/Nouveau), ntsync, сетевые твики (BBR), `asos-game` + список игровых доменов/IP для zapret (Steam, Epic, EA, Ubisoft, Battle.net, Riot, Roblox, Minecraft, FACEIT, Twitch…) |
| **Офис** | LibreOffice (рус.), Thunderbird, Zathura (PDF), Xournal++, Mousepad, Qalculate, KeePassXC, GIMP, Simple Scan |
| **Сисадмин** | мониторинг (htop, btop, nvtop, glances, iotop, sysstat, lm_sensors, inxi, hwinfo), сеть (nmap, Wireshark, termshark, tcpdump, mtr, iperf3, dig, nethogs, iftop, bandwhich, arp-scan, socat), удалённый доступ (OpenSSH, sshfs, Remmina, FreeRDP, TigerVNC, FileZilla, PuTTY), диски и восстановление (GParted, testdisk/photorec, ddrescue, Clonezilla, partclone, fsarchiver, smartmontools, nvme-cli, LVM, mdadm, LUKS, btrfs/xfs/f2fs/ntfs/exfat, chntpw), бэкапы (rsync, rclone, restic, borg), виртуализация и контейнеры (Docker + compose/buildx, QEMU, libvirt, virt-manager), IaC (Ansible, OpenTofu, kubectl, Helm, k9s), безопасность (Lynis, ClamAV), Memtest86+, CLI (tmux, neovim, jq/yq, ripgrep, fd, fzf, bat, eza, ncdu, dust, duf…) |
| **Установка** | `sudo asos-install` — переносит live-систему со всеми настройками на диск (UEFI → systemd-boot, BIOS → GRUB; ext4 или Btrfs с подтомами) |

## Структура репозитория

```
build.sh                    сборка ISO (нативно на Arch или через Docker)
scripts/fetch-zapret.sh     загрузка nfqws (bol-van/zapret) и стратегий/списков Flowseal
archiso/                    профиль archiso
  profiledef.sh             параметры образа
  packages.x86_64           список пакетов (разбит по категориям)
  pacman.conf               core + extra + multilib
  syslinux/, efiboot/       меню загрузки BIOS / UEFI
  airootfs/                 файлы, попадающие в систему
    etc/skel/.config/       конфиги Hyprland, Waybar, Wofi, Mako, Kitty, MangoHud
    etc/zapret/             конфиг zapret и пользовательские списки
    etc/systemd/system/     zapret.service, live-службы
    usr/local/bin/          asos-zapret, asos-install, asos-game, asos-power …
    usr/share/asos/atom/    Atom game pack: hostlist + ipset игр
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

Версии можно зафиксировать: `ZAPRET_VERSION=v72.13 FLOWSEAL_REF=1.10.4 sudo ./build.sh`.

> Образ большой (~5–6 ГБ) из‑за LibreOffice, Steam/Wine и инструментов. Для сборки нужно ~25 ГБ свободного места.
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
* Лицензии: zapret — MIT (bol-van), стратегии и списки — MIT (Flowseal).
