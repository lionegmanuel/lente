# Lente: Webcam iPhone (Windows)
#
# Abre la ventana "Lente" con la camara del iPhone, para "Captura de ventana" en OBS.
# Usa Lente para la PC (lente.exe, en tools\windows\lente-pc) con reconexion, controles y
# telemetria. Si no esta o no arranca (por ejemplo, la app del iPhone es anterior a 1.0 y no
# rota la imagen), usa el modo rapido (ffplay).
#
#   powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File webcam_iphone.ps1 [-SinGirar] [-Rapido] [-VentanaLibre]
#
# Ventana fija de 1920x1080 sin bordes y fuera de la vista (cambio del 2026-11-16): OBS captura la
# ventana al tamano que tiene, asi que con este tamano graba siempre 1080p pixel a pixel, con uno,
# dos o los monitores que sean y de cualquier resolucion. La ventana queda a la izquierda de todo
# el escritorio (sea cual sea al abrirla), no ocupa ninguna pantalla y OBS la sigue capturando
# (probado). Se ve en la vista previa de OBS; Alt+Tab la enfoca para los atajos. Nunca minimizarla:
# Windows deja de dibujar las ventanas minimizadas y OBS recibe negro.
# -Visible la abre en la esquina del monitor principal (mismo tamano); -VentanaLibre, la ventana comun.
param(
    [switch]$SinGirar,
    [switch]$Rapido,
    [switch]$VentanaLibre,
    [switch]$Visible,
    [int]$Fps = 30,
    [int]$Mbps = 24
)

# Esquina de la ventana fija: a la izquierda de todo el escritorio virtual, medido al abrirla
$posicion = $null
if (-not $VentanaLibre) {
    Add-Type -AssemblyName System.Windows.Forms
    if ($Visible) {
        $principal = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $posicion = @($principal.X, $principal.Y)
    } else {
        $escritorio = [System.Windows.Forms.SystemInformation]::VirtualScreen
        # 1 pixel adentro del escritorio: Windows no deja empezar a capturar (WGC) una ventana que
        # nace afuera de todas las pantallas (OBS: winrt_capture_init 0x80070057, 2026-11-16)
        $posicion = @(($escritorio.Left - 1919), $escritorio.Top)
    }
}

$tools = Split-Path -Parent $PSScriptRoot
# La version mas alta (carpetas Lente-PC-windows-x64-vX.Y.Z)
$lente = Get-ChildItem (Join-Path $PSScriptRoot 'lente-pc\*\lente.exe') -ErrorAction SilentlyContinue |
    Sort-Object { try { [version]($_.Directory.Name -replace '^.*-v', '') } catch { [version]'0.0' } } -Descending |
    Select-Object -First 1
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
    if ($posicion) {
        $argumentos += @('--window-borderless', "--window-x=$($posicion[0])", "--window-y=$($posicion[1])",
                         '--window-width=1920', '--window-height=1080')
    }
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
if ($posicion) { $args2 += @('--fija', "$($posicion[0])", "$($posicion[1])") }
Registrar ("Modo rapido: {0} {1}" -f $pythonw, ($args2 -join ' '))
Start-Process -FilePath $pythonw -ArgumentList $args2 -WorkingDirectory $tools
