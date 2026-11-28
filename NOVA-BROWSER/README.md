# NOVA Browser (iPadOS 15.0+ / iPad Air 2)

Navegador web nativo para iPad desarrollado en **Swift** y **SwiftUI** sobre **WKWebView**, optimizado específicamente para el hardware del **iPad Air 2 (iOS 15.8.9, chip A8X arm64, 2 GB de RAM, pantalla de 9,7")**.

## Características principales

- **Diseño minimalista estilo Safari moderno**: barra de direcciones redondeada, menú compacto de acciones, tira de pestañas con el botón `+` junto a las pestañas y adaptación automática a Split View en iPad.
- **Compatibilidad real con iOS 15.0+ / iPadOS 15.8.9**: sin APIs exclusivas de iOS 16, 17 o 18.
- **Ventana flotante Picture-in-Picture (PiP)**: botón nativo de PiP en la barra superior y dentro de YouTube (vídeos normales y Shorts) con audio en segundo plano activo para seguir viendo mientras usas WhatsApp u otras apps.
- **YouTube optimizado + Shorts fluidos**: sincronización estable de audio y vídeo al deslizar entre Shorts, corrección del panel de comentarios (`×` de cierre visible) y menú `⋮` (calidad y descripción) accesibles junto con barra inferior tipo app (**Inicio**, **Shorts**, **Suscripciones**, **Tú**).
- **Gestor de contraseñas en Llavero de iOS**: aviso automático para guardar credenciales al iniciar sesión, autocompletado en un toque y administración completa.
- **Traductor web integrado**: traducción directa del texto visible de cualquier página (Español, Inglés, Portugués, Francés, Italiano y Alemán) con opción para restaurar el idioma original.
- **Sesiones y cookies persistentes**: `WKProcessPool` compartido en pestañas normales y respaldo automático de cookies para mantener tus cuentas iniciadas al reabrir el navegador.
- **Bloqueador de anuncios inteligente (`WKContentRuleList` + reproductor)**: bloqueo de red en C++ para dominios y rutas publicitarias de YouTube/web, combinado con omisión automática instantánea y silenciamiento temporal en anuncios de reproductor.
- **Motor de búsqueda Google predeterminado** y **gestor de descargas multihilo tipo IDM** con archivos en `Archivos > En mi iPad > NOVA Browser > Descargas`.

## Cómo compilar en CodeMagic

1. Sube el contenido de la carpeta `NOVA-BROWSER` a la raíz de un repositorio en GitHub (de modo que `codemagic.yaml` y `NOVABrowser.xcodeproj` queden en la raíz).
2. Conecta el repositorio en **CodeMagic**.
3. Selecciona `ios-nova-browser-signed` o `ios-nova-browser-unsigned`.
