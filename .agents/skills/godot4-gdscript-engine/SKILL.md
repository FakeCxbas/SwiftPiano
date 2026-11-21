---
name: godot4-gdscript-engine
description: >-
  Godot 4.x engine workflows, GDScript 2.0 static typing, scene management,
  signal architecture, and headless test execution. Use when creating or refactoring
  nodes, scripts, scenes, or running automated test suites in SwiftPiano.
---

# Godot 4.x & GDScript 2.0 Engine Standards

Guidelines for crafting reliable, strictly-typed, and modular GDScript code in Godot 4.

---

## 1. GDScript 2.0 Syntax & Typing

Always enforce static typing across variables, parameters, and return values:

```gdscript
# Class header
class_name PianoKey
extends Control

# Signals
signal key_pressed(note_pitch: int, velocity: float)
signal key_released(note_pitch: int)

# Exports with explicit hints
@export var pitch_index: int = 60
@export var is_black_key: bool = false
@export_range(0.0, 1.0) var velocity_multiplier: float = 1.0

# Node references
@onready var visual_rect: ColorRect = $VisualRect
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

# Private state
var _is_active: bool = false

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)

func trigger_press(velocity: float = 1.0) -> void:
	_is_active = true
	key_pressed.emit(pitch_index, velocity)
```

### Prohibited Patterns
- Untyped arrays (`var notes = []`) $\rightarrow$ use typed arrays: `var notes: Array[int] = []` or `PackedInt32Array`.
- Calling non-existent methods dynamically via string names $\rightarrow$ use `Callable(self, &"method")` or direct lambdas.
- Modifying scene tree during physics steps without `call_deferred()`.

---

## 2. Headless Verification Suite

Before committing any GDScript modification, verify parser integrity and execute the full test suite:

```bash
# 1. Parse and syntax dry-run (must exit code 0)
godot --headless --path . --editor --quit

# 2. Core piano & audio logic tests
godot --headless --path . --script tests/test_piano.gd

# 3. MIDI import & sheet converter tests
godot --headless --path . --script tests/test_midi_import.gd
godot --headless --path . --script tests/test_sheet_converter.gd

# 4. UI controls & instrument tests
godot --headless --path . --script tests/test_ui_controls.gd
godot --headless --path . --script tests/test_instruments.gd
```

Never commit code that fails any of the headless assertions.
