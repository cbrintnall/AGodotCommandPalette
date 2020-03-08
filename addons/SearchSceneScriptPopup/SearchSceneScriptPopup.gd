tool
extends Popup


onready var filter = $Panel/MarginContainer/VBoxContainer/MarginContainer2/HSplitContainer/VBoxContainer/HBoxContainer/Filter
onready var item_list = $Panel/MarginContainer/VBoxContainer/MarginContainer2/HSplitContainer/VBoxContainer/MarginContainer/HBoxContainer/ItemList
onready var copy_path_button =$Panel/MarginContainer/VBoxContainer/MarginContainer2/HSplitContainer/VBoxContainer/HBoxContainer/Button
onready var file_tree = $Panel/MarginContainer/VBoxContainer/MarginContainer2/HSplitContainer/Tree

# save the file after you made changes in the inspector; reenable the plugin in the project settings or reopen the project to apply the update
export (Vector2) var popup_size = Vector2(800, 900) 
export (bool) var select_file_in_filesystem_dock = true
export (bool) var collapse_paths_when_full = true
export (Color) var file_tree_selection_color = Color.aquamarine

var current_file # switch between the last 2 opened files (only when opened with this plugin)
var last_file # switch between the last 2 opened files (only when opened with this plugin)
var scenes_to_scripts : Dictionary # maps the scripts to the scene roots they are attached to
var files : Dictionary # holds ALL scenes and scripts with different properties, see _update_files_dictionaries()
var first_key_press : bool = true # to stop "pressed" spam
var current_selection # used for deleting the old colors of the file tree selection
enum FILTER {ALL_SCENES_AND_SCRIPTS, ALL_SCENES, ALL_SCRIPTS, ALL_OPEN_SCENES, ALL_OPEN_SCRIPTS}

var PLUGIN : EditorPlugin
var INTERFACE : EditorInterface
var EDITOR : ScriptEditor
var FILE_SYSTEM : EditorFileSystem


# TODO: 
# seperate scripts and scenes into 2 columns
# documentation for jumping to the opened file in the filesystem dock
# add feature: search folder for files
# add feature: go_to_line in script
# add feature: Type "?" for help instead of tooltip
# add feature: listing all signals for the node and its parent classes and auto-paste its code at line X, at  cursor position or file end (?)
# add feature: code snippets for virtual methods: insert at line X, at  cursor position or file end (?)
# better themeing
# submit PR for documentation of get_children() on TreeItem


func _ready() -> void:
	_initialize()


func _initialize() -> void:
	connect("popup_hide", self, "_on_popup_hide")
	filter.connect("text_changed", self, "_on_filter_text_changed")
	filter.connect("text_entered", self, "_on_filter_text_entered")
	item_list.connect("item_selected", self, "_on_item_list_selected")
	item_list.connect("item_activated", self, "_on_item_list_activated")
	file_tree.connect("item_selected", self, "_on_tree_item_selected")
	file_tree.connect("item_activated", self, "_on_tree_item_activated")
	copy_path_button.connect("pressed", self, "_on_copy_button_pressed")
	FILE_SYSTEM.connect("filesystem_changed", self, "_on_filesystem_changed")


# global keyboard shortcuts
func _unhandled_key_input(event: InputEventKey) -> void:
	if event.as_text() == "Control+E" and event.pressed and visible and not filter.text and filter.has_focus() and first_key_press:
		# switch between the last two opened files (only when opened via this plugin)
		if last_file:
			_open_scene(files[last_file].File_Path) if files[last_file].Type == "Scene" else _open_script(files[last_file].Instance)
		hide()
		
	elif event.as_text() == "Control+E" and event.pressed and first_key_press:
		first_key_press = false
		rect_size = popup_size
		popup_centered()
		_update_popup_list()
		
	elif event.as_text() == "Control+E" and not event.pressed:
		first_key_press = true


func _on_filesystem_changed() -> void:
	_update_files_dictionaries(FILE_SYSTEM.get_filesystem(), true)


func _on_copy_button_pressed() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		var path = files[item_list.get_item_text(selection[0]).split("  ::  ")[1]].File_Path
		OS.clipboard = "\"" + path + "\""
	hide()


func _on_popup_hide() -> void:
	filter.clear()


func _on_item_list_selected(index : int) -> void:
	_update_tree_colors()


func _on_item_list_activated(index : int) -> void:
	_open_selection()


func _on_tree_item_selected() -> void:
	item_list.select(files[file_tree.get_selected().get_text(0)].List_Index)


func _on_tree_item_activated() -> void:
	_open_selection()


func _on_filter_text_changed(new_txt : String) -> void:
	_update_popup_list()


func _on_filter_text_entered(new_txt : String) -> void:
	_open_selection()


func _open_selection() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		var selected_name = item_list.get_item_text(selection[0]).split("  ::  ")[1]
		if files[selected_name].Type == "Script": 
			_open_script(files[selected_name].Instance)
		else: 
			_open_scene(files[selected_name].File_Path)
	hide()


