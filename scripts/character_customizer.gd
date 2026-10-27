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

const LYING_ANIM := "beg"

## Mallas de piel que se tiñen con el tono elegido. Las mallas de ropa
## (arms_001..008 / torso_001..008) no se tocan.
const SKIN_MESHES := [
	"arms", "arms_009", "feet", "hands", "head",
	"lower_leg", "lower_meck", "torso", "upper_leg",
]

const RANDOM_NAMES := ["Alex", "Sam", "Jordan", "Riley", "Morgan", "Casey", "Rowan", "Quinn"]
const RANDOM_SURNAMES := ["Vega", "Moore", "Reed", "Carter", "Hayes", "Brooks", "Ellis", "Ward"]

const BASE_HEIGHT := 1.85

## Listas cortas de peso/altura. El tooltip explica la ventaja y la
## desventaja de cada punto al pasar el ratón. Los textos se traducen
## con las claves W*_NAME/W*_ADV/W*_DIS y H*_NAME/H*_ADV/H*_DIS.
const WEIGHT_OPTIONS := [
	{"value": 55.0, "label": "55", "key": "W55"},
	{"value": 65.0, "label": "65", "key": "W65"},
	{"value": 75.0, "label": "75", "key": "W75"},
	{"value": 90.0, "label": "90", "key": "W90"},
	{"value": 110.0, "label": "110", "key": "W110"},
	{"value": 135.0, "label": "135", "key": "W135"},
]

const HEIGHT_OPTIONS := [
	{"value": 1.55, "label": "1.55", "key": "H155"},
	{"value": 1.65, "label": "1.65", "key": "H165"},
	{"value": 1.75, "label": "1.75", "key": "H175"},
	{"value": 1.85, "label": "1.85", "key": "H185"},
	{"value": 1.95, "label": "1.95", "key": "H195"},
]

const OUTFIT_KEYS := [
	"OUTFIT_1", "OUTFIT_2", "OUTFIT_3", "OUTFIT_4",
	"OUTFIT_5", "OUTFIT_6", "OUTFIT_7", "OUTFIT_8",
]

const SKIN_KEYS := ["SKIN_FAIR", "SKIN_LIGHT", "SKIN_TAN", "SKIN_BROWN", "SKIN_DEEP"]

@onready var scroll: ScrollContainer = $Panel/Margin/VBox/Scroll
@onready var name_edit: LineEdit = $Panel/Margin/VBox/Scroll/Fields/NameRow/NameEdit
@onready var surname_edit: LineEdit = $Panel/Margin/VBox/Scroll/Fields/SurnameRow/SurnameEdit
@onready var male_button: Button = $Panel/Margin/VBox/Scroll/Fields/GenderRow/MaleButton
@onready var female_button: Button = $Panel/Margin/VBox/Scroll/Fields/GenderRow/FemaleButton
@onready var weight_buttons_box: HBoxContainer = $Panel/Margin/VBox/Scroll/Fields/WeightRow/WeightButtons
@onready var blood_label: Label = $Panel/Margin/VBox/Scroll/Fields/BloodLabel
@onready var height_buttons_box: HBoxContainer = $Panel/Margin/VBox/Scroll/Fields/HeightRow/HeightButtons
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
var _skin_entries: Array = []
var _outfit_buttons: Array = []
var _skin_buttons: Array = []
var _skin_styles: Array = []
var _weight_buttons: Array = []
var _height_buttons: Array = []

var _outfit_normal: StyleBoxFlat
var _outfit_hover: StyleBoxFlat
var _outfit_pressed: StyleBoxFlat
var _outfit_selected: StyleBoxFlat
var _outfit_selected_hover: StyleBoxFlat

