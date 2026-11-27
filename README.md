# NOVA Browser (iPadOS 15.0+ / iPad Air 2)

Navegador web nativo para iPad desarrollado en **Swift** y **SwiftUI** sobre **WKWebView**, optimizado específicamente para el hardware del **iPad Air 2 (iOS 15.8.9, chip A8X arm64, 2 GB de RAM, pantalla de 9,7")**.

## Características principales

- **Compatibilidad real con iOS 15.0+ / iPadOS 15.8.9**: sin APIs exclusivas de iOS 16, 17 o 18.
- **Gestión eficiente de memoria para iPad Air 2**: caché LRU limitada a un máximo de 4 `WKWebView` activas simultáneamente y liberación automática de pestañas en segundo plano ante alertas de memoria del sistema.
- **Navegación completa**: barra integrada de URL y búsqueda, atrás, adelante, recargar/detener, página de inicio personalizada, atajos de teclado físicos (`Cmd+T`, `Cmd+W`, `Cmd+L`, `Cmd+R`, `Cmd+[`, `Cmd+]`, `Cmd+Shift+N`), gestión de errores de conexión, enlaces `target="_blank"` en nuevas pestañas y hoja nativa para compartir.
- **Pestañas e Incógnito**: tira de pestañas horizontal y vista en cuadrícula. Las pestañas privadas usan `WKWebsiteDataStore.nonPersistent()`, no registran historial y no se guardan al cerrar la app.
- **Interfaz tipo app en YouTube + modo Shorts limpio**: barra superior simplificada (solo menú `≡`, logo y búsqueda), barra inferior compacta estilo app (**Inicio**, **Shorts**, **Suscripciones**, **Tú**) y ocultación automática de la cabecera superior dentro de Shorts.
- **Optimización de vídeo, YouTube y pantalla completa nativa**: `isElementFullscreenEnabled` (iOS 15.4+) con respaldo directo a `webkitEnterFullscreen()` (`AVPlayerViewController` nativo de iPad), botón rápido de pantalla completa en la barra superior, renderizado opaco (`isOpaque = true`), eliminación de desenfoques/cinematics/previews animados y ajuste instantáneo sin transiciones lentas al rotar el iPad.
- **Modo oscuro forzado en páginas web**: botón dedicado en la barra superior (`moon`) y ajuste para oscurecer sitios claros (o activar modo oscuro en YouTube) manteniendo imágenes y vídeos con colores reales.
- **Motores de búsqueda Google y Brave Search**: soporte nativo para **Google** y **Brave Search (`search.brave.com`)** con identificador Safari en `WKWebView` y asistente de respaldo automático si Brave activa su verificación WebAssembly 2.0 (no soportada por WebKit en iOS 15.8.9).
- **Gestor de descargas multihilo tipo IDM**: descargas paralelas con hasta 4 conexiones (`HTTP Range`), pausar y reanudar descargas, velocidad en tiempo real, soporte para `WKDownload` y archivos guardados en `Archivos > En mi iPad > NOVA Browser > Descargas`.
- **Bloqueador de anuncios inteligente (`WKContentRuleList`)**:
  - Reglas nativas compiladas en el motor C++ de WebKit (`default_blocklist.json`).
  - Descarga y conversión de listas compatibles con EasyList / AdBlock Plus (`FilterListParser.swift`) con respaldo local automático si falla la red.
  - Excepciones por sitio web desde el botón de escudo o desde Ajustes.
  - Reglas de protección explícitas (`ignore-previous-rules`) para no romper YouTube ni reproductores de vídeo HTML5.
- **Página de inicio rápida**: buscador, accesos rápidos personalizables (añadir, editar, eliminar) y acceso directo a favoritos.
- **Ajustes completos**: bloqueo global, actualización de listas, administrador de excepciones, limpieza independiente de historial, cookies y todos los datos de navegación, tema Automático / Claro / Oscuro, modo oscuro web forzado, optimización de vídeo, motor de búsqueda y página de inicio.

## Limitaciones técnicas conocidas de WKWebView en iOS 15

1. **Conteo exacto de recursos bloqueados por `WKContentRuleList`**: Apple no expone en `WKWebView` un callback por cada petición bloqueada por `WKContentRuleList` (el filtrado de red ocurre de forma silenciosa dentro del proceso de WebKit). El contador del escudo refleja de manera fiable las redirecciones/popups interceptados por el navegador y los elementos/contenedores publicitarios detectados en el DOM.
2. **Anuncios integrados en el flujo de vídeo de YouTube (SSAI)**: Cuando YouTube inserta un anuncio directamente en la misma secuencia de vídeo, ninguna regla de red puede eliminarlo sin cortar el vídeo; en ese caso, el script auxiliar de NOVA pulsa automáticamente el botón de saltar anuncio en cuanto aparece (mediante `MutationObserver`) y oculta los banners superpuestos sin romper la reproducción ni el modo de pantalla completa.

## Estructura del proyecto

- `NOVABrowser.xcodeproj`: Proyecto de Xcode con esquema compartido `NOVABrowser` y target de pruebas `NOVABrowserTests`.
- `NOVABrowser/App`: Punto de entrada `@main` y configuración de `AVAudioSession` para vídeo web.
- `NOVABrowser/Core`: `URLResolver`, `FilterListParser` y `AdBlockerEngine`.
- `NOVABrowser/WebKit`: `WebViewPool`, `WebViewRepresentable` y `ShareSheetView`.
- `NOVABrowser/Storage`: `PersistenceStore`, `PrivacyDataManager` y `DownloadManager`.
- `NOVABrowser/ViewModels`: `BrowserViewModel`.
- `NOVABrowser/Views`: Interfaz completa en SwiftUI (barra superior, pestañas, inicio, descargas, librería y ajustes).
- `NOVABrowser/Resources`: `default_blocklist.json` y `ad_domains.txt`.
- `codemagic.yaml`: Configuración lista para compilar y generar el `.ipa` en CodeMagic.

## Cómo compilar en CodeMagic

1. Sube el contenido de la carpeta `NOVA-BROWSER` a la raíz de un repositorio en GitHub (de modo que `codemagic.yaml` y `NOVABrowser.xcodeproj` queden en la raíz del repositorio).
2. Conecta el repositorio en **CodeMagic**.
3. Selecciona el flujo adecuado:
   - **`ios-nova-browser-signed`**: requiere configurar tu integración de App Store Connect / certificados y perfiles de aprovisionamiento (`ad_hoc`, `development` o `app_store`) con el Bundle ID `com.novabrowser.ipad` (o el que configures en Xcode). Genera un `.ipa` firmado listo para instalar.
   - **`ios-nova-browser-unsigned`**: ejecuta las pruebas unitarias en simulador iPad y genera `NOVABrowser-unsigned.ipa` sin requerir certificados de Apple (útil para verificación de compilación o firma local posterior con herramientas como Sideloadly/AltStore).
