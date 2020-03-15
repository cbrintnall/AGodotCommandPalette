tool
extends Popup


onready var filter = $PanelContainer/Panel/MarginContainer/Content/VBoxContainer/SearchFilter/MarginContainer/Filter
onready var item_list = $PanelContainer/Panel/MarginContainer/Content/VBoxContainer/MarginContainer/HSplitContainer/ItemList
onready var copy_path_button =$PanelContainer/Panel/MarginContainer/Content/VBoxContainer/SearchFilter/CopyButton
onready var info_box = $PanelContainer/Panel/MarginContainer/Content/VBoxContainer/MarginContainer/HSplitContainer/RightInfoBox

# after making changes in the inspector turn the plugin off and then on again in the project settings or reopen the project to apply the changes
export (Color) var secondary_color = Color(1, 1, 1, .3) # color for 3rd column
export (bool) var adapt_popup_height = true
var keyboard_shortcut = "Command+P" if OS.get_name() == "OSX" else "Control+P" # go to "Editor > Editor Settings... > Shortcuts > Bindings" to see how a shortcut looks as a String 
var max_popup_size = Vector2(clamp(1000 * (OS.get_screen_dpi() / 100), 500, OS.get_screen_size().x / 2), OS.get_screen_size().y / 2) 

var current_file # file names as String
var last_file  # switch between last 2 files opened with this plugin
var files_are_updating = false
var files : Dictionary # holds ALL scenes and scripts with different properties, see _update_files_dictionary()
enum FILTER {ALL_SCENES_AND_SCRIPTS, ALL_SCENES, ALL_SCRIPTS, ALL_OPEN_SCENES_SCRIPTS, ALL_OPEN_SCENES, ALL_OPEN_SCRIPTS, SIGNALS}
var types = ["-", "bool", "int", "float", "String", "Vector2", "Rect2", "Vector3", "Transform2D", "Plane", "Quat", "AABB", "Basis", \
		"Transform", "Color", "NodePath", "RID", "Object", "Dictionary", "Array", "PoolByteArray", "PoolIntArray", "PoolRealArray", \
		"PoolStringArray", "PoolVector2Array", "PoolVector3Array", "PoolColorArray", "Variant"] # for type hints for vars when using "sig " keyword
var code_snippets : ConfigFile = ConfigFile.new()

var PLUGIN : EditorPlugin
var INTERFACE : EditorInterface
var EDITOR : ScriptEditor
var FILE_SYSTEM : EditorFileSystem


# TODO: refactor


func _ready() -> void:
	connect("popup_hide", self, "_on_popup_hide")
	filter.connect("text_changed", self, "_on_filter_text_changed")
	filter.connect("text_entered", self, "_on_filter_text_entered")
	item_list.connect("item_activated", self, "_on_item_list_activated")
	item_list.connect("item_selected", self, "_on_item_list_selected")
	copy_path_button.connect("pressed", self, "_on_copy_button_pressed")
	PLUGIN.connect("main_screen_changed", self, "_on_main_screen_changed")
		
	$PanelContainer/Panel.set("custom_styles/panel", INTERFACE.get_base_control().get_stylebox("Content", "EditorStyles"))
	filter.right_icon = INTERFACE.get_base_control().get_icon("Search", "EditorIcons")
		
	var error = code_snippets.load("res://addons/CommandPalettePopup/CodeSnippets.cfg")
	if error != OK:
		print("Error loading the code_snippets. Error code: %s" % error)


func _unhandled_key_input(event: InputEventKey) -> void:
	if event.as_text() == keyboard_shortcut and event.pressed and visible and not filter.text and filter.has_focus():
		# switch between the last two opened files (only when opened via this plugin)
		if last_file:
			_open_scene(files[last_file].File_Path) if files[last_file].Type == "Scene" else _open_script(files[last_file].ScriptResource)
		hide()
		
	elif event.as_text() == keyboard_shortcut and event.pressed:
		rect_size = max_popup_size
		popup_centered()
		filter.grab_focus()
		_update_popup_list()


