# SwiftPiano

Piano de escritorio 2D de 88 teclas (A0–C8), con 61 etiquetas Virtual Piano
centrales, barras ascendentes arcoíris y Auto por pulsación. No hay reproducción
temporizada: cada pulsación avanza un paso y cada liberación suelta ese acorde.

## Requisitos y ejecución

- Python 3.11 o superior
- `pygame-ce` 2.5+
- NumPy 2.2+ (síntesis vectorizada durante la precarga)

```bash
python -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
./run.sh
```

`run.sh` funciona desde Bash, Fish y Zsh sin activar manualmente el entorno.
También se puede ejecutar directamente con `.venv/bin/python main.py`.

Si se prefiere activar el entorno, use el script correspondiente al shell:

```bash
# Bash/Zsh
source .venv/bin/activate

# Fish
source .venv/bin/activate.fish
```

El entorno virtual del workspace ya está actualizado. Para instalaciones nuevas,
los comandos anteriores instalan todas las dependencias. No requiere Internet
después de instalarlas. El sonido se precarga antes de habilitar el teclado,
con un breve mensaje de carga; no hay síntesis costosa dentro de `keydown`.

Se usa un solo timbre de piano sintetizado como alternativa autónoma. No es una
grabación de Grand Piano ni el audio original de Piano Rooms. Para usar un banco
de grabaciones de piano, coloque WAV estéreo/mono en `assets/samples/` con nombres
como `C4.wav`, `Cs4.wav`, `C#4.wav` o `60.wav`. Las notas faltantes o los WAV que
no puedan abrirse recurren al mismo sintetizador. Hay 128 canales iniciales y el
mezclador amplía su capacidad si se agotan: no roba voces de acordes anteriores.
Las notas tienen decaimiento acústico finito incluso con sustain, como un piano.

## Controles

- Teclas blancas: `1234567890qwertyuiopasdfghjklzxcvbnm`
- Negras: `! @ $ % ^ * ( Q W E T Y I O P S D G H J L Z C V B`.
  Manualmente se usa Shift con `1 2 4 5 6 8 9 q w e t y i o p s d g h j l z c v b`.
- Clic o arrastre sobre cualquiera de las 88 teclas: tocar con ratón.
- `Qwerty Toggle`: muestra/oculta etiquetas, sin desactivar el teclado físico.
- `Sustain`: enclava el pedal; `Space` lo mantiene momentáneamente.
- `Invert Sustain`: pedal activo por defecto, `Space` lo levanta mientras se mantiene.
  La inversión tiene prioridad sobre el enclavamiento de Sustain.
- `Transposition`: clic izquierdo +1, derecho −1; también admite rueda.
  Se aplica a audio y tecla visual al iniciar una nota; los extremos fuera de
  A0–C8 se omiten, sin plegarlos ni cambiarlos a otra octava.
- `Volume`: clic izquierdo +5%, derecho −5% o rueda; afecta también voces activas.
- `Velocity`: clic izquierdo +1, derecho −1 o rueda, entre 1 y 127.
- `Auto`: abre/cierra la ventana; `Sheets` también la abre.
- `2D Synth`: muestra/oculta las barras. El piano continúa funcionando.
- `Esc`: quita el foco del editor, cierra Auto o sale, según el contexto.

`R` vuelve a ser una nota; no hay atajos alfabéticos que compitan con el piano.

## Auto y editor de hojas

1. Pulse `Auto` en el panel inferior derecho. La hoja solicitada está precargada.
2. El botón `Auto` de la ventana activa el avance por pulsación y muestra una barra verde.
3. Pulse cualquier letra o número: ejecuta un paso. Mantenga la tecla para alargar
   las barras; suéltela para desprenderlas. Se permiten acordes y fuentes solapadas.
4. Al completar la hoja, el índice vuelve a cero. El contador muestra el próximo
   índice, comenzando en 0. No hay temporizador ni evaluación Perfect/Good/Miss.

Para editar, desactive Auto y haga clic en el cuadro blanco. Admite Ctrl+V desde
el portapapeles de escritorio, Ctrl+A/C/X, texto Unicode, flechas, Inicio/Fin,
selección con Shift, Enter, borrar y rueda para desplazamiento. Al activar Auto
o hacer clic fuera, pierde el foco y compila la hoja. `Clear` borra y reinicia el
índice; `Exit` cierra la ventana, sin cancelar las notas que aún se mantienen.
`88KEY` identifica el rango fijo y muestra A0–C8; no cambia la afinación ni el mapa.

El portapapeles usa SDL/Pygame y necesita una sesión gráfica con acceso al
portapapeles del escritorio. Un error se muestra dentro de la ventana Auto.

## Formato de canción

```text
Title: Mi canción
Transposition: 4
6 [er] [680] [W0ryd] abc
Transposition: 0
[qe]
```

Cada carácter mapeado fuera de corchetes es un paso; un acorde es un único paso.
Los caracteres repetidos en un mismo acorde se deduplican. Las directivas se
aplican a los pasos siguientes y se repiten correctamente al volver al inicio.
Se ignoran separadores y caracteres no mapeados; un acorde puede cruzar líneas.
Los corchetes incompletos se recuperan sin provocar excepciones.

Para títulos se reconocen `Title:`, `Song:`, `Artist:`, `By:`, sus variantes
españolas, líneas `#`/`//` y encabezados típicos de varias palabras en Title Case.
Texto sin marcar compuesto solo por letras válidas es ambiguo con una partitura:
use `Title:` o `#` para garantizar que se ignore cualquier título.

La especificación incluye `(` como nota negra y como separador ignorado:
se conserva en el teclado manual y se ignora en las hojas. El antiguo JSON
temporizado ya no se utiliza. Puede cargar un archivo de letras UTF-8 con:

```sh
./run.sh --sheet mi-cancion.txt
```

## Arquitectura y verificación

- `input_manager.py`: mapeo y propiedad de notas por fuente física.
- `audio_engine.py`: banco precargado, canales independientes y pedal.
- `sheet_parser.py`: pasos, directivas y avance cíclico.
- `waterfall_renderer.py`: geometría, barras, controles y editor con foco.
- `vfx_manager.py`: píldoras con glow aditivo RGB y ciclo HSV global.
- `main.py`: coordinación, eventos y bucle limitado a 60 FPS.

Lienzo `#050505` superior al 80%; teclado inferior con el 82% del ancho;
panel con el 18% restante. Fieltro `#a50000` de 4 px. Teclas activas grises.
El hue sigue exactamente `(segundos * 35) % 360` (por ello empieza en rojo).
Se siguen las proporciones y colores de la especificación; no se ha realizado
una comparación píxel a píxel con una captura del juego original.

```sh
.venv/bin/python -m pip install pytest
.venv/bin/python -m pytest -q
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./run.sh --frames 5
```

Las pruebas incluyen el mezclador real con audio SDL virtual, 80 voces,
solapamiento de acordes, foco, pegado simulado, mouse, parser, transposición y
colores del render. La salida al dispositivo de audio y el portapapeles de tu
sesión gráfica necesitan una comprobación interactiva en tu escritorio.
