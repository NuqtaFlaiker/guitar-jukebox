// ============================================================================
// GuitarJukebox.lsl — Jukebox MOAP para guitarra (attachment) en Second Life
//
// Al tocar la guitarra (solo el dueño) se abre un menú principal:
//   ♪ Canciones — descarga catalog.txt y muestra la lista paginada
//   Animación   — reproduce la animación "1" o "2" del Contenido del objeto
//   Mover / Rotar / Tamaño — ajusta la guitarra puesta sin abrir el editor
//   ■ Detener   — para la música
//
// Con una canción sonando, el clic sobre la cara de la media interactúa con
// la página web y puede NO abrir el menú: escribe "/1 menu" en el chat para
// abrirlo siempre.
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
float   HTTP_TIMEOUT   = 15.0; // segundos de espera máxima por catalog.txt

// Canal de chat de emergencia: mientras suena una canción, el clic sobre la
// cara de la media lo captura la página web y no dispara el touch. Escribiendo
// "/1 menu" en el chat local el menú se abre siempre (solo funciona al dueño).
integer CHAT_CHANNEL = 1;
string  CHAT_CMD     = "menu";

// 9 canciones por página + 3 botones de navegación = 12 botones,
// que es el MÁXIMO permitido por llDialog. No subir de 9.
integer SONGS_PER_PAGE = 9;

// Nombres de las animaciones dentro del Contenido de la guitarra.
string  ANIM_1 = "1";
string  ANIM_2 = "2";

// Pasos de los ajustes.
float   MOVE_STEP = 0.02;  // metros por pulsación
float   ROT_STEP  = 15.0;  // grados por pulsación
float   SIZE_STEP = 1.10;  // factor por pulsación (10 % más grande / pequeña)
float   SIZE_MIN  = 0.25;  // tamaño total mínimo respecto al original (25 %)
float   SIZE_MAX  = 4.0;   // tamaño total máximo respecto al original (400 %)

// Volumen base del reproductor (1–10), IGUAL PARA TODOS los oyentes: viaja
// en la URL de la media. OJO: la media MOAP apenas atenúa (o nada) con la
// distancia según el viewer de cada uno, así que este volumen es la única
// palanca real para que la guitarra no atrone en toda la sim. Por eso el
// tope es un 10 % del volumen del navegador, ajustable de 1 en 1.
integer VOLUME_DEFAULT = 5;
integer VOLUME_MIN     = 1;
integer VOLUME_MAX     = 10;
integer VOLUME_STEP    = 1;

// Etiquetas de botones (cada una muy por debajo del límite de 24 bytes).
string BTN_PREV     = "« Ant";
string BTN_NEXT     = "Sig »";
string BTN_STOP     = "■ Detener";
string BTN_SONGS    = "♪ Canciones";
string BTN_ANIM     = "Animación";
string BTN_MOVE     = "Mover";
string BTN_ROT      = "Rotar";
string BTN_SIZE     = "Tamaño";
string BTN_BACK     = "« Menú";
string BTN_RESET    = "Reset";
string BTN_ANIM1    = "Anim 1";
string BTN_ANIM2    = "Anim 2";
string BTN_ANIM_OFF = "Quitar anim";
string BTN_BIGGER   = "+ Grande";
string BTN_SMALLER  = "- Pequeña";
string BTN_VOL      = "Volumen";
string BTN_VOL_UP   = "Vol +";
string BTN_VOL_DOWN = "Vol -";

// Identificadores del menú activo (para saber qué significan los botones).
integer MENU_MAIN  = 0;
integer MENU_SONGS = 1;
integer MENU_ANIM  = 2;
integer MENU_MOVE  = 3;
integer MENU_ROT   = 4;
integer MENU_SIZE  = 5;
integer MENU_VOL   = 6;

