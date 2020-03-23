tool
extends WindowDialog


onready var filter = $MarginContainer/Content/VBoxContainer/SearchFilter/MarginContainer/Filter
onready var item_list = $MarginContainer/Content/VBoxContainer/MarginContainer/HSplitContainer/ItemList
onready var copy_path_button = $MarginContainer/Content/VBoxContainer/SearchFilter/CopyButton
onready var info_box = $MarginContainer/Content/VBoxContainer/MarginContainer/HSplitContainer/RightInfoBox
onready var current_label = $MarginContainer/Content/VBoxContainer/HSplitContainer/CurrentLabel # meta data "Path" saves file path
onready var last_label = $MarginContainer/Content/VBoxContainer/HSplitContainer/LastLabel

# after making changes in the inspector, reopen the project to apply the changes
export (String) var custom_keyboard_shortcut # go to "Editor > Editor Settings... > Shortcuts > Bindings" to see how a keyboard_shortcut looks as a String 
export (Vector2) var custom_popup_size
export (String) var keyword_goto_line = ": " # go to line
export (String) var keyword_goto_method = ":m " # go to method m 
export (String) var keyword_signals = "sig " # short for signals
export (String) var keyword_snippets = "_ " # _: like Godot's style guide for virtual/private methods
export (String) var keyword_all_scenes_and_scripts = "a " # "a" for A(ll) scenes and scripts
export (String) var keyword_all_scenes = "as " # "as" for A(ll) S(cenes)
export (String) var keyword_all_scripts = "ac " # "ac" for A(ll) C(ode) files 
export (String) var keyword_all_open_scenes = "s " # "s " for all open S(cenes)
export (String) var keyword_all_open_scenes_and_scripts = "cs " # "cs " for all open C(ode) and S(cene) files
export (String) var keyword_add_script = "+"
export (String) var keyword_editor_settings = "sett "
export (Color) var secondary_color = Color(1, 1, 1, .3) # color for 3rd column in ItemList (file paths, additional_info...)
export (String) var snippet_marker_pos = "@"
export (bool) var adapt_popup_height = true
export (bool) var show_full_path_in_recent_files = false

var keyboard_shortcut = "Command+P" if OS.get_name() == "OSX" else "Control+P" 
var max_popup_size = Vector2(clamp(1000 * OS.get_screen_dpi() / 100, 0, OS.get_screen_size().x / 1.5), \
		clamp(OS.get_screen_size().y / 2 + 100 * OS.get_screen_dpi() / 100, 0, OS.get_screen_size().y - 200))
var current_main_screen : String = ""
var editor_settings : Dictionary # holds the paths to the settings
var project_settings : Dictionary # holds the paths to the settings
var scenes : Dictionary # holds all scenes; [file_path] = file_name, icon
var scripts : Dictionary # holds all scripts; [file_path] = file_name, icon, resource
var other_files : Dictionary # holds all other files; [file] = file_name, icon
var files_are_updating : bool = false
var recent_files_are_updating : bool  = false
var types : Array = ["-", "bool", "int", "float", "String", "Vector2", "Rect2", "Vector3", "Transform2D", "Plane", "Quat", "AABB", "Basis", \
		"Transform", "Color", "NodePath", "RID", "Object", "Dictionary", "Array", "PoolByteArray", "PoolIntArray", "PoolRealArray", \
		"PoolStringArray", "PoolVector2Array", "PoolVector3Array", "PoolColorArray", "Variant"] # type hints for vars when using the signals keyword
enum FILTER {ALL_SCENES_AND_SCRIPTS, ALL_SCENES, ALL_SCRIPTS, ALL_OPEN_SCENES_SCRIPTS, ALL_OPEN_SCENES, ALL_OPEN_SCRIPTS, \
		SIGNALS, SNIPPETS, METHODS, ADD_SCRIPT, SETTINGS}
var current_filter : int
var code_snippets : ConfigFile = ConfigFile.new()
var script_added_to : Node # the node a script, which is created with this plugin, will be added to
var submenu : Popup

var PLUGIN : EditorPlugin
var INTERFACE : EditorInterface
var EDITOR : ScriptEditor
var FILE_SYSTEM : EditorFileSystem
var SCRIPT_CREATE_DIALOG : ScriptCreateDialog
var EDITOR_SETTINGS : EditorSettings

# TODO quick set node properties
# TODO regex
# TODO move code snippets/and signals into their own plugin
# TODO refactor this mess

