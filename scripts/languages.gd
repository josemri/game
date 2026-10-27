extends Node3D
@onready var anim: AnimationPlayer = $AnimationPlayer

## Segundos que el ratón debe permanecer sobre un libro para sacarlo.
const HOVER_DELAY := 0.5
## Segundos que tarda un libro en volver a su posición inicial.
const RETURN_TIME := 0.4

const LOCALE_MAP := {
	"1": "es",
	"2": "ca",
	"3": "en",
	"4": "bg",
	"5": "de",
	"6": "fr",
}

## Colores del texto de los libros: el idioma guardado se queda marcado
## para que el jugador vea que la elección se aplicó.
const LABEL_NORMAL := Color(0.52883124, 0.4972877, 0.45905, 1)
const LABEL_SELECTED := Color(0.92, 0.86, 0.68, 1)

## Libros que tienen el ratón encima ahora mismo (los selectores se solapan un poco).
var _hovered := {}
## Último libro sobre el que ha entrado el ratón: el único que manda.
var _active := ""
## Identificador del hover en curso: invalida los temporizadores pendientes.
var _hover_seq := 0
## Libro que está fuera (al que se le lanzó su animación "selected").
var _selected := ""
## Tween de vuelta a la posición inicial, uno por libro.
var _return_tweens := {}
## Transformada inicial de cada libro, guardada al arrancar.
var _base := {}
var _labels := {}
## Libro cuyo idioma está guardado ahora mismo ("" si aún no hay ninguno).
var _saved_book := ""

func _ready() -> void:
	_load_translations()
	for i in range(1, 7):
		var book := get_node_or_null("language%d" % i) as Node3D
		if book:
			_base[str(i)] = book.transform
		var label := get_node_or_null("language%d/Label3D" % i) as Label3D
		if label:
			_labels[str(i)] = label
	_load_language()
	_localize_books()
	_apply_saved_highlight()

func _on_area_3d_mouse_entered(book_id: int) -> void:
	var book := str(book_id)
	_hovered[book] = true
	if _active != book:
		_set_active(book)

func _on_area_3d_mouse_exited(book_id: int) -> void:
	var book := str(book_id)
	_hovered.erase(book)
	if _active != book:
		# Salida de un select que ya había quedado atrás: no toca el estado del ratón.
		return
	# El ratón sale del select activo: cancelamos su espera y devolvemos el libro.
	_active = ""
	_hover_seq += 1
	_deselect(book)
	if not _hovered.is_empty():
		# Quedaba otro libro solapado bajo el ratón: pasamos a él.
		_set_active(str(_hovered.keys().back()))

func _set_active(book: String) -> void:
	var previous := _active
	_active = book
	_hover_seq += 1 # invalida el temporizador del select anterior
	if previous != "":
		_deselect(previous) # el libro anterior vuelve a su sitio
	_wait_hover(book)

func _wait_hover(book: String) -> void:
	var seq := _hover_seq
	await get_tree().create_timer(HOVER_DELAY).timeout
	# Si mientras esperábamos el ratón salió o cambió de select, no hacemos nada.
	if seq != _hover_seq or _active != book or not _hovered.has(book):
		return
	_select(book)

func _select(book: String) -> void:
	if _selected == book:
		return
	if _selected != "":
		_deselect(_selected) # debería estar vacío, pero por si acaso
	_kill_return(book)
	_selected = book
	var anim_name := "selected" + book
	if anim.has_animation(anim_name):
		# Siempre arranca de cero: la clave 0 es la posición inicial del libro.
		anim.play(anim_name)
	_apply_language(book)
	_apply_saved_highlight()

func _deselect(book: String) -> void:
	if _selected != book:
		return
	_selected = ""
	var anim_name := "selected" + book
	var animating := anim.has_animation(anim_name) \
		and anim.current_animation == anim_name and anim.is_playing()
	var book_node := get_node_or_null("language%s" % book) as Node3D
	if book_node == null or not _base.has(book):
		if animating:
			anim.stop(true)
		return
	_kill_return(book)
	if animating:
		# Corta la animación dejando el libro donde está, para recogerlo con el tween.
		anim.stop(true)
	var tw := create_tween()
	tw.tween_property(book_node, "transform", _base[book], RETURN_TIME)
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.set_ease(Tween.EASE_IN_OUT)
	_return_tweens[book] = tw

func _kill_return(book: String) -> void:
	if _return_tweens.has(book):
		var tw: Tween = _return_tweens[book]
		tw.kill()
		_return_tweens.erase(book)


func _load_translations() -> void:
	for locale in ["en", "es", "ca", "bg", "de", "fr"]:
		var path := "res://translations/translations.%s.translation" % locale
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if res is Translation:
			TranslationServer.add_translation(res)


func _localize_books() -> void:
	var book_keys := {
		"1": "LANG_SPANISH",
		"2": "LANG_CATALAN",
		"3": "LANG_ENGLISH",
		"4": "LANG_BULGARIAN",
		"5": "LANG_GERMAN",
		"6": "LANG_FRENCH",
	}
	for book in book_keys.keys():
		var label: Label3D = _labels.get(book)
		if label:
			label.text = tr(book_keys[book])


func _apply_language(book: String) -> void:
	if not LOCALE_MAP.has(book):
		return
	var locale: String = LOCALE_MAP[book]
	TranslationServer.set_locale(locale)
	_saved_book = book
	_save_language(book)
	_localize_books()


func _load_language() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")
	if err != OK:
		TranslationServer.set_locale("es")
		_localize_books()
		return
	var locale: String = String(config.get_value("language", "locale", "es"))
	TranslationServer.set_locale(locale)
	for book in LOCALE_MAP.keys():
		if LOCALE_MAP[book] == locale:
			_saved_book = book
			break
	_localize_books()


## Pinta el texto del libro cuyo idioma está guardado; el resto queda
## en el tono normal para que la elección se lea de un vistazo.
func _apply_saved_highlight() -> void:
	for book in _labels.keys():
		var label: Label3D = _labels[book]
		label.modulate = LABEL_SELECTED if book == _saved_book else LABEL_NORMAL


func _save_language(book: String) -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	var locale: String = LOCALE_MAP.get(book, TranslationServer.get_locale())
	config.set_value("language", "locale", locale)
	config.save("user://settings.cfg")