// ------------------------------ ESTADO INTERNO -----------------------------
list    gTitles;      // títulos visibles           (lista paralela a gFiles)
list    gFiles;       // nombres de archivo mp3     (lista paralela a gTitles)
integer gPage;        // página actual del menú de canciones (base 0)
integer gMenu;        // qué menú está abierto ahora mismo (MENU_*)
integer gChannel;     // canal de diálogo (negativo, derivado de la key del objeto)
integer gListen;      // handle del llListen activo (0 = ninguno)
key     gReqId;       // id de la petición HTTP en curso
integer gHidden;      // TRUE si la cara está oculta ahora mismo por HIDE_SCREEN
vector  gSavedColor;  // color original de la cara (para restaurarlo)
float   gSavedAlpha;  // alpha original de la cara (para restaurarlo)
string  gAnim;        // animación sonando ahora ("" = ninguna)
string  gPendingAnim; // animación a lanzar cuando lleguen los permisos
integer gPendingSet;  // TRUE si gPendingAnim está pendiente
vector  gHomePos;     // posición local original (para Reset de Mover)
rotation gHomeRot;    // rotación local original (para Reset de Rotar)
float   gSizeFactor;  // factor de tamaño acumulado respecto al original
integer gVolume;      // volumen base actual (se inicia a VOLUME_DEFAULT)
string  gNowFile;     // archivo de la canción sonando ("" = ninguna)
string  gNowTitle;    // título de la canción sonando
integer gChatListen;  // handle del listener permanente de chat ("/1 menu")
integer gHttpWait;    // TRUE mientras esperamos la descarga del catálogo

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
// Nota: llClearPrimMedia duerme el script 1.0 s; es normal. Solo se llama si
// de verdad hay media puesta: al vestirse la guitarra se disparan on_rez y
// attach seguidos, y sin esta comprobación el script dormiría 2 s para nada.
stopSong()
{
    if (llGetPrimMediaParams(MEDIA_FACE, [PRIM_MEDIA_CURRENT_URL]) != [])
        llClearPrimMedia(MEDIA_FACE);
    restoreScreen();
    gNowFile  = "";
    gNowTitle = "";
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

// Abre el listener del dueño y arma el timeout; común a todos los menús.
openDialog(string text, list buttons, integer menu)
{
    cleanup();
    gHttpWait = FALSE; // abrir cualquier menú abandona la espera del catálogo
    gMenu   = menu;
    gListen = llListen(gChannel, "", llGetOwner(), ""); // solo escucha al dueño
    llSetTimerEvent(DIALOG_TIMEOUT);
    llDialog(llGetOwner(), text, buttons, gChannel);
}

// Guarda la pose actual como "original" para los botones Reset.
captureHome()
{
    gHomePos    = llGetLocalPos();
    gHomeRot    = llGetLocalRot();
    gSizeFactor = 1.0;
}

// Etiqueta de botón de la canción i: número global + título, truncado a los
// 24 bytes de llDialog. El número hace cada etiqueta única, así dos títulos
// que truncaran igual (o uno idéntico a un botón de navegación) no pueden
// mapearse a la canción equivocada.
string songLabel(integer i)
{
    return truncBytes((string)(i + 1) + " " + llList2String(gTitles, i), 24);
}

// ------------------------------ MENÚS --------------------------------------

// llDialog coloca los primeros botones de la lista en la fila INFERIOR.
showMain()
{
    openDialog("🎸 Jukebox — ¿qué hacemos?",
        [BTN_SONGS, BTN_ANIM, BTN_STOP,
         BTN_MOVE, BTN_ROT, BTN_SIZE,
         BTN_VOL],
        MENU_MAIN);
}

// Muestra la página gPage del menú de canciones al dueño.
showSongs()
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

    // La navegación va primero para quedar en la fila de abajo del todo.
    list buttons = [BTN_PREV, BTN_BACK, BTN_NEXT];
    integer i;
    for (i = start; i <= end; ++i)
        buttons += [songLabel(i)];

    // Mensaje del diálogo: límite de 511 bytes; este texto queda muy por debajo.
    openDialog("🎸 Jukebox — página " + (string)(gPage + 1) + " de " + (string)pages
        + "\nElige una canción:",
        buttons, MENU_SONGS);
}