func _ready() -> void: 
	connect("popup_hide", self, "_on_popup_hide")
	filter.connect("text_changed", self, "_on_filter_text_changed")
	filter.connect("text_entered", self, "_on_filter_text_entered")
	item_list.connect("item_activated", self, "_on_item_list_activated")
	item_list.connect("item_selected", self, "_on_item_list_selected")
	copy_path_button.connect("pressed", self, "_on_copy_button_pressed")
	FILE_SYSTEM.connect("filesystem_changed", self, "_on_filesystem_changed")
	PLUGIN.connect("main_screen_changed", self, "_on_main_screen_changed")
	SCRIPT_CREATE_DIALOG.connect("script_created", self, "_on_script_created")
		
	current_label.add_stylebox_override("normal", INTERFACE.get_base_control().get_stylebox("normal", "LineEdit"))
	last_label.add_stylebox_override("normal", INTERFACE.get_base_control().get_stylebox("normal", "LineEdit"))
	last_label.add_color_override("font_color", secondary_color)
	filter.right_icon = INTERFACE.get_base_control().get_icon("Search", "EditorIcons")
		
	keyboard_shortcut = custom_keyboard_shortcut if custom_keyboard_shortcut else keyboard_shortcut
	max_popup_size = custom_popup_size if custom_popup_size else max_popup_size
		
	submenu = load("res://addons/CommandPalettePopup/SubmenuSettingsSetter.tscn").instance()
	add_child(submenu)
		
	yield(get_tree().create_timer(0.2), "timeout")
	EDITOR.connect("editor_script_changed", self, "_on_editor_script_changed")
	PLUGIN.connect("scene_changed", self, "_on_scene_changed")
		
	_update_editor_settings()
	_update_project_settings()


func _unhandled_key_input(event: InputEventKey) -> void:
	if event.as_text() == keyboard_shortcut and event.pressed and visible and not filter.text and filter.has_focus():
		if last_label.has_meta("Path"): 
			if current_main_screen in ["2D", "3D", "Script"]:
				_open_scene(last_label.get_meta("Path")) if scenes.has(last_label.get_meta("Path")) \
						else _open_script(scripts[last_label.get_meta("Path")].ScriptResource)
			else:
				_open_scene(current_label.get_meta("Path")) if scenes.has(current_label.get_meta("Path")) \
						else _open_script(scripts[current_label.get_meta("Path")].ScriptResource)
		hide()
		
	elif event.as_text() == keyboard_shortcut and event.pressed:
		var error = code_snippets.load("res://addons/CommandPalettePopup/CodeSnippets.cfg")
		if error != OK:
			push_warning("Command Palette Plugin: Error loading the code_snippets. Error code: %s." % error)
			
		rect_size = max_popup_size
		popup_centered()
		_update_popup_list(true)


func _on_scene_changed(new_root : Node):
	_update_recent_files()


func _on_editor_script_changed(new_script : Script):
	_update_recent_files()


func _on_main_screen_changed(new_screen : String) -> void:
	current_main_screen = new_screen
	_update_recent_files()


func _on_script_created(script : Script) -> void:
	if script_added_to:
		script_added_to.set_script(script)
		if script_added_to.filename:
			script.set_meta("Scene_Path", script_added_to.filename)
		INTERFACE.select_file(script.resource_path)
		_open_script(script)


func _update_recent_files():
	if not recent_files_are_updating and current_main_screen in ["2D", "3D", "Script"]:
		recent_files_are_updating = true
			
		yield(get_tree().create_timer(.2), "timeout")
		var path : String
		if current_main_screen == "Script":
			path = EDITOR.get_current_script().resource_path
		elif current_main_screen in ["2D", "3D"]:
			path = INTERFACE.get_edited_scene_root().filename
		if current_label.has_meta("Path"):
			last_label.text = current_label.text
			last_label.set_meta("Path", current_label.get_meta("Path"))
		else:
			last_label.text = ""
		current_label.text = path if show_full_path_in_recent_files else path.get_file()
		current_label.set_meta("Path", path)
			
		recent_files_are_updating = false


func _on_filesystem_changed() -> void:
	# to prevent unnecessarily updating cause the signal gets fired multiple times
	if not files_are_updating:
		files_are_updating = true
		_update_files_dictionary(FILE_SYSTEM.get_filesystem(), true)
		yield(get_tree().create_timer(0.2), "timeout")
		files_are_updating = false


