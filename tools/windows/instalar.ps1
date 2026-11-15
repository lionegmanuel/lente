# Lente: instalacion en Windows, una sola vez
#
#   powershell -ExecutionPolicy Bypass -File tools\windows\instalar.ps1 [-SinCliente]
#
# Revisa lo necesario y crea los accesos directos del Escritorio:
#   1. Apple Mobile Device Service (viene con iTunes descargado de apple.com).
#   2. Python 3 (pythonw.exe) y ffplay (FFmpeg) para el modo rapido. Si falta FFmpeg, lo
#      instala con winget (Gyan.FFmpeg).
#   3. Lente para la PC (lente.exe) del ultimo release, verificado por SHA256, en
#      tools\windows\lente-pc (dentro del repositorio, en el disco D:).
#   4. "Webcam iPhone" y "Webcam iPhone (sin girar)": Lente para la PC, y si no arranca, el
#      modo rapido. "Webcam iPhone (modo rapido)": siempre el modo rapido.
# Se puede volver a correr: reemplaza los accesos directos, no duplica nada.
param([switch]$SinCliente)

$ErrorActionPreference = 'Stop'
$tools = Split-Path -Parent $PSScriptRoot
$rapido = Join-Path $tools 'lente_rapido.py'
$lanzador = Join-Path $PSScriptRoot 'webcam_iphone.ps1'
$fallas = 0
function Bien($t) { Write-Host "[OK] $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "[AVISO] $t" -ForegroundColor Yellow }
function Mal($t) { Write-Host "[FALLA] $t" -ForegroundColor Red; $script:fallas++ }

Write-Host "Lente: Webcam iPhone por cable (Windows)" -ForegroundColor Cyan

# 1. Apple Mobile Device Service
$amds = Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue
if ($amds) { Bien "Apple Mobile Device Service: $($amds.Status)" }
else { Mal "Falta Apple Mobile Device Service: instalar iTunes desde apple.com/itunes/download/win64 (no el de Microsoft Store)" }

# 2. Python y ffplay (modo rapido)
$pythonw = $null
foreach ($c in @((Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source,
                 (Get-Command python.exe -ErrorAction SilentlyContinue).Source)) {
    if ($c) {
        $candidato = Join-Path (Split-Path $c) 'pythonw.exe'
        if ((Test-Path $candidato) -and ($candidato -notlike '*WindowsApps*')) { $pythonw = $candidato; break }
    }
}
if ($pythonw) { Bien "Python: $pythonw" }
else { Mal "Falta Python 3: winget install Python.Python.3.12 (y volver a correr este script)" }

$ffplay = (Get-Command ffplay.exe -ErrorAction SilentlyContinue).Source
if (-not $ffplay) {
    Write-Host "Instalando FFmpeg con winget..."
    winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements | Out-Null
    $ffplay = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffplay.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($ffplay) { [Environment]::SetEnvironmentVariable('LENTE_FFPLAY', $ffplay, 'User') }
}
if ($ffplay) { Bien "ffplay: $ffplay" } else { Mal "Falta ffplay: winget install Gyan.FFmpeg" }

# 3. Lente para la PC
if (-not $SinCliente) {
    $destino = Join-Path $PSScriptRoot 'lente-pc'
    $url = 'https://github.com/lionegmanuel/lente/releases/latest/download'
    $zip = Join-Path $destino 'Lente-PC-windows-x64.zip'
    try {
        New-Item -ItemType Directory -Force $destino | Out-Null
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest "$url/Lente-PC-windows-x64.zip" -OutFile $zip -UseBasicParsing
        # El .sha256 llega como binario: se guarda y se lee como texto
        $sha = "$zip.sha256"
        Invoke-WebRequest "$url/Lente-PC-windows-x64.zip.sha256" -OutFile $sha -UseBasicParsing
        $esperado = ((Get-Content $sha -Raw).Trim() -split '\s+')[0].ToLower()
        Remove-Item $sha
        $real = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
        if ($real -ne $esperado) { throw "SHA256 no coincide ($real, esperado $esperado)" }
        # Versiones viejas: se borran si se puede (si un archivo esta en uso, quedan; el
        # lanzador usa siempre la version mas alta)
        Get-ChildItem $destino -Directory | ForEach-Object {
            try { Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop } catch { Aviso "Queda $($_.Exception.Message)" }
        }
        Expand-Archive $zip -DestinationPath $destino -Force
        Remove-Item $zip
        $exe = Get-ChildItem (Join-Path $destino '*\lente.exe') |
            Sort-Object { try { [version]($_.Directory.Name -replace '^.*-v', '') } catch { [version]'0.0' } } -Descending |
            Select-Object -First 1
        Bien "Lente para la PC: $($exe.FullName)"
    } catch {
        Remove-Item $zip, "$zip.sha256" -ErrorAction SilentlyContinue
        Aviso "No se pudo bajar Lente para la PC ($($_.Exception.Message)): queda el modo rapido."
    }
}

# 4. Accesos directos
if ($pythonw -and $ffplay) {
    $escritorio = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $accesos = @(
        @{ Nombre = 'Webcam iPhone'; Destino = $powershell
           Args = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$lanzador`"" },
        @{ Nombre = 'Webcam iPhone (sin girar)'; Destino = $powershell
           Args = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$lanzador`" -SinGirar" },
        @{ Nombre = 'Webcam iPhone (modo rapido)'; Destino = $pythonw
           Args = "`"$rapido`" --girar" }
    )
    foreach ($a in $accesos) {
        $lnk = $shell.CreateShortcut((Join-Path $escritorio "$($a.Nombre).lnk"))
        $lnk.TargetPath = $a.Destino
        $lnk.Arguments = $a.Args
        $lnk.WorkingDirectory = $tools
        $lnk.Description = 'Lente: camara del iPhone por cable para OBS'
        $lnk.IconLocation = 'C:\Windows\System32\shell32.dll,203'
        $lnk.WindowStyle = 7
        $lnk.Save()
    }
    Bien "Accesos directos: 'Webcam iPhone', 'Webcam iPhone (sin girar)' y 'Webcam iPhone (modo rapido)'"
}

if ($fallas -eq 0) {
    Write-Host "Listo. Uso diario: Lente abierta en el iPhone, cable, doble clic en 'Webcam iPhone' y en OBS 'Captura de ventana' de la ventana 'Lente'." -ForegroundColor Green
} else {
    Write-Host "$fallas falla(s): arreglarlas y volver a correr este script." -ForegroundColor Red
    exit 1
}
