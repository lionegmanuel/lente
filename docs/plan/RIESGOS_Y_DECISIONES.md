# Lente · Riesgos y registro de decisiones

## 1 · Riesgos

| # | Riesgo | Prob. | Impacto | Mitigación | Plan B |
|---|---|---|---|---|---|
| R1 | usbmux exige que el iPhone «confíe» en la PC para conectar a un puerto de la app | Media | Bajo | Fase 0 lo prueba. Si lo exige, el cliente lo detecta y explica el paso | En Linux, `idevicepair pair` (libimobiledevice, código abierto) |
| R2 | Una actualización de iOS rompe SideStore o la renovación | Media | Alto | Seguir los avisos de SideStore; no actualizar iOS el día que sale sin revisar | Sideloadly cada 7 días; cuenta paga |
| R3 | El iPhone se calienta y baja cuadros en 4K60 o en sesiones largas | Alta en 4K60 | Medio | Por defecto 1080p60; telemetría y aviso en «serious»; sin funda; iPhone en el USB-C | `--thermal-auto` explícito; 4K a 30 |
| R4 | El codificador de baja latencia no está disponible para HEVC en iOS 16 o agrega delay | Media | Medio | Medir en Fase 1 y 5; H.264 por defecto | HEVC solo para 4K |
| R5 | scrcpy cambia su protocolo o su estructura en versiones nuevas | Alta a largo plazo | Medio | Fijado en 4.1; diff aislado en `app/src/ios/`; pruebas de integración | Quedarse en la versión anterior hasta adaptar |
| R6 | Falta Apple Mobile Device Service en Windows | Alta en usuarios nuevos | Bajo | Detección con mensaje claro y enlace a Apple Devices | Driver de iTunes |
| R7 | Delay mayor que la meta | Baja a media | Alto | Sin cuadros B, sin estabilización, colas de un cuadro, TCP sin Nagle, medición temprana en Fase 1 | Ajustar tasa de bits e intervalo de cuadro clave; sockets BSD |
| R8 | Interrupciones de iOS (llamadas, Centro de Control) cortan la cámara | Alta | Bajo | Reanudación automática y reconexión del cliente | Modo avión o «No molestar» al grabar (guía de usuario) |
| R9 | Límite de 10 identificadores de app por semana con Apple ID gratis | Baja | Medio | Bundle ID fijo desde la Fase 0 | Esperar 7 días |
| R10 | Licencias: código LGPL de libusbmuxd en un proyecto Apache 2.0 | Baja | Alto | Reimplementar el subconjunto de usbmux sin copiar código | Enlazar dinámicamente libusbmuxd en Linux como dependencia del sistema |
| R11 | Marca: usar «scrcpy» en el nombre del producto | Baja | Medio | Nombre propio (D3), aviso de origen en `--version` y NOTICE | |
| R12 | Fedora sin códecs H.264 o HEVC en FFmpeg | Media | Medio | Documentar RPM Fusion; compilar en CI con FFmpeg completo | Binario con FFmpeg propio |
| R13 | La decodificación por GPU no mejora por la copia a memoria con SDL | Media | Bajo | Medir; activar solo donde conviene | Software para 1080p |
| R14 | Revisión de App Store rechaza la app por depender de un cliente de escritorio | Media | Medio (solo si se lanza) | Ficha clara y enlace al cliente, como Camo y EpocCam | Seguir con SideStore y releases de GitHub |

## 2 · Registro de decisiones

| # | Fecha | Decisión | Por qué | Quién |
|---|---|---|---|---|
| D1 | 2026-11-15 | Firma gratis con SideStore y un Apple ID gratis aparte, solo para firmar; Sideloadly de plan B; cuenta paga solo para lanzar | Costo cero; la cuenta principal de Manuel no se expone. SideStore funciona en iOS 26 (la renovación se rompió en 26.4 y se arregló en abril de 2026) | Manuel |
| D2 | 2026-11-15 | Repositorio público, Apache 2.0 | Minutos ilimitados de macOS en CI, confianza para lanzar, licencia heredada de scrcpy | Manuel |
| D3 | 2026-11-15 | Nombre definitivo «Lente» | Corto, se entiende en español, italiano y portugués, y en inglés suena a «lens»; libre en GitHub | Manuel |
| D4 | 2026-11-15 | iOS mínimo 16.0; el iPhone de Manuel tiene iOS 26 | Cubre a la mayoría de los iPhone con soporte; Modo desarrollador desde iOS 16 | Manuel |
| D5 | 2026-11-15 | Fork de scrcpy 4.1 con backend iOS | Réplica exacta de la experiencia, Android incluido, menos trabajo que un cliente propio, más robusto que un adb falso | Manuel aprobó el enfoque |
| D6 | 2026-11-15 | Puerto 27183 solo en loopback | Mismo puerto que scrcpy; nada expuesto a la red | Arquitecto |
| D7 | 2026-11-15 | Sin audio del iPhone en v1 | Manuel: el micrófono va siempre aparte (BY-V por USB) | Manuel |
| D8 | 2026-11-15 | Por defecto 1080p60 H.264 16 Mbps | Igual a lo que Manuel usaba con scrcpy y el POCO; menor delay y temperatura | Arquitecto, revisable en Fase 5 |
| D9 | 2026-11-15 | Swift nativo, sin dependencias | Tamaño mínimo y menor delay; no hace falta multiplataforma porque Android ya tiene scrcpy | Arquitecto, Manuel de acuerdo |
| D10 | 2026-11-15 | Compilar en GitHub Actions | No hay Mac; gratis en repositorio público | Arquitecto |

Toda decisión nueva se agrega acá con fecha y razón. Si una medición cambia una meta, también.