func _open_script(script : Script) -> void:
	if scenes_to_scripts.has(script):
		INTERFACE.open_scene_from_path(scenes_to_scripts[script])
		
	INTERFACE.edit_resource(script)
	INTERFACE.call_deferred("set_main_screen_editor", "Script")
		
	if not current_file:
		current_file = script.resource_path.get_file()
	else:
		last_file = current_file
		current_file = script.resource_path.get_file()
		
	if select_file_in_filesystem_dock:
		INTERFACE.select_file(script.resource_path)


func _open_scene(path : String) -> void:
	INTERFACE.open_scene_from_path(path)
	INTERFACE.call_deferred("set_main_screen_editor", "3D") if INTERFACE.get_edited_scene_root() is Spatial else INTERFACE.call_deferred("set_main_screen_editor", "2D")
		
	if not current_file:
		current_file = path.get_file()
	else:
		last_file = current_file
		current_file = path.get_file()
		
	if select_file_in_filesystem_dock:
		INTERFACE.select_file(path)


func _update_files_dictionaries(folder : EditorFileSystemDirectory, reset : bool = false) -> void:
	if reset:
		files.clear()
		
	for file in folder.get_file_count():
		var file_path = folder.get_file_path(file)
		var file_type = FILE_SYSTEM.get_file_type(file_path)
			
		if file_type.findn("Script") != -1:
			files[folder.get_file(file)] = { "Type" : "Script", "File_Path" : file_path, "Instance" : load(file_path)} # +List_Index = index in ItemList
		elif file_type.findn("Scene") != -1: 
			files[folder.get_file(file)] = {"Type" : "Scene", "File_Path" : file_path} # +List_Index = index in ItemList
			var scene = load(file_path).instance()
			var attached_script = scene.get_script()
			if attached_script:
				scenes_to_scripts[attached_script] = file_path
			scene.free()
		
	for subdir in folder.get_subdir_count():
		_update_files_dictionaries(folder.get_subdir(subdir))


# search happens only on the actual file name
func _update_popup_list() -> void:
	item_list.clear()
	var search_string = filter.text
		
	# typing " X" at the end of the search_string jumps to that X-th item in the list
	var quickselect_line = 0 
	var quickselect_index = search_string.find_last(" ")
	if quickselect_index != -1 and not search_string.ends_with(" "):
		quickselect_line = search_string.substr(quickselect_index + 1)
		if quickselect_line.is_valid_integer():
			search_string.erase(quickselect_index + 1, String(quickselect_line).length())
		
	if search_string.begins_with("a "):
		_fill_item_list(search_string.substr(2).strip_edges(), FILTER.ALL_SCENES_AND_SCRIPTS)
		
	elif search_string.begins_with("ac ") or search_string.begins_with("ca "):
		_fill_item_list(search_string.substr(3).strip_edges(), FILTER.ALL_SCRIPTS)
		
	elif search_string.begins_with("as ") or search_string.begins_with("sa "):
		_fill_item_list(search_string.substr(3).strip_edges(), FILTER.ALL_SCENES)
		
	elif search_string.begins_with("c "):
		_fill_item_list(search_string.substr(2).strip_edges(), FILTER.ALL_OPEN_SCRIPTS)
		
	elif search_string.begins_with("s "):
		_fill_item_list(search_string.substr(2).strip_edges(), FILTER.ALL_OPEN_SCENES)
		
	else:
		_fill_item_list(search_string.strip_edges())
		
	item_list.sort_items_by_text()
	_count_list()
	_select_item_in_list(quickselect_line as int)
	var list : Array
	for item in item_list.get_item_count():
		var fname = item_list.get_item_text(item).split("  ::  ")[1]
		list.push_back(files[fname].File_Path)
	_update_tree_structure(list)


func _select_item_in_list(index : int) -> void:
	index = clamp(index, 0, item_list.get_item_count() - 1)
	item_list.select(index)
	item_list.ensure_current_is_visible()


