extends Control

## Menú de personalización del personaje. Se abre durante la transición
## de "play" del menú principal, cuando la cámara vuela hasta el
## personaje, y edita en vivo la malla que hay en la escena:
## ropa (8 conjuntos del GLB), tono de piel, peso y altura.
##
## El perfil se guarda en GameProfile (autoload) y en disco para que el
## personaje creado siga existiendo al empezar la partida.

signal start_pressed
signal back_pressed

const STAND_ANIM := "Armature_001|mixamo_com|Layer0"
const LYING_ANIM := "beg"

## Mallas de piel que se tiñen con el tono elegido. Las mallas de ropa
## (arms_001..008 / torso_001..008) no se tocan.
const SKIN_MESHES := [
	"arms", "arms_009", "feet", "hands", "head",
	"lower_leg", "lower_meck", "torso", "upper_leg",
]

const RANDOM_NAMES := ["Alex", "Sam", "Jordan", "Riley", "Morgan", "Casey", "Rowan", "Quinn"]
const RANDOM_SURNAMES := ["Vega", "Moore", "Reed", "Carter", "Hayes", "Brooks", "Ellis", "Ward"]

const BASE_HEIGHT := 1.83

@onready var panel: PanelContainer = $Panel
@onready var scroll: ScrollContainer = $Panel/Margin/VBox/Scroll
@onready var name_edit: LineEdit = $Panel/Margin/VBox/Scroll/Fields/NameRow/NameEdit
@onready var surname_edit: LineEdit = $Panel/Margin/VBox/Scroll/Fields/SurnameRow/SurnameEdit
@onready var gender_option: OptionButton = $Panel/Margin/VBox/Scroll/Fields/GenderRow/GenderOption
@onready var weight_slider: HSlider = $Panel/Margin/VBox/Scroll/Fields/WeightRow/WeightSlider
@onready var weight_value: Label = $Panel/Margin/VBox/Scroll/Fields/WeightRow/WeightValue
@onready var blood_label: Label = $Panel/Margin/VBox/Scroll/Fields/BloodLabel
@onready var height_slider: HSlider = $Panel/Margin/VBox/Scroll/Fields/HeightRow/HeightSlider
@onready var height_value: Label = $Panel/Margin/VBox/Scroll/Fields/HeightRow/HeightValue
@onready var skin_row: HBoxContainer = $Panel/Margin/VBox/Scroll/Fields/SkinRow
@onready var outfit_grid: GridContainer = $Panel/Margin/VBox/Scroll/Fields/OutfitGrid
@onready var random_button: Button = $Panel/Margin/VBox/Buttons/RandomButton
@onready var back_button: Button = $Panel/Margin/VBox/Buttons/BackButton
@onready var start_button: Button = $Panel/Margin/VBox/Buttons/StartButton

var _profile: Node
var _character: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _base_scale := Vector3.ONE
var _base_rotation_y := 0.0
var _skin_entries: Array = []
var _outfit_buttons: Array = []
var _skin_buttons: Array = []
var _skin_styles: Array = []

var _outfit_normal: StyleBoxFlat
var _outfit_hover: StyleBoxFlat
var _outfit_pressed: StyleBoxFlat
var _outfit_selected: StyleBoxFlat
var _outfit_selected_hover: StyleBoxFlat

