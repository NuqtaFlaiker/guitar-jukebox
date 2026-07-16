// ============================================================================
// GuitarJukebox.lsl — Jukebox MOAP para guitarra (attachment) en Second Life
//
// Al tocar la guitarra (solo el dueño) descarga catalog.txt del servidor,
// muestra un menú paginado con llDialog y, al elegir una canción, apunta la
// media de una cara del prim a player.html?song=...&title=...
//
// Recuerda: MOAP NO funciona en HUDs; usa la guitarra como attachment normal.
// ============================================================================

// ------------------------------ CONFIGURACIÓN ------------------------------
string  BASE_URL       = "https://nuqtaflaiker.github.io/guitar-jukebox"; // sin slash final
integer MEDIA_FACE     = 0;    // cara del prim que llevará la media (ver README)

// TRUE  = la cara se vuelve transparente mientras suena y recupera su aspecto
//         al detener. ¡OJO! Con la cara transparente el visor puede NO cargar
//         la media (prioriza por área visible) y nadie puede pulsar el botón
//         "Reproducir" de respaldo: solo queda la barrita de media de arriba.
//         Úsalo únicamente si MEDIA_FACE es una pantallita pequeña que no
//         forma parte del cuerpo de la guitarra.
// FALSE = (recomendado) la pantalla del reproductor se ve en la cara.
integer HIDE_SCREEN    = FALSE;

float   DIALOG_TIMEOUT = 60.0; // segundos antes de cerrar el menú por inactividad

// 9 canciones por página + 3 botones de navegación = 12 botones,
// que es el MÁXIMO permitido por llDialog. No subir de 9.
integer SONGS_PER_PAGE = 9;

// Etiquetas de navegación (cada una muy por debajo del límite de 24 bytes).
string BTN_PREV = "« Ant";
string BTN_NEXT = "Sig »";
string BTN_STOP = "■ Detener";

// ------------------------------ ESTADO INTERNO -----------------------------
list    gTitles;      // títulos visibles           (lista paralela a gFiles)
list    gFiles;       // nombres de archivo mp3     (lista paralela a gTitles)
integer gPage;        // página actual del menú (base 0)
integer gChannel;     // canal de diálogo (negativo, derivado de la key del objeto)
integer gListen;      // handle del llListen activo (0 = ninguno)
key     gReqId;       // id de la petición HTTP en curso
integer gHidden;      // TRUE si la cara está oculta ahora mismo por HIDE_SCREEN
vector  gSavedColor;  // color original de la cara (para restaurarlo)
float   gSavedAlpha;  // alpha original de la cara (para restaurarlo)

// ------------------------------ UTILIDADES ---------------------------------

// Bytes UTF-8 de una cadena (LSL cuenta caracteres, no bytes; para el límite
// de 24 BYTES por botón de llDialog necesitamos bytes reales).
integer utf8Bytes(string s)
{
    string  b64   = llStringToBase64(s);
    integer chars = llStringLength(b64);
    integer bytes = chars / 4 * 3;
    if (llGetSubString(b64, -2, -1) == "==")     bytes -= 2;
    else if (llGetSubString(b64, -1, -1) == "=") bytes -= 1;
    return bytes;
}

// Trunca una cadena a maxBytes bytes UTF-8 quitando caracteres ENTEROS por el
// final, así nunca se corta un carácter multibyte (tildes, ñ...) a la mitad.
string truncBytes(string s, integer maxBytes)
{
    while (utf8Bytes(s) > maxBytes)
        s = llGetSubString(s, 0, llStringLength(s) - 2);
    return s;
}

// Oculta la cara de la media (guardando su color/alpha original) para que la
// pantalla del reproductor no tape la textura de la guitarra. El audio sigue
// sonando: la media se carga igual aunque la cara sea transparente.
hideScreen()
{
    if (!HIDE_SCREEN || gHidden) return;
    list c = llGetPrimitiveParams([PRIM_COLOR, MEDIA_FACE]);
    gSavedColor = llList2Vector(c, 0);
    gSavedAlpha = llList2Float(c, 1);
    llSetPrimitiveParams([PRIM_COLOR, MEDIA_FACE, gSavedColor, 0.0]);
    gHidden = TRUE;
}

// Devuelve a la cara su color/alpha original tras detener la reproducción.
restoreScreen()
{
    if (!gHidden) return;
    llSetPrimitiveParams([PRIM_COLOR, MEDIA_FACE, gSavedColor, gSavedAlpha]);
    gHidden = FALSE;
}

