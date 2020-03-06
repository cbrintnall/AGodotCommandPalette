tool
extends Popup


onready var filter = $Panel/MarginContainer/VBoxContainer/MarginContainer2/VBoxContainer/Filter
onready var item_list = $Panel/MarginContainer/VBoxContainer/MarginContainer2/VBoxContainer/MarginContainer/HBoxContainer/ItemList

var scenes : Dictionary # hodls all scenes wether they are open or not; Key: file_name, Value: file_path
var scripts : Dictionary # hodls all scripts wether they are open or not; Key: file_name, Value: Scripts
var last_file
var current_file

var PLUGIN : EditorPlugin
var INTERFACE : EditorInterface
var EDITOR : ScriptEditor
var FILE_SYSTEM : EditorFileSystem


func _ready() -> void:
	call_deferred("initialize")


func initialize() -> void:
	filter.connect("text_changed", self, "_on_filter_text_changed")
	filter.connect("text_entered", self, "_on_filter_text_entered")
	item_list.connect("item_activated", self, "_on_item_list_activated")
	connect("popup_hide", self, "_on_popup_hide")
	FILE_SYSTEM.connect("filesystem_changed", self, "_on_filesystem_changed") 


# global keyboard shortcuts
func _unhandled_key_input(event: InputEventKey) -> void: 
	if event.as_text() == "Control+E" and event.is_pressed() and visible and not filter.text:
		# switch between the last two opened files (only when opened via this plugin)
		if scripts.has(last_file):
			_switch_to_scene_tab_of(scripts[last_file])
			_open_script(scripts[last_file])
		elif scenes.has(last_file):
			_open_scene(scenes[last_file])
		hide()
	elif event.as_text() == "Control+E" and event.is_pressed():
		popup_centered_minsize(Vector2(100, 1000))
		_update_popup_list()


func _on_filesystem_changed():
	scenes.clear()
	scripts.clear()
	_update_file_dictionaries(FILE_SYSTEM.get_filesystem())


func _on_popup_hide() -> void:
	filter.clear()


func _on_item_list_activated(index : int) -> void:
	_open_selection()


func _on_filter_text_changed(new_txt : String) -> void:
	_update_popup_list()


func _on_filter_text_entered(new_txt : String) -> void:
	_open_selection()


func _open_selection() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		var selected = item_list.get_item_text(selection[0])
		var selection_without_line_number = selected.split("  ::  ")[1] 
		var selected_file_name = selection_without_line_number.split("    >>    ")[0]
		if selected_file_name.findn(".gd") != -1 or selected_file_name.findn(".vs") != -1: 
			_switch_to_scene_tab_of(scripts[selected_file_name])
			_open_script(scripts[selected_file_name])
		else: 
			_open_scene(scenes[selected_file_name])
	hide()


# open the scene a script is attached to. Only works if the script is attached to the scene root.
# I dont know how expensive the constant loading/freeing of scenes is, so there is a "cruder" option commented out.
# limitation of that: only works if script and scene file have the same name. And it only opens .tscn files.
func _switch_to_scene_tab_of(script : Script) -> void:
	for scene_name in scenes:
		var scene_path = scenes[scene_name]
		var scene = load(scene_path).instance()
		if scene.get_script() == script:
			scene.queue_free()
			INTERFACE.open_scene_from_path(scene_path)
			return
		scene.queue_free()
#	var scene_name = script.resource_path.get_file().split(".")[0] + ".tscn"
#	if scenes.has(scene_name):
#		INTERFACE.open_scene_from_path(scenes[scene_name])


func _open_script(script : Script) -> void:
	INTERFACE.edit_resource(script)
	INTERFACE.call_deferred("set_main_screen_editor", "Script")
	if not current_file:
		current_file = script.resource_path.get_file()
	else:
		last_file = current_file
		current_file = script.resource_path.get_file()


