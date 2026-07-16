# Plan: Guitarra con jukebox MOAP para Second Life

## 1. Objetivo

Construir un sistema para que una guitarra (objeto attachment en Second Life) reproduzca
cualquier canción de un catálogo alojado en un servidor web propio, elegida desde un menú
in-world, **sin subir audio a Second Life y sin permisos de parcela**.

Mecanismo: **Media on a Prim (MOAP)**. Una cara del objeto muestra una página web con un
reproductor de audio. Un script LSL cambia la URL de esa media según la canción elegida.
El audio lo reproduce el viewer de cada persona que tenga media habilitada.

## 2. Arquitectura

```
[Servidor estático (GitHub Pages o similar)]
 ├── player.html          ← página reproductora (recibe ?song=...&title=...)
 ├── catalog.txt          ← catálogo de canciones (texto plano)
 └── songs/
     ├── cancion-1.mp3
     └── ...

[Second Life]
 └── Guitarra (attachment)
     └── script "GuitarJukebox.lsl"
         ├── al tocar (touch) → descarga catalog.txt por llHTTPRequest
         ├── muestra menú paginado con llDialog
         └── al elegir → llSetPrimMediaParams(cara, player.html?song=...)
```

Notas de contexto SL que el implementador debe respetar (no inventar APIs):
- El viewer de SL renderiza MOAP con un Chromium embebido (CEF). La página debe ser
  ligera, sin frameworks, un solo archivo HTML con CSS/JS inline.
- MOAP **no funciona en HUDs**; sí en attachments normales y objetos rezzados.
- La URL de media tiene un límite de 1024 bytes.
- Solo el script decide la URL; los espectadores no interactúan con la página.

## 3. Entregables

1. `player.html` — reproductor web.
2. `catalog.txt` — catálogo de ejemplo (formato definido abajo) con 3-4 entradas dummy.
3. `GuitarJukebox.lsl` — script LSL completo y comentado en español.
4. `README.md` — instrucciones de despliegue y uso paso a paso.
5. (Opcional) `tools/normalize.sh` — script que renombra MP3 a slugs seguros para URL
   (minúsculas, sin espacios/acentos) y regenera `catalog.txt` a partir del directorio.

## 4. Especificación: `catalog.txt`

Texto plano UTF-8, una canción por línea:

```
Título visible|archivo.mp3
```

Ejemplo:

```
Hotel California|hotel-california.mp3
Wish You Were Here|wish-you-were-here.mp3
Tears in Heaven|tears-in-heaven.mp3
```

Reglas:
- El separador es `|` (prohibido en títulos).
- Los nombres de archivo deben ser "URL-safe": ASCII minúsculas, guiones, sin espacios.
- Líneas vacías o que empiecen con `#` se ignoran (comentarios).
- Tamaño total objetivo < 8 KB para que quepa en una respuesta HTTP de LSL
  (ver límite HTTP_BODY_MAXLENGTH en §6). Con ~35 bytes/línea caben ~200 canciones.
  Si el catálogo crece más, ver §9 (paginación server-side), pero NO implementarla ahora.

## 5. Especificación: `player.html`

### Funcionalidad
- Lee query params: `song` (nombre de archivo dentro de `songs/`) y `title` (texto).
  Ambos llegan URL-encoded; decodificar con `decodeURIComponent`.
- Sanitizar `song`: aceptar solo `[a-z0-9._-]`; si no valida, mostrar estado de error.
- Crea un `<audio>` con `src="songs/" + song`, `autoplay`, `loop` opcional vía param
  `loop=1`, y **volume inicial 0.8**.
- Intentar `audio.play()` al cargar. Si el navegador bloquea el autoplay (promesa
  rechazada), mostrar un botón grande de "Reproducir" que ocupe casi toda la página
  (la cara del prim puede ser pequeña; todo debe ser legible/clickeable a 256×256 px).
- Sin `song` en la URL → estado reposo: mostrar solo el nombre del sistema y "En silencio".
- Al terminar la canción (evento `ended`, sin loop) → volver al estado reposo visual.