var _syncing := false
var _fade_tween: Tween
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_load_translations()
	_load_language()
	_profile = get_node_or_null("/root/GameProfile")
	if _profile == null:
		# Fallback para ejecuciones con -s (tests) donde el autoload no
		# está disponible: el menú funciona igual con un perfil local.
		_profile = load("res://scripts/game_profile.gd").new()
		add_child(_profile)
	_rng.randomize()
	_localize_static()
	_build_styles()
	_build_outfit_buttons()
	_build_skin_buttons()
	_weight_buttons = _build_choice_buttons(weight_buttons_box, WEIGHT_OPTIONS, _on_weight_pressed)
	_height_buttons = _build_choice_buttons(height_buttons_box, HEIGHT_OPTIONS, _on_height_pressed)
	var gender_group := ButtonGroup.new()
	gender_group.allow_unpress = false
	male_button.button_group = gender_group
	female_button.button_group = gender_group
	male_button.pressed.connect(_on_gender_pressed.bind(0))
	female_button.pressed.connect(_on_gender_pressed.bind(1))
	random_button.pressed.connect(_on_randomize_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	visible = false


func _load_translations() -> void:
	# Las traducciones se importan como un .translation por idioma.
	for locale in ["en", "es", "ca", "bg", "de", "fr"]:
		var path := "res://translations/translations.%s.translation" % locale
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if res is Translation:
			TranslationServer.add_translation(res)


func _load_language() -> void:
	var config := ConfigFile.new()
	var locale := "es"
	if config.load("user://settings.cfg") == OK:
		locale = String(config.get_value("language", "locale", "es"))
	TranslationServer.set_locale(locale)


func _localize_static() -> void:
	var title := get_node_or_null("Panel/Margin/VBox/Title") as Label
	if title: title.text = tr("CUSTOM_TITLE")
	var id_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/IdentityLabel") as Label
	if id_label: id_label.text = tr("CUSTOM_IDENTITY")
	var body_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/BodyLabel") as Label
	if body_label: body_label.text = tr("CUSTOM_BODY")
	var outfit_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/OutfitLabel") as Label
	if outfit_label: outfit_label.text = tr("CUSTOM_OUTFIT")
	var name_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/NameRow/NameLabel") as Label
	if name_label: name_label.text = tr("CUSTOM_NAME")
	var surname_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/SurnameRow/SurnameLabel") as Label
	if surname_label: surname_label.text = tr("CUSTOM_SURNAME")
	var gender_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/GenderRow/GenderLabel") as Label
	if gender_label: gender_label.text = tr("CUSTOM_GENDER")
	var weight_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/WeightRow/WeightLabel") as Label
	if weight_label: weight_label.text = tr("CUSTOM_WEIGHT")
	var height_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/HeightRow/HeightLabel") as Label
	if height_label: height_label.text = tr("CUSTOM_HEIGHT")
	var skin_label := get_node_or_null("Panel/Margin/VBox/Scroll/Fields/SkinLabel") as Label
	if skin_label: skin_label.text = tr("CUSTOM_SKIN")
	if male_button: male_button.text = tr("CUSTOM_MALE")
	if female_button: female_button.text = tr("CUSTOM_FEMALE")
	if random_button: random_button.text = tr("BTN_RANDOMIZE")
	if back_button: back_button.text = tr("MENU_BACK")
	if start_button: start_button.text = tr("BTN_START")
	if name_edit: name_edit.placeholder_text = tr("PLACEHOLDER_NAME")
	if surname_edit: surname_edit.placeholder_text = tr("PLACEHOLDER_SURNAME")


## Vuelve a aplicar los textos generados (ropa, tonos, tooltips) cuando
## el idioma cambia entre una apertura y la siguiente.
func _refresh_dynamic_texts() -> void:
	for i in range(_outfit_buttons.size()):
		var key: String = OUTFIT_KEYS[i] if i < OUTFIT_KEYS.size() else "OUTFIT_1"
		var button: Button = _outfit_buttons[i]
		button.text = tr(key)
		button.tooltip_text = tr(key)
	for i in range(_skin_buttons.size()):
		var key: String = SKIN_KEYS[i] if i < SKIN_KEYS.size() else "SKIN_FAIR"
		_skin_buttons[i].tooltip_text = tr(key)
	for i in range(_weight_buttons.size()):
		_weight_buttons[i].tooltip_text = _choice_tip(String(WEIGHT_OPTIONS[i]["key"]))
	for i in range(_height_buttons.size()):
		_height_buttons[i].tooltip_text = _choice_tip(String(HEIGHT_OPTIONS[i]["key"]))
	_update_blood_label()

## Aplica el aspecto guardado al personaje sin abrir el panel: así el
## personaje del menú ya lleva la ropa y el cuerpo elegidos antes de
## pulsar play.
func prepare(character: Node3D) -> void:
	if character == null:
		return
	_bind_character(character)
	_sync_from_profile()
	_apply_appearance()

## Abre el editor con el personaje que se va a previsualizar. El
## personaje sigue tumbado (beg) durante toda la creación.
func open(character: Node3D) -> void:
	if character == null:
		return
	_load_translations()
	_load_language()
	_localize_static()
	_refresh_dynamic_texts()
	_bind_character(character)
	if _character == null:
		return
	_sync_from_profile()
	_apply_appearance()
	if _anim and _anim.has_animation(LYING_ANIM) and _anim.current_animation != LYING_ANIM:
		_anim.play(LYING_ANIM, 0.3)
	_refresh_visual_selection()
	scroll.scroll_vertical = 0
	_show()

func _bind_character(character: Node3D) -> void:
	if _character != character or _skin_entries.is_empty():
		_character = character
		_cache_character()

func close() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	visible = false
	modulate.a = 1.0

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
	name_edit.placeholder_text = tr("PLACEHOLDER_NAME")
	surname_edit.placeholder_text = tr("PLACEHOLDER_SURNAME")
	_profile.set_names(new_name, new_surname)
	_profile.save_profile()

func _cache_character() -> void:
	_base_scale = _character.scale
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

func _sync_from_profile() -> void:
	_syncing = true
	name_edit.text = _profile.player_name
	surname_edit.text = _profile.surname
	if name_edit.text.strip_edges() == "":
		name_edit.placeholder_text = tr("PLACEHOLDER_NAME")
	else:
		name_edit.placeholder_text = tr("PLACEHOLDER_NAME")
	if surname_edit.text.strip_edges() == "":
		surname_edit.placeholder_text = tr("PLACEHOLDER_SURNAME")
	else:
		surname_edit.placeholder_text = tr("PLACEHOLDER_SURNAME")
	var weight_index := _nearest_option(WEIGHT_OPTIONS, float(_profile.weight))
	var height_index := _nearest_option(HEIGHT_OPTIONS, float(_profile.height))
	# El perfil guardado puede venir de la versión con sliders: se ajusta
	# a la opción más cercana para que la lista y el cuerpo coincidan.
	if not is_equal_approx(float(_profile.weight), float(WEIGHT_OPTIONS[weight_index]["value"])):
		_profile.set_weight(float(WEIGHT_OPTIONS[weight_index]["value"]))
	if not is_equal_approx(float(_profile.height), float(HEIGHT_OPTIONS[height_index]["value"])):
		_profile.set_height(float(HEIGHT_OPTIONS[height_index]["value"]))
	_syncing = false
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
	# Los brazos de piel van siempre debajo de la ropa: las mangas cortas
	# son transparentes en el antebrazo y sin esta malla los brazos
	# desaparecían. En las mangas largas la tela opaca los tapa.
	var skin_arms := _skeleton.get_node_or_null("arms") as MeshInstance3D
	var skin_arms009 := _skeleton.get_node_or_null("arms_009") as MeshInstance3D
	if skin_arms:
		skin_arms.visible = true
	if skin_arms009:
		skin_arms009.visible = true

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

func _on_weight_pressed(index: int) -> void:
	if _syncing:
		return
	_profile.set_weight(float(WEIGHT_OPTIONS[index]["value"]))
	_update_blood_label()
	_apply_body()
	_refresh_visual_selection()

func _on_height_pressed(index: int) -> void:
	if _syncing:
		return
	_profile.set_height(float(HEIGHT_OPTIONS[index]["value"]))
	_apply_body()
	_refresh_visual_selection()

func _on_gender_pressed(index: int) -> void:
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
	_refresh_visual_selection()

func _on_randomize_pressed() -> void:
	_syncing = true
	var new_gender := _rng.randi_range(0, 1)
	var new_name: String = tr("PLACEHOLDER_NAME") if _rng.randf() < 0.5 else RANDOM_NAMES[_rng.randi_range(0, RANDOM_NAMES.size() - 1)]
	var new_surname: String = tr("PLACEHOLDER_SURNAME") if _rng.randf() < 0.5 else RANDOM_SURNAMES[_rng.randi_range(0, RANDOM_SURNAMES.size() - 1)]
	var weight_index := _rng.randi_range(0, WEIGHT_OPTIONS.size() - 1)
	var height_index := _rng.randi_range(0, HEIGHT_OPTIONS.size() - 1)
	_profile.set_gender(new_gender)
	_profile.set_names(new_name, new_surname)
	_profile.set_weight(float(WEIGHT_OPTIONS[weight_index]["value"]))
	_profile.set_height(float(HEIGHT_OPTIONS[height_index]["value"]))
	_profile.set_outfit(_rng.randi_range(1, 8))
	_profile.set_skin_tone(_rng.randi_range(0, _profile.skin_tone_list().size() - 1))
	name_edit.text = new_name
	surname_edit.text = new_surname
	name_edit.placeholder_text = tr("PLACEHOLDER_NAME")
	surname_edit.placeholder_text = tr("PLACEHOLDER_SURNAME")
	_syncing = false
	_update_blood_label()
	_apply_appearance()
	_refresh_visual_selection()

func _on_start_pressed() -> void:
	commit_profile()
	start_pressed.emit()

func _on_back_pressed() -> void:
	commit_profile()
	back_pressed.emit()

func _update_blood_label() -> void:
	var liters := 0.0
	if _profile.stats != null:
		liters = float(_profile.stats.max_blood) / 1000.0
	var build := "normal"
	if _profile.weight < 62.0:
		build = "slim"
	elif _profile.weight > 95.0:
		build = "heavy"
	var build_key := "BUILD_NORMAL"
	if build == "slim":
		build_key = "BUILD_SLIM"
	elif build == "heavy":
		build_key = "BUILD_HEAVY"
	blood_label.text = tr("CUSTOM_BLOOD") % [liters, tr(build_key)]

func _show() -> void:
	visible = true
	modulate.a = 0.0
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.3)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()

