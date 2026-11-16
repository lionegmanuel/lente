# Lente · reglas del proyecto

Lente convierte un iPhone en cámara para la PC por cable USB, con la experiencia de scrcpy. Es un fork de scrcpy 4.1 con un backend iOS (`app/src/ios/`) y una app propia para el iPhone (`ios/`). El plan completo está en `docs/plan/`: empezar siempre por `UPDATES.md` (raíz del repo) y después `docs/plan/PLAN.md` y `docs/plan/ESTADO.md`.

## 0 · `UPDATES.md`: leer SIEMPRE al iniciar sesión

**Lo primero en cualquier sesión de trabajo en este repo es leer `UPDATES.md`, sea cual sea la tarea.** Es el resumen de las últimas sesiones: qué se hizo, qué se decidió, qué archivos cambiaron, qué falta probar o decidir y en qué computadora se estaba (laptop con Windows o PC con Fedora). Sirve para retomar enseguida sin reconstruir el contexto a mano ni pedírselo a Manuel.

* **Se lee siempre, sin que Manuel lo pida**, al arrancar y antes de cualquier otra acción.
* **Se escribe o actualiza SOLO cuando Manuel lo pide explícitamente.** Si no lo pide, no se toca: ni se agrega una línea, ni se aprovecha para anotar algo de paso, ni se corrige. El registro técnico de cada tarea sigue yendo a `docs/plan/ESTADO.md`.
* **Retención por días, no por sesiones:** se guardan siempre los **últimos 3 días**. Al agregar un día nuevo que supere ese total, se borra el día completo más antiguo (por cantidad de días, nunca por una fecha fija).
* **Cada sección es un único día** (`## AAAA-MM-DD`) y puede tener **sesiones ilimitadas**: nunca truncar, resumir ni fusionar sesiones de un mismo día por volumen. Cada sesión lleva su propio **título corto** (`###`), va en orden cronológico de la más antigua a la más reciente y se separa de la siguiente con `---`.
* **Cada sesión se entiende sola:** contexto, qué se trabajó y por qué, decisiones, archivos tocados, qué falta (probar, instalar, decidir) y alertas activas (por ejemplo, el vencimiento de Lente y SideStore), para que la próxima sesión, en cualquiera de las dos computadoras, siga solo con esa lectura.

Estas reglas se suman a las de `D:\Documents\MANUEL\DEV\CLAUDE.md` y a las globales de Manuel. Si algo choca, manda este archivo para lo técnico del proyecto.

## Reglas duras

1. **No se publica nada en GitHub** (repositorio, release, fuente de SideStore) hasta que Manuel confirme D2 en `docs/plan/ESTADO.md`.
2. **Credenciales:** el Apple ID, contraseñas y códigos los escribe solo Manuel. Nunca pedirlos, guardarlos ni teclearlos.
3. **Compuertas:** no se empieza una fase sin la compuerta anterior pasada y anotada en `ESTADO.md`.
4. **scrcpy 4.1 manda:** antes de implementar algo del protocolo o del cliente, leer el código del tag `v4.1`. Si difiere del plan, se sigue el código y se corrige el plan en el mismo commit.
5. **Android intacto:** el backend adb y el servidor Java no cambian de comportamiento. Todas las pruebas de scrcpy pasan.
6. **Nada de código LGPL copiado** (libusbmuxd, libimobiledevice). Se reimplementa lo necesario.
7. **Bundle ID fijo** (`digital.velinex.lente`) salvo que Manuel cambie el nombre antes de cerrar la Fase 0.
8. **Sin audio del iPhone** en la versión 1.
9. **Éxito con evidencia:** nada se da por hecho sin CI en verde o la prueba guiada con Manuel registrada.

## Reglas de Velinex que aplican

* Nada se guarda ni se compila en C:. Temporales y builds locales en `D:\Temp\operius\lente\`.
* Procesamiento pesado con GPU (GTX 1650 en la laptop, RX 9060 XT en Fedora) y con el tope del 80% (`VELINEX/Contenido y Marketing/Kit de Postproduccion/herramientas/tope80.py`).
* Procesos se detienen solo por PID, nunca por nombre.
* Sin copias de respaldo propias; lo temporal se borra al terminar.
* **Cero guiones largos y medios** (U+2012 a U+2015) en documentos, mensajes, código y comentarios nuevos. El guion corto solo dentro de palabras, opciones de línea de comandos, rangos y nombres de archivo.
* Documentación en español. Identificadores y comentarios de código en inglés, como el resto de scrcpy.

## Cómo se trabaja

* Rama por fase (`fase-N-nombre`), commits chicos, fusión a `main` al pasar la compuerta.
* Al cerrar cada tarea: una línea en el Registro de `ESTADO.md`.
* Las pruebas con el iPhone se agrupan y se le pasan a Manuel como checklist corto (`PRUEBAS_Y_ACEPTACION.md` §3).
* Ante una decisión que cambia el alcance, el costo o la experiencia de Manuel: preguntar antes y anotarla en `RIESGOS_Y_DECISIONES.md`.
