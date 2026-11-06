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
$script:AlreadyRunning = $false
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

# ------------------------------------------------ start with diagnostics
function Get-VmLogDir([string]$vm) {
    $line = (& $vbm showvminfo $vm --machinereadable 2>$null) | Where-Object { $_ -like 'CfgFile=*' } | Select-Object -First 1
    if (-not $line) { return $null }
    $cfg = ($line -replace '^CfgFile="', '' -replace '"$', '') -replace '\\\\', '\'
    return (Join-Path (Split-Path $cfg -Parent) "Logs")
}

function Get-VmLogErrors([string]$vm) {
    $dir = Get-VmLogDir $vm
    if (-not $dir -or -not (Test-Path $dir)) { return "" }
    $lines = @()
    foreach ($f in @("VBox.log", "VBoxHardening.log")) {
        $p = Join-Path $dir $f
        if (Test-Path $p) {
            $lines += Get-Content $p -Tail 600 -ErrorAction SilentlyContinue |
                Select-String -Pattern 'VERR_|error|failed|denied' |
                Select-Object -Last 12 | ForEach-Object { "  " + $_.Line.Trim() }
        }
    }
    return ($lines -join "`n")
}

function Get-VmState([string]$vm) {
    $line = (& $vbm showvminfo $vm --machinereadable 2>$null) | Where-Object { $_ -like 'VMState=*' } | Select-Object -First 1
    return ($line -replace '^VMState="', '' -replace '"$', '')
}

function Invoke-VmStart([string]$vm) {
    # never power off here: the VM may be running an installation
    $text = (& $vbm startvm $vm --type gui 2>&1 | ForEach-Object { "$_" }) -join "`n"
    return @{ Ok = ($LASTEXITCODE -eq 0); Text = $text }
}

