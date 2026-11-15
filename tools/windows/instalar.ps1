# Lente · instalacion en Windows, una sola vez
#
#   powershell -ExecutionPolicy Bypass -File tools\windows\instalar.ps1
#
# Revisa lo necesario y crea los accesos directos del Escritorio:
#   1. Apple Mobile Device Service (viene con iTunes descargado de apple.com).
#   2. Python 3 (el de pythonw.exe, sin consola).
#   3. ffplay (FFmpeg). Si falta, lo instala con winget (Gyan.FFmpeg).
#   4. "Webcam iPhone" (imagen girada 180 grados: iPhone horizontal con el cable hacia la PC)
#      y "Webcam iPhone (sin girar)".
# Se puede volver a correr: reemplaza los accesos directos, no duplica nada.

$ErrorActionPreference = 'Stop'
$tools = Split-Path -Parent $PSScriptRoot
$script = Join-Path $tools 'lente_rapido.py'
$fallas = 0
function Bien($t) { Write-Host "[OK] $t" -ForegroundColor Green }
function Mal($t) { Write-Host "[FALLA] $t" -ForegroundColor Red; $script:fallas++ }

Write-Host "Lente: Webcam iPhone por cable (Windows)" -ForegroundColor Cyan

# 1. Apple Mobile Device Service
$amds = Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue
if ($amds) { Bien "Apple Mobile Device Service: $($amds.Status)" }
else { Mal "Falta Apple Mobile Device Service: instalar iTunes desde apple.com/itunes/download/win64 (no el de Microsoft Store)" }

# 2. Python
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

# 3. ffplay
$ffplay = (Get-Command ffplay.exe -ErrorAction SilentlyContinue).Source
if (-not $ffplay) {
    Write-Host "Instalando FFmpeg con winget..."
    winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements | Out-Null
    $ffplay = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffplay.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if ($ffplay) { Bien "ffplay: $ffplay" } else { Mal "Falta ffplay: winget install Gyan.FFmpeg" }

# 4. Accesos directos
if ($pythonw -and $ffplay) {
    $escritorio = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    foreach ($a in @(@{ Nombre = 'Webcam iPhone'; Extra = ' --girar' },
                     @{ Nombre = 'Webcam iPhone (sin girar)'; Extra = '' })) {
        $lnk = $shell.CreateShortcut((Join-Path $escritorio "$($a.Nombre).lnk"))
        $lnk.TargetPath = $pythonw
        $lnk.Arguments = "`"$script`"$($a.Extra)"
        $lnk.WorkingDirectory = $tools
        $lnk.Description = 'Lente: camara del iPhone por cable para OBS'
        $lnk.IconLocation = 'C:\Windows\System32\shell32.dll,203'
        $lnk.Save()
    }
    # ffplay fuera del PATH (recien instalado): el acceso directo lo encuentra por LENTE_FFPLAY
    if (-not (Get-Command ffplay.exe -ErrorAction SilentlyContinue)) {
        [Environment]::SetEnvironmentVariable('LENTE_FFPLAY', $ffplay, 'User')
    }
    Bien "Accesos directos en el Escritorio: 'Webcam iPhone' y 'Webcam iPhone (sin girar)'"
}

if ($fallas -eq 0) {
    Write-Host "Listo. Uso diario: Lente abierta en el iPhone, cable, doble clic en 'Webcam iPhone' y en OBS 'Captura de ventana' de '[ffplay.exe]: Lente'." -ForegroundColor Green
} else {
    Write-Host "$fallas falla(s): arreglarlas y volver a correr este script." -ForegroundColor Red
    exit 1
}
