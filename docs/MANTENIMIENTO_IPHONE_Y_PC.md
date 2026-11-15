# Lente · Mantenimiento del iPhone y de la PC

Lo que queda por hacer una sola vez para no tener que renovar Lente a mano, y la limpieza de la laptop. Escrito el 2026-11-15 para hacerlo en otro momento: no es urgente.

Cada paso indica dónde se hace: 📱 en el iPhone, 💻 en la PC.

## Pendientes (marcar al hacerlos)

- [ ] **Renovación automática de Lente** con una automatización de Atajos (sección 1). Hasta que esté hecha, renovar a mano antes del vencimiento (sección 2).
- [ ] **Desinstalar iloader** de la laptop (sección 4).
- [ ] Opcional: sacar **iTunesHelper** del inicio de Windows (sección 4).

**Fechas:** Lente se instaló el 2026-11-15 y vence el **2026-11-22** si no se renueva. Cada renovación suma 7 días desde ese momento.

---

## 1. Renovación automática (una sola vez, unos 5 minutos)

### Por qué hace falta

Lente está firmada con una cuenta gratis de Apple: la firma dura **7 días**. Pasado ese plazo, Lente no abre hasta renovarla (no se pierde nada, no hay que reinstalar). SideStore renueva desde el mismo iPhone, sin PC, pero alguien tiene que pedírselo. Esta automatización se lo pide **todos los días**: así nunca llega al vencimiento y, si un día falla (iPhone apagado o sin internet), quedan 6 días de margen.

La renovación necesita **LocalDevVPN conectada**: es la que deja a SideStore instalar apps en el propio iPhone. La automatización la conecta sola.

### Paso a paso

1. 📱 Abrir la app **Atajos** (viene con el iPhone).
2. 📱 Abajo, pestaña **Automatización** › **«+»** (o **Nueva automatización**).
3. 📱 Elegir **Hora del día**:
   * Hora: una en la que el iPhone suela estar prendido y con internet (por ejemplo **13:00**).
   * Repetir: **Diariamente**.
   * Marcar **Ejecutar inmediatamente** (no **Ejecutar tras confirmación**) y apagar **Notificar al ejecutar** si se quiere que no avise.
   * **Siguiente**.
4. 📱 **Nueva automatización en blanco** (o **Crear atajo**) y agregar estas cuatro acciones, en este orden (se buscan con la barra de búsqueda de acciones):

   | Orden | Acción | Cómo dejarla |
   |---|---|---|
   | 1 | **Configurar VPN** (en inglés, «Set VPN») | VPN: **LocalDevVPN** · acción: **Conectar** |
   | 2 | **Abrir app** | App: **SideStore** |
   | 3 | **Esperar** | **5** segundos |
   | 4 | **Refresh All Apps** (de SideStore; buscar «SideStore» en las acciones) | Sin opciones |

   El paso 2 importa: si SideStore está cerrado del todo, la acción 4 puede fallar con «You are not signed in» (problema conocido de SideStore, `SideStore/SideStore#1584`). Abrirla antes lo evita.
5. 📱 **OK** para guardar.

### Probarla

1. 📱 En **Atajos › Automatización**, tocar la automatización recién creada y **Ejecutar** (o esperar a la hora elegida).
2. 📱 Abrir **SideStore › My Apps**: al lado de **Lente** y de **SideStore** tiene que decir **7 DAYS**.
3. Si dice 7 DAYS, listo para siempre. Anotar la fecha en `docs/plan/ESTADO.md`.

### Si algo falla

