# MEJORAS REALIZADAS — NOVA Browser (Auditoría Profunda iPad Air 2 / iPadOS 15.8.9)

Este documento resume la auditoría técnica completa y las optimizaciones aplicadas al proyecto Xcode **NOVA Browser**, manteniendo compatibilidad estricta con **iPad Air 2 (arm64 / A8X / 2 GB RAM)**, **iPadOS 15.8.9 (`IPHONEOS_DEPLOYMENT_TARGET = 15.0`)** y compilación en **CodeMagic (`xcode: latest`)**.

---

## 1. Archivos modificados y creados

- `NOVABrowser/App/AppDelegate.swift`
- `NOVABrowser/Storage/PersistenceStore.swift`
- `NOVABrowser/Storage/PrivacyDataManager.swift`
- `NOVABrowser/Storage/DownloadManager.swift`
- `NOVABrowser/WebKit/WebViewPool.swift`
- `NOVABrowser/WebKit/WebViewRepresentable.swift`
- `NOVABrowser/Core/FilterListParser.swift`
- `NOVABrowser/Resources/default_blocklist.json`
- `NOVABrowser/ViewModels/BrowserViewModel.swift`
- `NOVABrowser/Views/Browser/MainBrowserView.swift`
- `NOVABrowser/Views/Browser/TopToolbarView.swift`
- `NOVABrowser/Views/Library/PasswordsSheetView.swift`
- `NOVABrowser/Views/Settings/SettingsView.swift`
- `NOVABrowserTests/NOVABrowserTests.swift`
- `MEJORAS-REALIZADAS.md` *(nuevo)*

---

## 2. Problemas encontrados durante la auditoría

1. **Bloqueos en el hilo principal por E/S síncrona (`PersistenceStore`, `PrivacyDataManager`, `BrowserViewModel`)**:
   - `PersistenceStore.save(...)` serializaba y escribía archivos JSON (`history.json`, `tabs_snapshot.json`, `settings.json`, `bookmarks.json`) de forma síncrona en el hilo principal.
   - `BrowserViewModel.recordBlockedItems` guardaba `settings.json` en disco cada vez que se ocultaba un contenedor o se bloqueaba una petición.
   - `PrivacyDataManager.syncCookiesToPersistentBackup()` ejecutaba `NSKeyedArchiver` sin limitación de frecuencia en *cada* `didFinish` de navegación (además de usar `NSKeyedUnarchiver.unarchiveTopLevelObjectWithData` obsoleto en iOS 15).
2. **Caché HTTP por defecto insuficiente (`AppDelegate`)**:
   - `URLCache.shared` mantenía el tamaño mínimo por defecto de iOS (~4 MB RAM / ~20 MB disco), generando recargas repetidas y errores parciales en páginas con muchos recursos o reproductores multimedia.
3. **Captura errónea de manifiestos de vídeo como descargas (`WebViewRepresentable`)**:
   - `decidePolicyFor navigationResponse` convertía cualquier respuesta con `!navigationResponse.canShowMIMEType` en `.download`, sin distinguir `isForMainFrame` ni excluir manifiestos/subtítulos de streaming (`.m3u8`, `.mpd`, `mpegurl`, `.vtt`).
4. **Sobreescritura de `requestFullscreen` rompiendo controles propios en reproductores de terceros (`WebViewPool`)**:
   - El hook temprano `novaEnterFullscreen` forzaba `video.webkitEnterFullscreen()` antes de probar el `requestFullscreen` nativo del contenedor (`origReqFS`), eliminando controles personalizados, selectores de episodio o subtítulos HTML/VTT en reproductores de terceros (JWPlayer, Video.js, Plyr, embeds de anime).
