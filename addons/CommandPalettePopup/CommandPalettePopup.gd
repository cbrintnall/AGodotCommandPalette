tool
extends WindowDialog


onready var settings_setter : WindowDialog = $SettingsSetter
onready var settings_adder : WindowDialog = $SettingsAdder
onready var filter = $PaletteMarginContainer/VBoxContainer/SearchFilter/MarginContainer/Filter
onready var item_list = $PaletteMarginContainer/VBoxContainer/MarginContainer/TabContainer/ItemList
onready var info_box = $PaletteMarginContainer/VBoxContainer/MarginContainer/TabContainer/RightInfoBox
onready var tabs = $PaletteMarginContainer/VBoxContainer/MarginContainer/TabContainer
enum TABS {ITEM_LIST, INFO_BOX}
onready var copy_button = $PaletteMarginContainer/VBoxContainer/SearchFilter/CopyButton
onready var current_label = $PaletteMarginContainer/VBoxContainer/HSplitContainer/CurrentLabel # meta data "Path" saves file path
onready var last_label = $PaletteMarginContainer/VBoxContainer/HSplitContainer/LastLabel
onready var add_button = $PaletteMarginContainer/VBoxContainer/SearchFilter/AddButton
onready var switch_button = $PaletteMarginContainer/VBoxContainer/HSplitContainer/SwitchIcon
	
# after making changes in the inspector, reopen the project to apply the changes
export (String) var custom_keyboard_shortcut # go to "Editor > Editor Settings... > Shortcuts > Bindings" to see how a keyboard_shortcut looks as a String
export (Vector2) var custom_popup_size
export (String) var keyword_goto_line = ": " # go to line
export (String) var keyword_goto_method = ":m " # go to method m
export (String) var keyword_all_files = "a " # "a" for A(ll) files
export (String) var keyword_all_scenes = "as " # "as" for A(ll) S(cenes)
export (String) var keyword_all_scripts = "ac " # "ac" for A(ll) C(ode) files
export (String) var keyword_all_open_scenes = "s " # "s " for all open S(cenes)
export (String) var keyword_select_node = "n "
export (String) var keyword_editor_settings = "set "
export (Color) var secondary_color = Color(1, 1, 1, .3) # color for 3rd column in ItemList (file paths, additional_info...)
export (bool) var adapt_popup_height = true
export (bool) var show_full_path_in_recent_files = false
export (bool) var keep_main_screen_when_selecting_node = true
	
var keywords = [keyword_goto_line, keyword_goto_method, keyword_all_files, keyword_all_scenes, keyword_all_scripts, keyword_all_open_scenes, keyword_select_node, keyword_editor_settings]
var screen_factor = max(OS.get_screen_dpi() / 100, 1)
var keyboard_shortcut = "Command+P" if OS.get_name() == "OSX" else "Control+P"
var max_popup_size = Vector2(clamp(1500 * screen_factor, 0, OS.get_screen_size().x * 0.75), \
		clamp(OS.get_screen_size().y / 2 + 200 * screen_factor, 0, OS.get_screen_size().y * 0.75))
var current_main_screen : String = ""
var editor_settings : Dictionary # holds all editor settings [path] : {settings_dictionary}
var project_settings : Dictionary # holds all project settings [path] : {settings_dictionary}
var scenes : Dictionary # holds all scenes; [file_path] = file_name, icon
var scripts : Dictionary # holds all scripts; [file_path] = file_name, icon, resource
var other_files : Dictionary # holds all other files; [file] = file_name, icon
var files_are_updating : bool = false
var recent_files_are_updating : bool  = false
enum FILTER {ALL_FILES, ALL_SCENES, ALL_SCRIPTS, ALL_OPEN_SCENES, ALL_OPEN_SCRIPTS, SELECT_NODE, SETTINGS, GOTO_LINE, GOTO_METHOD, HELP}
var current_filter : int
var script_added_to : Node # the node a script, which is created with this plugin, will be added to
	
var INTERFACE : EditorInterface
var EDITOR : ScriptEditor
var FILE_SYSTEM : EditorFileSystem
var SCRIPT_CREATE_DIALOG : ScriptCreateDialog
var EDITOR_SETTINGS : EditorSettings

	# TODO wildcards - for ALL paths, spaces will be replaced with *; for OPEN ones still just filename, removed cs keyword
	# TODO move code snippets/and signals into their own plugin
	# TODO add project settings
	# TODO select nodes
	# TODO add autocompletion on add setting, node paths and ALL file paths