| Síntoma | Qué hacer |
|---|---|
| En **Configurar VPN** no aparece LocalDevVPN | Abrir LocalDevVPN una vez y tocar **Connect** (registra la VPN en el iPhone), y volver a armar la acción. Si igual no aparece, buscar en las acciones **LocalDevVPN** (puede traer su propia acción de conectar) y usar esa en el lugar de la acción 1. |
| No aparece **Refresh All Apps** | Abrir SideStore una vez (registra sus acciones en Atajos) y buscar de nuevo «SideStore» en las acciones. |
| «You are not signed in» | Abrir SideStore › **Settings** y volver a iniciar sesión con el Apple ID (lo escribe solo Manuel). Revisar que la acción 2 (Abrir app SideStore) esté antes de la 4. |
| Error de conexión o «could not connect» | LocalDevVPN no quedó conectada: abrirla, tocar **Connect** y ejecutar la automatización de nuevo. Revisar que no haya otra VPN prendida al mismo tiempo. |
| La automatización no corrió | Ver que diga **Ejecutar inmediatamente** y que el iPhone estuviera prendido a esa hora. |
| Error con el «pairing file» (archivo de emparejamiento) | Puede vencer al actualizar iOS. Se reemplaza con la guía de SideStore: `docs.sidestore.io/docs/advanced/pairing-file` (en la PC con iloader, sección «Manage Pairing File»). |

---

## 2. Renovación a mano (respaldo, 1 minuto)

Mientras no esté la automatización, o si falla:

1. 📱 Abrir **LocalDevVPN** y tocar **Connect** (que diga «Connected»).
2. 📱 Abrir **SideStore › My Apps**.
3. 📱 Tocar el contador de días al lado de **Lente** (y al lado de **SideStore**). Si pregunta por el certificado, **Refresh Now**.
4. 📱 Tiene que quedar en **7 DAYS**.

Si Lente ya venció (no abre), es lo mismo: renovar desde SideStore. No hay que reinstalar ni se pierde nada.

## 3. Límites de la cuenta gratis

* Máximo **3 apps** instaladas por fuera de la App Store. SideStore y Lente ocupan 2.
* Máximo **10 apps nuevas por semana**. Actualizar Lente no gasta cupo (es la misma app, `digital.velinex.lente`). Nunca cambiar ese identificador.
* Actualizar Lente a una versión nueva: 📱 Safari › `github.com/lionegmanuel/lente/releases` › descargar el `.ipa` › SideStore › My Apps › **«+»** › Descargas › el `.ipa`. Reemplaza la anterior sin borrar nada. (Más adelante, con la fuente de SideStore de la Fase 6, va a alcanzar con tocar «Update».)

---

## 4. Limpieza de la laptop con Windows

| Programa | ¿Desinstalar? | Por qué |
|---|---|---|
| **iloader** | **Sí** | Solo sirvió para instalar SideStore la primera vez. Se vuelve a bajar (`github.com/nab138/iloader/releases`, el `x64.msi`) únicamente si hay que reinstalar SideStore o cambiar el archivo de emparejamiento. |
| **iTunes** | **No** | Instala «Apple Mobile Device Service», el servicio que deja a Lente hablar con el iPhone por el cable en Windows. Sin él, «Webcam iPhone» deja de andar. iTunes en sí nunca hace falta abrirlo. |
| Apple Mobile Device Support, Apple Application Support | **No** | Son partes de iTunes que usa el servicio. |
| FFmpeg, Python | **No** | Los usa «Webcam iPhone» (ffplay y `lente_rapido.py`). |

Pasos:

1. 💻 **Desinstalar iloader:** Configuración › Aplicaciones › Aplicaciones y características › buscar **iloader** › **Desinstalar**.
2. 💻 **Opcional, iTunesHelper:** Administrador de tareas (Ctrl+Mayús+Esc) › pestaña **Inicio** › **iTunesHelper** › **Deshabilitar**. Evita que arranque con Windows; el servicio que usa Lente sigue funcionando igual.
3. 💻 Comprobar que todo sigue bien: Lente abierta en el iPhone, cable y doble clic en **Webcam iPhone**. Tiene que aparecer la ventana con la cámara.

En el iPhone no se desinstala nada: **SideStore** renueva Lente y **LocalDevVPN** es lo que le permite hacerlo.

En Linux no hay nada de esto: no se usan iTunes ni iloader (ahí el cable lo maneja `usbmuxd`, ver `docs/MODO_RAPIDO.md`).