var _syncing := false
var _dragging := false
var _fade_tween: Tween
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_profile = get_node_or_null("/root/GameProfile")
	if _profile == null:
		# Fallback para ejecuciones con -s (tests) donde el autoload no
		# está disponible: el menú funciona igual con un perfil local.
		_profile = load("res://scripts/game_profile.gd").new()
		add_child(_profile)
	_rng.randomize()
	_build_styles()
	_build_outfit_buttons()
	_build_skin_buttons()
	for gender_name in _profile.gender_list():
		gender_option.add_item(String(gender_name).capitalize())
	gender_option.item_selected.connect(_on_gender_selected)
	weight_slider.value_changed.connect(_on_weight_changed)
	height_slider.value_changed.connect(_on_height_changed)
	random_button.pressed.connect(_on_randomize_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	visible = false

## Abre el editor con el personaje que se va a previsualizar.
func open(character: Node3D) -> void:
	if character == null:
		return
	if _character != character or _skin_entries.is_empty():
		_character = character
		_cache_character()
	_play_standing()
	_character.rotation = Vector3(0, _base_rotation_y, 0)
	_sync_from_profile()
	_apply_appearance()
	_refresh_visual_selection()
	scroll.scroll_vertical = 0
	_show()

func close() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	visible = false
	modulate.a = 1.0
	_dragging = false
	if _character:
		_character.rotation = Vector3(0, _base_rotation_y, 0)
	if _anim and _anim.has_animation(LYING_ANIM):
		_anim.play(LYING_ANIM, 0.4)

## Guarda lo que hay en el formulario en el perfil. Se llama al volver y
## al empezar, de modo que un nombre vacío nunca llega a la partida.
func commit_profile() -> void:
	var new_name := name_edit.text.strip_edges()
	if new_name == "":
		new_name = _profile.default_name_for(_profile.gender)
	var new_surname := surname_edit.text.strip_edges()
	if new_surname == "":
		new_surname = "Doe"
	name_edit.text = new_name
	surname_edit.text = new_surname
	_profile.set_names(new_name, new_surname)
	_profile.set_height(height_slider.value)
	_profile.save_profile()

func _cache_character() -> void:
	_base_scale = _character.scale
	_base_rotation_y = _character.rotation.y
	_skeleton = _character.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim = _character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skin_entries.clear()
	if _skeleton == null:
		return
	for mesh_name in SKIN_MESHES:
		var mesh := _skeleton.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh == null:
			continue
		var original := mesh.get_active_material(0) as BaseMaterial3D
		if original == null:
			continue
		var material := original.duplicate() as BaseMaterial3D
		mesh.material_override = material
		_skin_entries.append({
			"mat": material,
			"base_color": material.albedo_color,
		})

func _play_standing() -> void:
	if _anim == null or not _anim.has_animation(STAND_ANIM):
		return
	var animation := _anim.get_animation(STAND_ANIM)
	# El idle de pie empieza y acaba en la misma pose: se puede repetir.
	animation.loop_mode = Animation.LOOP_LINEAR
	_anim.play(STAND_ANIM, 0.45)

func _sync_from_profile() -> void:
	_syncing = true
	name_edit.text = _profile.player_name
	surname_edit.text = _profile.surname
	gender_option.select(_profile.gender)
	weight_slider.value = _profile.weight
	height_slider.value = _profile.height
	_syncing = false
	_update_value_labels()
	_update_blood_label()

func _apply_appearance() -> void:
	_apply_outfit(_profile.outfit)
	_apply_skin(_profile.skin_tone)
	_apply_body()

func _apply_outfit(outfit_id: int) -> void:
	if _skeleton == null:
		return
	for i in range(1, 9):
		var suffix := "%03d" % i
		var arms := _skeleton.get_node_or_null("arms_%s" % suffix) as MeshInstance3D
		var torso := _skeleton.get_node_or_null("torso_%s" % suffix) as MeshInstance3D
		if arms:
			arms.visible = i == outfit_id
		if torso:
			torso.visible = i == outfit_id

func _apply_skin(tone_index: int) -> void:
	var tones: Array = _profile.skin_tone_list()
	if tone_index < 0 or tone_index >= tones.size():
		return
	var tint: Color = tones[tone_index]["tint"]
	for entry in _skin_entries:
		var material: BaseMaterial3D = entry["mat"]
		var base_color: Color = entry["base_color"]
		material.albedo_color = Color(
			base_color.r * tint.r,
			base_color.g * tint.g,
			base_color.b * tint.b,
			base_color.a)

func _apply_body() -> void:
	if _character == null:
		return
	var thickness := clampf(1.0 + (_profile.weight - 75.0) * 0.0035, 0.86, 1.20)
	var height_scale := clampf(_profile.height / BASE_HEIGHT, 0.84, 1.08)
	_character.scale = Vector3(
		_base_scale.x * thickness,
		_base_scale.y * height_scale,
		_base_scale.z * thickness)

func _on_outfit_selected(outfit_id: int) -> void:
	if _syncing:
		return
	_profile.set_outfit(outfit_id)
	_apply_outfit(outfit_id)
	_refresh_visual_selection()

func _on_skin_selected(tone_index: int) -> void:
	if _syncing:
		return
	_profile.set_skin_tone(tone_index)
	_apply_skin(tone_index)
	_refresh_visual_selection()

func _on_weight_changed(value: float) -> void:
	if _syncing:
		return
	_profile.set_weight(value)
	weight_value.text = "%d kg" % int(round(value))
	_update_blood_label()
	_apply_body()

func _on_height_changed(value: float) -> void:
	if _syncing:
		return
	_profile.set_height(value)
	height_value.text = "%.2f m" % value
	_apply_body()

func _on_gender_selected(index: int) -> void:
	if _syncing:
		return
	var previous_default: String = _profile.default_name_for(_profile.gender)
	var current_name := name_edit.text.strip_edges()
	_profile.set_gender(index)
	if current_name == "" or current_name == previous_default:
		current_name = _profile.default_name_for(index)
		name_edit.text = current_name
	_profile.set_names(current_name, surname_edit.text.strip_edges())
	_update_blood_label()

func _on_randomize_pressed() -> void:
	_syncing = true
	var new_gender := _rng.randi_range(0, 1)
	var new_name: String = RANDOM_NAMES[_rng.randi_range(0, RANDOM_NAMES.size() - 1)]
	var new_surname: String = RANDOM_SURNAMES[_rng.randi_range(0, RANDOM_SURNAMES.size() - 1)]
	var new_weight := _rng.randf_range(55.0, 115.0)
	var new_height := _rng.randf_range(1.65, 1.95)
	_profile.set_gender(new_gender)
	_profile.set_names(new_name, new_surname)
	_profile.set_weight(new_weight)
	_profile.set_height(new_height)
	_profile.set_outfit(_rng.randi_range(1, 8))
	_profile.set_skin_tone(_rng.randi_range(0, _profile.skin_tone_list().size() - 1))
	name_edit.text = new_name
	surname_edit.text = new_surname
	gender_option.select(new_gender)
	weight_slider.value = new_weight
	height_slider.value = new_height
	_syncing = false
	_update_value_labels()
	_update_blood_label()
	_apply_appearance()
	_refresh_visual_selection()

func _on_start_pressed() -> void:
	commit_profile()
	start_pressed.emit()

func _on_back_pressed() -> void:
	commit_profile()
	back_pressed.emit()

func _update_value_labels() -> void:
	weight_value.text = "%d kg" % int(round(weight_slider.value))
	height_value.text = "%.2f m" % height_slider.value

func _update_blood_label() -> void:
	var liters := 0.0
	if _profile.stats != null:
		liters = float(_profile.stats.max_blood) / 1000.0
	var build := "normal"
	if _profile.weight < 62.0:
		build = "slim"
	elif _profile.weight > 95.0:
		build = "heavy"
	blood_label.text = "Blood volume: %.1f L  ·  build: %s" % [liters, build]

func _show() -> void:
	visible = true
	modulate.a = 0.0
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.3)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if _character:
			_character.rotate_y(-event.relative.x * 0.01)
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()

