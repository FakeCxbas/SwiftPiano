# Directrices de Desarrollo de SwiftPiano (Godot 4 / GDScript)

Estas directrices son de obligado cumplimiento para todos los agentes al trabajar en el repositorio **SwiftPiano** (`/home/fakecxbas/Proyectos/SwiftPiano`).

---

## 1. Flujo Estricto de Git y Buenas Prácticas
- **Prohibido Push Directo a Main**: Todo cambio debe desarrollarse en rama dedicada (`feat/...`, `fix/...`, `perf/...`).
- **Trazabilidad de Issues**: Registrar o referenciar un Issue (`gh issue create`) y enlazarlo en el commit (`closes #X`).
- **Conventional Commits**: Mensajes concisos e imperativos (`feat(audio): ...`, `fix(midi): ...`, `test(parser): ...`).
- **Tono Humano y Cero Emojis de IA**: Prohibidos emojis en commits, PRs y código.

---

## 2. Orquestación Automática: Antigravity + Codex
- **Lógica pesada, DSP de audio y algoritmos matemáticos/musicales**: Delegar a **`gpt-6-astra`**:
  `codex exec -m gpt-6-astra --full-auto "<instrucción técnica>"`
- **Scripts de parseo, utilidades de conversión y suites de tests**: Delegar a **`gpt-6-luna`**:
  `codex exec -m gpt-6-luna --full-auto "<instrucción técnica>"`
- **Auditoría final de regresiones**: `codex review`.
- **Persistencia en Engram**: Tras recibir resultados clave o definir arquitectura, persistir con `mem_save`.

---

## 3. Verificación Automatizada Obligatoria (Headless)
Antes de confirmar cualquier cambio, ejecutar la suite completa en la terminal:
```bash
godot --headless --path . --editor --quit
godot --headless --path . --script tests/test_piano.gd
godot --headless --path . --script tests/test_midi_import.gd
godot --headless --path . --script tests/test_sheet_converter.gd
```
Todo código debe pasar con 0 errores y 0 fallos de aserción.

---

## 4. Skills Locales Disponibles (`.agents/skills/`)
- `godot4-gdscript-engine`: Convenciones de tipado estricto GDScript 2.0 y gestión de nodos.
- `swiftpiano-audio-dsp`: Síntesis polifónica, gestión de buses, envelopes y pedal sustain para las 88 teclas (A0 a C8).
- `swiftpiano-midi-sheets`: Parser y conversor de partituras Virtual Piano con soporte de acordes y extensión `MIDI:`.
- `godot-glsl-shaders`: Estándares de shaders reactivos en GLSL / CanvasItem y optimización de GPU (evitar sobrecarga Vulkan).
