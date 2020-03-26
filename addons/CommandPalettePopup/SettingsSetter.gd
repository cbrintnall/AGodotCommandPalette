tool
extends WindowDialog


onready var path_label = $MainVB/PathLabel
onready var hint_label = $MainVB/HintMarginContainer/HintLabel
onready var tabs = $MainVB/MainMarginContainer/TabContainer
onready var checkbox = $MainVB/MainMarginContainer/TabContainer/CheckBox
onready var option_button = $MainVB/MainMarginContainer/TabContainer/OptionButton
onready var spinbox = $MainVB/MainMarginContainer/TabContainer/SpinBox
onready var file_dialog = $MainVB/MainMarginContainer/TabContainer/FileDirLineEdit/FileDialog
onready var text_editors = $MainVB/MainMarginContainer/TabContainer/FileDirLineEdit/TabContainer
onready var open_file_dir_button = $MainVB/MainMarginContainer/TabContainer/FileDirLineEdit/FileDirButton
onready var colorpicker = $MainVB/MainMarginContainer/TabContainer/ColorPickerButton
onready var cancel_button = $MainVB/ButtonsHB/CancelButton
onready var accept_button = $MainVB/ButtonsHB/AcceptButton
	
enum TABS {CHECKBOX, OPTION_BUTTON, SPINBOX, FILE_DIR_LINE_EDIT, COLOR_PICKER} # needs to be same order as the children in scenetree dock
enum TEXT_EDITORS {LINE_EDIT, TEXT_EDIT}
# impletmented hints; otherwise the hint just gets set as a label.text
const HINTS = [PROPERTY_HINT_NONE, PROPERTY_HINT_RANGE, PROPERTY_HINT_ENUM, PROPERTY_HINT_FILE, PROPERTY_HINT_DIR, PROPERTY_HINT_GLOBAL_FILE, PROPERTY_HINT_GLOBAL_DIR, PROPERTY_HINT_MULTILINE_TEXT] 
	
var curr_setting # ProjectSettings or EditorSetting objects
var screen_factor = max(OS.get_screen_dpi() / 100, 1)

func _ready() -> void:
	open_file_dir_button.icon = get_icon("Folder", "EditorIcons")


func _unhandled_key_input(event: InputEventKey) -> void:
	if visible:
		get_tree().set_input_as_handled()


