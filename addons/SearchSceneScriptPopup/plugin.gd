tool
extends EditorPlugin


var search_scene_script_popup : Popup


func _enter_tree() -> void:
	connect("resource_saved", self, "_on_resource_saved")
	_initialize()


func _exit_tree() -> void:
	_cleanup()


func _on_resource_saved(resource : Resource) -> void: 
	# reload "plugin" if you save it. Doesn't work for plugin.gd or changes made to the exported vars
	var name = resource.resource_path.get_file()
	if name.begins_with("SearchSceneScriptPopup"):
		_cleanup()
		_initialize() 


func _initialize() -> void:
	search_scene_script_popup = load("res://addons/SearchSceneScriptPopup/SearchSceneScriptPopup.tscn").instance()
	search_scene_script_popup.PLUGIN = self
	search_scene_script_popup.INTERFACE = get_editor_interface()
	search_scene_script_popup.EDITOR = get_editor_interface().get_script_editor()
	search_scene_script_popup.FILE_SYSTEM = get_editor_interface().get_resource_filesystem()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, search_scene_script_popup)


func _cleanup() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, search_scene_script_popup)
	search_scene_script_popup.free()
