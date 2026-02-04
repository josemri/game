extends Node
class_name PlayerStats

# ENUMS
enum Sex { HOMBRE, MUJER }
enum HungerState { SACIADO, BIEN, HAMBRIENTO, MUY_HAMBRIENTO, FAMELICO }
enum ThirstState { HIDRATADO, BIEN, SED, MUCHA_SED, DESHIDRATADO }
enum StrengthState { MUY_DEBIL, DEBIL, NORMAL, FUERTE, MUY_FUERTE }
enum TemperatureState { HIPOTERMIA, FRIO, NORMAL, CALOR, FIEBRE }

# STATS BASE
var sex: Sex
var max_blood: float
var blood_current: float
var weight: float
var diet: float = 50.0 # 0 - 100

var playerName: String
var playersurname: String

var body_temperature: float = 36.6

var strength: float = 50.0 # 0 - 100
var agility: float = 50.0
var velocity: float = 50.0

var resistance: float = 50.0 # stamina max

var hunger: float = 100.0 # 0 - 100
var thirst: float = 100.0

var vista: float = 100.0
var oido: float = 100.0
var olfato: float = 50.0
var gusto: float = 50.0

var habilidades: Array = []
var enfermedades: Array = []
var sintomas: Array = []

# =========================
# CONSTRUCTOR
# =========================

func _init(_sex: Sex = Sex.HOMBRE, _weight: float = 70.0, _playerName: String = "", _playerSurname: String = ""):
	sex = _sex
	weight = _weight
	
	if (_playerName == ""):
		if(sex == Sex.HOMBRE):
			playerName = "Jhon"
		else:
			playerName = "Jane"
	
	if (_playerSurname == ""):
		playersurname = "Doe"
	
	
	_calculate_blood()
	blood_current = max_blood
	_recalculate_resistance()

# =========================
# CALCULOS INTERNOS
# =========================

func _calculate_blood():
	var base_ml_per_kg: float
	
	# Base según sexo
	if sex == Sex.HOMBRE:
		base_ml_per_kg = 72.0
	else:
		base_ml_per_kg = 65.0
	
	# Modificador por estado de fuerza
	var strength_modifier := 0.0
	match get_strength_state():
		StrengthState.MUY_DEBIL:
			strength_modifier = -2.0
		StrengthState.DEBIL:
			strength_modifier = -1.0
		StrengthState.NORMAL:
			strength_modifier = 0.0
		StrengthState.FUERTE:
			strength_modifier = 1.0
		StrengthState.MUY_FUERTE:
			strength_modifier = 2.0
	
	# Cálculo final
	var total_ml_per_kg := base_ml_per_kg + strength_modifier
	max_blood = total_ml_per_kg * weight

func _recalculate_resistance():
	# stamina depende de stats físicos
	resistance = 30.0
	resistance += strength * 0.3
	resistance += agility * 0.2
	resistance += velocity * 0.1
	resistance = clamp(resistance, 20.0, 150.0)

# =========================
# UPDATE POR TIEMPO
# =========================

func update_stats(delta: float):
	_update_hunger(delta)
	_update_thirst(delta)
	_update_temperature(delta)
	_apply_diet_effects(delta)
	_update_symptoms()

# =========================
# HUNGER / THIRST
# =========================

func _update_hunger(delta):
	hunger -= delta * 0.5
	hunger = clamp(hunger, 0.0, 100.0)
	
	if hunger <= 20:
		strength -= delta * 0.2

func _update_thirst(delta):
	thirst -= delta * 0.8
	thirst = clamp(thirst, 0.0, 100.0)
	
	if thirst <= 15:
		velocity -= delta * 0.3

# =========================
# TEMPERATURA CORPORAL
# =========================

func _update_temperature(delta):
	# ejemplo simple: hambre y sed afectan
	if hunger < 30:
		body_temperature -= delta * 0.01
	if thirst < 30:
		body_temperature += delta * 0.015

	body_temperature = clamp(body_temperature, 33.0, 41.5)

# =========================
# DIETA
# =========================

func eat_food(nutrition: float):
	diet += nutrition
	hunger += nutrition * 0.8
	diet = clamp(diet, 0.0, 100.0)
	hunger = clamp(hunger, 0.0, 100.0)

func drink_water(amount: float):
	thirst += amount
	thirst = clamp(thirst, 0.0, 100.0)

func _apply_diet_effects(delta):
	if diet < 20:
		strength -= delta * 0.3
	elif diet > 80:
		strength += delta * 0.2

	strength = clamp(strength, 0.0, 100.0)
	_recalculate_resistance()

# =========================
# ENFERMEDADES Y SINTOMAS
# =========================

func add_disease(disease_name: String):
	if disease_name not in enfermedades:
		enfermedades.append(disease_name)

func _update_symptoms():
	sintomas.clear()
	for disease in enfermedades:
		match disease:
			"gripe":
				sintomas.append("fiebre")
				sintomas.append("debilidad")
			"deshidratacion":
				sintomas.append("mareos")

# =========================
# GETTERS PARA EL JUGADOR
# =========================

func get_hunger_state() -> HungerState:
	if hunger > 80: return HungerState.SACIADO
	if hunger > 60: return HungerState.BIEN
	if hunger > 40: return HungerState.HAMBRIENTO
	if hunger > 20: return HungerState.MUY_HAMBRIENTO
	return HungerState.FAMELICO

func get_thirst_state() -> ThirstState:
	if thirst > 80: return ThirstState.HIDRATADO
	if thirst > 60: return ThirstState.BIEN
	if thirst > 40: return ThirstState.SED
	if thirst > 20: return ThirstState.MUCHA_SED
	return ThirstState.DESHIDRATADO

func get_strength_state() -> StrengthState:
	if strength < 20: return StrengthState.MUY_DEBIL
	if strength < 40: return StrengthState.DEBIL
	if strength < 60: return StrengthState.NORMAL
	if strength < 80: return StrengthState.FUERTE
	return StrengthState.MUY_FUERTE

func get_temperature_state() -> TemperatureState:
	if body_temperature < 34: return TemperatureState.HIPOTERMIA
	if body_temperature < 35.5: return TemperatureState.FRIO
	if body_temperature < 37.6: return TemperatureState.NORMAL
	if body_temperature < 39.1: return TemperatureState.CALOR
	return TemperatureState.FIEBRE