5. **Carga excesiva de CPU/JS en YouTube y Shorts (`WebViewPool`)**:
   - Un `MutationObserver` global observaba todo `document.body` (`subtree: true`, `attributes: true`) y lanzaba `sweepAdContainers()` con 18 selectores cada 180 ms incluso al deslizar Shorts.
   - Un `setInterval(..., 400)` consultaba `location.href` constantemente.
   - El salto de anuncios SSAI (`adVideo.currentTime` / `playbackRate = 16`) se reintentaba en bucle cada 180 ms sin control por anuncio, pudiendo provocar trabas o errores de buffering.
   - El botón flotante HTML `#nova-yt-pip-fab` podía quedar superpuesto sobre subtítulos o controles en pantalla de Shorts/Watch cuando ya existe el botón nativo `pip.enter` en la barra superior de NOVA.
   - `forceDarkModeToggleJS` se ejecutaba también dentro de `<iframe>` (`forMainFrameOnly: false`), aplicando doble/triple inversión CSS sobre reproductores embebidos.
6. **User-Agent incompleto para reproductores modernos (`WebViewPool`)**:
   - `applicationNameForUserAgent` usaba `"Version/15.6 Safari/605.1.15"` sin el token estándar `Mobile/15E148 Safari/604.1` esperado por varios reproductores HTML5 de iPadOS.
7. **Reconstrucción innecesaria del contenedor SwiftUI al cambiar de pestaña (`MainBrowserView`)**:
   - `.id(viewModel.activeTabID)` en `WebViewRepresentable` destruía y recreaba `WebViewHostContainer` en cada cambio de pestaña.
8. **Traductor tras navegación SPA y accesibilidad en Split View (`WebViewPool`, `BrowserViewModel`, `TopToolbarView`)**:
   - `__novaCollectTranslatableNodes()` reutilizaba nodos cacheados si el usuario navegaba dentro de una SPA sin recarga completa.
   - En Split View estrecho (`< 500 pt`), el menú `⋯` solo permitía traducir al idioma predeterminado y no elegir otro idioma.
9. **Navegación frágil desde Ajustes hacia Contraseñas (`SettingsView`, `PasswordsSheetView`)**:
   - Se usaba `dismiss()` + `DispatchQueue.main.asyncAfter(deadline: .now() + 0.25)` en lugar de una navegación nativa estable.
10. **Prevención de descargas duplicadas y seguridad de hilos (`DownloadManager`)**:
    - Faltaba evitar descargas activas duplicadas para la misma URL y capturar una instantánea inmutable de `segments` antes de pasar al hilo de ensamblado final.

---

## 3. Optimizaciones implementadas

- **Configuración de `URLCache.shared` en `AppDelegate`**: 16 MB en memoria y 96 MB en disco (`nova_url_cache`), evitando revalidaciones constantes de scripts/imágenes sin comprometer los 2 GB de RAM del iPad Air 2.
- **E/S asíncrona en `PersistenceStore`**: todas las escrituras JSON pasan a una cola serial `com.novabrowser.persistence` (`.utility`) con lectura ordenada mediante `saveQueue.sync`.
- **Respaldo de cookies optimizado (`PrivacyDataManager`)**: intervalo mínimo de 25 segundos durante navegación activa, serialización binaria `PropertyListSerialization` en segundo plano (eliminando APIs obsoletas) y guardado forzado al pasar la app a segundo plano o inactiva.
- **Debounce de estadísticas del bloqueador (`BrowserViewModel`)**: `recordBlockedItems` agrupa escrituras a disco cada 2.5 s y vacía cambios pendientes al pasar a segundo plano.
- **Cambio de pestañas sin reconstruir el host (`MainBrowserView`)**: se eliminó `.id(viewModel.activeTabID)` sobre `WebViewRepresentable` para reutilizar `WebViewHostContainer`.

---

## 4. Mejoras aplicadas en YouTube y Shorts

