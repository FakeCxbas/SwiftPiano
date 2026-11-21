---
name: swiftpiano-audio-dsp
description: >-
  Digital signal processing, 88-key piano polyphony, audio buses, ADSR envelopes,
  sustain pedal logic, and sample management for SwiftPiano. Use when adjusting audio latency,
  volume curves, voice pooling, or adding audio effects.
---

# SwiftPiano Audio Architecture & DSP

Engineering principles for 88-key low-latency sound synthesis and polyphonic audio routing.

---

## 1. Tesitura y Mapeo de Notas (88 Teclas)

SwiftPiano cubre la tesitura completa de un piano acústico de cola:
* **Rango MIDI**: 21 (A0, 27.5 Hz) a 108 (C8, 4186.0 Hz).
* **Teclas blancas vs. negras**:
  - Teclas blancas: notas naturales.
  - Teclas negras: sostenidos/bemoles (`[C#, D#, F#, G#, A#]`).
* **Preservación incondicional**: Jamás truncar el registro a 61 teclas. Las 27 notas extremas deben ser accesibles y reproducibles.

---

## 2. Gestión de Voces y Polifonía

* **Voice Pooling**:
  - Reutilizar nodos `AudioStreamPlayer` pre-instanciados para evitar pausas del Garbage Collector (`GC`) durante acordes densos o glissandos rápidos.
* **Prevención de Clicks y Chasquidos (Anti-Pop)**:
  - Al cortar una voz o soltar una tecla, aplicar un decaimiento exponencial breve (`fade-out` de 5ms a 15ms) antes de detener el player:
    ```gdscript
    var tween: Tween = create_tween()
    tween.tween_property(player, "volume_db", -80.0, 0.015)
    tween.tween_callback(player.stop)
    ```
* **Pedal Sustain**:
  - Cuando el pedal está activo (`sustain_active == true`), las notas liberadas mantienen su decaimiento natural de resonancia de cuerda hasta que el pedal se levanta.

---

## 3. Ruteo de Buses de Audio

Configuración en `default_bus_layout.tres`:
* `Master`: Salida global con limitador protector (`AudioEffectLimiter`) para evitar clipping digital.
* `Piano`: Canal principal con compresión sutil y ecualización paramétrica.
* `Effects`: Envío auxiliar opcional para reverberación (`AudioEffectReverb`) controlada por la UI.

---

## 4. Orquestación con Codex CLI

Para algoritmos complejos de DSP, curvas matemáticas de atenuación armónica o transformadas de Fourier (FFT), delegar a Codex CLI:
```bash
codex exec -m gpt-6-astra --full-auto "Optimizar la curva de liberación exponencial del sintetizador de audio en scripts/audio_manager.gd"
```
