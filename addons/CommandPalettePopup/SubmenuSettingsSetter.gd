tool
extends WindowDialog


onready var path_label = $VBoxContainer/PathLabel
onready var hint_label = $VBoxContainer/MarginContainer3/HintLabel
onready var tabs = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer
enum TABS {CHECKBOX, OPTION_BUTTON, SPIN_BOX, FILE_FOLDER_LINE_EDIT, COLOR_PICKER}
onready var checkbox = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer/CheckBox
onready var optionbutton = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer/OptionButton
onready var spinbox = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer/SpinBox
onready var file_dialog = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer/FileFolderLineEdit/FileDialog
onready var line_edit = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer/FileFolderLineEdit/LineEdit
onready var line_button = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer/FileFolderLineEdit/ToolButton
onready var line_hbox = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer/FileFolderLineEdit
onready var colorpicker = $VBoxContainer/MarginContainer2/VBoxContainer/TabContainer/ColorPickerButton
onready var cancel_button = $VBoxContainer/MarginContainer/HBoxContainer/CancelButton
onready var accept_button = $VBoxContainer/MarginContainer/HBoxContainer/AcceptButton

var curr_setting


func _ready() -> void:
	line_button.icon = get_icon("Folder", "EditorIcons")
	cancel_button.connect("pressed", self, "_on_CancelButton_pressed")
	accept_button.connect("pressed", self, "_on_AcceptButton_pressed")
	line_button.connect("pressed", self, "_on_open_file_button_pressed")


func _unhandled_key_input(event: InputEventKey) -> void:
	if visible:
		get_tree().set_input_as_handled()


# called by CommandPalette.gd
func _show(setting : Dictionary, source : String = "Editor_Settings", SETTINGS = null) -> void:
	var setting_path = setting.name
	curr_setting = SETTINGS
	
	window_title = source.capitalize()
	path_label.text = setting_path
	hint_label.text = ""
	hint_label.get_parent().visible = false
	
	if setting.hint == PROPERTY_HINT_ENUM and not setting.type == TYPE_STRING:
			tabs.current_tab = TABS.OPTION_BUTTON 
			optionbutton.clear()
			var counter = 0
			for item in setting.hint_string.split(","):
				optionbutton.add_item(item)
				if counter == SETTINGS.get_setting(setting_path):
					optionbutton.select(optionbutton.get_item_count() - 1)
				counter += 1
	else:
		match setting.type:
			TYPE_BOOL:
				tabs.current_tab = TABS.CHECKBOX
				checkbox.pressed = SETTINGS.get_setting(setting_path)
			
			TYPE_INT:
				tabs.current_tab = TABS.SPIN_BOX
				var tmp = ["min_value", "max_value", "step"]
				if setting.hint == PROPERTY_HINT_RANGE:
					for val in setting.hint_string.split(","):
						if tmp.empty():
							break
						var property = tmp.pop_front()
						spinbox.set(property, val.strip_edges() as float)
				spinbox.value = SETTINGS.get_setting(setting_path)
			
			TYPE_REAL:
				tabs.current_tab = TABS.SPIN_BOX 
				var tmp = ["min_value", "max_value", "step"]
				if setting.hint == PROPERTY_HINT_RANGE:
					for val in setting.hint_string.split(","):
						if tmp.empty():
							break
						var property = tmp.pop_front()
						spinbox.set(property, val.strip_edges() as float)
				spinbox.value = SETTINGS.get_setting(setting_path)
			
			TYPE_STRING:
				line_button.visible = false
				
				if setting.hint == PROPERTY_HINT_ENUM:
					tabs.current_tab = TABS.OPTION_BUTTON 
					optionbutton.clear()
					for item in setting.hint_string.split(","):
						optionbutton.add_item(item)
						if item == SETTINGS.get_setting(setting_path):
							optionbutton.select(optionbutton.get_item_count() - 1)
				
				elif setting.hint == PROPERTY_HINT_GLOBAL_FILE:
					tabs.current_tab = TABS.FILE_FOLDER_LINE_EDIT
					file_dialog.mode = FileDialog.MODE_OPEN_FILE
					file_dialog.clear_filters()
					line_button.visible = true
					line_edit.text = SETTINGS.get_setting(setting_path)
					if setting.hint_string:
						for filter in setting.hint_string.split(","):
							file_dialog.add_filter("%s ; %s" % [filter.strip_edges(), filter.strip_edges()])
				
				elif setting.hint == PROPERTY_HINT_GLOBAL_DIR:
					tabs.current_tab = TABS.FILE_FOLDER_LINE_EDIT
					file_dialog.mode = FileDialog.MODE_OPEN_DIR
					file_dialog.clear_filters()
					line_button.visible = true
					line_edit.text = SETTINGS.get_setting(setting_path)
				
				else:
					tabs.current_tab = TABS.FILE_FOLDER_LINE_EDIT
					line_edit.text = SETTINGS.get_setting(setting_path)
			
			TYPE_COLOR:
				tabs.current_tab = TABS.COLOR_PICKER
				colorpicker.color = SETTINGS.get_setting(setting_path)
			
			_:
				push_warning("Command Palette Plugin: Type of the setting not yet implemented. %s" % setting)
				return
	# spinbox cant grab focus for some reason
	tabs.get_current_tab_control().call_deferred("grab_focus") if tabs.current_tab != TABS.FILE_FOLDER_LINE_EDIT else line_edit.call_deferred("grab_focus")
	if setting.hint and not setting.hint in [PROPERTY_HINT_ENUM, PROPERTY_HINT_GLOBAL_DIR, PROPERTY_HINT_GLOBAL_FILE]:
		hint_label.text = "Hint: " + setting.hint_string
		hint_label.get_parent().visible = true
		
	if setting.hint_string and not setting.hint in [PROPERTY_HINT_ENUM, PROPERTY_HINT_RANGE, PROPERTY_HINT_GLOBAL_FILE, PROPERTY_HINT_GLOBAL_DIR]:
		push_warning("Command Palette Plugin: No hint for this setting implemented yet.")
	
	popup_centered(Vector2(max(setting.name.length() * 10, 350), 250))


func _on_open_file_button_pressed() -> void:
	file_dialog.popup_centered(Vector2(700, 700))


func _on_CancelButton_pressed() -> void:
	hide()


func _on_AcceptButton_pressed() -> void:
	var new_val = _get_current_tab_value()
	if curr_setting.get_setting(path_label.text) != new_val:
		curr_setting.set_setting(path_label.text, new_val)
	hide()


func _get_current_tab_value():
	var curr = tabs.get_current_tab_control()
	
	if curr is CheckBox:
		return curr.pressed
	elif curr is OptionButton:
		return curr.text
	elif curr is SpinBox:
		return curr.value
	elif curr is HBoxContainer:
		return line_edit.text
	elif curr is ColorPickerButton:
		return curr.color
	else:
		push_warning("Command Palette Plugin: SubmenuSetting.gd line 160+")


func _on_FileDialog_dir_selected(dir: String) -> void:
	line_edit.text = dir


func _on_FileDialog_file_selected(path: String) -> void:
	line_edit.text = path