func _fill_item_list(search_string : String, special_filter : int = -1) -> void:
	var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
	var scene_icon = INTERFACE.get_base_control().get_icon("PackedScene", "EditorIcons")
	match special_filter:
		FILTER.ALL_SCENES_AND_SCRIPTS:
			for file in files:
				if search_string:
					if file.findn(search_string) != -1:
						item_list.add_item(file, scene_icon if files[file].Type == "Scene" else script_icon)
				else:
					item_list.add_item(file, scene_icon if files[file].Type == "Scene" else script_icon)
			
		FILTER.ALL_SCRIPTS:
			for file in files:
				if files[file].Type == "Script":
					if search_string:
						if file.findn(search_string) != -1:
							item_list.add_item(file, script_icon)
					else:
						item_list.add_item(file, script_icon)
			
		FILTER.ALL_SCENES:
			for file in files:
				if files[file].Type == "Scene":
					if search_string:
						if file.findn(search_string) != -1:
							item_list.add_item(file, scene_icon)
					else:
						item_list.add_item(file, scene_icon)
			
		FILTER.ALL_OPEN_SCENES:
			var open_scenes = INTERFACE.get_open_scenes()
			for scene_path in open_scenes:
				var scene_name = scene_path.get_file()
				if search_string:
					if scene_name.findn(search_string) != -1:
						item_list.add_item(scene_name, scene_icon)
				else:
					item_list.add_item(scene_name, scene_icon)
			
		FILTER.ALL_OPEN_SCRIPTS:
			var open_scripts = EDITOR.get_open_scripts()
			for script in open_scripts:
				var script_name = script.resource_path.get_file()
				if search_string:
					if script_name.findn(search_string) != -1:
						item_list.add_item(script_name, script_icon)
						
				else:
					item_list.add_item(script_name, script_icon)
			
		_: # all open scenes and scripts
			var open_scenes = INTERFACE.get_open_scenes()
			for scene_path in open_scenes:
				var scene_name = scene_path.get_file()
				if search_string:
					if scene_name.findn(search_string) != -1:
						item_list.add_item(scene_name, scene_icon)
				else:
					item_list.add_item(scene_name, scene_icon)
				
			var open_scripts = EDITOR.get_open_scripts()
			for script in open_scripts:
				var script_name = script.resource_path.get_file()
				if search_string:
					if script_name.findn(search_string) != -1:
						item_list.add_item(script_name, script_icon)
				else:
					item_list.add_item(script_name, script_icon)


func _count_list() -> void:
	for item in item_list.get_item_count():
		files[item_list.get_item_text(item)].List_Index = item
		item_list.set_item_text(item, String(item) + "  ::  " + item_list.get_item_text(item))


func _update_tree_structure(file_paths : Array) -> void:
	file_tree.clear()
	var root = file_tree.create_item()
	root.set_text(0, "res://")
	root.set_custom_color(0, file_tree_selection_color)
	root.set_selectable(0, false)
	for scene_path in file_paths:
		scene_path.erase(0, 6)
		var current_parent = file_tree.get_root()
		var current_dir = file_tree.get_root().get_children()
		var file_or_folder_names = scene_path.split("/")
		# travel through the tree and create the folders according to the scene_paths to a file, if they don't exist.
		while true:
			# if the current directory doesn't exit, it means all the following folders of the scene_path need to be created as well
			if not current_dir:
				while file_or_folder_names:
					var new_item = file_tree.create_item(current_parent)
					new_item.set_text(0, file_or_folder_names[0])
					file_or_folder_names.remove(0)
					# case: file creation
					if file_or_folder_names.size() == 0:
						var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
						var scene_icon = INTERFACE.get_base_control().get_icon("PackedScene", "EditorIcons")
						new_item.set_icon(0, script_icon if new_item.get_text(0).findn(".gd") != -1 or new_item.get_text(0).findn(".vs") != -1 else scene_icon)
						files[new_item.get_text(0)].Tree_Item = new_item
					# case: more folders
					else:
						current_parent = new_item
						new_item.set_selectable(0, false) 
				break # reaching this, it means the entire path for the current file has been created
			# if the current directiory exists, we just travel through the TreeItems matching the file_path
			if current_dir.get_text(0) == file_or_folder_names[0]:
				file_or_folder_names.remove(0)
				current_parent = current_dir
				current_dir = current_dir.get_children()
			else:
				current_dir = current_dir.get_next()
	_update_tree_colors()


func _update_tree_colors() -> void: 
	if current_selection:
		_reset_colors(current_selection.split("/"))
	var new_selection = item_list.get_selected_items()
	if new_selection:
		var selected_path = files[item_list.get_item_text(new_selection[0]).split("  ::  ")[1]].File_Path
		selected_path.erase(0, 6)
		current_selection = selected_path
		_color_path(selected_path.split("/"))


func _reset_colors(file_or_folder : PoolStringArray) -> void:
	var current_dir = file_tree.get_root().get_children()
	while file_or_folder.size() and current_dir:
		if current_dir.get_text(0) == file_or_folder[0]:
			current_dir.set_custom_color(0, Color(0.63, 0.63, 0.63, 1))
			file_or_folder.remove(0)
			current_dir = current_dir.get_children()
		else:
			current_dir = current_dir.get_next()


func _color_path(file_or_folder : PoolStringArray) -> void:
	var current_dir = file_tree.get_root().get_children()
	while file_or_folder.size() and current_dir:
		if current_dir.get_text(0) == file_or_folder[0]:
			if current_dir.get_children() and collapse_paths_when_full:
				current_dir.collapsed = false
			if file_or_folder.size() > 1:
				current_dir.set_custom_color(0, file_tree_selection_color)
			else:
				current_dir.select(0)
				file_tree.ensure_cursor_is_visible()
				#break
			file_or_folder.remove(0) 
			current_dir = current_dir.get_children()
		else:
			if collapse_paths_when_full:
				current_dir.collapsed = true
			current_dir = current_dir.get_next()
