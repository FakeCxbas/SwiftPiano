---
name: swiftpiano-midi-sheets
description: >-
  MIDI import parser, Virtual Piano (VP) notation, chord voicings, transpositions,
  and sheet converter architecture for SwiftPiano. Use when modifying notation formats,
  song libraries, MIDI parsing, or chord reduction.
---

# SwiftPiano MIDI & Sheet Music Architecture

Standards for importing MIDI files, converting scores into Virtual Piano notation, and serializing musical chords.

---

## 1. Virtual Piano Notation & Extensions

* **Mapeo Básico VP (61 Teclas)**:
  - Teclas simples: caracteres alfanuméricos (`1..0`, `q..p`, `a..l`, `z..m`).
  - Teclas mayúsculas: sostenidos / bemoles (`!`, `@`, `Q`, `W`, etc.).
  - Acordes: notas simultáneas agrupadas entre corchetes, por ejemplo `[9o]`, `[etup]`.
* **Extensión SwiftPiano para 88 Teclas (`MIDI:`)**:
  - Para notas extremas por debajo de A1 o por encima de C7 que no tienen tecla en el teclado QWERTY estándar de Virtual Piano, serializar como líneas explícitas `MIDI:`:
    ```text
    [9o] [8i] MIDI:21,108
    ```
  - Esta sintaxis previene la pérdida de las 27 notas fuera del mapa VP central.

---

## 2. Reducción y Voicing de Acordes (`sheet_converter.gd`)

Al convertir un archivo MIDI denso (e.g. archivo de piano de 10 dedos) para ejecución manual:
* **Separación de Voces**: Reducir a un máximo de 3 voces interpretables simultáneamente:
  1. *Bajo*: Nota más grave en el tick.
  2. *Voz Intermedia*: Nota con mayor relevancia armónica o centro tonal.
  3. *Agudo (Melodía)*: Nota más aguda en el tick.
* **Transposición Controlada**:
  - Ajustar por semitonos manteniendo la tonalidad coherente.
  - Informar el conteo exacto de notas transpuestas que se salieron de la tesitura A0–C8.

---

## 3. Principio de Preservación de Formato

* No inventar BPMs ni tempos automáticos que no existan en el texto de la hoja.
* El modo `Auto` de SwiftPiano es reactivo y manual: avanza cuando el usuario presiona las teclas, sosteniendo acordes hasta que se liberan.
