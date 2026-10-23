extends Node

## Perfil del jugador: identidad + aspecto elegidos en el menú de
## personalización y que las partidas pueden consultar desde cualquier
## escena (autoload "GameProfile").
##
## Guarda el perfil en user://player_profile.cfg para que la
## personalización se conserve entre ejecuciones. El perfil también
## mantiene un PlayerStats reconstruido con el sexo y el peso, que es
## lo que alimenta la previsualización del volumen de sangre.

const SAVE_PATH := "user://player_profile.cfg"

const OUTFITS := [
	{"id": 1, "name": "blue polo", "color": Color(0.23, 0.43, 0.65)},
	{"id": 2, "name": "blue t-shirt", "color": Color(0.18, 0.50, 0.82)},
	{"id": 3, "name": "grey polo", "color": Color(0.50, 0.50, 0.53)},
	{"id": 4, "name": "khaki polo", "color": Color(0.70, 0.63, 0.43)},
	{"id": 5, "name": "red shirt", "color": Color(0.66, 0.19, 0.18)},
	{"id": 6, "name": "grey v-neck", "color": Color(0.37, 0.39, 0.42)},
	{"id": 7, "name": "white polo", "color": Color(0.90, 0.89, 0.87)},
	{"id": 8, "name": "white shirt", "color": Color(0.85, 0.85, 0.85)},
]

const SKIN_TONES := [
	{"name": "fair", "tint": Color(1.00, 1.00, 1.00)},
	{"name": "light", "tint": Color(0.93, 0.82, 0.74)},
	{"name": "tan", "tint": Color(0.84, 0.70, 0.60)},
	{"name": "brown", "tint": Color(0.72, 0.56, 0.46)},
	{"name": "deep", "tint": Color(0.58, 0.42, 0.34)},
]

const GENDERS := ["male", "female"]

const DEFAULT_NAME_MALE := "John"
const DEFAULT_NAME_FEMALE := "Jane"
const DEFAULT_SURNAME := "Doe"

var player_name: String = DEFAULT_NAME_MALE
var surname: String = DEFAULT_SURNAME
var gender: int = 0
var weight: float = 75.0
var height: float = 1.83
var outfit: int = 2
var skin_tone: int = 0

var stats = null

func _ready() -> void:
	load_profile()
	_rebuild_stats()

## Reconstruye las estadísticas derivadas del perfil (volumen de sangre,
## resistencia...). El menú la llama al mover peso o sexo para que el
## dato que se muestra sea el que se guardará.
func _rebuild_stats() -> void:
	var script = load("res://scripts/stats.gd")
	stats = script.new(gender, weight, player_name, surname)

func set_weight(value: float) -> void:
	weight = clampf(value, 45.0, 140.0)
	_rebuild_stats()

func set_gender(value: int) -> void:
	gender = clampi(value, 0, 1)
	_rebuild_stats()

func set_names(new_name: String, new_surname: String) -> void:
	player_name = new_name
	surname = new_surname
	_rebuild_stats()

func set_outfit(value: int) -> void:
	outfit = clampi(value, 1, OUTFITS.size())

func set_skin_tone(value: int) -> void:
	skin_tone = clampi(value, 0, SKIN_TONES.size() - 1)

func set_height(value: float) -> void:
	height = clampf(value, 1.55, 1.95)

func refresh_stats() -> void:
	_rebuild_stats()

func outfit_list() -> Array:
	return OUTFITS

func skin_tone_list() -> Array:
	return SKIN_TONES

func gender_list() -> Array:
	return GENDERS

func default_name_for(gender_index: int) -> String:
	return DEFAULT_NAME_FEMALE if gender_index == 1 else DEFAULT_NAME_MALE

func full_name() -> String:
	return ("%s %s" % [player_name, surname]).strip_edges()

## Vuelve a los valores de fábrica sin tocar el archivo guardado.
func reset() -> void:
	player_name = DEFAULT_NAME_MALE
	surname = DEFAULT_SURNAME
	gender = 0
	weight = 75.0
	height = 1.83
	outfit = 2
	skin_tone = 0
	_rebuild_stats()

func save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("identity", "name", player_name)
	config.set_value("identity", "surname", surname)
	config.set_value("identity", "gender", gender)
	config.set_value("body", "weight", weight)
	config.set_value("body", "height", height)
	config.set_value("appearance", "outfit", outfit)
	config.set_value("appearance", "skin_tone", skin_tone)
	config.save(SAVE_PATH)

func load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	player_name = str(config.get_value("identity", "name", DEFAULT_NAME_MALE))
	surname = str(config.get_value("identity", "surname", DEFAULT_SURNAME))
	gender = clampi(int(config.get_value("identity", "gender", 0)), 0, 1)
	weight = clampf(float(config.get_value("body", "weight", 75.0)), 45.0, 140.0)
	height = clampf(float(config.get_value("body", "height", 1.83)), 1.55, 1.95)
	outfit = clampi(int(config.get_value("appearance", "outfit", 2)), 1, OUTFITS.size())
	skin_tone = clampi(int(config.get_value("appearance", "skin_tone", 0)), 0, SKIN_TONES.size() - 1)
