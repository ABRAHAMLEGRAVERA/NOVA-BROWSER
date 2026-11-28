# NOVA Browser — actualización de código

Cambios aplicados sobre el proyecto original:

- Añadido botón `+` en la tira de pestañas junto a las pestañas abiertas, con atajo Cmd+T.
- Conservado el botón de pestaña privada junto al botón de nueva pestaña.
- Retirado el acceso rápido Brave de los accesos rápidos predeterminados.
- En Ajustes, Google queda como opción visible de buscador. El enum legado de Brave se conserva para evitar romper datos de configuración antiguos.
- Añadido un botón de traducción de página al español que abre Google Translate en una pestaña separada usando la URL de la página.
- Ajustes de WebKit para mantener renderizado incremental y reducir retrasos de interacción en scroll en el hardware antiguo.
- Afinado el matcher de dominios del bloqueador para coincidencias de dominio/subdominio explícitas, evitando el heurístico de los últimos dos segmentos que podía bloquear hosts no relacionados.

## Limitaciones verificadas del alcance

- No se puede garantizar que el bloqueador elimine todos los anuncios de YouTube: WebKit/iOS limita el filtrado y algunos anuncios comparten infraestructura con contenido.
- La función de traducción depende de la disponibilidad del servicio de Google Translate y su compatibilidad con la URL de destino.
- No se implementó un gestor de contraseñas propio. El almacenamiento de credenciales requeriría una solución de Keychain y una revisión de seguridad y flujo de autofill; no es apropiado añadir una bóveda improvisada.
- Cookies y sesiones se mantienen usando el almacén persistente de WKWebView que ya tenía el proyecto; las pestañas privadas siguen usando el almacén no persistente del pool.
- No se afirma haber compilado con Xcode: este entorno no tiene Xcode/macOS.