func _on_main_screen_changed(new_screen : String) -> void:
# set current_file; only during startup of the project:
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	for path in INTERFACE.get_open_scenes():
	# INTERFACE.get_edited_scene_root().name removes all leading underscores, so we also remove them
		var file_name = path.get_file()
		while file_name.begins_with("_"):
			file_name.erase(0, 1)
		if file_name.begins_with(INTERFACE.get_edited_scene_root().name + "."):
			current_file = path.get_file()
			break
	if PLUGIN.is_connected("main_screen_changed", self, "_on_main_screen_changed"):
		PLUGIN.disconnect("main_screen_changed", self, "_on_main_screen_changed")
	if not FILE_SYSTEM.is_connected("filesystem_changed", self, "_on_filesystem_changed"):
		_update_files_dictionary(FILE_SYSTEM.get_filesystem(), true)
		FILE_SYSTEM.connect("filesystem_changed", self, "_on_filesystem_changed")


func _on_filesystem_changed() -> void:
# to prevent unnecessarily updating the dictionary cause the signal gets fired multiple times
	if not files_are_updating:
		files_are_updating = true
		_update_files_dictionary(FILE_SYSTEM.get_filesystem(), true)
		yield(get_tree().create_timer(0.1), "timeout")
		files_are_updating = false


func _on_copy_button_pressed() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		if filter.text.begins_with("_ "): # code snippets are shown
			var use_type_hints = INTERFACE.get_editor_settings().get_setting("text_editor/completion/add_type_hints")
			var snippet_name = item_list.get_item_text(selection[0]).strip_edges()
			OS.clipboard = code_snippets.get_value(snippet_name, "signature")
			OS.clipboard += code_snippets.get_value(snippet_name, "type_hint") if use_type_hints else code_snippets.get_value(snippet_name, "no_type_hint")
		else:
			if selection[0] % item_list.max_columns == 1 and not filter.text.begins_with("sig ") and not filter.text.begins_with(": "): # selection is a file name
				var path = files[item_list.get_item_text(selection[0]).strip_edges()].File_Path
				OS.clipboard = "\"" + path + "\""
	hide()


func _on_popup_hide() -> void:
	filter.clear()


func _on_item_list_selected(index : int) -> void:
	if index % item_list.max_columns == 1 and filter.text.begins_with("_ "): # selection is a code_snippet
		_build_info_box(item_list.get_item_text(index).strip_edges())


func _on_item_list_activated(index : int) -> void:
	var selected_name = item_list.get_item_text(index).strip_edges()
	if filter.text.begins_with("_ "): # code snippets
		_paste_code_snippet(selected_name, item_list.get_meta("snippet_at_end"))
	elif filter.text.begins_with(": "): # go to line
		var number = filter.text.substr(2).strip_edges()
		if number.is_valid_integer():
			var max_lines = EDITOR.get_current_script().source_code.count("\n")
			EDITOR.goto_line(clamp(number as int - 1, 0, max_lines))
			INTERFACE.call_deferred("set_main_screen_editor", "Script")
	elif filter.text.begins_with("sig "):
		_paste_signal(selected_name)
	elif index % item_list.max_columns == 1: # file names
		_open_selection(selected_name)
	elif index % item_list.max_columns == 2: # file paths 
		var file_name = item_list.get_item_text(index - 1).strip_edges()
		INTERFACE.select_file(files[file_name].File_Path)
	hide()


func _on_filter_text_changed(new_txt : String) -> void:
	rect_size = max_popup_size
	_update_popup_list()