- Se eliminó el `MutationObserver` global sobre `document.body`; ahora solo se observa `#movie_player` / `.html5-video-player` por cambio de atributo `class`.
- `sweepAdContainers` tiene *cooldown* de 1.8 s para no competir con la fluidez de scroll o cambio de Shorts.
- Se reemplazó el sondeo agresivo cada 400 ms por hooks SPA (`yt-navigate-finish`, `yt-page-data-updated`, `popstate`, `hashchange`, `history.pushState/replaceState`) más respaldo ligero cada 1.5 s.
- En **Shorts**, se pausa únicamente el `<video>` precargado que queda completamente fuera del viewport después de estabilizarse el scroll (`140 ms`), evitando cortes o desfase A/V al deslizar.
- En anuncios SSAI sin botón de omitir, el salto de tiempo se ejecuta **una sola vez por identificador de anuncio** y solo cuando `readyState >= 2`, evitando bucles de error.
- Se retiró el botón HTML superpuesto `#nova-yt-pip-fab` del DOM de YouTube; **Picture-in-Picture** se activa de forma limpia y consistente desde el icono `pip.enter` de la barra superior (disponible también en Split View estrecho), manteniendo despejados controles, menú de tres puntos (`⋮`), calidad, descripción y panel de comentarios con su botón `×`.

---

## 5. Mejoras aplicadas para reproductores de terceros (anime, HTML5, HLS)

- **`decidePolicyFor navigationResponse`**: nunca desvía manifiestos HLS/DASH/subtítulos (`.m3u8`, `.mpd`, `.vtt`, `mpegurl`) ni subframes embebidos hacia descargas automáticas; solo descarga respuestas no renderizables cuando `isForMainFrame == true` o hay `Content-Disposition: attachment`.
- **Fullscreen respetuoso con controles propios**: `novaEnterFullscreen` intenta primero `requestFullscreen` nativo del elemento contenedor (compatible con `isElementFullscreenEnabled = true` desde iOS 15.4) para conservar controles personalizados y subtítulos HTML, recurriendo a `video.webkitEnterFullscreen()` solo como respaldo o cuando el objetivo es `<video>` directamente.
- **Aislamiento de modo oscuro web en `<iframe>`**: `forceDarkModeToggleJS` ahora solo actúa en el documento superior (`window.top === window.self`), evitando inversiones múltiples o pérdida de superficie de vídeo en reproductores embebidos.
- **User-Agent Safari iPadOS coherente**: `Version/15.6 Mobile/15E148 Safari/604.1` (y `Version/16.6` en modo escritorio macOS Safari) para reducir rechazos falsos de "navegador antiguo" sin suplantar motores incompatibles.

---

## 6. Mejoras de rendimiento y memoria (iPad Air 2 — 2 GB RAM)

- Límite de hasta 4 `WKWebView` activas simultáneas en `WebViewPool` con expulsión inmediata de pestañas en segundo plano ante `didReceiveMemoryWarningNotification`.
- Eliminación de capas compositoras forzadas sobre `<video>` y reducción de `MutationObserver`/timers JS en segundo plano.
- Escrituras de disco fuera del hilo principal (`PersistenceStore`, `PrivacyDataManager`).
- `URLCache` acotado (16 MB RAM / 96 MB disco) para evitar crecimiento descontrolado en memoria.

---

## 7. Cambios en descargas

- Protección contra descargas activas duplicadas de la misma URL tanto en `attachWKDownload` como en `startDirectDownload`.
- Instantánea segura de segmentos antes de fusionar archivos en segundo plano (`SegmentedDownloadEngine.finalizeBatch`).
- Se mantiene descarga multisegmento (hasta 4 conexiones HTTP `Range` cuando el servidor responde `Accept-Ranges: bytes` / HTTP 206) y pausa/reanudación con persistencia en `Files > En mi iPad > NOVA Browser > Descargas`.

---

## 8. Cambios en el AdBlocker

- `FilterListParser.isProtectedVideoDomain` amplía la lista de dominios protegidos con CDNs legítimos de vídeo (`dailymotion.com`, `dmcdn.net`, `cloudflarestream.com`, `videodelivery.net`, `streamable.com`, `wistia.com`, `vidyard.com`) junto a YouTube/Vimeo/JWPlayer/Twitch.
- `default_blocklist.json` acota reglas agresivas (`adsterra`, `hilltopads`, `onclickalgo`, etc.) a `"load-type": ["third-party"]` y añade `ignore-previous-rules` sobre dichas CDNs multimedia.