func _on_copy_button_pressed() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		if current_filter == FILTER.SNIPPETS: 
			var use_type_hints = INTERFACE.get_editor_settings().get_setting("text_editor/completion/add_type_hints")
			var snippet_name = item_list.get_item_text(selection[0]).strip_edges()
			var snippet : String = code_snippets.get_value(snippet_name, "body")
			if use_type_hints and code_snippets.has_section_key(snippet_name, "type_hint"):
				snippet += code_snippets.get_value(snippet_name, "type_hint")
			elif not use_type_hints and code_snippets.has_section_key(snippet_name, "no_type_hint"):
				snippet += code_snippets.get_value(snippet_name, "no_type_hint")
			var marker_pos = snippet.find(snippet_marker_pos)
			if marker_pos != -1:
				snippet.erase(marker_pos, snippet_marker_pos.length()) 
			OS.clipboard = snippet
			
		elif current_filter == FILTER.SETTINGS:
			OS.clipboard =  "\"" + item_list.get_item_text(selection[0]) + "\""
			
		# selection is a file name
		elif selection[0] % item_list.max_columns == 1 and _current_filter_displays_files(): 
			var path = _format_string(item_list.get_item_text(selection[0] + 1), true) + "/" + item_list.get_item_text(selection[0]).strip_edges()
			OS.clipboard = "\"" + path + "\""
	hide()


func _on_popup_hide() -> void:
	filter.clear()


func _on_item_list_selected(index : int) -> void:
	if index % item_list.max_columns == 1 and current_filter == FILTER.SNIPPETS:
		_build_snippet_description(item_list.get_item_text(index).strip_edges())
		
	# selection is a file path
	elif index % item_list.max_columns == 2 and _current_filter_displays_files(): 
		INTERFACE.select_file(_format_string(item_list.get_item_text(index), true) + "/" + item_list.get_item_text(index - 1).strip_edges())


func _on_item_list_activated(index : int) -> void:
	_activate_item(index)


func _on_filter_text_changed(new_txt : String) -> void:
	# autocompletion on settings; double spaces because one space for jumping in item_list
	if filter.text.begins_with(keyword_editor_settings) and filter.text.ends_with("  ") and filter.text.length() > keyword_editor_settings.length() + 1:
		var search_string = filter.text.substr(keyword_editor_settings.length()).strip_edges()
		var selection = item_list.get_selected_items()
		if selection:
			var sel_text = item_list.get_item_text(selection[0])
			var pos = sel_text.findn(search_string)
			var end_pos = sel_text.findn("/", pos + filter.text.length() - keyword_editor_settings.length()) + 1
			filter.text = keyword_editor_settings + sel_text.substr(0, end_pos if end_pos else -1)
			filter.caret_position = filter.text.length()
		
	rect_size = max_popup_size
	_update_popup_list()


func _on_filter_text_entered(new_txt : String) -> void: 
	var selection = item_list.get_selected_items()
	if selection:
		_activate_item(selection[0])
	else:
		_activate_item()


func _activate_item(selected_index : int = -1) -> void:
	if filter.text.begins_with(keyword_goto_line): 
		var number = filter.text.substr(keyword_goto_line.length()).strip_edges()
		if number.is_valid_integer():
			var max_lines = EDITOR.get_current_script().source_code.count("\n")
			EDITOR.goto_line(clamp(number as int - 1, 0, max_lines))
			selected_index = -1
		
	if selected_index == -1 or item_list.is_item_disabled(selected_index):
		hide()
		return
		
	var selected_name = item_list.get_item_text(selected_index).strip_edges()
		
	if current_filter == FILTER.SNIPPETS: 
		_paste_code_snippet(selected_name)
		
	elif current_filter == FILTER.SETTINGS:
		if item_list.get_item_text(selected_index - 1).begins_with("Project"):
			submenu._show(project_settings[item_list.get_item_text(selected_index)], "Project_Settings", ProjectSettings)
		else:
			submenu._show(editor_settings[item_list.get_item_text(selected_index)], "Editor_Settings", EDITOR_SETTINGS)
		return
		
	elif current_filter == FILTER.METHODS:
		var line = item_list.get_item_text(selected_index + 1).split(":")[1].strip_edges()
		EDITOR.goto_line(line as int - 1)
		
	# create script and attach it to a node in the current scene
	elif current_filter == FILTER.ADD_SCRIPT:
		var sel = INTERFACE.get_selection()
		sel.clear()
		var root = INTERFACE.get_edited_scene_root()
		script_added_to = root.find_node(selected_name.strip_edges()) 
		if not script_added_to:
			script_added_to = root
		sel.add_node(script_added_to)
		var file_path = INTERFACE.get_edited_scene_root().filename.get_base_dir() 
		SCRIPT_CREATE_DIALOG.config(script_added_to.get_class(), (file_path if file_path else "res:/") + "/" + selected_name + ".gd")
		SCRIPT_CREATE_DIALOG.popup_centered()
		
	# signals for current scene root
	elif current_filter == FILTER.SIGNALS:
		_paste_signal(selected_name)
		
	# files
	else:
		var path = _format_string(item_list.get_item_text(selected_index + 1), true) + "/" + item_list.get_item_text(selected_index).strip_edges()
		_open_selection(path) 
		
	hide()


