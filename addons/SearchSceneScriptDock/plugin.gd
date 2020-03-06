tool
extends EditorPlugin


var SearchSceneScriptDock : Popup = load("res://addons/SearchSceneScriptDock/SearchSceneScriptDock.tscn").instance()


func _enter_tree() -> void:
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, SearchSceneScriptDock)
	SearchSceneScriptDock.PLUGIN = self
	SearchSceneScriptDock.INTERFACE = get_editor_interface()
	SearchSceneScriptDock.EDITOR = get_editor_interface().get_script_editor()
	SearchSceneScriptDock.FILE_SYSTEM = get_editor_interface().get_resource_filesystem()


func _exit_tree() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_SIDE_RIGHT, SearchSceneScriptDock)
	SearchSceneScriptDock.free()

