tool
extends Popup


onready var filter = $Panel/MarginContainer/VBoxContainer/MarginContainer2/VBoxContainer/Filter
onready var list = $Panel/MarginContainer/VBoxContainer/MarginContainer2/VBoxContainer/MarginContainer/HBoxContainer/ItemList

var open_scenes : Dictionary # this saves the actual Scripts (class)
var open_scripts : Dictionary # this saves the file paths to the scenes

var PLUGIN : EditorPlugin
var INTERFACE : EditorInterface
var EDITOR : ScriptEditor


func _ready() -> void:
	filter.connect("text_changed", self, "_on_filter_text_changed")
	filter.connect("text_entered", self, "_on_filter_text_entered")
	list.connect("item_activated", self, "_on_item_list_activated")
	connect("popup_hide", self, "_on_popup_hide")


# global keyboard shortcuts
# hitting ESC hides the popup
func _unhandled_key_input(event: InputEventKey) -> void: 
	if event.as_text() == "Control+E" and event.is_pressed():
		popup_centered()
		_update_list()
		
	if event.as_text() == "Control+Alt+E" and event.is_pressed():
		popup_centered()
		_update_list()


func _on_popup_hide() -> void:
	filter.clear()


func _on_item_list_activated(index : int) -> void:
	_open_selection()


func _on_filter_text_changed(new_txt : String) -> void:
	_update_list()


func _on_filter_text_entered(new_txt : String) -> void:
	_open_selection()


func _open_selection() -> void:
	var selection = list.get_selected_items()
	if selection:
		var selected = list.get_item_text(selection[0])
		var selection_without_line_number = selected.split("  ::  ")[1] 
		var selected_file_name = selection_without_line_number.split("    >>    ")[0]
			
		if selected_file_name.findn(".gd") != -1 or selected_file_name.findn(".vs") != -1: # selected file is a gd/gdns/vs script
			INTERFACE.edit_resource(open_scripts[selected_file_name])
			INTERFACE.set_main_screen_editor("Script")
			
		else: # selected file is a scene file
			INTERFACE.open_scene_from_path(open_scenes[selected_file_name])
			INTERFACE.set_main_screen_editor("3D") if INTERFACE.get_edited_scene_root() is Spatial else INTERFACE.set_main_screen_editor("2D")
	hide()


# search happens only on the actual file name
func _update_list() -> void:
	list.clear()
	open_scenes.clear()
	open_scripts.clear()
	var search_string = filter.text as String
	
	var quickselect_line = 0 # typing " X" (where X is an integer) at the end of the search_string jumps to that item in the list
	var quickselect_index = search_string.find_last(" ")
	if quickselect_index != -1 and not search_string.ends_with(" "):
		quickselect_line = search_string.substr(quickselect_index + 1)
		if quickselect_line.is_valid_integer():
			search_string.erase(quickselect_index + 1, String(quickselect_line).length())
		
	if search_string.begins_with("c "):
		_add_scripts(search_string.substr(2).strip_edges())
	elif search_string.begins_with("s "):
		_add_scenes(search_string.substr(2).strip_edges())
	else:
		_add_scripts(search_string.strip_edges())
		_add_scenes(search_string.strip_edges())
		
	list.sort_items_by_text()
	_count_list()
	list.call_deferred("select", clamp(quickselect_line as int, 0, list.get_item_count() - 1)) # call_deferred because of a weird selection issue (highlight only goes partly) on first call of the popup whenever a project is opened


func _add_scripts(search_string : String) -> void:
	var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
	for script in EDITOR.get_open_scripts():
		var script_name = script.resource_path.get_file()
		if search_string:
			if script_name.findn(search_string) != -1 :
				open_scripts[script_name] = script
				list.add_item(script_name + "    >>    " + script.resource_path.get_base_dir(), script_icon)
		else:
			open_scripts[script_name] = script
			list.add_item(script_name + "    >>    " + script.resource_path.get_base_dir(), script_icon)


func _add_scenes(search_string : String) -> void:
	var scene_icon = INTERFACE.get_base_control().get_icon("PackedScene", "EditorIcons")
	for scene_path in INTERFACE.get_open_scenes():
		var scene_name = scene_path.get_file()
		if search_string:
			if scene_name.findn(search_string) != -1:
				open_scenes[scene_name] = scene_path
				list.add_item(scene_name + "    >>    " + scene_path.get_base_dir(), scene_icon)
		else:
			open_scenes[scene_name] = scene_path
			list.add_item(scene_name + "    >>    " + scene_path.get_base_dir(), scene_icon)


func _count_list() -> void:
	for item in list.get_item_count():
		list.set_item_text(item, String(item) + "  ::  " + list.get_item_text(item))