# TODO update readme, screenshot, help page

func _ready() -> void:
	connect("popup_hide", self, "_on_popup_hide")
	filter.connect("text_changed", self, "_on_filter_text_changed")
	filter.connect("text_entered", self, "_on_filter_text_entered")
	item_list.connect("item_activated", self, "_on_item_list_activated")
	item_list.connect("item_selected", self, "_on_item_list_selected")
	copy_button.connect("pressed", self, "_on_copy_button_pressed")
	
	current_label.add_stylebox_override("normal", get_stylebox("normal", "LineEdit"))
	last_label.add_stylebox_override("normal", get_stylebox("normal", "LineEdit"))
	last_label.add_color_override("font_color", secondary_color)
	filter.right_icon = get_icon("Search", "EditorIcons")
	copy_button.icon = get_icon("ActionCopy", "EditorIcons")
	switch_button.icon = get_icon("MirrorX", "EditorIcons")
	
	keyboard_shortcut = custom_keyboard_shortcut if custom_keyboard_shortcut else keyboard_shortcut
	max_popup_size = custom_popup_size if custom_popup_size else max_popup_size


func _unhandled_key_input(event: InputEventKey) -> void:
	if event.as_text() == keyboard_shortcut and event.pressed and visible and not filter.text and filter.has_focus():
		_switch_to_recent_file()
	
	elif event.as_text() == keyboard_shortcut and event.pressed:
		rect_size = max_popup_size
		popup_centered()
		_update_project_settings()
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
	# to prevent unnecessarily updating cause multiple signals call this method (for ex.: changing scripts changes scenes as well)
	if not recent_files_are_updating and current_main_screen in ["2D", "3D", "Script"]:
		recent_files_are_updating = true
	
		yield(get_tree().create_timer(.2), "timeout")
		var path : String = ""
		if current_main_screen == "Script" and EDITOR.get_current_script():
			path = EDITOR.get_current_script().resource_path
		elif current_main_screen in ["2D", "3D"] and INTERFACE.get_edited_scene_root():
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
		if current_filter == FILTER.SETTINGS:
			OS.clipboard =  "\"" + item_list.get_item_text(selection[0]) + "\""
		
		# selection is a file name
		elif _current_filter_displays_files():
			var path : String = ""
			if current_filter in [FILTER.ALL_OPEN_SCENES, FILTER.ALL_OPEN_SCRIPTS]:
				path = item_list.get_item_text(selection[0] + 1) + "/" + item_list.get_item_text(selection[0]).strip_edges()
			else:
				path = item_list.get_item_text(selection[0] - 1) + "/" + item_list.get_item_text(selection[0]).strip_edges()
			OS.clipboard = "\"" + path + "\""
		
		elif current_filter == FILTER.SELECT_NODE:
			var selected_index = selection[0]
			var selected_name = item_list.get_item_text(selected_index)
			var path : String = ""
			path = item_list.get_item_text(selected_index - 1) + selected_name if item_list.get_item_text(selected_index - 1).begins_with("./") else "."
			OS.clipboard = "\"" + path + "\""
	hide()


func _on_popup_hide() -> void:
	filter.clear()


func _on_item_list_selected(index : int) -> void:
	# selection is a file path
	if _current_filter_displays_files():
		if current_filter in [FILTER.ALL_OPEN_SCENES, FILTER.ALL_OPEN_SCRIPTS] and index % item_list.max_columns == 2:
			INTERFACE.select_file(item_list.get_item_text(index) + "/" + item_list.get_item_text(index - 1).strip_edges())
		elif index % item_list.max_columns == 1:
			INTERFACE.select_file(item_list.get_item_text(index) + "/" + item_list.get_item_text(index + 1).strip_edges())


func _on_item_list_activated(index : int) -> void:
	_activate_item(index)