### Diseño (brief para la parte visual)
- Sujeto: el "alma" de una guitarra acústica; la página es la boca de la guitarra vista
  de cerca. Audiencia: el dueño y curiosos que hagan zoom a la cara del prim.
  Trabajo único de la página: decir qué suena y si está sonando.
- Paleta (tokens): `--rosewood: #2B1B12` (fondo), `--spruce: #E8D9BE` (texto),
  `--brass: #C9973F` (acento/estado activo), `--shadow: #17100A`, `--muted: #8A7460`.
  Evitar cremas claras con terracota y evitar negro puro + verde ácido.
- Tipografía: system stack para carga instantánea en CEF
  (`Georgia, 'Times New Roman', serif` para el título de canción;
  `system-ui, sans-serif` para etiquetas pequeñas). El título de la canción es el
  elemento dominante: grande, serif, alto contraste.
- Elemento firma: **seis cuerdas** — seis líneas horizontales SVG/CSS que vibran con una
  animación sutil (amplitudes distintas por cuerda) solo mientras `audio` está en play;
  quietas en pausa/reposo. Respetar `prefers-reduced-motion` (cuerdas estáticas).
- Nada de controles de reproducción visibles salvo el fallback de "Reproducir";
  el control real es el menú in-world.
- Todo en un solo archivo, < 15 KB, sin fuentes externas ni CDNs.

## 6. Especificación: `GuitarJukebox.lsl`

### Configuración (constantes al inicio, comentadas)
```lsl
string BASE_URL   = "https://TU-USUARIO.github.io/TU-REPO"; // sin slash final
integer MEDIA_FACE = 0;   // cara del prim que llevará la media
float   DIALOG_TIMEOUT = 60.0;
```

### Comportamiento
1. **touch_start** (solo si `llDetectedKey(0) == llGetOwner()`; ignorar a otros):
   - Pedir `BASE_URL + "/catalog.txt"` con `llHTTPRequest`, usando
     `[HTTP_BODY_MAXLENGTH, 16384]` (el default es 2048 y truncaría el catálogo).
2. **http_response**:
   - Validar status 200; si no, `llOwnerSay` con mensaje de error claro.
   - Parsear líneas → dos listas paralelas: `titles` y `files` (strided no; paralelas).
   - Mostrar el menú (ver abajo).
3. **Menú con llDialog** (límites duros de SL, no violarlos):
   - Máximo **12 botones** por diálogo y **24 bytes** por etiqueta de botón
     (¡bytes UTF-8, no caracteres! truncar títulos con cuidado de no cortar un
     carácter multibyte a la mitad; helper de truncado por bytes).
   - Mensaje del diálogo ≤ 511 bytes.
   - Paginación: 9 canciones por página + botones `« Ant`, `Sig »`, `■ Detener`.
   - Canal de escucha: negativo y pseudoaleatorio derivado de la key del objeto,
     p.ej. `-1 - (integer)llFrand(1000000) - canal fijo`; abrir `llListen` filtrado
     por el dueño, guardar el handle, y cerrarlo con `llListenRemove` tras usarlo o
     tras `DIALOG_TIMEOUT` (usar `llSetTimerEvent`; recordar apagar el timer).
   - Mapear la etiqueta truncada de vuelta al índice real (lista paralela
     `buttonLabels` → índice global). No confiar en el texto para buscar el archivo.
4. **Reproducir** (al elegir canción):
   ```lsl
   string url = BASE_URL + "/player.html?song=" + llEscapeURL(file)
              + "&title=" + llEscapeURL(title);
   llSetPrimMediaParams(MEDIA_FACE, [
       PRIM_MEDIA_CURRENT_URL, url,
       PRIM_MEDIA_HOME_URL, url,
       PRIM_MEDIA_AUTO_PLAY, TRUE,
       PRIM_MEDIA_AUTO_SCALE, TRUE,
       PRIM_MEDIA_PERMS_INTERACT, PRIM_MEDIA_PERM_OWNER,
       PRIM_MEDIA_PERMS_CONTROL, PRIM_MEDIA_PERM_OWNER,
       PRIM_MEDIA_WIDTH_PIXELS, 512,
       PRIM_MEDIA_HEIGHT_PIXELS, 512
   ]);
   ```
   - Nota: `llSetPrimMediaParams` duerme el script 1.0 s; está bien.
   - Verificar que la URL final no exceda 1024 bytes; si excede, avisar al dueño.
