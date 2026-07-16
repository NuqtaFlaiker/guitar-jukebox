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
nombre original como título visible.

## 3. En Second Life

1. Ponte la guitarra o rézzala en el suelo para editarla.
   **Importante: MOAP no funciona en HUDs** — la guitarra debe ir como
   attachment normal (mano, cadera...), no como HUD.
2. Botón derecho → **Editar** → pestaña **Contenido** → **Nuevo script**.
3. Abre el script, borra el contenido y pega el de `GuitarJukebox.lsl`.
4. Edita las dos primeras constantes:
   - `BASE_URL`: tu URL de GitHub Pages, **con https y sin barra final**.
   - `MEDIA_FACE`: número de la cara del prim que llevará la media.
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
- Que se oiga en mono o estéreo, y el volumen relativo, dependen del viewer
  de cada oyente.