func _on_filter_text_changed(new_txt : String) -> void:
	# autocompletion on paths; double spaces because one space for jumping in item_list
	if filter.text.ends_with("  "):
		var selection = item_list.get_selected_items()
		if selection:
			var key = ""
			for keyword in keywords:
				if filter.text.begins_with(keyword):
					key = keyword
					break
			var search_string = filter.text.substr(key.length()).strip_edges()
			var path_to_select : String = ""
			
			if key in [keyword_all_files, keyword_all_scenes, keyword_all_scripts, keyword_select_node]:
				path_to_select = item_list.get_item_text(selection[0] - 1)
			elif key in [keyword_editor_settings]:
				path_to_select = item_list.get_item_text(selection[0])
			
			var pos = max(path_to_select.find(search_string), 0)
			var end_pos = path_to_select.find("/", pos + search_string.length()) + 1
			path_to_select = path_to_select.substr(0, end_pos if end_pos else -1)
			if path_to_select == "res:/":
				path_to_select = "res://"
			filter.text = key + path_to_select
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
	if current_filter == FILTER.GOTO_LINE:
		var number = filter.text.substr(keyword_goto_line.length()).strip_edges()
		if number.is_valid_integer():
			var max_lines = EDITOR.get_current_script().source_code.count("\n")
			EDITOR.goto_line(clamp(number as int - 1, 0, max_lines))
		selected_index = -1
	
	if selected_index == -1 or item_list.is_item_disabled(selected_index) \
			or item_list.get_item_text(selected_index) == "" or selected_index % item_list.max_columns == 0:
		hide()
		return
	
	var selected_name = item_list.get_item_text(selected_index).strip_edges()
	
	if current_filter == FILTER.SETTINGS:
		if item_list.get_item_text(selected_index - 1).begins_with("Project"):
			settings_setter._show(project_settings[item_list.get_item_text(selected_index)], "Project_Settings", ProjectSettings)
		else:
			settings_setter._show(editor_settings[item_list.get_item_text(selected_index)], "Editor_Settings", EDITOR_SETTINGS)
		return
	
	elif current_filter == FILTER.GOTO_METHOD:
		var line = item_list.get_item_text(selected_index + 1).split(":")[1].strip_edges()
		EDITOR.goto_line(line as int - 1)
	
	# select a node in the current scene
	elif current_filter == FILTER.SELECT_NODE:
		var selection = INTERFACE.get_selection()
		selection.clear()
		var node_path = item_list.get_item_text(selected_index - 1).split("./")[1] + selected_name if item_list.get_item_text(selected_index - 1).begins_with("./") else "."
		var tmp = current_main_screen
		selection.add_node(INTERFACE.get_edited_scene_root().get_node(node_path))
		if keep_main_screen_when_selecting_node:
			yield(get_tree().create_timer(.05), "timeout")
			INTERFACE.set_main_screen_editor(tmp)
	
	# files
	else:
		var path : String = ""
		if current_filter in [FILTER.ALL_OPEN_SCENES, FILTER.ALL_OPEN_SCRIPTS]:
			path = item_list.get_item_text(selected_index + 1) + "/" + item_list.get_item_text(selected_index).strip_edges()
		else:
			path = item_list.get_item_text(selected_index - 1) + "/" + item_list.get_item_text(selected_index).strip_edges()
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
	selection.add_node(INTERFACE.get_edited_scene_root()) # to see the "Node" dock in Script view
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
	
	var script_icon = get_icon("Script", "EditorIcons")
	for file in folder.get_file_count():
		var file_path = folder.get_file_path(file)
		var file_type = FILE_SYSTEM.get_file_type(file_path)
		
		if file_type.find("Script") != -1:
			scripts[file_path] = {"Icon" : script_icon, "ScriptResource" : load(file_path)}
		
		elif file_type.find("Scene") != -1:
			scenes[file_path] = {"Icon" : null}
			
			var scene = load(file_path).instance()
			scenes[file_path].Icon = get_icon(scene.get_class(), "EditorIcons")
			var attached_script = scene.get_script()
			if attached_script:
				attached_script.set_meta("Scene_Path", file_path)
			scene.free()
		
		else:
			other_files[file_path] = {"Icon" : get_icon(file_type, "EditorIcons")}
	
	for subdir in folder.get_subdir_count():
		_update_files_dictionary(folder.get_subdir(subdir))


