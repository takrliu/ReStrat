-----------------------------------------------------------------------------
--System Daemons, Reglitch's Profile
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
--Encounter Logic
-----------------------------------------------------------------------------

--Binary Daemon
local function binaryInit(unit)
	local binary = "Binary System Daemon";

	-----------------------------
	--Initial Timers
	-----------------------------
	-- Add a new add wave with probes tossed in.
	ReStrat.tEncounterVariables.addwaves = function()
		ReStrat:createAlert("Probe 1 Spawn", 10, nil, ReStrat.color.yellow, function()
			ReStrat:createAlert("Probe 2 Spawn", 10, nil, ReStrat.color.yellow, function()
				ReStrat:createAlert("Probe 3 Spawn", 10, nil, ReStrat.color.yellow, nil)
			end)
		end)
		ReStrat:createAlert("Next Add Wave", 50, nil, ReStrat.color.orange, ReStrat.tEncounterVariables.addwaves)
	end

	-- Disconnect
	local disconnect = function() ReStrat:createAlert("Next Disconnect", 60, nil, ReStrat.color.purple, nil) end;

	ReStrat:createAlert("Next Add Wave", 15, nil, ReStrat.color.orange, ReStrat.tEncounterVariables.addwaves)
	ReStrat:createAlert("Next Disconnect", 45, nil, ReStrat.color.purple, nil)

	-----------------------------
	--Health Bars
	-----------------------------

	ReStrat:createHealth("North Daemon", unit, 1, nil, nil)

	-----------------------------
	--Datachron Hooks
	-----------------------------
	local phaseTwo = function()
		for i=1, #ReStrat.tAlerts do
			ReStrat.tAlerts[i].alert:Destroy();
		end

		ReStrat.tAlerts = {};


		ReStrat:createAlert("Next Add Wave", 95, nil, ReStrat.color.orange, ReStrat.tEncounterVariables.addwaves)
		ReStrat:createAlert("Next Disconnect", 87, nil, ReStrat.color.white, nil)
	end

	ReStrat:OnDatachron("COMMENCING ENHANCEMENT SEQUENCE.", phaseTwo);


	-----------------------------
	--Binary Casts
	-----------------------------
	--Next purge
	local nextpurge = function() ReStrat:createAlert("[SOUTH] Purge Next", 16, nil, ReStrat.color.blue, nil) end

	ReStrat:createCastAlert(binary, "Purge", nil, "Icon_SkillMisc_UI_srcr_frecho", ReStrat.color.red, nextpurge);
	ReStrat:createCastAlert(binary, "Disconnect", nil, nil, ReStrat.color.purple, disconnect);
end

--Null Daemon
local function nullInit(unit)
	local null = "Null System Daemon";

	-----------------------------
	--Health Bars
	-----------------------------

	ReStrat:createHealth("South Daemon", unit, 1, nil, nil)

	-----------------------------
	--Null Casts
	-----------------------------

	--Next purge
	local nextpurge = function() ReStrat:createAlert("[NORTH] Purge Next", 16, nil, ReStrat.color.blue, nil) end

	-- Disconnect
	local disconnect = function() ReStrat:createAlert("Next Disconnect", 60, nil, ReStrat.color.purple, nil) end;

	ReStrat:createCastAlert(null, "Purge", nil, "Icon_SkillMisc_UI_srcr_frecho", ReStrat.color.red, nextpurge);
	ReStrat:createCastAlert(null, "Disconnect", nil, nil, ReStrat.color.black, disconnect);
end

--Defragmentation Unit
local function defragInit()
	defrag = "Defragmentation Unit";

	ReStrat:createCastAlert(defrag, "Black IC", nil, "Icon_SkillMisc_UI_m_enrgypls", ReStrat.color.red, nil);
	ReStrat:createCastAlert(defrag, "Defrag", nil, "Icon_SkillMedic_magneticlockdown", ReStrat.color.red, nil);
end

-----------------------------------------------------------------------------
--Encounter Packaging
-----------------------------------------------------------------------------
if not ReStrat.tEncounters then
	ReStrat.tEncounters = {}
end

--Profile Settings
ReStrat.tEncounters["Binary System Daemon"] = {
	fInitFunction = binaryInit,
	strCategory  = "Datascape",
	tModules = {
		["Purge"] = {
			strLabel = "Purge",
			bEnabled = true,
		},
		["Disconnect"] = {
			strLabel = "Disconnect",
			bEnabled = true,
		},
	}
}

ReStrat.tEncounters["Null System Daemon"] = {
	fInitFunction = nullInit,
	strCategory  = "Datascape",
	tModules = {
		["Purge"] = {
			strLabel = "Purge",
			bEnabled = true,
		},
		["Disconnect"] = {
			strLabel = "Disconnect",
			bEnabled = true,
		},
	}
}

ReStrat.tEncounters["Defragmentation Unit"] = {
	fInitFunction = defragInit,
	strCategory  = "Datascape",
	tModules = {
		["Black IC"] = {
			strLabel = "Black IC",
			bEnabled = true,
		},
		["Defrag"] = {
			strLabel = "Defrag",
			bEnabled = true,
		},
	}
}