func _open_selection(path : String) -> void:
	if scripts.has(path): 
		_open_script(scripts[path].ScriptResource)
	elif scenes.has(path): 
		_open_scene(path)
	else:
		_open_other_file(path)


func _open_script(script : Script) -> void:
	INTERFACE.edit_resource(script)
		
	if script.has_meta("Scene_Path"):
		INTERFACE.open_scene_from_path(script.get_meta("Scene_Path"))
		var selection = INTERFACE.get_selection()
		selection.clear()
		selection.add_node(INTERFACE.get_edited_scene_root()) # to see the "Node" dock in Script view
		yield(get_tree(), "idle_frame")
		yield(get_tree(), "idle_frame")
		
	INTERFACE.call_deferred("set_main_screen_editor", "Script")


func _open_scene(path : String) -> void:
	INTERFACE.open_scene_from_path(path)
		
	var selection = INTERFACE.get_selection()
	selection.clear()
	selection.add_node(INTERFACE.get_edited_scene_root())
	INTERFACE.call_deferred("set_main_screen_editor", "3D") if INTERFACE.get_edited_scene_root() is Spatial \
			else INTERFACE.call_deferred("set_main_screen_editor", "2D")


func _open_other_file(path : String) -> void:
	INTERFACE.select_file(path)
	INTERFACE.edit_resource(load(path))


func _update_files_dictionary(folder : EditorFileSystemDirectory, reset : bool = false) -> void:
	if reset:
		scenes.clear()
		scripts.clear()
		other_files.clear()
		
	var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
	for file in folder.get_file_count():
		var file_path = folder.get_file_path(file)
		var file_type = FILE_SYSTEM.get_file_type(file_path)
		var file_name = folder.get_file(file)
		
		if file_type.findn("Script") != -1:
			scripts[file_path] = {"File_Name" : file_name, "Icon" : script_icon, "ScriptResource" : load(file_path)}
			
		elif file_type.findn("Scene") != -1: 
			scenes[file_path] = {"File_Name" : file_name, "Icon" : null}
		
			var scene = load(file_path).instance()
			scenes[file_path].Icon = INTERFACE.get_base_control().get_icon(scene.get_class(), "EditorIcons")
			var attached_script = scene.get_script()
			if attached_script:
				attached_script.set_meta("Scene_Path", file_path)
			scene.free()
			
		else:
			other_files[file_path] = {"File_Name": file_name, "Icon" : INTERFACE.get_base_control().get_icon(file_type, "EditorIcons")}
		
	for subdir in folder.get_subdir_count():
		_update_files_dictionary(folder.get_subdir(subdir))