func _build_styles() -> void:
	_outfit_normal = _flat_style(
		Color(0.09, 0.095, 0.09, 0.98), Color(0.28, 0.28, 0.24), 1, 0)
	_outfit_hover = _flat_style(
		Color(0.13, 0.14, 0.12, 1.0), Color(0.42, 0.41, 0.35), 1, 0)
	_outfit_pressed = _flat_style(
		Color(0.16, 0.17, 0.15, 1.0), Color(0.52, 0.5, 0.42), 1, 0)
	_outfit_selected = _flat_style(
		Color(0.16, 0.14, 0.09, 1.0), Color(0.78, 0.72, 0.48), 1, 0)
	_outfit_selected_hover = _flat_style(
		Color(0.19, 0.17, 0.11, 1.0), Color(0.88, 0.8, 0.56), 1, 0)

	var start_normal := _flat_style(
		Color(0.58, 0.5, 0.28, 1.0), Color(0.86, 0.76, 0.5), 1, 0)
	var start_hover := _flat_style(
		Color(0.68, 0.58, 0.32, 1.0), Color(0.92, 0.82, 0.58), 1, 0)
	var start_pressed := _flat_style(
		Color(0.48, 0.42, 0.24, 1.0), Color(0.82, 0.72, 0.46), 1, 0)
	start_button.add_theme_stylebox_override("normal", start_normal)
	start_button.add_theme_stylebox_override("hover", start_hover)
	start_button.add_theme_stylebox_override("pressed", start_pressed)
	start_button.add_theme_color_override("font_color", Color(0.09, 0.08, 0.05))
	start_button.add_theme_color_override("font_hover_color", Color(0.06, 0.05, 0.03))
	start_button.add_theme_color_override("font_pressed_color", Color(0.09, 0.08, 0.05))
	back_button.add_theme_color_override("font_color", Color(0.78, 0.76, 0.7))
	random_button.add_theme_color_override("font_color", Color(0.72, 0.76, 0.66))
	for button in [male_button, female_button]:
		button.add_theme_stylebox_override("normal", _outfit_normal)
		button.add_theme_stylebox_override("hover", _outfit_hover)
		button.add_theme_stylebox_override("pressed", _outfit_selected)
		button.add_theme_stylebox_override("hover_pressed", _outfit_selected_hover)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
		button.add_theme_color_override("font_hover_color", Color(0.9, 0.88, 0.8))
		button.add_theme_color_override("font_pressed_color", Color(0.92, 0.84, 0.6))
		button.add_theme_color_override("font_hover_pressed_color", Color(0.94, 0.86, 0.62))

