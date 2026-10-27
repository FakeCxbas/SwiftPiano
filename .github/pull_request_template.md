## Resumen de cambios
Explicacion concisa de los cambios incluidos en esta solicitud de extraccion.

## Trazabilidad
- Closes #(numero-de-issue)

## Tipo de cambio
- [ ] feat: Nueva funcionalidad o soporte de instrumentos
- [ ] fix: Correccion de errores en logica de audio o visualizacion
- [ ] refactor: Reestructuracion interna de codigo o shaders
- [ ] perf: Optimizaciones de rendimiento, latencia o consumo de memoria
- [ ] test: Incorporacion o ajuste de pruebas unitarias/audio
- [ ] docs: Documentacion tecnica o atribuciones de licencia

## Verificacion realizada
- [ ] Ejecucion de pruebas unitarias en modo headless: `godot --headless --path . --script tests/test_piano.gd`
- [ ] Verificacion de mezcla y limites de saturacion: `godot --headless --audio-driver Dummy --path . --script tests/test_audio_mix.gd`
- [ ] Ausencia de recorte a 0 dBFS y conformidad con estandar de audio.
