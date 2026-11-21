---
name: godot-glsl-shaders
description: >-
  Godot 4 CanvasItem shaders, GLSL visualizers, audio reactivity, and GPU performance
  guidelines. Use when creating or refining spectrum visualizers, key glow, note trails,
  or particle effects in SwiftPiano.
---

# Godot 4 CanvasItem Shaders & GLSL Performance

Engineering guidelines for audio-reactive shaders and real-time GPU rendering in SwiftPiano.

---

## 1. Shader Architecture in Godot 4

SwiftPiano utiliza shaders tipo `canvas_item` sobre `ColorRect` o `TextureRect` para los visualizadores de audio:

```glsl
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.2, 0.8, 0.4, 1.0);
uniform float audio_energy : hint_range(0.0, 1.0) = 0.0;
uniform float frequency_band : hint_range(0.0, 20000.0) = 440.0;

void fragment() {
    vec2 uv = UV;
    float wave = sin(uv.x * 20.0 + TIME * 4.0) * 0.1 * audio_energy;
    float line = smoothstep(0.02, 0.0, abs(uv.y - 0.5 - wave));
    COLOR = base_color * line;
}
```

---

## 2. Restricciones Críticas de Rendimiento en GPU

1. **Evitar lectura de `SCREEN_TEXTURE` innecesaria**:
   - `hint_screen_texture` fuerza una pasada de renderizado adicional que duplica el costo del framebuffer.
   - Si se requiere desenfoque o glow, preferir gradientes procedimentales analíticos o texturas precargadas.
2. **Prohibición de Mipmap Reading en Texturas No Filtradas**:
   - Para prevenir advertencias y bloqueos en controladores Vulkan (Mesa/AMD/Intel en Linux), nunca invocar `textureLod` sobre texturas que no tengan mipmaps generados explícitamente.
3. **Control de Complejidad**:
   - Mantener el fragment shader ligero para garantizar 60 FPS estables sin disparar el uso de CPU/GPU en entornos Wayland/Hyprland.