func _build_choice_buttons(container: Container, options: Array, handler: Callable) -> Array:
	var buttons: Array = []
	for i in range(options.size()):
		var button := Button.new()
		button.text = String(options[i]["label"])
		button.tooltip_text = _choice_tip(String(options[i]["key"]))
		button.custom_minimum_size = Vector2(0, 24)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 11)
		button.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
		button.add_theme_color_override("font_hover_color", Color(0.9, 0.88, 0.8))
		button.pressed.connect(handler.bind(i))
		container.add_child(button)
		buttons.append(button)
	return buttons

## Tooltip traducido: nombre del punto y sus pros/contras.
func _choice_tip(key: String) -> String:
	return "%s\n%s: %s\n%s: %s" % [
		tr(key + "_NAME"), tr("TIP_ADV"), tr(key + "_ADV"),
		tr("TIP_DIS"), tr(key + "_DIS"),
	]


func _nearest_option(options: Array, value: float) -> int:
	var best := 0
	var best_distance := INF
	for i in range(options.size()):
		var distance := absf(float(options[i]["value"]) - value)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best

func _build_outfit_buttons() -> void:
	var outfits: Array = _profile.outfit_list()
	for i in range(outfits.size()):
		var item: Dictionary = outfits[i]
		var outfit_key: String = OUTFIT_KEYS[i] if i < OUTFIT_KEYS.size() else "OUTFIT_1"
		var button := Button.new()
		button.text = tr(outfit_key)
		button.tooltip_text = tr(outfit_key)
		button.custom_minimum_size = Vector2(0, 25)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_constant_override("h_separation", 6)
		button.add_theme_color_override("font_color", Color(0.82, 0.8, 0.74))
		button.add_theme_color_override("font_hover_color", Color(0.92, 0.9, 0.82))
		button.icon = _color_swatch(item["color"])
		button.pressed.connect(_on_outfit_selected.bind(i + 1))
		outfit_grid.add_child(button)
		_outfit_buttons.append(button)

