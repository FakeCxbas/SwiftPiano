# SwiftPiano — Godot 4 / 2D Synth

Proyecto nativo en GDScript. Incluye muestras de Salamander Grand Piano; no requiere Python, pip, plugins
ni una conexión de red para tocar. La versión anterior se conserva en
`legacy_python/`, excluida del importador de Godot mediante `.gdignore`.

## Ejecutar

```sh
git clone https://github.com/FakeCxbas/SwiftPiano.git
cd SwiftPiano
godot --path .
```

También funciona `./run.sh`. Para abrir el editor:

```sh
godot --editor --path .
```

Probado con Godot **4.7.2** instalado en este equipo, sobre Vulkan Mobile y una
AMD Radeon RX 550. El proyecto usa Mobile, HDR 2D y WorldEnvironment con glow.
Si otro equipo no dispone de Vulkan, se puede ejecutar con:

```sh
godot --path . --rendering-method gl_compatibility
```

El halo multicapa aditivo sigue funcionando en Compatibility, aunque la
disponibilidad de bloom/HDR depende de la versión del motor y del backend.
El proyecto solicita 1600×900; acepta el tamaño real asignado por el gestor
de ventanas. No cambia configuraciones de Hyprland/Caelestia ni insiste en un
tamaño mínimo. Está limitado a 60 FPS con VSync habilitado.

## Archivos

```text
project.godot
scenes/main.tscn                    # Solo raíz Control + script por ruta
scripts/
  main.gd                          # Orquestación, foco y fuentes de entrada
  studio_menu.gd                   # Menú superior, biblioteca, editor y apariencia
  studio_theme.gd                  # Tema nativo compartido
  music_library.gd                 # Carga y búsqueda del catálogo JSON
  keymap_data.gd                   # 88 notas; 61 asignaciones QWERTY
  audio_engine.gd                  # Salamander Grand Piano y pool polifónico
  synth_visualizer.gd              # Barras a 340 px/s, HDR y halo aditivo
  piano_keyboard_renderer.gd       # Dibujo, etiquetas, clic/arrastre
  sheet_parser.gd                  # Acordes, notas y directivas
tests/test_piano.gd                 # Pruebas nativas Godot
run.sh
legacy_python/                     # Respaldo de la implementación anterior
assets/grand_piano/                 # 30 muestras estéreo + licencia/atribución
assets/library/letras.json          # 92 entradas extraídas de Letras.pdf
tools/extract_library.py            # Extracción reproducible con Poppler
```

Toda la jerarquía visual, los reproductores y el WorldEnvironment se crean por
código. La escena usa rutas `res://`, sin dependencias de UIDs en su contenido.
Los `.gd.uid` generados automáticamente por el editor pueden conservarse.

## Piano y controles

El teclado tiene 88 notas A0–C8 (52 blancas y 36 negras), todas con asignaciones
físicas permanentes y etiquetas. Las 61 centrales conservan Virtual Piano;
las 27 extremas usan teclas adicionales. No hay cambios de banco ni de octava.
El menú superior reúne Biblioteca, Hoja, Apariencia, Sustain, Auto y volumen.
Se adapta a ventanas estrechas en dos filas de acciones.
El piano ocupa todo el ancho del 20% inferior; el visualizador ocupa el espacio restante.
El borde superior y las teclas usan el color seleccionado. Al pulsar aparecen
un relleno luminoso y un brillo de contacto; al soltar, la luz cae en 200 ms.
Las etiquetas adaptan su contraste al color de la tecla.

- Blancas: `1234567890qwertyuiopasdfghjklzxcvbnm`.
- Negras: `! @ $ % ^ * ( Q W E T Y I O P S D G H J L Z C V B`.
  Usa Shift con `1 2 4 5 6 8 9 q w e t y i o p s d g h j l z c v b`.
- Ratón: clic y arrastre sobre cualquiera de las 88 teclas.
- A0–B1 (15 notas, de izquierda a derecha): F1–F12, acento grave, `-`, `=`.
- C#7–C8 (12 notas): `[`, `]`, barra invertida, `;`, comilla simple, coma,
  punto, `/`, Insert, Delete, PageUp, PageDown.
- Ejemplos: F1 toca A0 y PageDown toca C8, sin cambiar ningún modo.
  En portátiles puede ser necesario Fn para las teclas de función/navegación.
  Los atajos del sistema operativo tienen prioridad si interceptan alguna tecla.