func _update_popup_list(just_popupped : bool = false) -> void:
	if just_popupped:
		filter.grab_focus()
		script_added_to = null
	
	item_list.clear()
	copy_button.visible = false
	add_button.visible = false
	var search_string : String = filter.text
	
	# typing " X" at the end of the search_string jumps to the X-th item in the list
	var quickselect_line = 0
	var qs_starts_at = search_string.strip_edges().find_last(" ") if not search_string.begins_with(" ") else search_string.find_last(" ")
	if qs_starts_at != -1 and not search_string.begins_with(keyword_goto_line):
		quickselect_line = search_string.substr(qs_starts_at)
		if quickselect_line.strip_edges().is_valid_integer():
			search_string.erase(qs_starts_at + 1, search_string.length())
			quickselect_line = quickselect_line.strip_edges()
	
	# help page
	if search_string == "?":
		current_filter = FILTER.HELP
		tabs.current_tab = TABS.INFO_BOX
		_build_help_page()
		return
		
	tabs.current_tab = TABS.ITEM_LIST
	
	# go to line
	if search_string.begins_with(keyword_goto_line):
		current_filter = FILTER.GOTO_LINE
		if not current_main_screen == "Script":
			item_list.add_item("Go to \"Script\" view to goto_line.", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		else:
			var max_lines = EDITOR.get_current_script().source_code.count("\n")
			var number = search_string.substr(keyword_goto_line.length()).strip_edges()
			item_list.add_item("Enter a number between 1 and %s." % (max_lines + 1))
			if number.is_valid_integer():
				item_list.set_item_text(item_list.get_item_count() - 1, "Go to line %s of %s." % [clamp(number as int, 1, max_lines + 1), max_lines + 1])
				if search_string.ends_with(" "):
					EDITOR.goto_line(clamp(number as int - 1, 0, max_lines))
	
	# select node
	elif search_string.begins_with(keyword_select_node):
		add_button.visible = true
		add_button.icon = get_icon("ScriptCreate", "EditorIcons")
		current_filter = FILTER.SELECT_NODE
		_build_node_list(INTERFACE.get_edited_scene_root(), search_string.substr(keyword_select_node.length()).strip_edges())
		_count_node_list()

	# edit editor settings
	elif search_string.begins_with(keyword_editor_settings):
		add_button.visible = true
		add_button.icon = get_icon("MultiEdit", "EditorIcons")
		current_filter = FILTER.SETTINGS
		_build_item_list(search_string.substr(keyword_editor_settings.length()))
	
	# methods of the current script
	elif search_string.begins_with(keyword_goto_method):
		current_filter = FILTER.GOTO_METHOD
		if not current_main_screen == "Script":
			item_list.add_item("Go to \"Script\" view to goto_method.", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
		else:
			current_filter = FILTER.GOTO_METHOD
			_build_item_list(search_string.substr(keyword_goto_method.length()))
	
	# show all scripts and scenes
	elif search_string.begins_with(keyword_all_files):
		current_filter = FILTER.ALL_FILES
		_build_item_list(search_string.substr(keyword_all_files.length()))
	
	# show all scripts
	elif search_string.begins_with(keyword_all_scripts):
		current_filter = FILTER.ALL_SCRIPTS
		_build_item_list(search_string.substr(keyword_all_scripts.length()))
	
	# show all scenes
	elif search_string.begins_with(keyword_all_scenes):
		current_filter = FILTER.ALL_SCENES
		_build_item_list(search_string.substr(keyword_all_scenes.length()))
	
	# show open scenes
	elif search_string.begins_with(keyword_all_open_scenes):
		current_filter = FILTER.ALL_OPEN_SCENES
		_build_item_list(search_string.substr(keyword_all_open_scenes.length()))
	
	# show all open scripts
	else:
		current_filter = FILTER.ALL_OPEN_SCRIPTS
		_build_item_list(search_string)
	
	quickselect_line = clamp(quickselect_line as int, 0, item_list.get_item_count() / item_list.max_columns - 1)
	if item_list.get_item_count() > 0 and item_list.get_item_count() >= item_list.max_columns:
		copy_button.disabled = false
		add_button.disabled = false
		item_list.select(quickselect_line * item_list.max_columns + (1 if current_filter in [FILTER.ALL_OPEN_SCENES, FILTER.ALL_OPEN_SCRIPTS, FILTER.GOTO_METHOD] else 2))
		item_list.ensure_current_is_visible()
	else:
		copy_button.disabled = true
		add_button.disabled = true
	
	_adapt_list_height()


func _build_item_list(search_string : String) -> void:
	copy_button.visible = true
	copy_button.text = "Copy File Path"
	search_string = search_string.strip_edges().replace(" ", "*")
	var list : Array # array of file paths
	match current_filter:
		FILTER.ALL_FILES:
			for path in scenes:
				if search_string and not path.matchn("*" + search_string + "*"):
					continue
				list.push_back(path)
			
			for path in scripts:
				if search_string and not path.matchn("*" + search_string + "*"):
					continue
				list.push_back(path)
			
			for path in other_files:
				if search_string and not path.matchn("*" + search_string + "*"):
					continue
				list.push_back(path)
		
		FILTER.ALL_SCRIPTS:
			for path in scripts:
				if search_string and not path.matchn("*" + search_string + "*"):
					continue
				list.push_back(path)
		
		FILTER.ALL_SCENES:
			for path in scenes:
				if search_string and not path.matchn("*" + search_string + "*"):
					continue
				list.push_back(path)
		
		FILTER.ALL_OPEN_SCENES:
			var open_scenes = INTERFACE.get_open_scenes()
			for path in open_scenes:
				if search_string and not path.get_file().matchn("*" + search_string + "*"):
					continue
				list.push_back(path)
		
		FILTER.ALL_OPEN_SCRIPTS:
			var open_scripts = EDITOR.get_open_scripts()
			for script in open_scripts:
				var path = script.resource_path
				if search_string and not path.get_file().matchn("*" + search_string + "*"):
					continue
				list.push_back(path)
		
		FILTER.GOTO_METHOD:
			copy_button.visible = false
			var current_script = EDITOR.get_current_script()
			var method_dict : Dictionary # maps methods to their line position
			for method in current_script.get_script_method_list():
				if method.name != "_init": # _init always appears
					if search_string and not method.name.matchn("*" + search_string + "*"):
						continue
					var pos = current_script.source_code.find("func " + method.name)
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
			copy_button.text = "Copy Settings Path"
			for setting in editor_settings:
				if search_string and not setting.matchn("*" + search_string + "*"):
					continue
				list.push_back(setting)
			
			for setting in project_settings:
				if search_string and not setting.matchn("*" + search_string + "*"):
					continue
				list.push_back(setting)
	
	_quick_sort_by_file_name(list, 0, list.size() - 1) if _current_filter_displays_files() else list.sort()
	for index in list.size():
		item_list.add_item(" " + String(index) + "  :: ", null, false)
		
		if current_filter == FILTER.SETTINGS:
			item_list.add_item("Editor :: " if editor_settings.has(list[index]) else "Project :: ", null, false)
			item_list.set_item_disabled(item_list.get_item_count() - 1, true)
			item_list.add_item(list[index])
		
		elif _current_filter_displays_files():
			if current_filter in [FILTER.ALL_FILES, FILTER.ALL_SCENES, FILTER.ALL_SCRIPTS]:
				item_list.add_item(list[index].get_base_dir())
				item_list.set_item_custom_fg_color(item_list.get_item_count() - 1, secondary_color)
				item_list.add_item(list[index].get_file())
				if scenes.has(list[index]):
					item_list.set_item_icon(item_list.get_item_count() - 1, scenes[list[index]].Icon)
				elif scripts.has(list[index]):
					item_list.set_item_icon(item_list.get_item_count() - 1,  scripts[list[index]].Icon)
				elif other_files.has(list[index]):
					item_list.set_item_icon(item_list.get_item_count() - 1, other_files[list[index]].Icon)
			else:
				item_list.add_item(list[index].get_file())
				if scenes.has(list[index]):
					item_list.set_item_icon(item_list.get_item_count() - 1, scenes[list[index]].Icon)
				elif scripts.has(list[index]):
					item_list.set_item_icon(item_list.get_item_count() - 1,  scripts[list[index]].Icon)
				elif other_files.has(list[index]):
					item_list.set_item_icon(item_list.get_item_count() - 1, other_files[list[index]].Icon)
				item_list.add_item(list[index].get_base_dir())
				item_list.set_item_custom_fg_color(item_list.get_item_count() - 1, secondary_color)


# select a node
func _build_node_list(root : Node, search_string : String):
	var path = String(INTERFACE.get_edited_scene_root().get_path_to(root))
	if path != ".":
		path = "./" + path
	
	if not search_string or path.matchn("*" + search_string.replace(" ", "*") + "*"):
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


# select a node
func _count_node_list():
	copy_button.text = "Copy Node Path"
	copy_button.visible = true
	for i in item_list.get_item_count() / item_list.max_columns:
		item_list.set_item_text(i * item_list.max_columns, " " + String(i) + "  :: ")


func _build_help_page() -> void:
	var file = File.new()
	file.open("res://addons/CommandPalettePopup/Help.txt", File.READ)
	info_box.bbcode_text = file.get_as_text() % [keyword_all_open_scenes, keyword_all_files, keyword_all_scripts, \
			keyword_all_scenes, keyword_goto_line, keyword_goto_method]
	file.close()


func _adapt_list_height() -> void:
	if adapt_popup_height:
		var script_icon = get_icon("Script", "EditorIcons")
		var row_height = script_icon.get_size().y + (8 * screen_factor)
		var rows = max(item_list.get_item_count() / item_list.max_columns, 1) + 1
		var margin = filter.rect_size.y + $PaletteMarginContainer.margin_top + abs($PaletteMarginContainer.margin_bottom) \
				+ $PaletteMarginContainer/VBoxContainer/MarginContainer.get("custom_constants/margin_top") \
				+ $PaletteMarginContainer/VBoxContainer/MarginContainer.get("custom_constants/margin_bottom") \
				+ max(current_label.rect_size.y, last_label.rect_size.y)
		var height = row_height * rows + margin
		rect_size.y = clamp(height, 0, max_popup_size.y)


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
	return not current_filter in [FILTER.GOTO_METHOD, FILTER.SELECT_NODE, FILTER.SETTINGS, FILTER.HELP, FILTER.GOTO_LINE, FILTER.GOTO_METHOD]


func _update_editor_settings() -> void: # connected to editor settings_changed signal
	for setting in EDITOR_SETTINGS.get_property_list():
		# general settings only
		if setting.name and setting.name.find("/") != -1 and setting.usage & PROPERTY_USAGE_EDITOR and not setting.name.begins_with("favorite_projects/"):
			editor_settings[setting.name] = setting


func _update_project_settings() -> void:
	for setting in ProjectSettings.get_property_list():
		# generalt settings only
		if setting.name and setting.name.find("/") != -1 and setting.usage & PROPERTY_USAGE_EDITOR:
			project_settings[setting.name] = setting


func _on_SwitchIcon_pressed() -> void:
	_switch_to_recent_file()


func _switch_to_recent_file() -> void:
		if last_label.has_meta("Path"):
			if current_main_screen in ["2D", "3D", "Script"]:
				_open_scene(last_label.get_meta("Path")) if scenes.has(last_label.get_meta("Path")) \
						else _open_script(scripts[last_label.get_meta("Path")].ScriptResource)
			else:
				_open_scene(current_label.get_meta("Path")) if scenes.has(current_label.get_meta("Path")) \
						else _open_script(scripts[current_label.get_meta("Path")].ScriptResource)
		hide()


func _on_AddButton_pressed() -> void:
	if filter.text.begins_with(keyword_editor_settings):
		settings_adder._show()
		
		
#		var setting_path = Array(item_list.get_item_text(item_list.get_selected_items()[0]).split("/"))
#		var setting_name = setting_path.pop_back().capitalize()
#
#		var popup : PopupMenu = INTERFACE.get_base_control().get_child(1).get_child(0).get_child(0).get_child(3).get_child(0)
#		popup.emit_signal("id_pressed", 59)
#		var settings = INTERFACE.get_base_control().get_child(INTERFACE.get_base_control().get_child_count() - 1)
#		var sectionedinspec = settings.get_child(3).get_child(0).get_child(1)
#		var tree : Tree = sectionedinspec.get_child(0).get_child(0)
#		var inspec = sectionedinspec.get_child(1).get_child(0).get_child(0) # möglicherweise mehr als nur 1 kind als vbox wg sections
#
#
#		var tree_item : TreeItem = tree.get_root()
#		while setting_path:
#			tree_item = tree_item.get_children()
#			var sname = setting_path.pop_front().capitalize()
#			while tree_item.get_text(0) != sname:
#				tree_item = tree_item.get_next()
#		tree_item.select(0)
#		yield(.get_tree().create_timer(.1), "timeout")
#		tree.ensure_cursor_is_visible()
#		rec(inspec, setting_name)
	
	elif filter.text.begins_with(keyword_select_node):
		var selection = item_list.get_selected_items()
		if selection:
			var selected_index = selection[0]
			var selected_name = item_list.get_item_text(selected_index).strip_edges()
			var node_path = item_list.get_item_text(selected_index - 1).split("./")[1] + selected_name if item_list.get_item_text(selected_index - 1).begins_with("./") else "."
			script_added_to = INTERFACE.get_edited_scene_root().get_node(node_path)
			var file_path = INTERFACE.get_edited_scene_root().filename.get_base_dir()
			SCRIPT_CREATE_DIALOG.config(script_added_to.get_class(), (file_path if file_path else "res:/") + "/" + selected_name + ".gd")
			SCRIPT_CREATE_DIALOG.popup_centered()
		hide()

#func rec(node : Node, sname : String):
#	if node is EditorProperty:
#		if node.label == sname:
#			node = node.get_child(0)
#			while(node is Container):
#				node = node.get_child(0)
#			node.grab_focus()
#	else:
#		for child in node.get_children():
#			rec(child, sname)
