extends SceneTree
## Test del editor de personaje (scripts/character_customizer.gd) integrado
## en el vuelo de cámara de "play" del menú principal.
##
## Cubre: apertura durante la transición, ropa en vivo, tono de piel,
## peso/altura, identidad, guardado del perfil, vuelta al menú y que
## reabrir el editor no acumule tintes.
##
## Ejecutar:  godot --headless --path . -s res://tests/customization_test.gd

const SCENE := "res://scenes/mainmenu.tscn"
const SAVE_PATH := "user://player_profile.cfg"

var checks := 0
var failures := 0

var _backup := PackedByteArray()
var _had_save := false

func _check(label: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

func _initialize() -> void:
	_run()

func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_backup = FileAccess.get_file_as_bytes(SAVE_PATH)

func _restore_save() -> void:
	var abs_path := ProjectSettings.globalize_path(SAVE_PATH)
	if _had_save:
		var file := FileAccess.open(abs_path, FileAccess.WRITE)
		if file:
			file.store_buffer(_backup)
	else:
		DirAccess.remove_absolute(abs_path)

func _run() -> void:
	await process_frame
	_backup_save()

	var scene: Node3D = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(scene)
	await process_frame
	await create_timer(0.3).timeout

	var cam: Object = scene.get_node("Camera3D")
	var menu: Control = scene.get_node("Camera3D/CanvasLayer/Menu")
	var row1: Control = menu.get_node("HBoxContainer")
	var row2: Control = menu.get_node("HBoxContainer2")
	var cc: Control = menu.get_node("CharacterCustomizer")
	var main: Node3D = scene.get_node("mainCharMenu")
	var police: Node3D = scene.get_node("policeCharMenu")
	var anim: AnimationPlayer = main.find_child("AnimationPlayer", true, false)
	var skel: Skeleton3D = main.find_child("Skeleton3D", true, false)
	var profile: Object = get_root().get_node("GameProfile")
	# estado de fábrica en memoria (el archivo se restaura al terminar)
	profile.call("reset")

	# 1) antes de play el editor no existe y el menú está completo
	_check("1) el editor arranca oculto", not cc.visible)
	_check("1) el personaje secundario sigue visible", police.visible)
	_check("1) las filas del menú están visibles", row1.visible)

	# 2) play: el editor aparece durante el vuelo de cámara
	cam.call("_on_play_pressed")
	await create_timer(2.4).timeout
	_check("2) tras el vuelo el editor es visible", cc.visible)
	_check("2) las filas del menú se ocultan", not row1.visible and not row2.visible)
	_check("2) el personaje secundario se oculta", not police.visible)
	_check("2) el personaje sigue tumbado durante la creación",
		anim.current_animation == "beg")
	_check("2) el formulario se sincroniza con el perfil",
		cc.get("name_edit").text == profile.get("player_name")
		and cc.get("surname_edit").text == profile.get("surname"))
	_check("2) el panel cabe en la pantalla",
		cc.get_node("Panel").get_global_rect().end.x <= 1152.0
		and cc.get_node("Panel").get_global_rect().end.y <= 648.0)

	var weight_buttons: Array = cc.get("_weight_buttons")
	var height_buttons: Array = cc.get("_height_buttons")
	_check("2) el género son dos botones, no un desplegable",
		cc.get_node_or_null("Panel/Margin/VBox/Scroll/Fields/GenderRow/GenderOption") == null
		and cc.get_node("Panel/Margin/VBox/Scroll/Fields/GenderRow/MaleButton") != null
		and cc.get_node("Panel/Margin/VBox/Scroll/Fields/GenderRow/FemaleButton") != null)
	_check("2) el peso es una lista corta de opciones",
		weight_buttons.size() == 6 and String(weight_buttons[0].text) == "55"
		and String(weight_buttons[5].text) == "135")
	_check("2) la altura es una lista corta de opciones",
		height_buttons.size() == 5 and String(height_buttons[0].text) == "1.55"
		and String(height_buttons[4].text) == "1.95")
	var tips_ok := true
	for button in weight_buttons + height_buttons:
		var tip := String(button.tooltip_text)
		var lines := tip.split("\n")
		if lines.size() != 3 or not (":" in lines[1] and ":" in lines[2]):
			tips_ok = false
	_check("2) cada opción explica ventajas y desventajas al pasar el ratón", tips_ok)

	var visible_outfits: Array = []
	for i in range(1, 9):
		if (skel.get_node("arms_%03d" % i) as MeshInstance3D).visible:
			visible_outfits.append(i)
	_check("2) solo hay un conjunto de ropa visible", visible_outfits.size() == 1)
	_check("2) el conjunto visible es el del perfil",
		visible_outfits.size() == 1 and int(visible_outfits[0]) == int(profile.get("outfit")))
	_check("2) las 9 mallas de piel tienen material propio",
		(cc.get("_skin_entries") as Array).size() == 9)
	_check("2) la camiseta de manga corta muestra los brazos de piel",
		(skel.get_node("arms") as MeshInstance3D).visible
		and (skel.get_node("arms_009") as MeshInstance3D).visible)

	# 3) cambio de ropa en vivo
	cc.call("_on_outfit_selected", 5)
	await process_frame
	_check("3) la ropa 5 se activa",
		(skel.get_node("arms_005") as MeshInstance3D).visible
		and (skel.get_node("torso_005") as MeshInstance3D).visible)
	_check("3) la ropa anterior se oculta",
		not (skel.get_node("arms_002") as MeshInstance3D).visible
		and not (skel.get_node("torso_002") as MeshInstance3D).visible)
	_check("3) los brazos de piel siguen disponibles con otra ropa",
		(skel.get_node("arms") as MeshInstance3D).visible
		and (skel.get_node("arms_009") as MeshInstance3D).visible)
	_check("3) el perfil guarda la ropa", int(profile.get("outfit")) == 5)
	_check("3) cambiarse de ropa no levanta al personaje",
		anim.current_animation == "beg")

	# 4) tono de piel en vivo (el tinte se multiplica sobre el color base)
	var head: MeshInstance3D = skel.get_node("head")
	var skin_mat: BaseMaterial3D = head.material_override
	var fair_color: Color = skin_mat.albedo_color
	cc.call("_on_skin_selected", 4)
	await process_frame
	var deep_color: Color = skin_mat.albedo_color
	_check("4) el tono profundo oscurece la piel",
		deep_color.r < fair_color.r and deep_color.g < fair_color.g
		and deep_color.b < fair_color.b)
	_check("4) la textura de piel se conserva",
		skin_mat.albedo_texture != null)
	_check("4) el perfil guarda el tono", int(profile.get("skin_tone")) == 4)

	# 5) peso y altura cambian el cuerpo
	var base_scale: Vector3 = main.scale
	weight_buttons[4].pressed.emit()
	await process_frame
	_check("5) el peso ensancha el personaje",
		main.scale.x > base_scale.x and main.scale.z > base_scale.z)
	_check("5) el peso no altera la altura", is_equal_approx(main.scale.y, base_scale.y))
	_check("5) el volumen de sangre se recalcula",
		absf(float(profile.get("stats").max_blood) - 7920.0) < 0.5)
	_check("5) la etiqueta muestra sangre y constitución",
		"7.9" in cc.get("blood_label").text)

	var weight_scale: Vector3 = main.scale
	height_buttons[4].pressed.emit()
	await process_frame
	_check("5) la altura estira el personaje", main.scale.y > weight_scale.y)
	height_buttons[0].pressed.emit()
	await process_frame
	_check("5) bajar la altura encoge el personaje", main.scale.y < weight_scale.y)

	# 6) sexo, nombre y apellido; el nombre por defecto se adapta
	profile.call("set_names", "John", "Doe")
	cc.get("name_edit").text = "John"
	cc.get("surname_edit").text = "Doe"
	var male_button: Button = cc.get("male_button")
	var female_button: Button = cc.get("female_button")
	female_button.button_pressed = true
	female_button.pressed.emit()
	await process_frame
	_check("6) cambiar a mujer actualiza el nombre por defecto",
		cc.get("name_edit").text == "Jane")
	_check("6) la mujer tiene otro volumen de sangre",
		absf(float(profile.get("stats").max_blood) - 7150.0) < 0.5)
	_check("6) el botón de mujer queda marcado",
		female_button.button_pressed and not male_button.button_pressed)
	cc.get("name_edit").text = "Ana"
	cc.get("surname_edit").text = "Ruiz"
	male_button.button_pressed = true
	male_button.pressed.emit()
	await process_frame
	_check("6) un nombre propio no se pisa al cambiar de sexo",
		cc.get("name_edit").text == "Ana")
	_check("6) el botón de hombre queda marcado",
		male_button.button_pressed and not female_button.button_pressed)
	cc.call("commit_profile")
	_check("6) commit guarda nombre y apellido COMPLETOS",
		profile.get("player_name") == "Ana" and profile.get("surname") == "Ruiz")
	_check("6) el perfil compone el nombre completo",
		profile.call("full_name") == "Ana Ruiz")
	_check("6) el archivo de perfil se escribe",
		FileAccess.file_exists(SAVE_PATH))

	# 7) el perfil guardado se recupera en otra instancia
	var reloaded: Node = load("res://scripts/game_profile.gd").new()
	get_root().add_child(reloaded)
	await process_frame
	_check("7) se recupera el nombre", reloaded.get("player_name") == "Ana")
	_check("7) se recupera el apellido", reloaded.get("surname") == "Ruiz")
	_check("7) se recupera la ropa", int(reloaded.get("outfit")) == 5)
	_check("7) se recupera el tono de piel", int(reloaded.get("skin_tone")) == 4)
	_check("7) se recupera el peso", is_equal_approx(float(reloaded.get("weight")), 110.0))
	_check("7) se recupera la altura", is_equal_approx(float(reloaded.get("height")), 1.55))
	reloaded.queue_free()

	# 8) reabrir el editor no acumula el tinte de piel
	var tinted_once: Color = skin_mat.albedo_color
	cc.call("open", main)
	await process_frame
	_check("8) reabrir no vuelve a teñir la piel",
		skin_mat.albedo_color.is_equal_approx(tinted_once))

	# 9) randomize deja el formulario y el cuerpo coherentes
	cc.call("_on_randomize_pressed")
	await process_frame
	_check("9) randomize elige una ropa válida",
		int(profile.get("outfit")) >= 1 and int(profile.get("outfit")) <= 8)
	_check("9) randomize elige un peso de la lista",
		float(profile.get("weight")) in [55.0, 65.0, 75.0, 90.0, 110.0, 135.0])
	_check("9) randomize elige una altura de la lista",
		float(profile.get("height")) in [1.55, 1.65, 1.75, 1.85, 1.95])
	_check("9) randomize sincroniza el campo de nombre",
		cc.get("name_edit").text == profile.get("player_name"))
	_check("9) randomize sincroniza los botones de sexo",
		male_button.button_pressed == (int(profile.get("gender")) == 0)
		and female_button.button_pressed == (int(profile.get("gender")) == 1))

	# 10) back: el menú vuelve al home y el personaje se tumba
	cc.call("_on_back_pressed")
	await process_frame
	_check("10) back oculta el editor", not cc.visible)
	_check("10) back devuelve el personaje secundario", police.visible)
	_check("10) back muestra la fila principal", row1.visible and not row2.visible)
	_check("10) back reactiva el menú", not cam.get("_leaving") and cam.get("_at_home"))
	_check("10) back dispara la transición de cámara",
		cam.get("_cond_seq").get("back") >= 1)
	await create_timer(0.6).timeout
	_check("10) el personaje vuelve a la animación tumbada", anim.current_animation == "beg")

	print("")
	print("%d comprobaciones, %d fallos" % [checks, failures])

	_restore_save()
	quit(1 if failures > 0 else 0)
