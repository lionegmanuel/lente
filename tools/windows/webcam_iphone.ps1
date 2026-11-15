# Lente: Webcam iPhone (Windows)
#
# Abre la ventana "Lente" con la camara del iPhone, para "Captura de ventana" en OBS.
# Usa Lente para la PC (lente.exe, en tools\windows\lente-pc) con reconexion, controles y
# telemetria. Si no esta o no arranca (por ejemplo, la app del iPhone es anterior a 1.0 y no
# rota la imagen), usa el modo rapido (ffplay).
#
#   powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File webcam_iphone.ps1 [-SinGirar] [-Rapido]
param(
    [switch]$SinGirar,
    [switch]$Rapido,
    [int]$Fps = 30,
    [int]$Mbps = 24
)

$tools = Split-Path -Parent $PSScriptRoot
$lente = Get-ChildItem (Join-Path $PSScriptRoot 'lente-pc\*\lente.exe') -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$registro = 'D:\Temp\operius\lente'
if (-not (Test-Path 'D:\')) { $registro = Join-Path $env:TEMP 'lente' }
New-Item -ItemType Directory -Force $registro | Out-Null
$log = Join-Path $registro 'webcam_iphone.log'

function Registrar($texto) {
    Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $texto) -Encoding UTF8
}

if ($lente -and -not $Rapido) {
    $argumentos = @('--ios', '--window-title=Lente', "--camera-fps=$Fps", "--video-bit-rate=${Mbps}M",
                    '--ios-reconnect=3600', '--pause-on-exit=false')
    if (-not $SinGirar) { $argumentos += '--capture-orientation=180' }
    Registrar ("Lente para la PC: {0} {1}" -f $lente.FullName, ($argumentos -join ' '))
    # Por cmd oculto, como scrcpy-noconsole.vbs: la consola no se ve y la ventana de video si
    $salida = Join-Path $registro 'lente.log'
    $linea = '/c ""{0}" {1} > "{2}" 2>&1"' -f $lente.FullName, ($argumentos -join ' '), $salida
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList $linea -WorkingDirectory $lente.DirectoryName `
        -WindowStyle Hidden -PassThru
    # Hasta 20 s: si la sesion arranca, listo; si lente.exe se cierra (sin iPhone, app vieja), modo rapido.
    # Si sigue abierto esperando que se abra la app en el iPhone, se queda (reconecta solo).
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        if ($p.HasExited) { break }
        if ((Test-Path $salida) -and (Select-String -Path $salida -Pattern 'App del iPhone:' -Quiet)) { exit 0 }
    }
    if (-not $p.HasExited) {
        exit 0
    }
    Registrar ("Lente para la PC no arranco (codigo {0}): paso al modo rapido" -f $p.ExitCode)
}

# Modo rapido
$pythonw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
if (-not $pythonw) {
    $python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
    if ($python) { $pythonw = Join-Path (Split-Path $python) 'pythonw.exe' }
}
$args2 = @("`"$(Join-Path $tools 'lente_rapido.py')`"", "--fps", "$Fps", "--mbps", "$Mbps")
if (-not $SinGirar) { $args2 += '--girar' }
Registrar ("Modo rapido: {0} {1}" -f $pythonw, ($args2 -join ' '))
Start-Process -FilePath $pythonw -ArgumentList $args2 -WorkingDirectory $tools
