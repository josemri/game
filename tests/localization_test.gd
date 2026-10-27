extends SceneTree
## Comprueba que la hoja de traducciones cubre todos los idiomas y que
## cambiar el locale actualiza los textos de la interfaz.

const LOCALES := ["en", "es", "ca", "bg", "de", "fr"]
const KEYS := [
	"MENU_PLAY", "MENU_OPTIONS", "MENU_CREDITS", "MENU_EXIT",
	"MENU_VOLUME", "MENU_LANGUAGE", "MENU_BRIGHTNESS", "MENU_BACK",
	"BTN_START", "BTN_RANDOMIZE", "CUSTOM_TITLE", "CUSTOM_IDENTITY",
	"CUSTOM_BODY", "CUSTOM_OUTFIT", "CUSTOM_NAME", "CUSTOM_SURNAME",
	"CUSTOM_GENDER", "CUSTOM_MALE", "CUSTOM_FEMALE", "CUSTOM_WEIGHT",
	"CUSTOM_HEIGHT", "CUSTOM_SKIN", "CUSTOM_BLOOD",
	"BUILD_SLIM", "BUILD_NORMAL", "BUILD_HEAVY",
	"LANG_SPANISH", "LANG_CATALAN", "LANG_ENGLISH",
	"LANG_BULGARIAN", "LANG_GERMAN", "LANG_FRENCH",
	"VOL_MASTER", "PLACEHOLDER_NAME", "PLACEHOLDER_SURNAME",
	"OUTFIT_1", "OUTFIT_2", "OUTFIT_3", "OUTFIT_4",
	"OUTFIT_5", "OUTFIT_6", "OUTFIT_7", "OUTFIT_8",
	"SKIN_FAIR", "SKIN_LIGHT", "SKIN_TAN", "SKIN_BROWN", "SKIN_DEEP",
	"TIP_ADV", "TIP_DIS",
	"W55_NAME", "W55_ADV", "W55_DIS", "W65_NAME", "W65_ADV", "W65_DIS",
	"W75_NAME", "W75_ADV", "W75_DIS", "W90_NAME", "W90_ADV", "W90_DIS",
	"W110_NAME", "W110_ADV", "W110_DIS", "W135_NAME", "W135_ADV", "W135_DIS",
	"H155_NAME", "H155_ADV", "H155_DIS", "H165_NAME", "H165_ADV", "H165_DIS",
	"H175_NAME", "H175_ADV", "H175_DIS", "H185_NAME", "H185_ADV", "H185_DIS",
	"H195_NAME", "H195_ADV", "H195_DIS",
]

var checks := 0
var failures := 0

func _check(label: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

func _initialize() -> void:
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		var missing: Array = []
		for key in KEYS:
			if tr(key) == key:
				missing.append(key)
		_check("%s: todas las claves traducidas (%d)" % [locale, KEYS.size()],
			missing.is_empty())
		if not missing.is_empty():
			print("   faltan: ", missing)

	var samples := {
		"es": "Jugar",
		"ca": "Jugar",
		"en": "Play",
		"bg": "Играй",
		"de": "Spielen",
		"fr": "Jouer",
	}
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		_check("%s: MENU_PLAY = %s" % [locale, samples[locale]],
			tr("MENU_PLAY") == samples[locale])

	TranslationServer.set_locale("es")
	_check("es: el título está en español", tr("CUSTOM_TITLE") == "SOBREVIVIENTE")
	_check("es: el botón START está en español", tr("BTN_START") == "EMPEZAR")
	_check("es: la ropa está en español", tr("OUTFIT_1") == "polo azul")
	_check("es: el tooltip de peso está en español",
		"muy ligero" in tr("W55_NAME") and "difícil" in tr("W55_ADV"))

	print("\n%d comprobaciones, %d fallos" % [checks, failures])
	quit(1 if failures > 0 else 0)
