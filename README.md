# Guitarra Jukebox (MOAP) para Second Life

Sistema para que tu guitarra (attachment) reproduzca cualquier canción de un
catálogo alojado en tu propio servidor web, elegida desde un menú in-world,
**sin subir audio a Second Life y sin permisos de parcela**.

Funciona con **Media on a Prim (MOAP)**: una cara de la guitarra muestra una
página web con un reproductor de audio, y el script cambia la URL de esa media
según la canción que elijas en el menú.

## Archivos

| Archivo | Qué es |
|---|---|
| `player.html` | Página reproductora que se carga en la cara del prim |
| `catalog.txt` | Catálogo de canciones (una por línea: `Título|archivo.mp3`) |
| `GuitarJukebox.lsl` | Script LSL que va dentro de la guitarra |
| `tools/normalize.sh` | (Opcional) Renombra MP3 a nombres seguros y regenera el catálogo |
| `tools/subir.sh` | Sube las canciones nuevas de `songs/` en un solo paso (normaliza + push + verifica) |
| `Subir canciones.cmd` | Doble clic en Windows para ejecutar `tools/subir.sh` |
| `songs/` | Carpeta donde van tus MP3 |

## 1. Desplegar el servidor (GitHub Pages)

1. Crea una cuenta en [github.com](https://github.com) si no la tienes.
2. Crea un repositorio nuevo (por ejemplo `guitar-jukebox`).
3. Sube al repositorio: `player.html`, `catalog.txt` y la carpeta `songs/`
   con tus MP3 dentro.
4. En el repositorio ve a **Settings → Pages**, en "Source" elige la rama
   `main` y carpeta `/ (root)`, y guarda.
5. Espera 1-2 minutos y anota la URL que te da GitHub, del tipo
   `https://TU-USUARIO.github.io/guitar-jukebox`. Esa es tu `BASE_URL`.

> ⚠️ **GitHub Pages es público**: cualquiera con la URL puede descargar tus
> archivos. Para música con derechos de autor usa un hosting propio privado.
> La responsabilidad sobre el contenido que publiques es tuya.

## 2. Preparar las canciones

- Los nombres de archivo deben ser "URL-safe": **minúsculas, sin espacios,
  sin acentos ni ñ**, solo letras, números, puntos, guiones y guiones bajos.
  Ejemplo: `Canción del Mariachi.mp3` → `cancion-del-mariachi.mp3`.
- El catálogo (`catalog.txt`) lleva una canción por línea con este formato
  (el separador es `|` y no puede aparecer en los títulos):

  ```
  Hotel California|hotel-california.mp3
  Canción del Mariachi|cancion-del-mariachi.mp3
  ```

- Las líneas vacías o que empiezan con `#` se ignoran (sirven de comentario).
- Mantén el catálogo por debajo de ~16 KB (unas 200 canciones); si es más
  grande, el script lo truncará.

Si tienes Linux, macOS o Git Bash en Windows, puedes automatizarlo: pon tus
MP3 con su nombre "bonito" en `songs/` y ejecuta:

```bash
./tools/normalize.sh
```

Renombra los archivos a slugs seguros y regenera `catalog.txt` usando el
nombre original como título visible. Los títulos de canciones que ya estaban
en el catálogo se conservan aunque los hayas editado a mano.

### Añadir canciones nuevas (el día a día)

1. Copia los MP3 nuevos a `songs/` (con el nombre "bonito" que quieras ver
   en el menú, p. ej. `Hotel California.mp3`).
2. Doble clic en **`Subir canciones.cmd`** (o ejecuta `./tools/subir.sh`).

El script normaliza los archivos, regenera el catálogo, hace commit y push,
y espera a que GitHub Pages publique para confirmarte que ya está en línea.
No hay que tocar nada en Second Life: la próxima vez que toques la guitarra
el menú ya trae las canciones nuevas.

## 3. En Second Life

1. Ponte la guitarra o rézzala en el suelo para editarla.
   **Importante: MOAP no funciona en HUDs** — la guitarra debe ir como
   attachment normal (mano, cadera...), no como HUD.
2. Botón derecho → **Editar** → pestaña **Contenido** → **Nuevo script**.
3. Abre el script, borra el contenido y pega el de `GuitarJukebox.lsl`.
4. Edita las constantes de configuración:
   - `BASE_URL`: tu URL de GitHub Pages, **con https y sin barra final**.
   - `MEDIA_FACE`: número de la cara del prim que llevará la media.
   - `HIDE_SCREEN`: con `FALSE` (por defecto, recomendado) se ve la pantalla
     del reproductor en la cara. Con `TRUE` la cara se vuelve transparente
     mientras suena y recupera su textura al detener. **Ojo con `TRUE`**: si
     `MEDIA_FACE` es una cara grande del mesh, media guitarra se vuelve
     invisible; además el viewer puede no cargar la media de una cara
     transparente (prioriza por área visible) y nadie podrá pulsar el botón
     "Reproducir" de respaldo — solo quedará la barrita de media de arriba.
     Úsalo solo si la cara es una pantallita pequeña independiente.
5. Guarda el script.

**¿Cómo saber el número de cara?** En la ventana de edición marca
**Seleccionar cara** y haz clic en la cara que quieras usar; en la pestaña
**Textura** verás la cara seleccionada. Si tienes dudas, un truco: activa
"Mostrar información de la cara" en el menú de desarrollo, o prueba números
del 0 al 7 cambiando `MEDIA_FACE`. Elige una cara pequeña y discreta
(la tapa trasera o la boca de la guitarra quedan bien).

## 4. Probar

1. Toca la guitarra → aparece el menú con las canciones.
2. Usa `« Ant` / `Sig »` para cambiar de página y `■ Detener` para parar.
3. Elige una canción → la cara del prim carga el reproductor y suena.

### Si algo falla

| Problema | Causa probable |
|---|---|
| No suena nada | Media desactivada en el viewer: **Preferencias → Sonido y multimedia → activar "Reproducir multimedia automáticamente"** |
| Solo suena si pulso el link de la barra de media | `HIDE_SCREEN` en `TRUE` (cara transparente = media sin cargar y botón de respaldo inaccesible), o autoplay desactivado en el viewer (misma preferencia de arriba) |
| La guitarra se vuelve transparente al reproducir | `HIDE_SCREEN` en `TRUE` con una `MEDIA_FACE` que es parte del cuerpo de la guitarra: ponlo en `FALSE` o elige una cara pequeña |
| A otros no les suena la media de un attachment | En su viewer: **Preferencias → Sonido y multimedia → "Reproducir multimedia adjunta a otros avatares"** debe estar activada |
| El menú no aparece | `BASE_URL` mal escrita (debe empezar por `https://` y NO acabar en `/`) |
| Faltan canciones del final | Catálogo > 16 KB: redúcelo o divídelo |
| A los visitantes no les suena | La parcela bloquea media de objetos: es limitación del terreno, no un bug |
| No funciona en absoluto | El objeto está puesto como HUD: MOAP no funciona en HUDs |
| Se corta tras un teleport | Normal; vuelve a elegir la canción en el menú |

## 5. Limitaciones conocidas

- Cada oyente necesita tener la media activada en su viewer; no puedes
  forzarla desde el objeto.
- La reproducción **no está sincronizada** entre oyentes: cada viewer carga
  y reproduce por su cuenta.
- El sonido es **zonal por diseño del viewer**: cada oyente oye la media más
  fuerte cuanto más cerca esté de la guitarra, y de lejos ni se carga. Es
  atenuación del viewer de cada uno; no se controla desde el script.
- Al **ponerte la guitarra** (o rezarla) siempre empieza **en silencio**,
  aunque te la quitaras con una canción sonando: el script limpia la media
  al vestirla.
- Que se oiga en mono o estéreo, y el volumen relativo, dependen del viewer
  de cada oyente.