- `Sustain` enclava el pedal; Space lo mantiene temporalmente cuando está apagado.
- `Shift + Space` alterna el enclavamiento. Soltar Space respeta el estado del botón,
  incluso al escribir espacios en el buscador o en la hoja.
- `Hoja` abre el editor; `Activar Auto` / `Pausar Auto` actúa directamente.
- `Biblioteca` permite buscar y cargar las canciones del PDF.
- `Estudio` reúne instrumentos, reverberación, colores, barras e iluminación.

La interfaz mantiene sincronizada la pestaña activa al cerrar los paneles.
Los paneles recortan su contenido y permiten desplazamiento en ventanas pequeñas;
los botones de instrumento muestran el nombre completo como ayuda al pasar el
cursor. Auto permanece deshabilitado cuando no hay pasos cargados.
El efecto de vidrio usa un desenfoque fijo sin mipmaps de pantalla.
Prueba de clics y distribución: `tests/test_ui_controls.gd` (85 comprobaciones).

### Convertir un MIDI a una hoja tocable

1. Abre **Hoja → Importar MIDI** y selecciona un `.mid` o `.midi`.
2. Revisa el resumen y activa **Auto**. Cada pulsación de una letra o número
   toca el siguiente paso; mantenerla sostiene ese acorde hasta que la sueltes.
3. **Guardar hoja** exporta el resultado como `.txt`; para recuperarlo, copia su
   contenido y usa **Pegar** en la hoja. Importar no agrega una entrada permanente
   a la biblioteca del PDF.

El lector integrado admite Standard MIDI File 0/1 con división PPQN, combina
las pistas melódicas y agrupa ataques con el mismo tick, sin cuantización.
Se omite el canal de percusión (10) y las notas fuera de A0–C8, con un aviso.
No selecciona automáticamente una melodía entre los instrumentos de un arreglo:
para tocar solo una parte, exporta previamente esa pista desde tu editor MIDI.

La hoja usa líneas `MIDI: 21 60 108 # teclas: F1 t PgD` con pitches absolutos,
para conservar las 88 teclas sin transponerlas al rango central de Virtual Piano.
El comentario muestra las teclas físicas asignadas. Estas líneas pueden editarse
y coexistir con la notación de Virtual Piano. Los números MIDI van de 21 a 108.

Esta conversión está pensada para el Auto manual: no reproduce los tempos,
silencios, duraciones, velocidades, pedal ni cambios de instrumento del archivo.
El intérprete controla el ritmo y Sustain, con el timbre actual de SwiftPiano.
Se rechazan archivos inválidos, formato 2 y SMPTE. Límites: 8 MB, 256 pistas,
200.000 eventos y 10.000 pasos. Un error no sustituye la hoja existente.