function Start-AsosVm([string]$vm) {
    $state = Get-VmState $vm
    if ($state -in @("running", "paused", "starting", "restoring")) {
        Info "ВМ `"$vm`" уже запущена (состояние: $state) — окно ВМ в VirtualBox Manager"
        $script:AlreadyRunning = $true
        return $true
    }
    $r = Invoke-VmStart $vm
    if ($r.Ok) { return $true }

    # settings that are switched off one by one until the VM starts (3D last: Hyprland needs it)
    $fallbacks = @(
        @{ Name = "USB 3.0 (xHCI)"; Pattern = 'USB|EHCI|XHCI|xHCI|Extension Pack';
           Fix = @(@("modifyvm", $vm, "--usb-xhci", "off"), @("modifyvm", $vm, "--usbxhci", "off")) },
        @{ Name = "звук"; Pattern = '.';
           Fix = @(@("modifyvm", $vm, "--audio-enabled", "off"), @("modifyvm", $vm, "--audio", "none")) },
        @{ Name = "3D-ускорение"; Pattern = '.';
           Fix = @(@("modifyvm", $vm, "--accelerate-3d", "off"), @("modifyvm", $vm, "--accelerate3d", "off")) }
    )
    $all = $r.Text + "`n" + (Get-VmLogErrors $vm)

    # problems that cannot be fixed from the VM settings
    if ($all -match 'VERR_VMX_MSR_ALL_VMX_DISABLED|VERR_VMX_MSR_VMX_DISABLED|VERR_SVM_DISABLED|VERR_VMX_NO_VMX|VERR_SVM_NO_SVM|VT-x is (disabled|not available)|AMD-V is (disabled|not available)') {
        Write-Host $r.Text
        Fail "в BIOS/UEFI выключена аппаратная виртуализация. Включите Intel VT-x (Intel Virtualization Technology) или AMD SVM, сохраните настройки и запустите скрипт снова"
    }
    if ($all -match 'VERR_NEM_|VERR_HM_.*HYPER|Hyper-V is (enabled|running|active)') {
        Write-Host $r.Text
        Fail ("VirtualBox конфликтует с Hyper-V. Выключите: «Безопасность Windows → Безопасность устройства → Изоляция ядра → Целостность памяти», " +
              "компоненты «Платформа виртуальной машины», «Платформа гипервизора Windows», «Hyper-V», затем в PowerShell (администратор): " +
              "bcdedit /set hypervisorlaunchtype off  и перезагрузите ПК")
    }
    if ($all -match 'VERR_VM_DRIVER|VERR_SUPDRV_|VERR_SUPLIB_|VERR_SUP_VP_|vboxdrv') {
        Write-Host $r.Text
        Fail ("не загружен или заблокирован драйвер VirtualBox (часто мешает антивирус). Переустановите VirtualBox от имени администратора, " +
              "добавьте папку VirtualBox в исключения антивируса и перезагрузите ПК")
    }
    if ($all -match 'VERR_NO_MEMORY|VERR_NO_PHYS_MEMORY|NO_PAGE_MEMORY|not enough memory') {
        Warn "не хватает памяти — уменьшаю ОЗУ ВМ до 4 ГБ"
        & $vbm modifyvm $vm --memory 4096 2>$null | Out-Null
        $r = Invoke-VmStart $vm
        if ($r.Ok) { return $true }
        $all = $r.Text + "`n" + (Get-VmLogErrors $vm)
    }

    foreach ($fb in $fallbacks) {
        if ($all -notmatch $fb.Pattern) { continue }
        Warn ("ВМ не запустилась, пробую без: {0}" -f $fb.Name)
        foreach ($v in $fb.Fix) { & $vbm @v 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { break } }
        $r = Invoke-VmStart $vm
        if ($r.Ok) {
            Warn ("ВМ запущена без: {0}" -f $fb.Name)
            if ($fb.Name -like "3D*") { Warn "без 3D-ускорения Hyprland в ВМ работать не будет (консоль и установка — будут). Обновите VirtualBox и драйвер видеокарты, затем включите 3D: Настроить → Дисплей → 3D-ускорение" }
            return $true
        }
        $all = $r.Text + "`n" + (Get-VmLogErrors $vm)
    }

    Write-Host ""
    Write-Host "Вывод VirtualBox:" -ForegroundColor Red
    Write-Host $r.Text
    $logs = Get-VmLogErrors $vm
    if ($logs) { Write-Host "Ошибки из журнала ВМ:" -ForegroundColor Red; Write-Host $logs }
    $dir = Get-VmLogDir $vm
    if ($dir) { Write-Host "Полный журнал: $dir\VBox.log" }
    Fail "ВМ не запускается — пришлите текст выше (от строки «Вывод VirtualBox»)"
    return $false
}

# -------------------------------------------------------------- create VM
$exists = (& $vbm list vms) -match "^`"$([regex]::Escape($Name))`" "
$startExisting = $false
if ($exists -and -not $Recreate) {
    Info "ВМ `"$Name`" уже существует (пересоздать с нуля: -Recreate, другая ВМ: -Name ASOS2)"
    $ans = Read-Host "Запустить существующую ВМ `"$Name`"? [Y/n]"
    if ($ans -ne "" -and $ans -notmatch "^[YyДд]") { Fail "отменено" }
    $startExisting = $true
} elseif ($exists) {
    $ans = Read-Host "Удалить существующую ВМ `"$Name`" вместе с её диском? Введите YES"
    if ($ans -ne "YES") { Fail "отменено" }
    & $vbm controlvm $Name poweroff 2>$null | Out-Null
    Start-Sleep -Seconds 2
    VBox unregistervm $Name --delete
}

if (-not $startExisting) {
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
}

Info "запуск ВМ"
if (-not (Start-AsosVm $Name)) { exit 1 }

# ------------------------------------------- type the installer command
Write-Host ""
Write-Host "Команда установщика ASOS для консоли Arch live:" -ForegroundColor Cyan
Write-Host "  $InstallCmd"
Write-Host ""
$isArchIso = (Split-Path $Iso -Leaf) -like "archlinux-*"
if ($isArchIso -and -not $NoAutoType -and -not $script:AlreadyRunning) {
    if ($startExisting) {
        # an existing VM may already have ASOS installed or an installation running: default "no"
        $ans = Read-Host "Ввести команду установщика в ВМ через $BootWaitSeconds с? Только если ВМ загружается с ISO Arch [y/N]"
        $go = $ans -match "^[YyДд]"
    } else {
        $ans = Read-Host "Ввести её в ВМ автоматически через $BootWaitSeconds с (после загрузки live-системы)? [Y/n]"
        $go = ($ans -eq "" -or $ans -match "^[YyДд]")
    }
    if ($go) {
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