---

## 9. Traductor de páginas web

- **Dependencia externa**: la traducción web realiza peticiones HTTPS al endpoint público `https://translate.googleapis.com/translate_a/single` (`PageTranslatorService.swift`). No depende de claves privadas ni APIs de IA embebidas, pero **requiere conexión a Internet** y está sujeto a disponibilidad o límites de tasa (HTTP 429) de dicho endpoint público de Google Translate.
- Se corrigió `__novaCollectTranslatableNodes(forceRefresh)` para re-escanear texto visible tras cambios de ruta en sitios SPA y comprobar `node.isConnected`.
- Se añadió submenú completo de idiomas dentro del botón `⋯` para mantener traducción en cualquier idioma incluso en Split View estrecho.

---

## 10. Ajustes de UI / Split View / Ajustes

- El botón PiP (`pip.enter`) sigue disponible en la barra superior incluso en Split View estrecho (`< 500 pt`) cuando hay vídeo en pantalla.
- En `SettingsView`, "Administrar contraseñas" ahora usa `NavigationLink` directo hacia `PasswordsManagerListView`, eliminando la transición diferida con `asyncAfter`.

---

## 11. Limitaciones reales que persisten por hardware / iPadOS 15.8.9

1. **Motor WebKit de iOS 15.8.9**: en iOS/iPadOS todos los navegadores usan el `WKWebView` del sistema. Sitios web que exijan APIs JavaScript/CSS exclusivas de Safari 17/18 o iOS 16+ (por ejemplo ciertos reproductores con codecs/MSE modernos o WebGPU) no pueden habilitarse por software mediante un cambio de User-Agent.
2. **Picture-in-Picture (PiP)**: depende de que el reproductor utilice `<video>` estándar compatible con `webkitSetPresentationMode('picture-in-picture')` o `requestPictureInPicture()`. Algunos reproductores con DRM/MSE personalizado o canvas pueden bloquear PiP por decisión del sitio.
3. **YouTube SSAI (anuncios insertados en el flujo)**: el bloqueo por `WKContentRuleList` + CSS + observador en `#movie_player` omite la gran mayoría de anuncios, pero YouTube actualiza sus formatos periódicamente y puede mostrar brevemente un anuncio integrado en el stream antes de que aparezca el selector de omisión.
4. **2 GB de RAM en iPad Air 2**: si el usuario mantiene muchas pestañas pesadas abiertas en paralelo, `WebViewPool` recicla automáticamente las más antiguas en segundo plano para evitar que iPadOS cierre la app por `jetsam`.

---

## 12. Qué se revisó vs qué requiere Xcode / dispositivo físico para verificación final

- **Implementado y revisado estáticamente**:
  - Auditoría completa de todos los archivos Swift, `.xcodeproj/project.pbxproj`, `Info.plist`, `codemagic.yaml`, `default_blocklist.json`, `ad_domains.txt` y `NOVABrowserTests.swift`.
  - Validación de sintaxis JavaScript embebida en `WebViewPool.swift` (mediante `node --check`), validación JSON de `default_blocklist.json`, validación XML de `Info.plist` y verificación estática de ausencia de APIs exclusivas de iOS 16+.
- **No verificable en este entorno Linux (requiere macOS + Xcode / CodeMagic / iPad Air 2 físico con iPadOS 15.8.9)**:
  - Compilación real con `xcodebuild` / Swift compiler y firma IPA.
  - Ejecución en vivo de `XCTest` (`NOVABrowserTests`).
  - Pruebas reales de fluidez en GPU A8X, reproducción YouTube/Shorts, reproductores de anime específicos, Picture-in-Picture multiapp sobre WhatsApp, descargas reales con HTTP `Range` y comportamiento en Split View sobre iPadOS 15.8.9.