showAnim()
{
    string now = "ninguna";
    if (gAnim != "") now = gAnim;
    openDialog("🕺 Animación (ahora: " + now + ")",
        [BTN_ANIM1, BTN_ANIM2, BTN_ANIM_OFF, BTN_BACK],
        MENU_ANIM);
}

showMove()
{
    openDialog("↔ Mover — paso de " + (string)((integer)(MOVE_STEP * 100.0))
        + " cm por pulsación.\nReset vuelve a la posición original.",
        [BTN_BACK, BTN_RESET, "X +", "X -", "Y +", "Y -", "Z +", "Z -"],
        MENU_MOVE);
}

showRot()
{
    openDialog("⟳ Rotar — " + (string)((integer)ROT_STEP)
        + "° por pulsación.\nReset vuelve a la rotación original.",
        [BTN_BACK, BTN_RESET, "RotX +", "RotX -", "RotY +", "RotY -", "RotZ +", "RotZ -"],
        MENU_ROT);
}

showSize()
{
    openDialog("⤢ Tamaño — ahora al " + (string)((integer)(gSizeFactor * 100.0))
        + " % del original (límites " + (string)((integer)(SIZE_MIN * 100.0))
        + "–" + (string)((integer)(SIZE_MAX * 100.0)) + " %).",
        [BTN_BACK, BTN_RESET, BTN_BIGGER, BTN_SMALLER],
        MENU_SIZE);
}

showVol()
{
    openDialog("🔊 Volumen base: " + (string)gVolume + " de " + (string)VOLUME_MAX
        + " (igual para TODOS los oyentes).\n"
        + "La media MOAP apenas atenúa con la distancia: mantenlo bajo.\n"
        + "Cambiarlo con una canción sonando la reinicia desde el principio.",
        [BTN_BACK, BTN_VOL_DOWN, BTN_VOL_UP],
        MENU_VOL);
}

// ------------------------------ ANIMACIÓN ----------------------------------

// Para la animación actual y lanza la nueva ("" = solo parar).
applyAnim(string a)
{
    if (gAnim != "")
    {
        llStopAnimation(gAnim);
        gAnim = "";
    }
    if (a != "")
    {
        if (llGetInventoryType(a) != INVENTORY_ANIMATION)
        {
            llOwnerSay("No encuentro la animación \"" + a
                + "\" en el Contenido de la guitarra. Añádela con ese nombre exacto.");
            return;
        }
        llStartAnimation(a);
        gAnim = a;
    }
}

// Pide permisos si hacen falta (en attachments se conceden solos, sin ventana)
// y aplica la animación; si los permisos aún no llegaron, queda en cola.
setAnim(string a)
{
    if (llGetPermissions() & PERMISSION_TRIGGER_ANIMATION)
    {
        applyAnim(a);
        return;
    }
    gPendingAnim = a;
    gPendingSet  = TRUE;
    llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
}

// ------------------------------ AJUSTES ------------------------------------

// Escala TODO el objeto (raíz e hijos, con sus posiciones locales) por f.
scaleObject(float f)
{
    integer n = llGetNumberOfPrims();
    if (n <= 1)
    {
        llSetScale(llGetScale() * f);
        return;
    }
    integer i;
    for (i = 1; i <= n; ++i)
    {
        list p = llGetLinkPrimitiveParams(i, [PRIM_SIZE, PRIM_POS_LOCAL]);
        vector s = llList2Vector(p, 0) * f;
        if (i == 1)
            llSetLinkPrimitiveParamsFast(i, [PRIM_SIZE, s]);
        else
            // Los hijos también se alejan/acercan de la raíz para que el
            // conjunto escale como un todo y no se descoloque.
            llSetLinkPrimitiveParamsFast(i,
                [PRIM_SIZE, s, PRIM_POS_LOCAL, llList2Vector(p, 1) * f]);
    }
}