func _build_styles() -> void:
	_outfit_normal = _flat_style(
		Color(0.11, 0.115, 0.13, 0.95), Color(0.24, 0.24, 0.27), 1, 4)
	_outfit_hover = _flat_style(
		Color(0.17, 0.17, 0.2, 0.98), Color(0.4, 0.4, 0.44), 1, 4)
	_outfit_pressed = _flat_style(
		Color(0.22, 0.22, 0.26, 1.0), Color(0.5, 0.5, 0.54), 1, 4)
	_outfit_selected = _flat_style(
		Color(0.23, 0.19, 0.11, 0.98), Color(0.86, 0.68, 0.32), 2, 4)
	_outfit_selected_hover = _flat_style(
		Color(0.3, 0.25, 0.14, 1.0), Color(0.96, 0.78, 0.4), 2, 4)

	var start_normal := _flat_style(
		Color(0.62, 0.46, 0.2, 1.0), Color(0.92, 0.75, 0.42), 1, 4)
	var start_hover := _flat_style(
		Color(0.72, 0.54, 0.24, 1.0), Color(1.0, 0.85, 0.55), 1, 4)
	var start_pressed := _flat_style(
		Color(0.5, 0.37, 0.15, 1.0), Color(0.92, 0.75, 0.42), 1, 4)
	start_button.add_theme_stylebox_override("normal", start_normal)
	start_button.add_theme_stylebox_override("hover", start_hover)
	start_button.add_theme_stylebox_override("pressed", start_pressed)
	start_button.add_theme_color_override("font_color", Color(0.1, 0.08, 0.04))
	start_button.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.02))
	start_button.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.04))
	back_button.add_theme_color_override("font_color", Color(0.82, 0.8, 0.76))
	random_button.add_theme_color_override("font_color", Color(0.72, 0.85, 0.7))

func _build_outfit_buttons() -> void:
	var outfits: Array = _profile.outfit_list()
	for i in range(outfits.size()):
		var item: Dictionary = outfits[i]
		var button := Button.new()
		button.text = String(item["name"])
		button.tooltip_text = String(item["name"])
		button.custom_minimum_size = Vector2(0, 27)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_constant_override("h_separation", 7)
		button.add_theme_color_override("font_color", Color(0.84, 0.83, 0.79))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		button.icon = _color_swatch(item["color"])
		button.pressed.connect(_on_outfit_selected.bind(i + 1))
		outfit_grid.add_child(button)
		_outfit_buttons.append(button)

func _build_skin_buttons() -> void:
	var tones: Array = _profile.skin_tone_list()
	for i in range(tones.size()):
		var tone: Dictionary = tones[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(34, 26)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = String(tone["name"])
		var style := _flat_style(tone["tint"], Color(0.16, 0.16, 0.18), 1, 4)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.pressed.connect(_on_skin_selected.bind(i))
		skin_row.add_child(button)
		_skin_buttons.append(button)
		_skin_styles.append(style)

func _refresh_visual_selection() -> void:
	for i in range(_outfit_buttons.size()):
		var button: Button = _outfit_buttons[i]
		var selected: bool = (i + 1) == int(_profile.outfit)
		button.add_theme_stylebox_override(
			"normal", _outfit_selected if selected else _outfit_normal)
		button.add_theme_stylebox_override(
			"hover", _outfit_selected_hover if selected else _outfit_hover)
		button.add_theme_stylebox_override("pressed", _outfit_pressed)
	for i in range(_skin_styles.size()):
		var style: StyleBoxFlat = _skin_styles[i]
		if i == _profile.skin_tone:
			style.border_color = Color(0.95, 0.78, 0.4, 1.0)
			style.set_border_width_all(2)
		else:
			style.border_color = Color(0.16, 0.16, 0.18, 1.0)
			style.set_border_width_all(1)

func _flat_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _color_swatch(color: Color) -> ImageTexture:
	var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