func _update_popup_list(just_popupped : bool = false) -> void:
	if just_popupped:
		filter.grab_focus()
		script_added_to = null
	copy_path_button.disabled = true
	item_list.clear()
	item_list.visible = true
	info_box.visible = false
	var search_string : String = filter.text 
		
	# typing " X" at the end of the search_string jumps to the X-th item in the list
	var quickselect_line = 0
	var qs_starts_at = search_string.strip_edges().find_last(" ")
	if qs_starts_at != -1 and not search_string.begins_with(keyword_goto_line):
		quickselect_line = search_string.substr(qs_starts_at + 1)
		if quickselect_line.strip_edges().is_valid_integer():
			search_string.erase(qs_starts_at + 1, quickselect_line.length())
			quickselect_line = quickselect_line.strip_edges()
		
	# help page
	if search_string == "?":
		_build_help_page()
		return
		
	# go to line
	elif search_string.begins_with(keyword_goto_line): 
		if not current_main_screen == "Script":
			item_list.add_item("Go to \"Script\" view to goto_line.", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item("", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item("", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		else:
			var text_editor = _get_current_text_editor() 
			var number = search_string.substr(keyword_goto_line.length()).strip_edges()
			item_list.add_item("Go to line: %s of " % (clamp(number as int, 1, text_editor.get_line_count()) if number.is_valid_integer() \
					else "Enter valid number") + String(text_editor.get_line_count()), null, false)
			if search_string.ends_with(" ") and number.is_valid_integer():
				EDITOR.goto_line(clamp(number as int - 1, 0, text_editor.get_line_count()))
			_adapt_list_height()
			return
		
	# add script to node
	elif search_string.begins_with(keyword_add_script):
		current_filter = FILTER.ADD_SCRIPT
		_build_node_list(INTERFACE.get_edited_scene_root(), search_string.substr(keyword_add_script.length()).strip_edges())
		_count_node_list()
		
	# edit editor settings
	elif search_string.begins_with(keyword_editor_settings):
		current_filter = FILTER.SETTINGS
		_build_item_list(search_string.substr(keyword_editor_settings.length()).strip_edges())
		
	# methods of the current script
	elif search_string.begins_with(keyword_goto_method):
		if not current_main_screen == "Script":
			item_list.add_item("Go to \"Script\" view to goto_method.", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item("", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item("", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		else:
			current_filter = FILTER.METHODS
			_build_item_list(search_string.substr(keyword_goto_method.length()).strip_edges())
		
	# show signals of the current scene root
	elif search_string.begins_with(keyword_signals):
		if not current_main_screen == "Script":
			item_list.add_item("Go to \"Script\" view to see the available signals.", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item("", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item("", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		else:
			current_filter = FILTER.SIGNALS
			_build_item_list(search_string.substr(keyword_signals.length()).strip_edges())
		
	# show code snippets
	elif search_string.begins_with(keyword_snippets): 
		if not current_main_screen == "Script":
			item_list.add_item("Go to \"Script\" view to see the available snippets.", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item("", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item("", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		else:
			current_filter = FILTER.SNIPPETS
			_build_item_list(search_string.substr(keyword_snippets.length()).strip_edges())
		
	# show all scripts and scenes
	elif search_string.begins_with(keyword_all_scenes_and_scripts): 
		current_filter = FILTER.ALL_SCENES_AND_SCRIPTS
		_build_item_list(search_string.substr(keyword_all_scenes_and_scripts.length()).strip_edges())
		
	# show all scripts
	elif search_string.begins_with(keyword_all_scripts): 
		current_filter = FILTER.ALL_SCRIPTS
		_build_item_list(search_string.substr(keyword_all_scripts.length()).strip_edges())
		
	# show all scenes
	elif search_string.begins_with(keyword_all_scenes):
		current_filter = FILTER.ALL_SCENES
		_build_item_list(search_string.substr(keyword_all_scenes.length()).strip_edges())
		
	# show open scenes and scripts
	elif search_string.begins_with(keyword_all_open_scenes_and_scripts):
		current_filter = FILTER.ALL_OPEN_SCENES_SCRIPTS
		_build_item_list(search_string.substr(keyword_all_open_scenes_and_scripts.length()).strip_edges())
		
	# show open scenes
	elif search_string.begins_with(keyword_all_open_scenes): 
		current_filter = FILTER.ALL_OPEN_SCENES
		_build_item_list(search_string.substr(keyword_all_open_scenes.length()).strip_edges())
		
	# show all open scripts
	else: 
		current_filter = FILTER.ALL_OPEN_SCRIPTS
		_build_item_list(search_string.strip_edges())
		
	quickselect_line = clamp(quickselect_line as int, 0, item_list.get_item_count() / item_list.max_columns - 1)
	if item_list.get_item_count() > 0:
		item_list.select(quickselect_line * item_list.max_columns + (2 if filter.text.begins_with(keyword_add_script) or current_filter == FILTER.SETTINGS else 1))
		item_list.ensure_current_is_visible()
		if filter.text.begins_with(keyword_snippets) and current_main_screen == "Script": 
			_build_snippet_description(item_list.get_item_text(item_list.get_selected_items()[0]).strip_edges())
		
	if not filter.text.begins_with(keyword_snippets) or current_main_screen != "Script":
		_adapt_list_height()


func _build_item_list(search_string : String) -> void:
	copy_path_button.disabled = false
	var list : Array # array of file paths
	match current_filter:
		FILTER.ALL_SCENES_AND_SCRIPTS:
			for path in scenes:
				if search_string and not scenes[path].File_Name.findn(search_string) != -1:
					continue
				list.push_back(path)
					
			for path in scripts:
				if search_string and not scripts[path].File_Name.findn(search_string) != -1:
					continue
				list.push_back(path)
				
			for path in other_files:
				if search_string and not other_files[path].File_Name.findn(search_string) != -1:
					continue
				list.push_back(path)
			
		FILTER.ALL_SCRIPTS:
			for path in scripts:
				if search_string and not scripts[path].File_Name.findn(search_string) != -1:
					continue
				list.push_back(path)
			
		FILTER.ALL_SCENES:
			for path in scenes:
				if search_string and not scenes[path].File_Name.findn(search_string) != -1:
					continue
				list.push_back(path)
			
		FILTER.ALL_OPEN_SCENES:
			var open_scenes = INTERFACE.get_open_scenes()
			for path in open_scenes:
				var scene_name = path.get_file()
				if search_string and not scene_name.findn(search_string) != -1:
					continue
				list.push_back(path)
			
		FILTER.ALL_OPEN_SCRIPTS:
			var open_scripts = EDITOR.get_open_scripts()
			for script in open_scripts:
				var script_name = script.resource_path.get_file()
				if search_string and not script_name.findn(search_string) != -1:
					continue
				list.push_back(script.resource_path)
			
		FILTER.ALL_OPEN_SCENES_SCRIPTS:
			var open_scenes = INTERFACE.get_open_scenes()
			for path in open_scenes:
				var scene_name = path.get_file()
				if search_string and not scene_name.findn(search_string) != -1:
					continue
				list.push_back(path)
				
			var open_scripts = EDITOR.get_open_scripts()
			for script in open_scripts:
				var script_name = script.resource_path.get_file()
				if search_string and not script_name.findn(search_string) != -1:
					continue
				list.push_back(script.resource_path)
			
		FILTER.SNIPPETS:
			var counter = 0
			for method_name in code_snippets.get_sections():
				if search_string and not method_name.findn(search_string) != -1:
					continue
				item_list.add_item(" " + String(counter) + "  :: ", null, false)
				item_list.add_item(" " + method_name)
				item_list.add_item(code_snippets.get_value(method_name, "additional_info"), null, false) \
						if code_snippets.has_section_key(method_name, "additional_info") else item_list.add_item("")
				item_list.set_item_custom_fg_color(item_list.get_item_count() - 1, secondary_color)
				counter += 1
			return
			
		FILTER.SIGNALS:
			copy_path_button.disabled = true
			var scene = load(EDITOR.get_current_script().get_meta("Scene_Path")).instance()
			var counter = 0
			for signals in scene.get_signal_list():
				if search_string and not signals.name.findn(search_string) != -1:
					continue
				item_list.add_item(" " + String(counter) + "  :: ", null, false)
				item_list.add_item(signals.name)
				if signals.args:
					item_list.add_item("(") 
					var current_item = item_list.get_item_count() - 1
					for arg_index in signals.args.size():
							item_list.set_item_text(current_item, item_list.get_item_text(current_item) + signals.args[arg_index].name + " : " \
							+ (signals.args[arg_index].get("class_name") if signals.args[arg_index].get("class_name") else types[signals.args[arg_index].type]) \
							+ (", " if arg_index < signals.args.size() - 1 else ""))
					item_list.set_item_text(current_item, item_list.get_item_text(current_item) + ")") 
					item_list.set_item_disabled(current_item, true)
				else:
					item_list.add_item("", null, false)
					item_list.set_item_disabled(item_list.get_item_count() - 1, true)
				counter += 1
			scene.free()
			return
			
		FILTER.METHODS:
			copy_path_button.disabled = true
			var current_script = EDITOR.get_current_script()
			var method_dict : Dictionary # maps methods to their line position
			for method in current_script.get_script_method_list():
				if method.name != "_init": # _init always appears
					if search_string and not method.name.findn(search_string) != -1:
						continue
					var pos = current_script.source_code.findn("func " + method.name)
					var line = current_script.source_code.count("\n", 0, pos)
					method_dict[line] = method.name
			var lines = method_dict.keys() # get_script_method_list() doesnt give the list in order of appearance in the script
			lines.sort()
				
			var counter = 0
			for line_number in lines:
				item_list.add_item(" " + String(counter) + "  :: ", null, false)
				item_list.add_item(method_dict[line_number])
				item_list.add_item(" : " + String(line_number + 1), null, false)
				item_list.set_item_disabled(item_list.get_item_count() - 1, true)
				counter += 1
			return
			
		FILTER.SETTINGS:
			for setting in editor_settings:
				if search_string and not setting.findn(search_string) != -1:
					continue
				list.push_back(setting)
				
			for setting in project_settings:
				if search_string and not setting.findn(search_string) != -1:
					continue
				list.push_back(setting)
		
	_quick_sort_by_file_name(list, 0, list.size() - 1) if _current_filter_displays_files() else list.sort()
	for index in list.size():
		var file_name = list[index].get_file()
		item_list.add_item(" " + String(index) + "  :: ", null, false)
			
		if current_filter == FILTER.SETTINGS:
			item_list.add_item("Editor :: " if editor_settings.has(list[index]) else "Project :: ", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			
		item_list.add_item(file_name if _current_filter_displays_files() else list[index])
		if scenes.has(list[index]):
			item_list.set_item_icon(item_list.get_item_count() - 1, scenes[list[index]].Icon)
		elif scripts.has(list[index]):
			item_list.set_item_icon(item_list.get_item_count() - 1,  scripts[list[index]].Icon)
		elif other_files.has(list[index]):
			item_list.set_item_icon(item_list.get_item_count() - 1, other_files[list[index]].Icon)
		
		if current_filter != FILTER.SETTINGS:
			if _current_filter_displays_files():
				item_list.add_item(_format_string(list[index].get_base_dir()))
			else:
				item_list.add_item("", null, false)
				item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.set_item_custom_fg_color(item_list.get_item_count() - 1, secondary_color)


func _build_node_list(root : Node, search_string : String):
	if not search_string or root.name.findn(search_string) != -1:
		item_list.add_item("", null, false)
		if root == INTERFACE.get_edited_scene_root():
			item_list.add_item(".", null, false)
		elif root.get_parent() == INTERFACE.get_edited_scene_root():
			item_list.add_item("./", null, false)
		else:
			item_list.add_item("./" + String(INTERFACE.get_edited_scene_root().get_path_to(root.get_parent())) + "/", null, false)
		item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		item_list.add_item(root.name)
		
	for child in root.get_children():
		_build_node_list(child, search_string)


func _count_node_list():
	for i in item_list.get_item_count() / 3:
		item_list.set_item_text(i * item_list.max_columns," " + String(i) + "  :: ")


func _build_snippet_description(snippet_name : String) -> void:
	info_box.bbcode_text = "[u]Body:[/u]\n"
	info_box.bbcode_text += code_snippets.get_value(snippet_name, "body") + "\n\n"
	if code_snippets.has_section_key(snippet_name, "type_hint"):
		info_box.bbcode_text += "[u]Body with type hint:[/u]\n"
		info_box.bbcode_text += code_snippets.get_value(snippet_name, "body") + code_snippets.get_value(snippet_name, "type_hint") + "\n\n" 
	if code_snippets.has_section_key(snippet_name, "no_type_hint"):
		info_box.bbcode_text += "[u]Body without type hint:[/u]\n"
		info_box.bbcode_text += code_snippets.get_value(snippet_name, "body") + code_snippets.get_value(snippet_name, "no_type_hint") + "\n\n" 
	if code_snippets.has_section_key(snippet_name, "description"):
		info_box.bbcode_text += "[u]\nDescription:[/u]\n\n"
		info_box.bbcode_text += code_snippets.get_value(snippet_name, "description")
	info_box.visible = true


func _build_help_page() -> void:
	var file = File.new()
	file.open("res://addons/CommandPalettePopup/Help.txt", File.READ)
	info_box.bbcode_text = file.get_as_text() % [keyword_all_open_scenes, keyword_all_scenes_and_scripts, keyword_all_scripts, \
			keyword_all_scenes, keyword_all_open_scenes_and_scripts, keyword_goto_line, keyword_goto_method, keyword_signals, \
			keyword_snippets, snippet_marker_pos]
	file.close()
	info_box.visible = true
	item_list.visible = false


func _paste_signal(signal_name : String) -> void:
	var text_editor = _get_current_text_editor()
	var node_name = EDITOR.get_current_script().resource_path.get_file().get_basename()
	var snippet = "connect(\"%s\", , \"_on_%s_%s\")" % [signal_name, node_name, signal_name]
	text_editor.insert_text_at_cursor(snippet)
	var new_column = text_editor.cursor_get_column() - signal_name.length() - node_name.length() - 10 # 10 = , "_on_")
	text_editor.cursor_set_column(new_column)
	OS.clipboard = "func _on_%s_%s():\n\tpass" % [node_name, signal_name]


func _paste_code_snippet(snippet_name : String) -> void:
	var text_editor : TextEdit = _get_current_text_editor()
	var use_type_hints = INTERFACE.get_editor_settings().get_setting("text_editor/completion/add_type_hints")
	var snippet : String = code_snippets.get_value(snippet_name, "body") 
	if use_type_hints and code_snippets.has_section_key(snippet_name, "type_hint"):
		snippet += code_snippets.get_value(snippet_name, "type_hint")
	elif not use_type_hints and code_snippets.has_section_key(snippet_name, "no_type_hint"):
		snippet += code_snippets.get_value(snippet_name, "no_type_hint")
		
	var goto_pos = snippet.findn(snippet_marker_pos)
	if goto_pos != -1:
		snippet.erase(goto_pos, snippet_marker_pos.length())
		_goto_snippet_marker(snippet, goto_pos, text_editor)
		
	text_editor.call_deferred("insert_text_at_cursor", snippet)


func _goto_snippet_marker(snippet : String, goto_pos: int, text_editor : TextEdit) -> void:
	var old_line = text_editor.cursor_get_line()
	var new_line = old_line + snippet.count("\n", 0, goto_pos)
	var new_columm = snippet.rfind("\n", goto_pos)
	new_columm = goto_pos - new_columm - 1 if new_columm != -1 else goto_pos
	new_columm += text_editor.get_line(new_line).length() if not snippet.count("\n", 0, goto_pos) else 0 # respect previous columns
	EDITOR.call_deferred("goto_line", new_line)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	text_editor.call_deferred("cursor_set_column", new_columm)


func _adapt_list_height() -> void:
	if adapt_popup_height:
		var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
		var row_height = script_icon.get_size().y + (8 * (OS.get_screen_dpi() / 100))
		var rows = max(item_list.get_item_count() / item_list.max_columns, 1) + 1
		var margin = filter.rect_size.y + $MarginContainer.margin_top + abs($MarginContainer.margin_bottom) \
				+ $MarginContainer/Content/VBoxContainer/MarginContainer.get("custom_constants/margin_top") \
				+ $MarginContainer/Content/VBoxContainer/MarginContainer.get("custom_constants/margin_bottom") \
				+ max(current_label.rect_size.y, last_label.rect_size.y)
		var height = row_height * rows + margin
		rect_size.y = clamp(height, 0, max_popup_size.y)


func _get_current_text_editor() -> TextEdit:
	var script_index = 0
	for script in EDITOR.get_open_scripts():
		if script == EDITOR.get_current_script():
			break
		script_index += 1
	return EDITOR.get_child(0).get_child(1).get_child(1).get_child(script_index).get_child(0).get_child(0).get_child(0) as TextEdit # :(


func _format_string(path : String, reversed : bool = false) -> String:
	# formatted path example: " - res:// - addons - plugin.gd"
	if reversed:
		return "res://" + path.substr(12).replace(" - ", "/") 
	else:
		var path_without_res = path.substr(6)
		return " - res:// - " + path_without_res.replace("/", " - ")


func _quick_sort_by_file_name(array : Array, lo : int, hi : int) -> void:
	if lo < hi:
		var p = _partition(array, lo, hi)
		_quick_sort_by_file_name(array, lo, p)
		_quick_sort_by_file_name(array, p + 1, hi)


func _partition(array : Array, lo : int, hi : int):
	var pivot = array[(hi + lo) / 2].get_file()
	var i = lo - 1
	var j = hi + 1
	while true:
		while true:
			i += 1
			if array[i].get_file().nocasecmp_to(pivot) in [1, 0]:
				break
		while true:
			j -= 1
			if array[j].get_file().nocasecmp_to(pivot) in [-1, 0]:
				break
		if i >= j:
			return j
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp


func _current_filter_displays_files() -> bool:
	return not current_filter in [FILTER.SNIPPETS, FILTER.METHODS, FILTER.SIGNALS, FILTER.ADD_SCRIPT, FILTER.SETTINGS] \
			and not filter.text.begins_with(keyword_goto_line)


func _update_editor_settings() -> void:
	for setting in INTERFACE.get_editor_settings().get_property_list():
		if setting.name:
			# general settings only
			if setting.name.begins_with("interface/") or setting.name.begins_with("filesystem/") or setting.name.begins_with("docks/")\
					or setting.name.begins_with("text_editor/") or setting.name.begins_with("editors/") or setting.name.begins_with("run/")\
					or setting.name.begins_with("network/") or setting.name.begins_with("project_manager/") or setting.name.begins_with("asset_library/")\
					or setting.name.begins_with("export/") or setting.name.begins_with("debugger/"):
				editor_settings[setting.name] = setting


func _update_project_settings() -> void:
	for setting in ProjectSettings.get_property_list():
		if setting.name:
			# general settings only
			if setting.name.begins_with("application/") or setting.name.begins_with("debug/") \
					or setting.name.begins_with("compression/") or setting.name.begins_with("network/") \
					or setting.name.begins_with("memory/") or setting.name.begins_with("logging/") \
					or setting.name.begins_with("rendering/") or setting.name.begins_with("display/") \
					or setting.name.begins_with("physics/") or setting.name.begins_with("input_devices/") \
					or setting.name.begins_with("gui/") or setting.name.begins_with("layer_names/") or setting.name.begins_with("filesystem/") \
					or setting.name.begins_with("locale/") or setting.name.begins_with("editor_plugins/") or setting.name.begins_with("node/") \
					or setting.name.begins_with("audio/") or setting.name.begins_with("editor/") or setting.name.begins_with("android/") :
				project_settings[setting.name] = setting