5. **Detener**: `llClearPrimMedia(MEDIA_FACE);` (también duerme 1.0 s) y confirmar
   con `llOwnerSay`.
6. **changed / on_rez / attach**: al re-attachar o cambiar de región, limpiar estado
   (cerrar listeners, apagar timer). No re-lanzar media automáticamente.
7. Mensajes al usuario en español, breves, vía `llOwnerSay`.

### Estilo del código LSL
- LSL no tiene try/catch ni diccionarios: usar listas paralelas y validar todo input.
- Comentar cada evento y cada límite de SL donde aplique (12 botones, 24 bytes,
  16384 de body, 1024 de URL) para que el dueño pueda modificarlo sin romperlo.
- Un solo script, un solo estado (`default`).

## 7. `README.md` (contenido a generar)

1. **Desplegar el servidor**: crear repo en GitHub → subir `player.html`, `catalog.txt`,
   carpeta `songs/` → activar GitHub Pages (branch main, root) → anotar la URL HTTPS.
   Advertencia visible: GitHub Pages es público; para música con derechos de autor usar
   un hosting propio privado y tener presente que la responsabilidad es del usuario.
2. **Preparar canciones**: nombres de archivo URL-safe; formato del catálogo; ejemplo
   del script `tools/normalize.sh` si se incluye.
3. **En Second Life**: crear el script en la guitarra, pegar `GuitarJukebox.lsl`,
   configurar `BASE_URL` y `MEDIA_FACE`. Cómo identificar el número de cara
   (herramienta editar → seleccionar cara). Sugerir usar una cara pequeña/discreta.
4. **Probar**: tocar la guitarra → menú → elegir canción. Checklist de problemas:
   - No suena → verificar media habilitada en preferencias del viewer
     (Sonido y Media → reproducir media automáticamente).
   - Menú no aparece → revisar `BASE_URL` (sin slash final, con https).
   - Catálogo cortado → catálogo > 16 KB, reducir o dividir.
   - En parcelas que bloquean media de objetos, no sonará para visitantes: es
     limitación del terreno, no un bug.
   - MOAP no funciona si el objeto está como HUD.
   - Tras teleport, si la media se detiene, volver a elegir la canción del menú.
5. **Limitaciones conocidas** (copiar honesto): cada oyente necesita media activada;
   la reproducción no está sincronizada entre oyentes; mono/estéreo depende del
   viewer del oyente.

## 8. Criterios de aceptación

- [ ] `player.html` valida y sanitiza `song`, autoreproduce o muestra fallback,
      cuerdas animadas solo durante reproducción, `prefers-reduced-motion` respetado,
      un solo archivo sin dependencias externas.
- [ ] `GuitarJukebox.lsl` compila mentalmente contra la API pública de LSL
      (solo funciones/constantes reales del wiki de SL: llHTTPRequest, llDialog,
      llListen/llListenRemove, llSetPrimMediaParams, llClearPrimMedia, llEscapeURL,
      llOwnerSay, llSetTimerEvent, llDetectedKey, llGetOwner). No inventar funciones.
- [ ] Paginación correcta con 25+ canciones en el catálogo de prueba.
- [ ] Truncado de etiquetas seguro con títulos con tildes/ñ (multibyte).
- [ ] README reproducible por un usuario no técnico de principio a fin.

## 9. Fuera de alcance (no implementar ahora, dejar anotado)

- Paginación server-side del catálogo (para >200 canciones): endpoint
  `catalog.txt?page=N` o dividir en varios archivos.
- Cola de reproducción / aleatorio / playlists.
- Sincronizar animación de pose con la reproducción (segundo script que escuche
  link_message del jukebox y dispare llStartAnimation).
- Variante de clips por UUID para audio nativo sincronizado (arquitectura alternativa
  ya evaluada; más cara).
