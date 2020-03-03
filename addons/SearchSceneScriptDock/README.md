# SearchScriptScenePlugin
This plugin for the Godot game engine (3.2.X) adds a global keyboard shortcut to access a list of all open scripts and scenes which can be filtered by a search_string.

After activation of the plugin reopen the project (only needed to do upon enabling the plugin the first time).


Features:

Pressing Ctrl+E opens a popup, which lists all open scenes and scripts.
The file names are preceded by a line number and followed by their respective file location.
Ending the search_string with \" X\", where X is an interger, jumps to that line in the list.
Starting the search-string with \"c \" (as in code) filters the open scripts.
Starting the search-string with \"s \" (as in scene) filters the open scenes.

(The filter only applies to the actual file name, so you won't get flooded with search results)