// TRUE si al multiplicar por f ningún prim se sale de los límites de SL
// (0.01–64 m por eje). Si un prim tocara el límite se deformaría el conjunto
// y el Reset ya no podría recuperarlo, así que mejor no aplicar nada.
integer canScale(float f)
{
    integer n = llGetNumberOfPrims();
    if (n < 1) n = 1;
    integer i;
    for (i = 1; i <= n; ++i)
    {
        vector s;
        if (n == 1) s = llGetScale() * f;
        else s = llList2Vector(llGetLinkPrimitiveParams(i, [PRIM_SIZE]), 0) * f;
        if (s.x < 0.01 || s.y < 0.01 || s.z < 0.01) return FALSE;
        if (s.x > 64.0 || s.y > 64.0 || s.z > 64.0) return FALSE;
    }
    return TRUE;
}

// Aplica un paso de tamaño respetando los límites configurados y los de SL.
resize(float f)
{
    float target = gSizeFactor * f;
    if (target < SIZE_MIN || target > SIZE_MAX || !canScale(f))
    {
        llOwnerSay("Ese tamaño se sale de los límites; no lo aplico.");
        return;
    }
    scaleObject(f);
    gSizeFactor = target;
}

// Rota la guitarra ROT_STEP grados alrededor de su propio eje axis.
rotateStep(vector axis, float sign)
{
    llSetLocalRot(llGetLocalRot()
        * llEuler2Rot(axis * (sign * ROT_STEP * DEG_TO_RAD)));
}

// ------------------------------ REPRODUCCIÓN -------------------------------

// Reproduce un archivo del catálogo apuntando la media de la cara. Se guarda
// el archivo/título (y no un índice): si el catálogo se recarga con otra
// lista, relanzar la canción actual (p. ej. al cambiar el volumen) sigue
// sonando la misma y no la que ahora ocupe su posición.
playFile(string file, string title)
{
    string url = BASE_URL + "/player.html?song=" + llEscapeURL(file)
               + "&title=" + llEscapeURL(title)
               + "&vol=" + (string)gVolume;

    // Límite de SL: la URL de media no puede superar 1024 bytes.
    // Tras llEscapeURL la cadena es ASCII puro, así que caracteres == bytes.
    if (llStringLength(url) > 1024)
    {
        llOwnerSay("No se puede reproducir \"" + title
            + "\": la URL supera los 1024 bytes. Acorta el título o el nombre de archivo.");
        return;
    }

    // Destruir la media anterior antes de poner la nueva: si un viewer ya
    // interactuó con la media (p.ej. pinchó el link flotante), deja de seguir
    // los cambios de URL del script y pide clic cada vez. Al limpiar primero,
    // cada canción llega como media nueva y carga sola para todos.
    llClearPrimMedia(MEDIA_FACE);

    // Nota: llSetPrimMediaParams (y llClearPrimMedia) duermen el script
    // 1.0 s cada una; el pequeño retardo al elegir canción es normal.
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
    gNowFile  = file;
    gNowTitle = title;
    llOwnerSay("♪ Reproduciendo: " + title);
}

