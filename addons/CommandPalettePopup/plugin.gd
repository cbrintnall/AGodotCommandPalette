tool
extends EditorPlugin


var command_palette_popup : WindowDialog


func _enter_tree() -> void:
	connect("resource_saved", self, "_on_resource_saved")
	_init_palette()


func _exit_tree() -> void:
	_cleanup_palette()


func _on_resource_saved(resource : Resource) -> void: 
	# reload "plugin" if you save it. Doesn't work for changes made to plugin.gd or changes made in the inspector
	var rname = resource.resource_path.get_file()
	if rname.begins_with(command_palette_popup.name):
		_cleanup_palette()
		_init_palette() 
		command_palette_popup._update_files_dictionary(get_editor_interface().get_resource_filesystem().get_filesystem()) 


func _init_palette() -> void:
	command_palette_popup = load("res://addons/CommandPalettePopup/CommandPalettePopup.tscn").instance()
	command_palette_popup.PLUGIN = self
	command_palette_popup.INTERFACE = get_editor_interface()
	command_palette_popup.EDITOR = get_editor_interface().get_script_editor()
	command_palette_popup.FILE_SYSTEM = get_editor_interface().get_resource_filesystem()
	command_palette_popup.SCRIPT_CREATE_DIALOG = get_script_create_dialog()
	command_palette_popup.EDITOR_SETTINGS = get_editor_interface().get_editor_settings()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, command_palette_popup)


func _cleanup_palette() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, command_palette_popup)
	command_palette_popup.free()
