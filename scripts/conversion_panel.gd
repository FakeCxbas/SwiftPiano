extends VBoxContainer
const Converter = preload("res://scripts/sheet_converter.gd")
const StudioSkin = preload("res://scripts/studio_theme.gd")
signal choose_requested
signal apply_requested(sheet: String, title: String)
var original = ""
var source_title = ""
var source_info = ""
var options_dirty: bool = false
var applied_mode: int = -1
var applied_transpose: int = 0
var last_status_text: String = ""
var filename: Label
var status: Label
var mode: OptionButton
var transpose: SpinBox
var preview: TextEdit
var generate: Button
var copy: Button
var use_sheet: Button

func _ready() -> void:
	_setup_ui()

func _setup_ui() -> void:
	if filename != null:
		return
	add_theme_constant_override("separation", 10)
	var file_row = HFlowContainer.new()
	add_child(file_row)
	make_button(file_row, "Elegir / reemplazar MIDI", func(): choose_requested.emit())
	filename = Label.new()
	filename.text = "01  /  Selecciona un archivo .mid o .midi"
	filename.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(filename)
	var options = HFlowContainer.new()
	add_child(options)
	mode = OptionButton.new()
	for title in ["Todas las notas", "Acordes reducidos · máx. 3", "Melodía · nota más aguda"]:
		mode.add_item(title)
	options.add_child(mode)
	mode.item_selected.connect(func(_index): mark_pending())
	var caption = Label.new()
	caption.text = "Transposición (semitonos)"
	options.add_child(caption)
	transpose = SpinBox.new()
	transpose.min_value = -24
	transpose.max_value = 24
	options.add_child(transpose)
	transpose.value_changed.connect(func(_value): mark_pending())
	generate = make_button(options, "Generar hoja", regenerate)
	generate.disabled = true
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "02  /  Elige una variante y genera tu hoja. Los acordes permanecen juntos."
	add_child(status)
	preview = TextEdit.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size.y = 120
	preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	preview.add_theme_font_size_override("font_size", 17)
	preview.add_theme_stylebox_override("normal", StudioSkin.surface(Color("#11151c"), Color("#363e49")))
	preview.placeholder_text = "03  /  Tu hoja aparecerá aquí. Puedes editarla antes de tocar."
	add_child(preview)
	preview.text_changed.connect(func():
		var empty = preload("res://scripts/sheet_parser.gd").parse(preview.text, true).is_empty()
		if options_dirty:
			copy.disabled = true
			use_sheet.disabled = true
		else:
			copy.disabled = empty
			use_sheet.disabled = empty)
	var footer = HFlowContainer.new()
	add_child(footer)
	copy = make_button(footer, "Copiar hoja", func(): DisplayServer.clipboard_set(preview.text))
	use_sheet = make_button(footer, "Usar en el atril →", func(): apply_requested.emit(preview.text, source_title))
	copy.disabled = true
	use_sheet.disabled = true
	var help = Label.new()
	help.text = "Auto avanza con tus pulsaciones, no por tiempo. Las notas extremas se conservan como MIDI: (formato SwiftPiano). MP3/MP4 requieren transcripción previa a MIDI."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("#9aaebf"))
	add_child(help)

func make_button(parent: Node, title: String, callback: Callable) -> Button:
	var item = Button.new()
	item.text = title
	item.focus_mode = Control.FOCUS_NONE
	item.custom_minimum_size.y = 36
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

func load_result(result: Dictionary, path: String) -> void:
	_setup_ui()
	original = result.sheet
	source_title = path.get_file().get_basename()
	filename.text = source_title
	filename.tooltip_text = path
	source_info = "%d pistas · percusión omitida: %d · notas fuera de 88: %d" % [result.tracks, result.percussion, result.omitted]
	generate.disabled = false
	regenerate()

func mark_pending() -> void:
	if original.is_empty():
		return
	if mode.selected == applied_mode and int(transpose.value) == applied_transpose:
		options_dirty = false
		status.text = last_status_text
		var empty = preload("res://scripts/sheet_parser.gd").parse(preview.text, true).is_empty()
		copy.disabled = empty
		use_sheet.disabled = empty
	else:
		options_dirty = true
		status.text = "Opciones modificadas: pulsa Generar hoja para aplicarlas (reemplaza la vista previa)."
		copy.disabled = true
		use_sheet.disabled = true

func regenerate() -> void:
	_setup_ui()
	if original.is_empty():
		return
	applied_mode = mode.selected
	applied_transpose = int(transpose.value)
	options_dirty = false
	var result = Converter.convert(original, mode.selected, int(transpose.value))
	preview.text = result.sheet
	copy.disabled = result.steps == 0
	use_sheet.disabled = result.steps == 0
	status.text = "%d notas · %d pasos · %d acordes en formato de 88 teclas\n%s\nOmitidas por transposición fuera de A0–C8: %d" % [result.notes, result.steps, result.extended, source_info, result.omitted]
	last_status_text = status.text