func _on_filter_text_entered(new_txt : String) -> void:
	if filter.text.begins_with(": "): # go to line
		var number = filter.text.substr(2).strip_edges()
		if number.is_valid_integer():
			var max_lines = EDITOR.get_current_script().source_code.count("\n")
			EDITOR.goto_line(clamp(number as int - 1, 0, max_lines))
			INTERFACE.call_deferred("set_main_screen_editor", "Script")
	var selection = item_list.get_selected_items()
	if selection:
		var selected_name = item_list.get_item_text(selection[0]).strip_edges()
		if filter.text.begins_with("_ "): # code snippets
			_paste_code_snippet(selected_name, item_list.get_meta("snippet_at_end"))
		elif filter.text.begins_with("sig "):
			_paste_signal(selected_name)
		else:
			_open_selection(selected_name) # file
	hide()


func _open_selection(selected_name : String) -> void:
	if files[selected_name].Type == "Script": 
		_open_script(files[selected_name].ScriptResource)
	else: 
		_open_scene(files[selected_name].File_Path)


func _open_script(script : Script) -> void:
	if script.has_meta("Scene_Path"):
		INTERFACE.open_scene_from_path(script.get_meta("Scene_Path"))
		
	INTERFACE.edit_resource(script)
	INTERFACE.call_deferred("set_main_screen_editor", "Script")
		
	last_file = current_file
	current_file = script.resource_path.get_file()


func _open_scene(path : String) -> void:
	INTERFACE.open_scene_from_path(path)
	INTERFACE.call_deferred("set_main_screen_editor", "3D") if INTERFACE.get_edited_scene_root() is Spatial else INTERFACE.call_deferred("set_main_screen_editor", "2D")
		
	last_file = current_file
	current_file = path.get_file()


func _update_files_dictionary(folder : EditorFileSystemDirectory, reset : bool = false) -> void:
	if reset:
		files.clear()
		
	var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
	for file in folder.get_file_count():
		var file_path = folder.get_file_path(file)
		var file_type = FILE_SYSTEM.get_file_type(file_path)
		var file_name = folder.get_file(file)
			
		if file_type.findn("Script") != -1:
			files[file_name] = { "Type" : "Script", "File_Path" : file_path, "ScriptResource" : load(file_path), "Icon" : script_icon}
			
		elif file_type.findn("Scene") != -1: 
			files[file_name] = {"Type" : "Scene", "File_Path" : file_path, "Icon" : null}
				
			var scene = load(file_path).instance()
			files[file_name].Icon = INTERFACE.get_base_control().get_icon(scene.get_class(), "EditorIcons")
			var attached_script = scene.get_script()
			if attached_script:
				attached_script.set_meta("Scene_Path", file_path)
			scene.free()
		
	for subdir in folder.get_subdir_count():
		_update_files_dictionary(folder.get_subdir(subdir))