Referencia del formato: [Standard MIDI Files, MIDI Association](https://midi.org/standard-midi-files).
Pruebas del lector y flujo de importación/exportación:
`godot --headless --audio-driver Dummy --path . --script tests/test_midi_import.gd`.

El ambiente inicial es **Sala → Estudio · Claro**: mantiene la señal directa al
100%, reduce la mezcla reverberada un 65% frente a Sala de Conciertos, acorta la
sala y elimina la realimentación del predelay. Las muestras, su caída natural,
la intensidad y el funcionamiento del Sustain se conservan. Sala de Conciertos
mantiene el ambiente anterior; Seco / Directo elimina la reverberación añadida
(no la resonancia que ya esté grabada en una muestra).

`tests/test_audio_clarity.gd` compara la cola de reverberación aislada entre el
ambiente original y el nuevo en tres pianos, capturando la salida Master.

Las etiquetas y el visualizador permanecen activos; Sustain comienza encendido.
La intensidad se fija en 88/127. El deslizador de volumen permite ajustar la salida
de 0 a 100% (100% inicial). El nuevo 100% equivale al antiguo 200%:
50% equivale al antiguo 100% en el control de voces, y 0% silencia. El realce de
salida es ahora 6,8 dB (+3 dB respecto al ajuste claro inicial) y ocurre antes del
limitador final de −0,5 dBFS, después de la reverberación. La prueba de audio captura
Master para comprobar toda la cadena. Conviene empezar con un volumen bajo,
especialmente con auriculares. La
transposición afecta tanto al audio como al estado visual. Las notas fuera de
A0–C8 se omiten. Cada fuente conserva sus pitches hasta keyup: cambiar de modo
o transposición durante una pulsación no deja notas atascadas. Perder el foco
de la aplicación libera todas las fuentes y silencia el pool.

## Auto

1. Abre `Hoja` en la barra superior o carga una canción desde `Biblioteca`.
2. La hoja de demostración viene precargada con **34 pasos**.
3. Pulsa `Activar Auto`: cada letra o número ejecuta el siguiente paso.
4. Mantén la tecla para sostener el acorde; soltarla libera solo esa fuente.
5. El contador indica el siguiente paso, con vista previa del acorde y progreso.
   Al terminar la hoja se vuelve al inicio.

`Pausar Auto` vuelve al modo manual y conserva la posición; reactivarlo continúa.
`Reiniciar` vuelve al primer paso. `Pegar` carga el portapapeles y pausa Auto para
revisar el texto; `Borrar` vacía la hoja y desactiva Auto. `Cerrar` oculta el
editor sin detener Auto: el indicador superior muestra si sigue activo.
Una hoja vacía no puede activar Auto.

El editor oscuro permite selección, Ctrl+A/C/V y texto multilínea cuando Auto
está pausado. Escape o un clic fuera libera su foco. Con Auto activo queda de
solo lectura y las letras/números se usan para tocar, no para editar.

La hoja y las etiquetas de próximos acordes se compilan solamente al cambiar
el texto. Cada paso actualiza únicamente el contador, la vista previa y el
progreso, sin regenerar etiquetas del piano ni refrescar todos los controles.

## Biblioteca del PDF

Se han separado **92 entradas** de las 181 páginas de `Letras.pdf`: canciones,
versiones y fragmentos. **91 contienen notas**; “Love Story” (página 152) solo
tiene título, se muestra como “sin notas” y no puede cargarse. El catálogo incluye
los encabezados pequeños que no figuran en el índice del PDF; no se mezclan con
la canción anterior. Se conservan los títulos originales, incluso sus erratas.

Busca por título, selecciona y pulsa **Cargar hoja**, o haz doble clic. Se carga
en pausa, con su página de origen, y vuelve al paso inicial. Los cambios de cada
hoja se conservan como borradores **durante la sesión**, al cambiar de canción.
No se guardan al cerrar. No hay reproducción temporizada: Auto sigue avanzando
una nota o acorde por pulsación; el PDF no incluye tiempos precisos.

El JSON incluido no necesita el PDF, Python ni Internet al ejecutar la aplicación.
El importador usa Poppler para leer texto y tamaño de fuente, y verifica los
62 encabezados principales contra el índice. Las 30 entradas adicionales se
detectan por su tipografía. La revisión visual confirmó límites con varios
títulos en una página y la entrada sin notas. El parser tolera corchetes incompletos
del documento original; no se ha corregido o inventado el arreglo musical.
Usa esta biblioteca personal conforme a los permisos que tengas sobre el PDF.

## Hojas “Letras”

```text
Title: Mi canción
Transposition: 4
6 [er] [680] [W0ryd] abc
Transposition: 0
r [yI]
```

Cada bloque entre corchetes produce un paso con notas simultáneas; fuera de los
corchetes, cada carácter válido es un paso. Se deduplican notas repetidas dentro
del mismo acorde. Las directivas se aplican a los pasos siguientes; los acordes
pueden cruzar saltos de línea. Se recuperan corchetes incompletos sin excepciones.

Los títulos se reconocen con `Title:`, `Song:`, `Artist:`, `By:`, variantes en
español, prefijos `#`/`//` y encabezados comunes de varias palabras en Title Case.
Un título arbitrario formado por letras válidas es ambiguo con una hoja: usa
`Title:` o `#` para garantizar su exclusión.

En las hojas de la biblioteca, `(` se interpreta como su tecla negra para
conservar las notas del PDF. En las hojas pegadas manualmente se conserva el
comportamiento anterior de ignorarlo. Los símbolos `|`, `?`, `-`, `)` se ignoran.
Se reconocen tanto `Transposition: 4` como `Transpose -11` o `Transposition -8`.

## Sonido y rendimiento

El sonido predeterminado es **Salamander Grand Piano V3**, un Yamaha C5 grabado
por Alexander Holm. Se incluyen 30 muestras Ogg Vorbis estéreo de la distribución
Tone.js, con referencias cada tres semitonos desde A0 hasta C8. Las notas
intermedias usan `pitch_scale` con un ajuste máximo de un semitono, conservando
el ataque, la resonancia y la caída natural de las grabaciones.

Es un banco reducido de una capa de intensidad, no el SFZ completo de 16 capas:
La intensidad fija usa una curva dinámica de volumen. No se requiere FluidSynth,
VST ni otro programa de audio. Un compresor moderado y un limitador predictivo
en un bus independiente controlan los picos de los acordes. El sintetizador anterior solo queda como
respaldo si faltan todas las muestras.

La ganancia base es 1,0: se retiró la amplificación excesiva de 2,0.
Esto deja 6 dB más de margen que aquella versión y conserva 3,74 dB más de
ganancia que la versión original de 0,65. Para aumentar la presencia sin
sobrecargar la entrada, el compresor usa umbral −16 dB, relación 2,5:1,
ataque 2 ms y recuperación 180 ms, con 6 dB de ganancia de compensación.
Esto eleva las notas suaves y comprime más los acordes intensos; reduce el
rango dinámico y no equivale a aumentar la potencia física de los altavoces.
AudioEffectHardLimiter sustituye al antiguo limitador de recorte suave:
reduce ganancia anticipando picos, con techo de −1,5 dB y recuperación 150 ms.
El volumen visible llega al 100% (equivalente al antiguo 200%); los acordes intensos pueden activar
la compresión. No se modifica el volumen del sistema ni se garantiza que
unos altavoces o amplificadores externos no distorsionen.

Las muestras ocupan aproximadamente **6,7 MB** y la carga medida fue de **28 ms**,
incluidos los 64 reproductores iniciales; puede variar con el equipo y la caché.
Los archivos están incluidos y funcionan sin Internet. Créditos, procedencia y
licencia **CC BY 3.0** en [ATTRIBUTION.md](assets/grand_piano/ATTRIBUTION.md).

La duración natural de cada muestra es finita. Con Sustain activo, soltar la
tecla conserva la caída grabada completa, sin un corte artificial a 1,8 s.
Sin pedal, soltar una tecla la amortigua en 0,18 s. Levantar el pedal amortigua
las notas ya soltadas, pero nunca las teclas que sigues manteniendo.
Volver a pisarlo durante esa amortiguación conserva el sonido restante.
El pedal no hace que las muestras suenen indefinidamente ni reinicia notas terminadas.
Si se ocupan los 64 reproductores, el pool crece en bloques de 16 para conservar
las voces anteriores. El volumen general afecta también las colas en curso.

El color fijo elegido se comparte entre teclas y barras. En modo arcoíris se
captura al nacer cada barra con `fmod(Time.get_ticks_msec() * 0.00008, 1.0)`. La punta sube a 340 px/s y la base
queda anclada mientras la fuente está pulsada. El dibujo usa `_draw()` y un
único hijo aditivo para los halos, sin crear nodos individuales por nota.

## Verificación

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_piano.gd
godot --headless --audio-driver Dummy --path . --script tests/test_audio_mix.gd
godot --path . --script tests/test_piano.gd -- --capture
```

El último comando abre brevemente una ventana real, prueba el render GPU,
guarda una captura en `/tmp/swiftpiano-godot.png` y cierra. Las pruebas cubren
mapeo, geometría, estados iniciales, PCM, parser, foco, eco, acordes mantenidos
y solapados, transposición, ratón, pedal, 80 voces y una ventana de 751 px.
El acceso a un portapapeles real y la calidad percibida del audio requieren
comprobación interactiva; las pruebas automáticas no sustituyen esa escucha.

La prueba de mezcla captura PCM después de los efectos, sin reproducirlo por
los altavoces. Comprueba señal no vacía, ausencia de recorte a 0 dBFS y el techo
de −1,5 dBFS: nota individual, acorde de ocho notas, acordes repetidos con pedal
al 200% y 64 voces a intensidad máxima. No mide la distorsión del equipo físico.
Añade `-- --reference` al comando de mezcla para medir el perfil anterior
sin modificar la configuración de la aplicación.

## Licencia y Autoría

Este proyecto está disponible bajo la licencia [MIT](LICENSE).
Consulta el archivo [AUTHORS.md](AUTHORS.md) para detalles del autor principal y créditos de desarrollo.

Los bancos de sonido y muestras de audio de terceros tienen sus propias licencias abiertas y atribuciones correspondientes:
- Muestras del piano de cola: [Salamander Grand Piano](assets/grand_piano/ATTRIBUTION.md) (Creative Commons CC BY 3.0).
- Instrumentos adicionales: [Attribution Instruments](assets/instruments/ATTRIBUTION.md).