func _open_scene(path : String) -> void:
	INTERFACE.open_scene_from_path(path)
	INTERFACE.call_deferred("set_main_screen_editor", "3D") if INTERFACE.get_edited_scene_root() is Spatial else INTERFACE.call_deferred("set_main_screen_editor", "2D")
	if not current_file:
		current_file = path.get_file()
	else:
		last_file = current_file
		current_file = path.get_file()


# not sure about performance (especially with large number of files)...
func _update_file_dictionaries(folder : EditorFileSystemDirectory) -> void:
	for file in folder.get_file_count():
		var file_path = folder.get_file_path(file)
		var file_type = FILE_SYSTEM.get_file_type(file_path)
			
		if file_type.findn("Script") != -1:
			scripts[folder.get_file(file)] = load(file_path)
			
		elif file_type.findn("Scene") != -1: 
			scenes[folder.get_file(file)] = file_path
		
	for subdir in folder.get_subdir_count():
		_update_file_dictionaries(folder.get_subdir(subdir))


# search happens only on the actual file name
func _update_popup_list() -> void:
	item_list.clear()
	var search_string = filter.text
	
	var quickselect_line = 0 # typing " X" (where X is an integer) at the end of the search_string jumps to that item in the item_list
	var quickselect_index = search_string.find_last(" ")
	if quickselect_index != -1 and not search_string.ends_with(" "):
		quickselect_line = search_string.substr(quickselect_index + 1)
		if quickselect_line.is_valid_integer():
			search_string.erase(quickselect_index + 1, String(quickselect_line).length())
	
	if search_string.begins_with("a "):
		_add_scripts(search_string.substr(2).strip_edges(), scripts)
		_add_scenes(search_string.substr(2).strip_edges(), scenes)
	elif search_string.begins_with("ac ") or search_string.begins_with("ca "):
		_add_scripts(search_string.substr(3).strip_edges(), scripts)
	elif search_string.begins_with("as ") or search_string.begins_with("sa "):
		_add_scenes(search_string.substr(3).strip_edges(), scenes)
	elif search_string.begins_with("c "):
		_add_scripts(search_string.substr(2).strip_edges(), EDITOR.get_open_scripts())
	elif search_string.begins_with("s "):
		_add_scenes(search_string.substr(2).strip_edges(), INTERFACE.get_open_scenes())
	else:
		_add_scripts(search_string.strip_edges(), EDITOR.get_open_scripts())
		_add_scenes(search_string.strip_edges(), INTERFACE.get_open_scenes())
		
	item_list.sort_items_by_text()
	_count_list()
	item_list.call_deferred("select", clamp(quickselect_line as int, 0, item_list.get_item_count() - 1)) # call_deferred because of a weird selection issue (highlight only goes partly) on first call of the popup whenever a project is opened


func _add_scripts(search_string : String, script_list) -> void:
	var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
	for script in script_list:
		var script_name = script.resource_path.get_file() if script_list is Array else script
		var script_path = script.resource_path.get_base_dir() if script_list is Array else scripts[script].resource_path.get_base_dir()
		if search_string:
			if script_name.findn(search_string) != -1:
				item_list.add_item(script_name + "    >>    " + script_path, script_icon)
		else:
			item_list.add_item(script_name + "    >>    " + script_path, script_icon)


func _add_scenes(search_string : String, scene_list) -> void:
	var scene_icon = INTERFACE.get_base_control().get_icon("PackedScene", "EditorIcons")
	for scene in scene_list:
		var scene_path = scene if scene_list is Array else scenes[scene]
		var scene_name = scene_path.get_file() if scene_list is Array else scene
		if search_string:
			if scene_name.findn(search_string) != -1:
				item_list.add_item(scene_name + "    >>    " + scene_path.get_base_dir(), scene_icon)
		else:
			item_list.add_item(scene_name + "    >>    " + scene_path.get_base_dir(), scene_icon)


func _count_list() -> void:
	for item in item_list.get_item_count():
		item_list.set_item_text(item, String(item) + "  ::  " + item_list.get_item_text(item))
