tool
extends EditorPlugin


var command_palette_popup : Popup


func _enter_tree() -> void:
	connect("resource_saved", self, "_on_resource_saved")
	_initialize()


func _exit_tree() -> void:
	_cleanup()


func _on_resource_saved(resource : Resource) -> void: 
	# reload "plugin" if you save it. Doesn't work for plugin.gd or changes made to the exported vars
	var name = resource.resource_path.get_file()
	if name.begins_with("CommandPalettePopup"):
		_cleanup()
		_initialize() 
		command_palette_popup._update_files_dictionary(get_editor_interface().get_resource_filesystem().get_filesystem()) 


func _initialize() -> void:
	command_palette_popup = load("res://addons/CommandPalettePopup/CommandPalettePopup.tscn").instance()
	command_palette_popup.PLUGIN = self
	command_palette_popup.INTERFACE = get_editor_interface()
	command_palette_popup.EDITOR = get_editor_interface().get_script_editor()
	command_palette_popup.FILE_SYSTEM = get_editor_interface().get_resource_filesystem()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, command_palette_popup)


func _cleanup() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, command_palette_popup)
	command_palette_popup.free()
