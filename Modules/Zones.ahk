#Requires AutoHotkey v2.0

; ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
; ZONE CONFIGURATION FILE
; ----------------------------------------------------------------------------------------
; This file is used to map all games ZONE number to ZONE names.
; ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰

; ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
; ZONE PROPERTIES & INITIALISATION
; ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰

global ZONE := Map()
ZONE.Default := "?"

global BEST_ZONE := 0
global SECOND_BEST_ZONE := 0
global RARE_EGG_ZONE := 0

fetchAPICollection(collectionName) {
    url := "https://biggamesapi.io/api/collection/" collectionName
    jsonString := ""
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", url, true)
        req.Send()
        req.WaitForResponse()
        if (req.Status == 200) {
            jsonString := req.ResponseText
        }
    } catch {
        return ""
    }
    return jsonString
}

initializeZones() {
    global ZONE, BEST_ZONE, SECOND_BEST_ZONE, RARE_EGG_ZONE

    iniFile := A_ScriptDir "\ZonesCache.ini"
    zonesJsonFile := A_ScriptDir "\Zones.json"

    ; 1. Pull Zones from API
    zonesRaw := fetchAPICollection("Zones")

    if (zonesRaw == "") {
        ; Fallback to disk if no internet
        if FileExist(zonesJsonFile)
            zonesRaw := FileRead(zonesJsonFile, "UTF-8")
        else
            return
    } else {
        ; Save latest zones raw
        if FileExist(zonesJsonFile)
            FileDelete(zonesJsonFile)
        FileAppend(zonesRaw, zonesJsonFile, "UTF-8")
    }

    try {
        zonesData := Jxon_Load(&zonesRaw)
        if (!zonesData.Has("data")) {
            return
        }

        maxZone := 0
        maxEgg := 0

        ; Extract zones and build map
        for index, item in zonesData["data"] {
            if (!item.Has("configData")) {
                continue
            }
            cd := item["configData"]

            if (cd.Has("ZoneNumber") && cd.Has("ZoneName")) {
                zNum := cd["ZoneNumber"]
                ZONE[zNum] := cd["ZoneName"]
                if (zNum > maxZone)
                    maxZone := zNum
            }
            if (cd.Has("MaximumAvailableEgg")) {
                if (cd["MaximumAvailableEgg"] > maxEgg)
                    maxEgg := cd["MaximumAvailableEgg"]
            }
        }

        BEST_ZONE := maxZone
        SECOND_BEST_ZONE := maxZone - 1

        ; 2. Check Cache for RARE_EGG_ZONE to prevent multi-megabyte parsing
        cachedMaxEgg := 0
        if FileExist(iniFile) {
            cachedMaxEgg := IniRead(iniFile, "Cache", "MaxEgg", 0)
            RARE_EGG_ZONE := IniRead(iniFile, "Cache", "RareEggZone", 0)
        }

        if (cachedMaxEgg == maxEgg && RARE_EGG_ZONE != 0) {
            return ; We are completely cached up to date.
        }

        ; 3. If new egg update happened, parse the heavy Pets and Eggs collections
        eggsRaw := fetchAPICollection("Eggs")
        petsRaw := fetchAPICollection("Pets")

        if (eggsRaw == "" || petsRaw == "") {
            return
        }

        eggsData := Jxon_Load(&eggsRaw)
        petsData := Jxon_Load(&petsRaw)

        ; Build Pets Map for quick O(1) lookup
        petsMap := Map()
        for i, pet in petsData["data"] {
            petsMap[pet["configName"]] := pet["configData"]
        }

        highestRareZone := 0

        ; Search backwards from highest zone down for efficiency
        for i, zoneItem in zonesData["data"] {
            cd := zoneItem["configData"]
            if (!cd.Has("WorldNumber") || cd["WorldNumber"] != 4) {
                continue
            }
            if (!cd.Has("MaximumAvailableEgg") || !cd.Has("ZoneNumber")) {
                continue
            }

            eggTarget := cd["MaximumAvailableEgg"]
            zoneTarget := cd["ZoneNumber"]

            ; Find the egg
            foundEgg := ""
            for j, eggItem in eggsData["data"] {
                if (eggItem["configData"].Has("EggNumber") && eggItem["configData"]["EggNumber"] == eggTarget) {
                    foundEgg := eggItem
                    break
                }
                if (InStr(eggItem["configName"], eggTarget " |") == 1) {
                    foundEgg := eggItem
                    break
                }
            }

            if (foundEgg == "") {
                continue
            }

            hasRare := false
            eggPets := foundEgg["configData"].Has("pets") ? foundEgg["configData"]["pets"] : []

            for k, petDrop in eggPets {
                pName := petDrop[1] ; Note Jxon maps JSON arrays to 1-indexed AHK arrays
                if (petsMap.Has(pName)) {
                    pData := petsMap[pName]

                    isHuge := false
                    if (pData.Has("huge") && pData["huge"] == true)
                        isHuge := true
                    if (InStr(pName, "Huge") == 1)
                        isHuge := true

                    rarityName := ""
                    if (pData.Has("rarity")) {
                        r := pData["rarity"]
                        if (r.Has("_id"))
                            rarityName := r["_id"]
                        else if (r.Has("DisplayName"))
                            rarityName := r["DisplayName"]
                    }

                    if (!isHuge && rarityName == "Rare") {
                        hasRare := true
                        break
                    }
                }
            }

            if (hasRare && zoneTarget > highestRareZone && zoneTarget < maxZone) {
                highestRareZone := zoneTarget
            }
        }

        if (highestRareZone != 0) {
            RARE_EGG_ZONE := highestRareZone
            IniWrite(maxEgg, iniFile, "Cache", "MaxEgg")
            IniWrite(highestRareZone, iniFile, "Cache", "RareEggZone")
        }

    } catch as err {
        MsgBox("Failed to initialize Zones from API: " err.Message)
    }
}

initializeZones()