func _build_skin_buttons() -> void:
	var tones: Array = _profile.skin_tone_list()
	for i in range(tones.size()):
		var tone: Dictionary = tones[i]
		var skin_key: String = SKIN_KEYS[i] if i < SKIN_KEYS.size() else "SKIN_FAIR"
		var button := Button.new()
		button.custom_minimum_size = Vector2(30, 24)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = tr(skin_key)
		var style := _flat_style(tone["tint"], Color(0.18, 0.18, 0.16), 1, 0)
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
			style.border_color = Color(0.88, 0.78, 0.52, 1.0)
			style.set_border_width_all(1)
		else:
			style.border_color = Color(0.24, 0.24, 0.2, 1.0)
			style.set_border_width_all(1)
	var weight_index := _nearest_option(WEIGHT_OPTIONS, float(_profile.weight))
	for i in range(_weight_buttons.size()):
		_style_choice(_weight_buttons[i], i == weight_index)
	var height_index := _nearest_option(HEIGHT_OPTIONS, float(_profile.height))
	for i in range(_height_buttons.size()):
		_style_choice(_height_buttons[i], i == height_index)
	male_button.button_pressed = int(_profile.gender) == 0
	female_button.button_pressed = int(_profile.gender) == 1

func _style_choice(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override(
		"normal", _outfit_selected if selected else _outfit_normal)
	button.add_theme_stylebox_override(
		"hover", _outfit_selected_hover if selected else _outfit_hover)
	button.add_theme_stylebox_override("pressed", _outfit_pressed)
	button.add_theme_stylebox_override("hover_pressed", _outfit_pressed)

func _flat_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style

func _color_swatch(color: Color) -> ImageTexture:
	var image := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