// Detiene la reproducción: quita la media de la cara y restaura su aspecto.
// Nota: llClearPrimMedia duerme el script 1.0 s; es normal.
stopSong()
{
    llClearPrimMedia(MEDIA_FACE);
    restoreScreen();
}

// Cierra el listener y apaga el timer del menú.
cleanup()
{
    if (gListen)
    {
        llListenRemove(gListen);
        gListen = 0;
    }
    llSetTimerEvent(0.0);
}

// Muestra la página gPage del menú al dueño.
showMenu()
{
    integer total = llGetListLength(gTitles);
    if (total == 0)
    {
        llOwnerSay("El catálogo está vacío o no se pudo leer.");
        return;
    }

    integer pages = (total + SONGS_PER_PAGE - 1) / SONGS_PER_PAGE;
    // Navegación circular: pasar del final vuelve al principio y viceversa.
    if (gPage < 0)      gPage = pages - 1;
    if (gPage >= pages) gPage = 0;

    integer start = gPage * SONGS_PER_PAGE;
    integer end   = start + SONGS_PER_PAGE - 1;
    if (end >= total) end = total - 1;

    // llDialog coloca los primeros botones de la lista en la fila INFERIOR,
    // así que la navegación va primero para quedar abajo del todo.
    list buttons = [BTN_PREV, BTN_STOP, BTN_NEXT];
    integer i;
    for (i = start; i <= end; ++i)
    {
        // Límite duro de llDialog: 24 BYTES por etiqueta (no caracteres).
        string label = truncBytes(llList2String(gTitles, i), 24);
        if (label == "") label = "♪ " + (string)(i + 1);
        buttons += [label];
    }

    cleanup();
    gListen = llListen(gChannel, "", llGetOwner(), ""); // solo escucha al dueño
    llSetTimerEvent(DIALOG_TIMEOUT);

    // Mensaje del diálogo: límite de 511 bytes; este texto queda muy por debajo.
    llDialog(llGetOwner(),
        "🎸 Jukebox — página " + (string)(gPage + 1) + " de " + (string)pages
        + "\nElige una canción:",
        buttons, gChannel);
}

// Reproduce la canción con índice global idx apuntando la media de la cara.
playSong(integer idx)
{
    string file  = llList2String(gFiles, idx);
    string title = llList2String(gTitles, idx);

    string url = BASE_URL + "/player.html?song=" + llEscapeURL(file)
               + "&title=" + llEscapeURL(title);

    // Límite de SL: la URL de media no puede superar 1024 bytes.
    // Tras llEscapeURL la cadena es ASCII puro, así que caracteres == bytes.
    if (llStringLength(url) > 1024)
    {
        llOwnerSay("No se puede reproducir \"" + title
            + "\": la URL supera los 1024 bytes. Acorta el título o el nombre de archivo.");
        return;
    }

    // Nota: llSetPrimMediaParams duerme el script 1.0 s; es normal.
    llSetPrimMediaParams(MEDIA_FACE, [
        PRIM_MEDIA_CURRENT_URL,    url,
        PRIM_MEDIA_HOME_URL,       url,
        PRIM_MEDIA_AUTO_PLAY,      TRUE,
        PRIM_MEDIA_AUTO_SCALE,     TRUE,
        // INTERACT en ANYONE: si el navegador de un oyente bloquea el autoplay,
        // podrá pulsar el botón "Reproducir" de respaldo de player.html.
        PRIM_MEDIA_PERMS_INTERACT, PRIM_MEDIA_PERM_ANYONE,
        PRIM_MEDIA_PERMS_CONTROL,  PRIM_MEDIA_PERM_OWNER,
        PRIM_MEDIA_WIDTH_PIXELS,   512,
        PRIM_MEDIA_HEIGHT_PIXELS,  512
    ]);
    hideScreen();
    llOwnerSay("♪ Reproduciendo: " + title);
}

