<#
.SYNOPSIS
  Create and start an ASOS virtual machine in Oracle VirtualBox (Windows).

.DESCRIPTION
  * 4 CPU cores max (never more than the host has), 8 GB RAM max (never more than half
    of the host's RAM), 20 GB dynamically allocated VDI disk on a SATA (AHCI) controller —
    not NVMe — plus the ISO as a SATA DVD drive.
  * EFI firmware, VMSVGA graphics with 3D acceleration and 128 MB VRAM (needed by Hyprland),
    NAT network, audio, USB 3.0 (for Arduino / NanoPi passthrough), shared clipboard.
  * The ISO is taken from your Downloads folder: asos-*.iso, then archlinux-*.iso, then the
    newest *.iso (or pass -Iso).
  * After start it can type the ASOS installer command into the Arch live console for you.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\create-vm.ps1
.EXAMPLE
  .\create-vm.ps1 -Iso "D:\iso\archlinux-2026.11.01-x86_64.iso" -Name ASOS-test
#>
[CmdletBinding()]
param(
    [string]$Iso,
    [string]$Name = "ASOS",
    [int]$Cpus = 4,
    [int]$MemoryMB = 8192,
    [int]$DiskGB = 20,
    [int]$BootWaitSeconds = 90,
    [switch]$NoAutoType,
    [switch]$Recreate
)
# "Continue": in Windows PowerShell 5.1 "Stop" turns any stderr line of a native
# command redirected with 2>$null into a terminating error. Exit codes are checked instead.
$ErrorActionPreference = "Continue"
$InstallCmd = "curl -fsSL https://raw.githubusercontent.com/Arqa322/asos/claude/arch-hyprland-custom-image-hl6sdl/scripts/install-online.sh -o i.sh && bash i.sh"

function Info($m) { Write-Host ":: $m" -ForegroundColor Green }
function Warn($m) { Write-Host "!! $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "error: $m" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- VBoxManage
$vbm = (Get-Command VBoxManage.exe -ErrorAction SilentlyContinue).Source
if (-not $vbm) {
    foreach ($p in @("$env:VBOX_MSI_INSTALL_PATH\VBoxManage.exe",
                     "$env:VBOX_INSTALL_PATH\VBoxManage.exe",
                     "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe")) {
        if ($p -and (Test-Path $p)) { $vbm = $p; break }
    }
}
if (-not $vbm) { Fail "VBoxManage.exe не найден — установлен ли Oracle VirtualBox?" }
$ver = (& $vbm --version) -join ""
Info "VirtualBox $ver"

function VBox {  # run VBoxManage, fail on error
    & $vbm @args
    if ($LASTEXITCODE -ne 0) { Fail "VBoxManage $($args -join ' ') завершился с ошибкой $LASTEXITCODE" }
}
function VBoxTry {  # optional setting: try each variant (new syntax first, then legacy)
    param([string]$What, [object[]]$Variants)
    foreach ($v in $Variants) {
        & $vbm @v 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    Warn "не удалось включить: $What (не критично)"
    return $false
}

# ------------------------------------------------------------------ the ISO
if (-not $Iso) {
    $downloads = $null
    try {
        $raw = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders")."{374DE290-123F-4565-9164-39C4925E467B}"
        if ($raw) { $downloads = [Environment]::ExpandEnvironmentVariables($raw) }
    } catch {}
    if (-not $downloads -or -not (Test-Path $downloads)) { $downloads = Join-Path $env:USERPROFILE "Downloads" }
    Info "ищу ISO в $downloads"
    $all = Get-ChildItem -Path $downloads -Filter *.iso -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    $pick = ($all | Where-Object Name -like "asos-*.iso" | Select-Object -First 1)
    if (-not $pick) { $pick = ($all | Where-Object Name -like "archlinux-*.iso" | Select-Object -First 1) }
    if (-not $pick) { $pick = ($all | Select-Object -First 1) }
    if (-not $pick) { Fail "в $downloads нет файлов .iso — укажите путь: -Iso C:\путь\к\образу.iso" }
    $Iso = $pick.FullName
}
if (-not (Test-Path $Iso)) { Fail "ISO не найден: $Iso" }
$Iso = (Resolve-Path $Iso).Path
Info ("ISO: {0} ({1:N1} ГБ)" -f $Iso, ((Get-Item $Iso).Length / 1GB))

# -------------------------------------------------- limits from the host PC
$cores = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
$ramMB = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
$Cpus = [Math]::Max(1, [Math]::Min($Cpus, $cores))
# leave the host at least 40% of its RAM; round to 256 MB
$cap = [int]([Math]::Floor($ramMB * 0.6 / 256) * 256)
$MemoryMB = [Math]::Max(2048, [Math]::Min($MemoryMB, $cap))
Info "хост: $cores физ. ядер, $ramMB МБ ОЗУ  ->  ВМ: $Cpus ядра, $MemoryMB МБ ОЗУ, диск $DiskGB ГБ (SATA)"
if ($MemoryMB -lt 4096) { Warn "меньше 4 ГБ ОЗУ для ВМ — Hyprland и установка будут медленными" }

# Hyper-V / WSL2 make VirtualBox run in the slow "NEM" mode
try {
    $hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
    if ($hv) { Warn "включён Hyper-V (или WSL2/песочница/защита ядра): VirtualBox будет работать медленнее. Отключение: bcdedit /set hypervisorlaunchtype off и перезагрузка" }
} catch {}

# -------------------------------------------------------------- create VM
$exists = (& $vbm list vms) -match "^`"$([regex]::Escape($Name))`" "
if ($exists) {
    if (-not $Recreate) { Fail "ВМ `"$Name`" уже существует. Другое имя: -Name ASOS2, или пересоздать: -Recreate (диск ВМ будет удалён)" }
    $ans = Read-Host "Удалить существующую ВМ `"$Name`" вместе с её диском? Введите YES"
    if ($ans -ne "YES") { Fail "отменено" }
    & $vbm controlvm $Name poweroff 2>$null | Out-Null
    Start-Sleep -Seconds 2
    VBox unregistervm $Name --delete
}

$props = & $vbm list systemproperties
$baseFolder = (($props | Select-String "^Default machine folder:\s+(.+)$").Matches[0].Groups[1].Value).Trim()
$vmDir = Join-Path $baseFolder $Name
$vdi = Join-Path $vmDir "$Name.vdi"

Info "создаю ВМ $Name"
$created = $false
foreach ($os in @("ArchLinux_64", "ArchLinux_x64", "Linux_64", "Linux_x64")) {
    & $vbm createvm --name $Name --ostype $os --register 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $created = $true; Info "тип ОС: $os"; break }
}
if (-not $created) { Fail "не удалось создать ВМ" }

VBox modifyvm $Name --cpus $Cpus --memory $MemoryMB --vram 128 --graphicscontroller vmsvga --firmware efi --ioapic on --nic1 nat --boot1 dvd --boot2 disk --boot3 none --boot4 none
$null = VBoxTry "часы в UTC" @(@("modifyvm", $Name, "--rtc-use-utc", "on"), @("modifyvm", $Name, "--rtcuseutc", "on"))
$null = VBoxTry "3D-ускорение (нужно для Hyprland)" @(@("modifyvm", $Name, "--accelerate-3d", "on"), @("modifyvm", $Name, "--accelerate3d", "on"))
$null = VBoxTry "паравиртуализация KVM" @(@("modifyvm", $Name, "--paravirt-provider", "kvm"), @("modifyvm", $Name, "--paravirtprovider", "kvm"))
$null = VBoxTry "звук" @(@("modifyvm", $Name, "--audio-enabled", "on", "--audio-out", "on", "--audio-in", "on"), @("modifyvm", $Name, "--audio", "dsound", "--audioout", "on"))
$null = VBoxTry "общий буфер обмена" @(@("modifyvm", $Name, "--clipboard-mode", "bidirectional"), @("modifyvm", $Name, "--clipboard", "bidirectional"))
$null = VBoxTry "drag'n'drop" @(@("modifyvm", $Name, "--drag-and-drop", "bidirectional"), @("modifyvm", $Name, "--draganddrop", "bidirectional"))
$null = VBoxTry "USB 3.0 (xHCI)" @(@("modifyvm", $Name, "--usb-xhci", "on"), @("modifyvm", $Name, "--usbxhci", "on"), @("modifyvm", $Name, "--usb-ohci", "on"), @("modifyvm", $Name, "--usb", "on"))
# leading comma: keep a one-variant list as an array of arrays (PowerShell flattens @(@(...)))
$null = VBoxTry "планшетная мышь" @(,@("modifyvm", $Name, "--mouse", "usbtablet"))

Info "диск $DiskGB ГБ (VDI, динамический) на контроллере SATA/AHCI"
VBox createmedium disk --filename $vdi --size ($DiskGB * 1024) --format VDI
VBox storagectl $Name --name "SATA" --add sata --controller IntelAhci --portcount 2 --hostiocache on --bootable on
VBox storageattach $Name --storagectl "SATA" --port 0 --device 0 --type hdd --medium $vdi --nonrotational on --discard on
VBox storageattach $Name --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium $Iso

Info "запуск ВМ"
VBox startvm $Name --type gui

# ------------------------------------------- type the installer command
Write-Host ""
Write-Host "Команда установщика ASOS для консоли Arch live:" -ForegroundColor Cyan
Write-Host "  $InstallCmd"
Write-Host ""
$isArchIso = (Split-Path $Iso -Leaf) -like "archlinux-*"
if ($isArchIso -and -not $NoAutoType) {
    $ans = Read-Host "Ввести её в ВМ автоматически через $BootWaitSeconds с (после загрузки live-системы)? [Y/n]"
    if ($ans -eq "" -or $ans -match "^[YyДд]") {
        for ($i = $BootWaitSeconds; $i -gt 0; $i -= 5) { Write-Host -NoNewline "`r  ожидание загрузки: $i с  "; Start-Sleep -Seconds 5 }
        Write-Host ""
        VBox controlvm $Name keyboardputstring $InstallCmd
        VBox controlvm $Name keyboardputscancode 1c 9c
        Info "команда введена. Дальше отвечайте на вопросы установщика в окне ВМ."
        Write-Host "  Если строка ввелась раньше, чем появилось приглашение root@archiso, наберите команду выше вручную."
    }
}
Write-Host ""
Info "после установки: Устройства -> Оптические диски -> Изъять диск, затем reboot в ВМ"
