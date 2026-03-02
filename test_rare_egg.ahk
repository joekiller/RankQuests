#Requires AutoHotkey v2.0
#Include "Lib/JXON.ahk"
#Include "Modules/Zones.ahk"

FileAppend("Initializing Zones...`n", "*")
initializeZones()

FileAppend("BEST_ZONE: " BEST_ZONE "`n", "*")
FileAppend("SECOND_BEST_ZONE: " SECOND_BEST_ZONE "`n", "*")
FileAppend("RARE_EGG_ZONE: " RARE_EGG_ZONE "`n", "*")