// ------------------------------ SCRIPT PRINCIPAL ---------------------------
default
{
    state_entry()
    {
        // Canal negativo pseudoaleatorio derivado de la key del objeto:
        // los últimos 8 hex de la key como entero, forzado a negativo con el
        // bit de signo. Evita colisiones con otros objetos con diálogos.
        gChannel = 0x80000000 | (integer)("0x" + llGetSubString((string)llGetKey(), -8, -1));
        cleanup();
        // Si el script se reseteó con la cara oculta, el alpha guardado se
        // perdió: con HIDE_SCREEN la cara debe verse en reposo, así que la
        // dejamos opaca conservando su color.
        if (HIDE_SCREEN)
        {
            list c = llGetPrimitiveParams([PRIM_COLOR, MEDIA_FACE]);
            if (llList2Float(c, 1) == 0.0)
                llSetPrimitiveParams([PRIM_COLOR, MEDIA_FACE, llList2Vector(c, 0), 1.0]);
        }
        llOwnerSay("Jukebox listo. Tócame para elegir canción.");
    }

    touch_start(integer num)
    {
        // Solo responde al dueño; el resto de avatares se ignora en silencio.
        if (llDetectedKey(0) != llGetOwner()) return;

        // El default de HTTP_BODY_MAXLENGTH es 2048 y truncaría el catálogo;
        // lo subimos a 16384 (catálogos de hasta ~16 KB).
        gReqId = llHTTPRequest(BASE_URL + "/catalog.txt",
            [HTTP_METHOD, "GET", HTTP_BODY_MAXLENGTH, 16384], "");
        if (gReqId == NULL_KEY)
            llOwnerSay("No se pudo lanzar la petición HTTP. Revisa BASE_URL en el script.");
    }

    http_response(key id, integer status, list meta, string body)
    {
        if (id != gReqId) return; // respuesta de otra petición, no nuestra

        if (status != 200)
        {
            llOwnerSay("Error al descargar el catálogo (HTTP " + (string)status
                + "). Revisa que BASE_URL sea correcta, con https y sin slash final.");
            return;
        }

        // Parseo del catálogo: una línea por canción, formato "Título|archivo".
        // Se ignoran líneas vacías y comentarios (#). llStringTrim también
        // elimina el \r de finales de línea CRLF.
        gTitles = [];
        gFiles  = [];
        list lines = llParseStringKeepNulls(body, ["\n"], []);
        integer n = llGetListLength(lines);
        integer i;
        for (i = 0; i < n; ++i)
        {
            string line = llStringTrim(llList2String(lines, i), STRING_TRIM);
            if (line != "" && llGetSubString(line, 0, 0) != "#")
            {
                integer sep = llSubStringIndex(line, "|");
                if (sep > 0)
                {
                    string t = llStringTrim(llGetSubString(line, 0, sep - 1), STRING_TRIM);
                    string f = llStringTrim(llGetSubString(line, sep + 1, -1), STRING_TRIM);
                    if (t != "" && f != "")
                    {
                        gTitles += [t];
                        gFiles  += [f];
                    }
                }
            }
        }

        gPage = 0;
        showMenu();
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (channel != gChannel) return;
        cleanup(); // cada respuesta consume el diálogo actual

        if (msg == BTN_PREV)
        {
            --gPage;
            showMenu();
            return;
        }
        if (msg == BTN_NEXT)
        {
            ++gPage;
            showMenu();
            return;
        }
        if (msg == BTN_STOP)
        {
            stopSong();
            llOwnerSay("■ Reproducción detenida.");
            return;
        }

        // Es una canción: mapear la etiqueta (posiblemente truncada) de vuelta
        // al índice GLOBAL comparando contra el truncado de los títulos de la
        // página actual. Nunca se busca el archivo por el texto del botón.
        integer start = gPage * SONGS_PER_PAGE;
        integer end   = start + SONGS_PER_PAGE - 1;
        integer total = llGetListLength(gTitles);
        if (end >= total) end = total - 1;
        integer i;
        for (i = start; i <= end; ++i)
        {
            string label = truncBytes(llList2String(gTitles, i), 24);
            if (label == "") label = "♪ " + (string)(i + 1);
            if (msg == label)
            {
                playSong(i);
                return;
            }
        }
        llOwnerSay("No reconozco esa opción; vuelve a tocarme para abrir el menú.");
    }

    timer()
    {
        // Menú caducado sin respuesta: cerrar listener para no gastar recursos.
        cleanup();
        llOwnerSay("Menú cerrado por inactividad.");
    }

    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript(); // nuevo dueño: canal y estado desde cero
        }
        if (change & (CHANGED_REGION | CHANGED_TELEPORT))
        {
            cleanup(); // no relanzar media automáticamente tras teleport
        }
    }

    on_rez(integer param)
    {
        cleanup();
        // La URL de media queda guardada en el prim: sin esto, al rezar la
        // guitarra la última canción arrancaría sola. Siempre nace en silencio.
        stopSong();
    }

    attach(key id)
    {
        cleanup();
        // id != NULL_KEY = alguien acaba de PONERSE la guitarra (NULL_KEY es
        // al quitársela). Limpia la media para que siempre empiece en silencio
        // aunque se la quitara con una canción sonando.
        if (id != NULL_KEY) stopSong();
    }
}
