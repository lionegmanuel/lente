# Lente: Webcam iPhone (Windows)
#
# Abre la ventana "Lente" con la camara del iPhone, para "Captura de ventana" en OBS.
# Usa Lente para la PC (lente.exe, en tools\windows\lente-pc) con reconexion, controles y
# telemetria. Si no esta o no arranca (por ejemplo, la app del iPhone es anterior a 1.0 y no
# rota la imagen), usa el modo rapido (ffplay).
#
#   powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File webcam_iphone.ps1 [-SinGirar] [-Rapido] [-VentanaLibre]
#
# Ventana fija de 1920x1080 sin bordes (cambio del 2026-11-16, como scrcpy pero con la resolucion
# fija): OBS captura la ventana al tamano que tiene, asi que con este tamano graba siempre 1080p
# pixel a pixel, sin importar el tamano ni la cantidad de monitores (si la pantalla es mas chica,
# lo que sobra queda afuera y OBS igual graba el cuadro entero). Se abre en la esquina del monitor
# principal y se usa la compu normal con otras ventanas por encima: OBS la sigue capturando tapada.
# Nunca minimizarla: Windows deja de dibujar las ventanas minimizadas y OBS recibe negro. Afuera de
# todas las pantallas tampoco: OBS no la lista ni puede empezar a capturarla (probado).
# -VentanaLibre vuelve a la ventana comun de antes, que cambia de tamano.
param(
    [switch]$SinGirar,
    [switch]$Rapido,
    [switch]$VentanaLibre,
    [int]$Fps = 30,
    [int]$Mbps = 24
)

# Esquina de la ventana fija: la del monitor principal, medido al abrirla
$posicion = $null
if (-not $VentanaLibre) {
    Add-Type -AssemblyName System.Windows.Forms
    $principal = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    # La posicion es la de la imagen: se baja el alto de la barra de titulo para que se vean
    # los botones de minimizar y cerrar (barra + borde + relleno del borde, como Windows la dibuja)
    Add-Type -Namespace Lente -Name Metricas -MemberDefinition '[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);'
    $barra = [Lente.Metricas]::GetSystemMetrics(4) + [Lente.Metricas]::GetSystemMetrics(33) + [Lente.Metricas]::GetSystemMetrics(92)
    $posicion = @($principal.X, ($principal.Y + $barra))
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
        $argumentos += @("--window-x=$($posicion[0])", "--window-y=$($posicion[1])",
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