// Reproduce la canción con índice global idx de la lista actual.
playSong(integer idx)
{
    playFile(llList2String(gFiles, idx), llList2String(gTitles, idx));
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
        captureHome();
        gVolume = VOLUME_DEFAULT;
        // Si el script se reseteó con la cara oculta, el alpha guardado se
        // perdió: con HIDE_SCREEN la cara debe verse en reposo, así que la
        // dejamos opaca conservando su color.
        if (HIDE_SCREEN)
        {
            list c = llGetPrimitiveParams([PRIM_COLOR, MEDIA_FACE]);
            if (llList2Float(c, 1) == 0.0)
                llSetPrimitiveParams([PRIM_COLOR, MEDIA_FACE, llList2Vector(c, 0), 1.0]);
        }
        // Listener permanente del comando de chat "/1 menu" (solo el dueño):
        // vía de escape cuando la media de la cara se traga los clics.
        gChatListen = llListen(CHAT_CHANNEL, "", llGetOwner(), "");
        // En attachments los permisos de animación se conceden en silencio.
        if (llGetAttached())
            llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
        llOwnerSay("Jukebox listo. Tócame para abrir el menú (o escribe /"
            + (string)CHAT_CHANNEL + " " + CHAT_CMD + ").");
    }

    touch_start(integer num)
    {
        // Solo responde al dueño; el resto de avatares se ignora en silencio.
        if (llDetectedKey(0) != llGetOwner()) return;
        showMain();
    }

    http_response(key id, integer status, list meta, string body)
    {
        if (id != gReqId) return; // respuesta de otra petición, no nuestra
        gHttpWait = FALSE;
        llSetTimerEvent(0.0);

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
        showSongs();
    }

    listen(integer channel, string name, key id, string msg)
    {
        // Comando de chat de emergencia: "/1 menu" abre el menú aunque la
        // media de la cara esté capturando los clics.
        if (channel == CHAT_CHANNEL)
        {
            if (llToLower(llStringTrim(msg, STRING_TRIM)) == CHAT_CMD)
                showMain();
            return;
        }

        if (channel != gChannel) return;
        integer menu = gMenu;
        cleanup(); // cada respuesta consume el diálogo actual

        if (msg == BTN_BACK)
        {
            showMain();
            return;
        }

        // ---------------- menú principal ----------------
        if (menu == MENU_MAIN)
        {
            if (msg == BTN_SONGS)
            {
                // El default de HTTP_BODY_MAXLENGTH es 2048 y truncaría el
                // catálogo; lo subimos a 16384 (catálogos de hasta ~16 KB).
                gReqId = llHTTPRequest(BASE_URL + "/catalog.txt",
                    [HTTP_METHOD, "GET", HTTP_BODY_MAXLENGTH, 16384], "");
                if (gReqId == NULL_KEY)
                {
                    llOwnerSay("No se pudo lanzar la petición HTTP. Revisa BASE_URL en el script.");
                    return;
                }
                // Si el servidor nunca responde, el timer avisa en vez de
                // dejar al dueño esperando un menú que no va a llegar.
                gHttpWait = TRUE;
                llSetTimerEvent(HTTP_TIMEOUT);
                return;
            }
            if (msg == BTN_ANIM)  { showAnim();  return; }
            if (msg == BTN_MOVE)  { showMove();  return; }
            if (msg == BTN_ROT)   { showRot();   return; }
            if (msg == BTN_SIZE)  { showSize();  return; }
            if (msg == BTN_VOL)   { showVol();   return; }
            if (msg == BTN_STOP)
            {
                stopSong();
                llOwnerSay("■ Reproducción detenida.");
                return;
            }
            return;
        }

        // ---------------- canciones ----------------
        if (menu == MENU_SONGS)
        {
            if (msg == BTN_PREV) { --gPage; showSongs(); return; }
            if (msg == BTN_NEXT) { ++gPage; showSongs(); return; }

            // Es una canción: mapear la etiqueta (numerada y posiblemente
            // truncada) de vuelta al índice GLOBAL regenerándola para cada
            // canción de la página actual. Nunca se busca el archivo por el
            // texto del botón.
            integer start = gPage * SONGS_PER_PAGE;
            integer end   = start + SONGS_PER_PAGE - 1;
            integer total = llGetListLength(gTitles);
            if (end >= total) end = total - 1;
            integer i;
            for (i = start; i <= end; ++i)
            {
                if (msg == songLabel(i))
                {
                    playSong(i);
                    return;
                }
            }
            llOwnerSay("No reconozco esa opción; vuelve a tocarme para abrir el menú.");
            return;
        }

        // ---------------- animación ----------------
        if (menu == MENU_ANIM)
        {
            if (msg == BTN_ANIM1)    setAnim(ANIM_1);
            else if (msg == BTN_ANIM2)    setAnim(ANIM_2);
            else if (msg == BTN_ANIM_OFF) setAnim("");
            showAnim(); // reabrir para poder seguir probando
            return;
        }

        // ---------------- mover ----------------
        if (menu == MENU_MOVE)
        {
            if (msg == BTN_RESET)  llSetPos(gHomePos);
            else if (msg == "X +") llSetPos(llGetLocalPos() + <MOVE_STEP, 0, 0>);
            else if (msg == "X -") llSetPos(llGetLocalPos() - <MOVE_STEP, 0, 0>);
            else if (msg == "Y +") llSetPos(llGetLocalPos() + <0, MOVE_STEP, 0>);
            else if (msg == "Y -") llSetPos(llGetLocalPos() - <0, MOVE_STEP, 0>);
            else if (msg == "Z +") llSetPos(llGetLocalPos() + <0, 0, MOVE_STEP>);
            else if (msg == "Z -") llSetPos(llGetLocalPos() - <0, 0, MOVE_STEP>);
            showMove();
            return;
        }

        // ---------------- rotar ----------------
        if (menu == MENU_ROT)
        {
            if (msg == BTN_RESET)     llSetLocalRot(gHomeRot);
            else if (msg == "RotX +") rotateStep(<1, 0, 0>,  1.0);
            else if (msg == "RotX -") rotateStep(<1, 0, 0>, -1.0);
            else if (msg == "RotY +") rotateStep(<0, 1, 0>,  1.0);
            else if (msg == "RotY -") rotateStep(<0, 1, 0>, -1.0);
            else if (msg == "RotZ +") rotateStep(<0, 0, 1>,  1.0);
            else if (msg == "RotZ -") rotateStep(<0, 0, 1>, -1.0);
            showRot();
            return;
        }

        // ---------------- volumen ----------------
        if (menu == MENU_VOL)
        {
            integer v = gVolume;
            if (msg == BTN_VOL_UP)        v += VOLUME_STEP;
            else if (msg == BTN_VOL_DOWN) v -= VOLUME_STEP;
            if (v < VOLUME_MIN) v = VOLUME_MIN; // 0 sería "no suena nada"
            if (v > VOLUME_MAX) v = VOLUME_MAX;
            if (v != gVolume)
            {
                gVolume = v;
                // El volumen viaja en la URL, así que para aplicarlo a la
                // canción actual hay que relanzarla (empieza desde el inicio).
                if (gNowFile != "") playFile(gNowFile, gNowTitle);
            }
            showVol();
            return;
        }

        // ---------------- tamaño ----------------
        if (menu == MENU_SIZE)
        {
            if (msg == BTN_RESET)
            {
                if (gSizeFactor != 1.0) scaleObject(1.0 / gSizeFactor);
                gSizeFactor = 1.0;
            }
            else if (msg == BTN_BIGGER)  resize(SIZE_STEP);
            else if (msg == BTN_SMALLER) resize(1.0 / SIZE_STEP);
            showSize();
            return;
        }
    }

    run_time_permissions(integer perms)
    {
        if ((perms & PERMISSION_TRIGGER_ANIMATION) && gPendingSet)
        {
            gPendingSet = FALSE;
            applyAnim(gPendingAnim);
        }
    }

    timer()
    {
        if (gHttpWait)
        {
            // El catálogo no llegó a tiempo: avisar en vez de callar.
            gHttpWait = FALSE;
            gReqId    = NULL_KEY; // ignorar una respuesta tardía
            llSetTimerEvent(0.0);
            llOwnerSay("El catálogo no responde (¿BASE_URL correcta? ¿GitHub Pages caído?). "
                + "Vuelve a intentarlo en un momento.");
            return;
        }
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
        if (id != NULL_KEY)
        {
            // Alguien acaba de PONERSE la guitarra (NULL_KEY es al quitársela).
            // Limpia la media para que siempre empiece en silencio aunque se
            // la quitara con una canción sonando.
            stopSong();
            // La pose "original" de los Reset pasa a ser la de este momento.
            captureHome();
            llRequestPermissions(llGetOwner(), PERMISSION_TRIGGER_ANIMATION);
        }
        else
        {
            // Al quitarse el attachment sus animaciones se detienen solas.
            gAnim = "";
        }
    }
}