func _update_popup_list() -> void:
	item_list.clear()
	item_list.visible = true
	info_box.bbcode_text = "No info..."
	info_box.visible = false
	var search_string = filter.text
	
	var snippet_at_end = false
	if search_string.begins_with("_ ") and search_string.ends_with(" e"):
		snippet_at_end = true
		search_string = search_string.substr(0, search_string.length() - 1 if search_string.length() == 3 else search_string.length() - 2)
		
	# typing " X" at the end of the search_string jumps to the X-th item in the list
	var quickselect_line = 0
	var qs_starts_at = search_string.find_last(" ")
	if qs_starts_at != -1 and not search_string.ends_with(" ") and not search_string.begins_with(": "):
		quickselect_line = search_string.substr(qs_starts_at + 1)
		if quickselect_line.is_valid_integer():
			search_string.erase(qs_starts_at + 1, String(quickselect_line).length())
		
	if search_string == "?":
		_build_help()
		info_box.visible = true
		item_list.visible = false
		return
		
	elif search_string.begins_with(": "): # go to line 
		var number = search_string.substr(2).strip_edges()
		_adapt_list_height()
		var max_lines = 0
		if number.is_valid_integer():
			max_lines = EDITOR.get_current_script().source_code.count("\n")
		item_list.add_item("Go to line: %s" % (clamp(number as int, 1, max_lines) if number.is_valid_integer() else "Enter valid number."))
		return
		
	elif search_string.begins_with("sig "): # show signals
		_build_item_list(search_string.substr(4).strip_edges(), FILTER.SIGNALS)
		
	elif search_string.begins_with("_ "): # show code snippets
		_build_method_list(search_string.substr(2).strip_edges(), snippet_at_end)
		
	elif search_string.begins_with("a "): # show all scripts and scenes
		_build_item_list(search_string.substr(2).strip_edges(), FILTER.ALL_SCENES_AND_SCRIPTS)
		
	elif search_string.begins_with("ac ") or search_string.begins_with("ca "): # show all scripts
		_build_item_list(search_string.substr(3).strip_edges(), FILTER.ALL_SCRIPTS)
		
	elif search_string.begins_with("as ") or search_string.begins_with("sa "): # show all scenes
		_build_item_list(search_string.substr(3).strip_edges(), FILTER.ALL_SCENES)
		
	elif search_string.begins_with("cs ") or search_string.begins_with("cs "): # show open scenes and scripts
		_build_item_list(search_string.substr(3).strip_edges(), FILTER.ALL_OPEN_SCENES_SCRIPTS)
		
	elif search_string.begins_with("s "): # show open scenes
		_build_item_list(search_string.substr(2).strip_edges(), FILTER.ALL_OPEN_SCENES)
		
	else: # show all open scripts
		_build_item_list(search_string.strip_edges(), FILTER.ALL_OPEN_SCRIPTS)
		
	quickselect_line = clamp(quickselect_line as int, 0, item_list.get_item_count() / item_list.max_columns - 1)
	if item_list.get_item_count() > 0:
		item_list.select(quickselect_line * item_list.max_columns + 1)
		item_list.ensure_current_is_visible()
		if filter.text.begins_with("_ "): # code snippets
			_build_info_box(item_list.get_item_text(item_list.get_selected_items()[0]).strip_edges())
		
	_adapt_list_height()


