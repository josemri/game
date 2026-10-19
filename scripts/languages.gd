extends Node3D
@onready var anim: AnimationPlayer = $AnimationPlayer

## Segundos que el ratón debe permanecer sobre un libro para sacarlo.
const HOVER_DELAY := 0.5
## Segundos que tarda un libro en volver a su posición inicial.
const RETURN_TIME := 0.4

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

func _ready() -> void:
	for i in range(1, 7):
		var book := get_node_or_null("language%d" % i) as Node3D
		if book:
			_base[str(i)] = book.transform

func _on_area_3d_mouse_entered(_name: int) -> void:
	var book := str(_name)
	_hovered[book] = true
	if _active != book:
		_set_active(book)

func _on_area_3d_mouse_exited(_name: int) -> void:
	var book := str(_name)
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

func _on_area_3d_input_event(_camera: Node, _event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	pass
