tool
extends Popup


onready var filter = $Panel/MarginContainer2/VBoxContainer2/HBoxContainer/Filter
onready var item_list = $Panel/MarginContainer2/VBoxContainer2/MarginContainer/ItemList
onready var copy_path_button =$Panel/MarginContainer2/VBoxContainer2/HBoxContainer/Button

# save the file after you made changes in the inspector; reenable the plugin in the project settings or reopen the project to apply the changes
export (Vector2) var popup_size
export (bool) var explain_function

var current_file # file names as String
var last_file  # switch between last 2 files opened with this plugin
var files_are_updating = false
var files : Dictionary # holds ALL scenes and scripts with different properties, see _update_files_dictionary()
enum FILTER {ALL_SCENES_AND_SCRIPTS, ALL_SCENES, ALL_SCRIPTS, ALL_OPEN_SCENES, ALL_OPEN_SCRIPTS, HELP}
var method_config : ConfigFile

var PLUGIN : EditorPlugin
var INTERFACE : EditorInterface
var EDITOR : ScriptEditor
var FILE_SYSTEM : EditorFileSystem

# TODO: 
# add feature: code snippets for virtual methods: insert at file end, add box at bottom with documentation
# add feature: display all incoming and outgoing signal connections
# add feature: listing all signals for the node and its parent classes and auto-paste its code at cursor position or file end (?)
# better themeing
# doc for go_to_line (": ")
# doc for code_snippet
# doc for copy button
# submit PR for documentation of get_children() on TreeItem


func _ready() -> void:
	connect("popup_hide", self, "_on_popup_hide")
	filter.connect("text_changed", self, "_on_filter_text_changed")
	filter.connect("text_entered", self, "_on_filter_text_entered")
	item_list.connect("item_activated", self, "_on_item_list_activated")
	copy_path_button.connect("pressed", self, "_on_copy_button_pressed")
	FILE_SYSTEM.connect("filesystem_changed", self, "_on_filesystem_changed")
	PLUGIN.connect("main_screen_changed", self, "_on_main_screen_changed")
		
	method_config = ConfigFile.new()
	var error = method_config.load("res://addons/SearchSceneScriptPopup/CodeSnippets.cfg")
	if error != OK:
		print("Error loading the _settings. Error code: %s" % error)


# global keyboard shortcuts
func _unhandled_key_input(event: InputEventKey) -> void:
	if event.as_text() == "Control+E" and event.pressed and visible and not filter.text and filter.has_focus():
		# switch between the last two opened files (only when opened via this plugin)
		if last_file:
			_open_scene(files[last_file].File_Path) if files[last_file].Type == "Scene" else _open_script(files[last_file].Instance)
		hide()
		
	elif event.as_text() == "Control+E" and event.pressed:
		rect_size = popup_size
		popup_centered()
		_update_popup_list()


func _on_main_screen_changed(new_screen : String) -> void:
# set current_file; only once on startup of the project:
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


func _on_filesystem_changed() -> void:
# to prevent unnecessarily updating the dictionary cause signal gets fired multiple times
	if not files_are_updating:
		files_are_updating = true
		_update_files_dictionary(FILE_SYSTEM.get_filesystem(), true)
		yield(get_tree().create_timer(0.1), "timeout")
		files_are_updating = false


func _on_copy_button_pressed() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		if filter.text.begins_with("_ "):
			var use_type_hint = INTERFACE.get_editor_settings().get_setting("text_editor/completion/add_type_hints")
			OS.clipboard = method_config.get_value(item_list.get_item_text(selection[0]).strip_edges(), "with_type_hint" if use_type_hint else "without_type_hint")
		else:
			var path = files[item_list.get_item_text(selection[0]).strip_edges()].File_Path
			OS.clipboard = "\"" + path + "\""
	hide()


func _on_popup_hide() -> void:
	filter.clear()