func _build_item_list(search_string : String, special_filter : int = -1) -> void:
	var list : Array
	match special_filter:
		FILTER.ALL_SCENES_AND_SCRIPTS:
			for file in files:
				if search_string:
					if file.findn(search_string) != -1:
						list.push_back(file)
				else:
					list.push_back(file)
			
		FILTER.ALL_SCRIPTS:
			for file in files:
				if files[file].Type == "Script":
					if search_string:
						if file.findn(search_string) != -1:
							list.push_back(file)
					else:
						list.push_back(file)
			
		FILTER.ALL_SCENES:
			for file in files:
				if files[file].Type == "Scene":
					if search_string:
						if file.findn(search_string) != -1:
							list.push_back(file)
					else:
						list.push_back(file)
			
		FILTER.ALL_OPEN_SCENES:
			var open_scenes = INTERFACE.get_open_scenes()
			for path in open_scenes:
				var scene_name = path.get_file()
				if search_string:
					if scene_name.findn(search_string) != -1:
						list.push_back(scene_name)
				else:
					list.push_back(scene_name)
			
		FILTER.ALL_OPEN_SCRIPTS:
			var open_scripts = EDITOR.get_open_scripts()
			for script in open_scripts:
				var script_name = script.resource_path.get_file()
				if search_string:
					if script_name.findn(search_string) != -1:
						list.push_back(script_name)
						
				else:
					list.push_back(script_name)
			
		FILTER.SIGNALS:
			var scene = load(EDITOR.get_current_script().get_meta("Scene_Path")).instance()
			var counter = 0
			for signals in scene.get_signal_list():
				if search_string:
					if signals.name.findn(search_string) != -1:
						item_list.add_item(" " + String(counter) + "  :: ", null, false)
						item_list.add_item(signals.name)
						if signals.args:
							item_list.add_item("(") 
							var current_item = item_list.get_item_count() - 1
							for arg_index in signals.args.size():
								item_list.set_item_text(current_item, item_list.get_item_text(current_item) + signals.args[arg_index].name + " : " + (signals.args[arg_index].get("class_name") if signals.args[arg_index].get("class_name") else types[signals.args[arg_index].type]) + (", " if arg_index < signals.args.size() - 1 else ""))
							item_list.set_item_text(current_item, item_list.get_item_text(current_item) + ")") 
							item_list.set_item_disabled(current_item, true)
						else:
							item_list.add_item("", null, false)
						counter += 1
				else:
					item_list.add_item(" " + String(counter) + "  :: ", null, false)
					item_list.add_item(signals.name)
					if signals.args:
						item_list.add_item("(") 
						var current_item = item_list.get_item_count() - 1
						for arg_index in signals.args.size():
								item_list.set_item_text(current_item, item_list.get_item_text(current_item) + signals.args[arg_index].name + " : " + (signals.args[arg_index].get("class_name") if signals.args[arg_index].get("class_name") else types[signals.args[arg_index].type]) + (", " if arg_index < signals.args.size() - 1 else ""))
						item_list.set_item_text(current_item, item_list.get_item_text(current_item) + ")") 
						item_list.set_item_disabled(current_item, true)
					else:
						item_list.add_item("", null, false)
					counter += 1
			scene.free()
			
		FILTER.ALL_OPEN_SCENES_SCRIPTS:
			var open_scenes = INTERFACE.get_open_scenes()
			for path in open_scenes:
				var scene_name = path.get_file()
				if search_string:
					if scene_name.findn(search_string) != -1:
						list.push_back(scene_name)
				else:
					list.push_back(scene_name)
				
			var open_scripts = EDITOR.get_open_scripts()
			for script in open_scripts:
				var script_name = script.resource_path.get_file()
				if search_string:
					if script_name.findn(search_string) != -1:
						list.push_back(script_name)
				else:
					list.push_back(script_name)
		
	list.sort()
	for index in list.size():
		item_list.add_item(" " + String(index) + "  :: ", null, false)
		item_list.add_item(" " + list[index], files[list[index]].Icon)
		var file_path = files[list[index]].File_Path.get_base_dir()
		item_list.add_item(" - " + file_path.substr(0, 6) + " - " + file_path.substr(6).replace("/", " - "))
		item_list.set_item_custom_fg_color(item_list.get_item_count() - 1, secondary_color)


func _adapt_list_height() -> void:
	if adapt_popup_height:
		var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
		var row_height = script_icon.get_size().y + (8 * (OS.get_screen_dpi() / 100))
		var rows = item_list.get_item_count() / item_list.max_columns + 1
		var margin = filter.rect_size.y + $PanelContainer/Panel/MarginContainer.margin_top + abs($PanelContainer/Panel/MarginContainer.margin_bottom) + $PanelContainer/Panel/MarginContainer/Content/VBoxContainer/MarginContainer.get("custom_constants/margin_top")
		var height = row_height * rows + margin
		rect_size.y = clamp(height, 0, max_popup_size.y)


func _build_help() -> void:
	var file = File.new()
	file.open("res://addons/CommandPalettePopup/Help.txt", File.READ)
	info_box.bbcode_text = file.get_as_text()
	file.close()


func _build_method_list(filtered_name : String, snippet_at_end : bool) -> void:
	var counter = 0
	item_list.set_meta("snippet_at_end", true) if snippet_at_end else item_list.set_meta("snippet_at_end", false)
	for method_name in code_snippets.get_sections():
		if filtered_name:
			if method_name.findn(filtered_name) != -1:
				item_list.add_item(" " + String(counter) + "  :: ", null, false)
				item_list.add_item(" " + method_name)
				item_list.add_item(code_snippets.get_value(method_name, "additional_info"), null, false) if code_snippets.has_section_key(method_name, "additional_info") else item_list.add_item("")
				item_list.set_item_custom_fg_color(item_list.get_item_count() - 1, secondary_color)
				counter += 1
		else:
			item_list.add_item(" " + String(counter) + "  :: ", null, false)
			item_list.add_item(" " + method_name)
			item_list.add_item(code_snippets.get_value(method_name, "additional_info"), null, false) if code_snippets.has_section_key(method_name, "additional_info") else item_list.add_item("")
			item_list.set_item_custom_fg_color(item_list.get_item_count() - 1, secondary_color)
			counter += 1