# called by CommandPalette.gd
func _show(setting : Dictionary, source : String = "Editor_Settings", SETTINGS = null) -> void:
	var setting_path = setting.name
	curr_setting = SETTINGS
	
	window_title = source.capitalize()
	path_label.text = setting_path
	hint_label.get_parent().visible = false
	hint_label.text = ""
	
	tabs.size_flags_vertical = 6 # one line for everything except TextEdit
	match setting.hint:
		PROPERTY_HINT_ENUM:
			tabs.current_tab = TABS.OPTION_BUTTON
			option_button.clear()
			var counter = 0
			for item in setting.hint_string.split(","):
				item = item.strip_edges()
				option_button.add_item(item)
				if setting.type == TYPE_STRING:
					if item == SETTINGS.get_setting(setting_path):
						option_button.select(option_button.get_item_count() - 1)
				
				elif setting.type == TYPE_INT:
					if counter == SETTINGS.get_setting(setting_path):
						option_button.select(option_button.get_item_count() - 1)
					counter += 1
		
		PROPERTY_HINT_GLOBAL_FILE, PROPERTY_HINT_FILE:
			tabs.current_tab = TABS.FILE_DIR_LINE_EDIT
			text_editors.current_tab = TEXT_EDITORS.LINE_EDIT
			open_file_dir_button.visible = true
			file_dialog.clear_filters()
			file_dialog.mode = FileDialog.MODE_OPEN_FILE
			file_dialog.access = FileDialog.ACCESS_FILESYSTEM if setting.hint == PROPERTY_HINT_GLOBAL_FILE else FileDialog.ACCESS_RESOURCES
			text_editors.get_current_tab_control().text = SETTINGS.get_setting(setting_path)
			if setting.hint_string:
				for filter in setting.hint_string.split(","):
					file_dialog.add_filter("%s ; %s" % [filter.strip_edges(), filter.strip_edges()])
		
		PROPERTY_HINT_GLOBAL_DIR, PROPERTY_HINT_DIR:
			tabs.current_tab = TABS.FILE_DIR_LINE_EDIT
			text_editors.current_tab = TEXT_EDITORS.LINE_EDIT
			open_file_dir_button.visible = true
			file_dialog.clear_filters()
			file_dialog.mode = FileDialog.MODE_OPEN_DIR
			file_dialog.access = FileDialog.ACCESS_FILESYSTEM if setting.hint == PROPERTY_HINT_GLOBAL_DIR else FileDialog.ACCESS_RESOURCES
			text_editors.get_current_tab_control().text = SETTINGS.get_setting(setting_path)
		
		PROPERTY_HINT_MULTILINE_TEXT:
			tabs.current_tab = TABS.FILE_DIR_LINE_EDIT
			text_editors.current_tab = TEXT_EDITORS.TEXT_EDIT
			tabs.size_flags_vertical = 7 # one line for everything except TextEdit
			open_file_dir_button.visible = false
			text_editors.get_current_tab_control().text = SETTINGS.get_setting(setting_path)
		
		PROPERTY_HINT_COLOR_NO_ALPHA:
			tabs.current_tab = TABS.COLOR_PICKER
			colorpicker.edit_alpha = false
			colorpicker.color = SETTINGS.get_setting(setting_path)
		
		_:
			match setting.type:
				TYPE_BOOL:
					tabs.current_tab = TABS.CHECKBOX
					checkbox.pressed = SETTINGS.get_setting(setting_path)
				
				TYPE_INT, TYPE_REAL:
					tabs.current_tab = TABS.SPINBOX
					spinbox.value = SETTINGS.get_setting(setting_path)
					spinbox.allow_greater = false
					spinbox.allow_lesser = false
					spinbox.min_value = -9999999999
					spinbox.max_value = 9999999999
					spinbox.step = 0.01
					if setting.hint == PROPERTY_HINT_RANGE:
						var possible_hints = ["min_value", "max_value", "step", "or_greater", "or_lesser"]
						for hint in setting.hint_string.split(","):
							hint = hint.strip_edges()
							var property = possible_hints.pop_front()
							if not hint.is_valid_float(): # min/max are the only ones guaranteed, but order of possible hints is known
								while hint != property:
									property = possible_hints.pop_front()
								if property == "or_greater":
									spinbox.allow_greater = true
								elif property == "or_lesser":
									spinbox.allow_lesser = true
							spinbox.set(property, hint as float)
				
				TYPE_STRING:
					tabs.current_tab = TABS.FILE_DIR_LINE_EDIT
					text_editors.current_tab = TEXT_EDITORS.LINE_EDIT
					open_file_dir_button.visible = false
					text_editors.get_current_tab_control().text = SETTINGS.get_setting(setting_path)
				
				TYPE_VECTOR2:
					pass
				
				TYPE_RECT2:
					pass
				
				TYPE_VECTOR3:
					pass
				
				TYPE_TRANSFORM2D:
					pass
				
				TYPE_PLANE:
					pass
				
				TYPE_QUAT:
					pass
				
				TYPE_AABB:
					pass
				
				TYPE_BASIS:
					pass
				
				TYPE_TRANSFORM:
					pass
				
				TYPE_COLOR: 
					tabs.current_tab = TABS.COLOR_PICKER
					colorpicker.edit_alpha = true
					colorpicker.color = SETTINGS.get_setting(setting_path)
				
				TYPE_NODE_PATH:
					pass
				
				TYPE_RID:
					pass
				
				TYPE_OBJECT: #resource
					pass
				
				TYPE_DICTIONARY:
					pass
				
				TYPE_ARRAY:
					pass
				
				TYPE_RAW_ARRAY:
					pass
				
				TYPE_INT_ARRAY:
					pass
				
				TYPE_REAL_ARRAY:
					pass
				
				TYPE_STRING_ARRAY:
					pass
				
				TYPE_VECTOR2_ARRAY:
					pass
				
				TYPE_VECTOR3_ARRAY:
					pass
				
				TYPE_COLOR_ARRAY:
					pass
	
	# TOFIXME spinbox cant grab focus for some reason, needs to be tabbed to
	tabs.get_current_tab_control().call_deferred("grab_focus")
	
	if setting.usage & PROPERTY_USAGE_RESTART_IF_CHANGED:
		hint_label.get_parent().visible = true
		hint_label.text = "Changes require a restart of Godot.\n"
	
	if not setting.hint in HINTS or (not setting.hint and setting.hint_string):
		hint_label.get_parent().visible = true
		hint_label.text += "Hint: %s" % (setting.hint_string if setting.hint_string else "PropertyHint = %s" % setting.hint)
	
	popup_centered(Vector2(max(setting.name.length() * 10, 350), 250) * screen_factor)


func _get_current_tab_value():
	var curr = tabs.get_current_tab_control()
	
	if curr is CheckBox:
		return curr.pressed
	elif curr is OptionButton:
		return curr.text if curr_setting.get_setting(path_label.text) is String else curr.selected
	elif curr is SpinBox:
		return curr.value
	elif curr is HBoxContainer: # File, Folder, or String setting
		return text_editors.get_current_tab_control().text
	elif curr is ColorPickerButton:
		return curr.color


func _on_FileDirLineEdit_focus_entered() -> void:
	text_editors.get_current_tab_control().grab_focus()


func _on_FileDirButton_pressed() -> void:
	file_dialog.popup_centered(Vector2(700, 700))


func _on_FileDialog_dir_selected(dir: String) -> void:
	text_editors.get_current_tab_control().text = dir


func _on_FileDialog_file_selected(path: String) -> void:
	text_editors.get_current_tab_control().text = path


func _on_CancelButton_pressed() -> void:
	hide()


func _on_AcceptButton_pressed() -> void:
	var new_val = _get_current_tab_value()
	if curr_setting.get_setting(path_label.text) != new_val:
		curr_setting.set_setting(path_label.text, new_val)
	hide()
	get_parent().hide()


func _on_SettingsSetter_popup_hide() -> void:
	get_parent().filter.grab_focus()