func _on_item_list_activated(index : int) -> void:
	if filter.text.begins_with("_ "):
		_paste_code_snippet(item_list.get_item_text(index).strip_edges())
	elif index % item_list.max_columns == 1:
		# file name
		_open_selection()
	elif index % item_list.max_columns == 2:
		# file path 
		var file_name = item_list.get_item_text(index - 1).strip_edges()
		INTERFACE.select_file(files[file_name].File_Path)
	hide()


func _on_filter_text_changed(new_txt : String) -> void:
	_update_popup_list()


func _on_filter_text_entered(new_txt : String) -> void:
	if filter.text.begins_with("_ "):
		var selection = item_list.get_selected_items()
		if selection:
			_paste_code_snippet(item_list.get_item_text(selection[0]).strip_edges())
	else:
		_open_selection()
	hide()


func _open_selection() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		var selected_name = item_list.get_item_text(selection[0]).strip_edges()
		if files[selected_name].Type == "Script": 
			_open_script(files[selected_name].Instance)
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
			
		if file_type.findn("Script") != -1:
			files[folder.get_file(file)] = { "Type" : "Script", "File_Path" : file_path, "Instance" : load(file_path), "List_Index" : 0, "Icon" : script_icon}
			
		elif file_type.findn("Scene") != -1: 
			files[folder.get_file(file)] = {"Type" : "Scene", "File_Path" : file_path, "List_Index" : 0, "Icon" : null}
			var scene = load(file_path).instance()
			files[folder.get_file(file)].Icon = INTERFACE.get_base_control().get_icon(scene.get_class(), "EditorIcons")
			var attached_script = scene.get_script() as Script
			if attached_script:
				attached_script.set_meta("Scene_Path", file_path)
			scene.free()
		
	for subdir in folder.get_subdir_count():
		_update_files_dictionary(folder.get_subdir(subdir))


func _update_popup_list() -> void:
	item_list.clear()
	var search_string = filter.text
		
	# typing " X" at the end of the search_string jumps to the X-th item in the list
	var quickselect_line = 0
	var qs_starts_at = search_string.find_last(" ")
	if qs_starts_at != -1 and not search_string.ends_with(" ") and not search_string.begins_with(": "):
		quickselect_line = search_string.substr(qs_starts_at + 1)
		if quickselect_line.is_valid_integer():
			search_string.erase(qs_starts_at + 1, String(quickselect_line).length())
		
	if search_string.begins_with("?"):
		_build_help_list()
		return
		
	elif search_string.begins_with(": "):
		var number = search_string.substr(2).strip_edges()
		if number.is_valid_integer():
			EDITOR.goto_line(number as int - 1)
		return
		
	elif search_string.begins_with("_ "):
		_build_method_list(search_string.substr(2).strip_edges())
		
	elif search_string.begins_with("a "):
		_build_item_list(search_string.substr(2).strip_edges(), FILTER.ALL_SCENES_AND_SCRIPTS)
		
	elif search_string.begins_with("ac ") or search_string.begins_with("ca "):
		_build_item_list(search_string.substr(3).strip_edges(), FILTER.ALL_SCRIPTS)
		
	elif search_string.begins_with("as ") or search_string.begins_with("sa "):
		_build_item_list(search_string.substr(3).strip_edges(), FILTER.ALL_SCENES)
		
	elif search_string.begins_with("c "):
		_build_item_list(search_string.substr(2).strip_edges(), FILTER.ALL_OPEN_SCRIPTS)
		
	elif search_string.begins_with("s "):
		_build_item_list(search_string.substr(2).strip_edges(), FILTER.ALL_OPEN_SCENES)
		
	else: # ALL OPEN scenes and scripts
		_build_item_list(search_string.strip_edges())
		
	quickselect_line = clamp(quickselect_line as int, 0, item_list.get_item_count() / item_list.max_columns - 1)
	if item_list.get_item_count() > 0:
		item_list.select(quickselect_line * item_list.max_columns + 1)
	item_list.ensure_current_is_visible()


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
			
		_:
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
		files[list[index]].List_Index = index
		var file_path = files[list[index]].File_Path.get_base_dir()
		item_list.add_item(" - " + file_path.substr(0, 6) + " - " + file_path.substr(6).replace("/", " - "))
		item_list.set_item_custom_fg_color(item_list.get_item_count() - 1, Color(1, 1, 1, .3))