func _build_info_box(snippet_name : String) -> void:
	info_box.bbcode_text = "No info..."
		
	if code_snippets.has_section_key(snippet_name, "description"):
		info_box.bbcode_text = code_snippets.get_value(snippet_name, "description")
		info_box.visible = true


func _paste_signal(signal_name : String) -> void:
	var script_index = 0
	for script in EDITOR.get_open_scripts():
		if script == EDITOR.get_current_script():
			break
		script_index += 1
	var code_editor = EDITOR.get_child(0).get_child(1).get_child(1).get_child(script_index).get_child(0).get_child(0).get_child(0) # TextEdit of current script
	var node_name = EDITOR.get_current_script().resource_path.get_file().get_basename()
	var snippet = "connect(\"%s\", , \"_on_%s_%s\")" % [signal_name, node_name, signal_name]
	code_editor.insert_text_at_cursor(snippet)
	var new_column = code_editor.cursor_get_column() - signal_name.length() - EDITOR.get_current_script().resource_path.get_file().get_basename().length() - 10 # 10 = "_on_...."
	code_editor.cursor_set_column(new_column)
	OS.clipboard = "func _on_%s_%s():\n\tpass" % [node_name, signal_name]


func _paste_code_snippet(snippet_name : String, insert_at_end : bool) -> void:
	var script_index = 0
	for script in EDITOR.get_open_scripts():
		if script == EDITOR.get_current_script():
			break
		script_index += 1
	var code_editor = EDITOR.get_child(0).get_child(1).get_child(1).get_child(script_index).get_child(0).get_child(0).get_child(0) # TextEdit of current script
	var use_type_hints = INTERFACE.get_editor_settings().get_setting("text_editor/completion/add_type_hints")
	var code_snippet = code_snippets.get_value(snippet_name, "signature")
	code_snippet += code_snippets.get_value(snippet_name, "type_hint") if use_type_hints else code_snippets.get_value(snippet_name, "no_type_hint")
	if insert_at_end:
		EDITOR.goto_line(code_editor.get_line_count() - 1)
	code_editor.call_deferred("insert_text_at_cursor", code_snippet)
# Alternative way of snippet implementation: copy to clipboard and creating Ctrl+V InputEvent
#	var old_clipboard = OS.clipboard 
#	OS.clipboard = ""
#
#	var use_type_hints = INTERFACE.get_editor_settings().get_setting("text_editor/completion/add_type_hints")
#	OS.clipboard +=  code_snippets.get_value(snippet_name, "signature")
#	OS.clipboard += code_snippets.get_value(snippet_name, "type_hint") if use_type_hints else code_snippets.get_value(snippet_name, "no_type_hint")
#	
#	if insert_at_end:
#		var max_lines = EDITOR.get_current_script().source_code.count("\n")
#		EDITOR.goto_line(max_lines)
#
#	call_deferred("_paste_helper_method", old_clipboard)
#
#
#func _paste_helper_method(old_clipboard : String) -> void:
#	var paste_key_combo = InputEventKey.new()
#	if OS.get_name() == "OSX":
#		paste_key_combo.command = true
#	else:
#		paste_key_combo.control = true
#	paste_key_combo.scancode = KEY_V
#	paste_key_combo.pressed = true
#	Input.parse_input_event(paste_key_combo)
#
#	OS.clipboard = old_clipboard
func test():
	var paste_key_combo = InputEventKey.new()
	paste_key_combo.command = true
	paste_key_combo.scancode = KEY_V
	paste_key_combo.pressed = true
	Input.parse_input_event(paste_key_combo)
