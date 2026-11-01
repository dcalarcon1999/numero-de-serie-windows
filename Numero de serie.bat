@echo off
title Numero de serie
rem Ejecuta el codigo PowerShell que esta al final de este archivo
rem Compatible con Windows 7 (PowerShell 2.0), Windows 10 y Windows 11
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$f = [IO.File]::ReadAllText('%~f0'); Invoke-Expression $f.Substring($f.IndexOf('#PS' + 'START'))"
echo.
pause
goto :eof

#PSSTART
# Se usa Get-WmiObject (y no Get-CimInstance ni Get-NetIP*/Get-PhysicalDisk)
# porque es lo unico disponible en PowerShell 2.0 de Windows 7.

# --- Marca y modelo ---
$cs     = Get-WmiObject Win32_ComputerSystem
$marca  = ([string]$cs.Manufacturer).Trim()
$modelo = ([string]$cs.Model).Trim()

# --- Numero de serie (BIOS, o placa base si la BIOS trae un valor de relleno) ---
$sn = [string](Get-WmiObject Win32_BIOS).SerialNumber
$origen = 'BIOS'
if ($sn -match '^\s*$|O\.E\.M|Default|None|System Serial|^0+$') {
    $sn = [string](Get-WmiObject Win32_BaseBoard).SerialNumber
    $origen = 'Placa base'
}
$sn = $sn.Trim()

# --- IPv4 (prioriza el adaptador que tiene puerta de enlace) ---
$adaptadores = @(Get-WmiObject Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE')
$conGateway  = @($adaptadores | Where-Object { $_.DefaultIPGateway })
if ($conGateway.Count -gt 0) { $adaptadores = $conGateway }
$ip = @($adaptadores | ForEach-Object { $_.IPAddress } |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^(127\.|169\.254\.)' }) -join ' / '
if (-not $ip) { $ip = 'Sin IP' }

# --- Sistema operativo ---
$os = Get-WmiObject Win32_OperatingSystem
$reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$so = ([string]$os.Caption -replace '^Microsoft\s+', '').Trim()
if ($reg.DisplayVersion)  { $so += ' ' + $reg.DisplayVersion }   # Windows 10 20H2 en adelante / 11
elseif ($reg.ReleaseId)   { $so += ' ' + $reg.ReleaseId }        # Windows 10 antiguos
if ($os.CSDVersion)       { $so += ' ' + $os.CSDVersion }        # Service Pack (Windows 7)
$so += ' (build ' + $os.BuildNumber + ', ' + $os.OSArchitecture + ')'

# --- Almacenamiento (tipo y capacidad comercial en GB) ---
$discos = @()
# Windows 8 en adelante: MSFT_PhysicalDisk distingue HDD / SSD / NVMe
$fisicos = @(Get-WmiObject -Namespace 'root\Microsoft\Windows\Storage' -Class MSFT_PhysicalDisk -ErrorAction SilentlyContinue |
             Where-Object { $_.BusType -ne 7 } | Sort-Object DeviceId)   # 7 = USB
if ($fisicos.Count -gt 0) {
    foreach ($d in $fisicos) {
        $tipo = switch ([int]$d.MediaType) { 3 { 'HDD' } 4 { 'SSD' } default { 'Disco' } }
        if ([int]$d.BusType -eq 17) { $tipo = 'SSD NVMe' }                 # 17 = NVMe
        $gb = [math]::Round($d.Size / 1e9)
        $discos += New-Object PSObject -Property @{ Corto = "$tipo $gb GB"; Detalle = "$tipo $gb GB - " + ([string]$d.FriendlyName).Trim() }
    }
} else {
    # Windows 7: Win32_DiskDrive no informa si es HDD o SSD; solo se marca SSD si el modelo lo dice
    foreach ($d in Get-WmiObject Win32_DiskDrive | Where-Object { $_.InterfaceType -ne 'USB' -and $_.MediaType -match 'Fixed' } | Sort-Object Index) {
        $tipo = if ($d.Model -match 'SSD|NVMe|Solid') { 'SSD' } else { 'Disco' }
        $gb = [math]::Round($d.Size / 1e9)
        $discos += New-Object PSObject -Property @{ Corto = "$tipo $gb GB"; Detalle = "$tipo $gb GB - " + ([string]$d.Model).Trim() }
    }
}
$almacenamiento = ($discos | ForEach-Object { $_.Corto }) -join ' + '
if (-not $almacenamiento) { $almacenamiento = 'No detectado' }

# --- RAM instalada y slots ---
$tiposRam = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
$modulos = @(Get-WmiObject Win32_PhysicalMemory)
$ramGB = [math]::Round(($modulos | Measure-Object Capacity -Sum).Sum / 1GB)
$tipoRam = $null
if ($modulos.Count -gt 0) {
    # SMBIOSMemoryType solo existe en Windows 10/11; en Windows 7 se usa MemoryType
    $codigo = [int]$modulos[0].SMBIOSMemoryType
    if (-not $codigo) { $codigo = [int]$modulos[0].MemoryType }
    $tipoRam = $tiposRam[$codigo]
}
$ram = "$ramGB GB"
if ($tipoRam) { $ram += " $tipoRam" }

$slotsTotal = (Get-WmiObject Win32_PhysicalMemoryArray | Where-Object { $_.Use -eq 3 } |
               Measure-Object MemoryDevices -Sum).Sum
$slotsUsados = $modulos.Count
if ($slotsTotal -ge $slotsUsados) {
    $slotsLibres = $slotsTotal - $slotsUsados
    $slots = "$slotsUsados de $slotsTotal usados ($slotsLibres libre$(if ($slotsLibres -ne 1) { 's' }))"
} else {
    $slots = "$slotsUsados usados (total no informado por la BIOS)"
}

# --- Mostrar ---
Write-Host ''
Write-Host ('Equipo:          ' + $env:COMPUTERNAME)
Write-Host ('Marca:           ' + $marca)
Write-Host ('Modelo:          ' + $modelo)
Write-Host ('IPv4:            ' + $ip)
Write-Host ('Sistema:         ' + $so)
Write-Host ''
Write-Host 'Almacenamiento:'
if ($discos.Count -gt 0) { $discos | ForEach-Object { Write-Host ('  ' + $_.Detalle) } } else { Write-Host '  No detectado' }
Write-Host ''
Write-Host ('RAM instalada:   ' + $ram)
Write-Host ('Slots de RAM:    ' + $slots)
foreach ($m in $modulos) {
    $mhz = if ($m.ConfiguredClockSpeed) { $m.ConfiguredClockSpeed } else { $m.Speed }
    Write-Host ('  {0}: {1} GB {2} MHz' -f $m.DeviceLocator, [math]::Round($m.Capacity / 1GB), $mhz)
}
Write-Host ''
Write-Host -NoNewline 'Numero de serie: '
Write-Host $sn -ForegroundColor Green
Write-Host ('(origen: ' + $origen + ')') -ForegroundColor DarkGray

# --- Linea concatenada ---
$linea = @($marca, $modelo, $sn, $ip, $so, $almacenamiento, $ram, $slots) -join ', '
Write-Host ''
Write-Host 'Marca, Modelo, Numero de serie, IPv4, Sistema, Almacenamiento, RAM, Slots:'
Write-Host $linea -ForegroundColor Yellow
# Set-Clipboard existe desde PowerShell 5; en Windows 7 se usa clip.exe
if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) { Set-Clipboard -Value $linea } else { $linea | clip.exe }
Write-Host ''
Write-Host 'Linea copiada al portapapeles.' -ForegroundColor Cyan