func _build_help_list() -> void:
	item_list.add_item(" By default", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("ALL OPEN scripts and scenes", null, false)
	item_list.add_item("will be shown.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		
	item_list.add_item("", null, false)
	item_list.add_item("", null, false)
	item_list.add_item("", null, false)
		
	item_list.add_item(" Starting the search_string with \"", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("c ", null, false)
	item_list.add_item("\" (c for code) will show all OPEN scripts.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		
	item_list.add_item(" Starting the search_string with \"", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("s ", null, false)
	item_list.add_item("\" (s for scene) will show all OPEN scenes.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		
	item_list.add_item(" Starting the search_string with \"", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("a ", null, false)
	item_list.add_item("\" will show ALL scripts and scenes.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		
	item_list.add_item(" Starting the search_string with \"", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("ac ", null, false)
	item_list.add_item("\" (or ca) will show ALL scripts.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		
	item_list.add_item(" Starting the search_string with \"", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("as ", null, false)
	item_list.add_item("\" (or sa) will show ALL scenes.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		
	item_list.add_item("", null, false)
	item_list.add_item("", null, false)
	item_list.add_item("", null, false)
		
	item_list.add_item(" Ending the search_string with \"", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item(" X", null, false)
	item_list.add_item("\", where X is an integer, will jump to the X-th line in the list.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		
	item_list.add_item("", null, false)
	item_list.add_item("", null, false)
	item_list.add_item("", null, false)
		
	item_list.add_item("Opening a script also opens the scene the sript is attached to", null, false)
	item_list.add_item(", if the script is attached to the scene root.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("", null, false)
		
	item_list.add_item("Activating the file path will", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("jump to the file in the filesystem dock.", null, false)
	item_list.add_item("", null, false)
		
	item_list.add_item("While the popup is open, pressing", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("Ctrl+E will switch to the last file opened", null, false)
	item_list.add_item("with this plugin.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		
	item_list.add_item("Some", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)
	item_list.add_item("export vars are available.", null, false)
	item_list.add_item("Reopen the project after changing those.", null, false)
	item_list.set_item_disabled(item_list.get_item_count() - 1, true)


func _build_method_list(search_string : String) -> void:
	var counter = 0
	for method_name in method_config.get_sections():
		if method_name != "TEMPLATE":
			if search_string:
				if method_name.findn(search_string) != -1:
					item_list.add_item(" " + String(counter) + "  :: ", null, false)
					item_list.add_item(" " + method_name)
					item_list.add_item("", null, false)
			else:
				item_list.add_item(" " + String(counter) + "  :: ", null, false)
				item_list.add_item(" " + method_name)
				item_list.add_item("", null, false)
		counter += 1


func _paste_code_snippet(method_name : String, at_end_of_file : bool = false) -> void:
	var old_clipboard = OS.clipboard 
	OS.clipboard = ""
		
	if explain_function and method_config.has_section_key(method_name, "explanation"):
		OS.clipboard = method_config.get_value(method_name, "explanation") + "\n" 
		
	var use_type_hints = INTERFACE.get_editor_settings().get_setting("text_editor/completion/add_type_hints")
	OS.clipboard +=  method_config.get_value(method_name, "with_type_hint") if use_type_hints else method_config.get_value(method_name, "without_type_hint")
		
	if at_end_of_file:
		var line_count = EDITOR.get_current_script().source_code.count("\n")
		EDITOR.goto_line(line_count)
		OS.clipboard = "\n\n" + OS.clipboard
		
	call_deferred("_paste_helper_method", old_clipboard)


func _paste_helper_method(old_clipboard : String) -> void:
	var paste_key_combo = InputEventKey.new()
	if OS.get_name() == "OSX":
		paste_key_combo.command = true
	else:
		paste_key_combo.control = true
	paste_key_combo.scancode = KEY_V
	paste_key_combo.pressed = true
	Input.parse_input_event(paste_key_combo)
		
	OS.clipboard = old_clipboard
