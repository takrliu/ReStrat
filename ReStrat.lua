-----------------------------------------------------------------------------------------------
-- Client Lua Script for ReStrat
-- Copyright (c) NCsoft. All rights reserved
-- Created by Ryan Park, aka Reglitch of Codex
-----------------------------------------------------------------------------------------------

require "Apollo"
require "Window"
require "Sound"

local ReStrat = {}

-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------

local BAR_SPACING = 4
local DEBUG = false

local COMMANDS = "--ReStrat Commands--\n\
/rs help - list of commands\n\
/rs or /rs setting - Settings list\n\
/pull NUM - Start a pull timer\
/break NUM - Length of a break in seconds.\
/break end - Ends break timer early\
/buff all|flask|pot|food - Print name of mesmebers not there or without a buff.\
/speed - Remind guildies to get a speed flask! \
"

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function ReStrat:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function ReStrat:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end


-----------------------------------------------------------------------------------------------
-- ReStrat OnLoad
-----------------------------------------------------------------------------------------------
function ReStrat:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("ReStrat.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	Apollo.LoadSprites("respr.xml", "SassyMedicSimSprites")
	self.lcf = 	Apollo.GetPackage("LibCombatLogFixes-1.0").tPackage;
end

-----------------------------------------------------------------------------------------------
-- ReStrat OnDocLoaded
-----------------------------------------------------------------------------------------------
function ReStrat:OnDocLoaded()


	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
		self.wndMain     = Apollo.LoadForm(self.xmlDoc, "mainForm", nil, self);
	  self.wndAlerts   = Apollo.LoadForm(self.xmlDoc, "alertForm", nil, self);
		self.wndHealths  = Apollo.LoadForm(self.xmlDoc, "healthForm", nil, self);
		self.wndPop      = Apollo.LoadForm(self.xmlDoc, "popForm", nil, self);
		self.wndIcon     = Apollo.LoadForm(self.xmlDoc, "iconForm", nil, self);
		self.wndLog      = Apollo.LoadForm(self.xmlDoc, "logForm", nil, self);
		self.wndSettings = Apollo.LoadForm(self.xmlDoc, "settingsForm", nil, self);



	  self.wndMain:Show(false, true)
		self.wndIcon:Show(false, true)
		self.wndLog:Show(false, true)
		self.wndSettings:Show(false, true)

		-- Register handlers for events, slash commands and timer, etc.
		Apollo.RegisterSlashCommand("restrat", "OnReStratOn", self)
		Apollo.RegisterSlashCommand("rs", "OnReStratOn", self)
		Apollo.RegisterSlashCommand("pull", "OnPull", self)
		Apollo.RegisterSlashCommand("break", "OnBreak", self)
		Apollo.RegisterSlashCommand("buff", "OnBuff", self)
		Apollo.RegisterSlashCommand("speed", "OnSpeed", self)

		Apollo.RegisterEventHandler("UnitCreated", "OnUnitCreated", self)
		Apollo.RegisterEventHandler("UnitDestroyed", "OnUnitDestroyed", self)
		Apollo.RegisterEventHandler("UnitEnteredCombat", "OnEnteredCombat", self)
		Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
		--Apollo.RegisterEventHandler("ChatMessage", "OnChatMessage", self)
		Apollo.RegisterEventHandler("PublicEventObjectiveUpdate", "OnPublicEvent", self)

		--[[
		Register LCLF events
		_LCLF_SpellAuraApplied(intSpellId, intStackCount, tTargetUnit)
		_LCLF_SpellAuraAppliedDose(intSpellId, intStackCount, tTargetUnit)
		_LCLF_SpellAuraRemoved(intSpellId, intStackCount, tTargetUnit)
		_LCLF_SpellAuraRemovedDose(intSpellId, intStackCount, tTargetUnit)
		_LCLF_SpellCastStart(strSpellName, tCasterUnit)
		_LCLF_SpellCastSuccess(strSpellName, tCasterUnit)
		]]--
		Apollo.RegisterEventHandler("_LCLF_SpellAuraApplied", "OnAuraApplied", self);
		Apollo.RegisterEventHandler("_LCLF_SpellAuraAppliedDose", "OnAuraStackAdded", self);
		Apollo.RegisterEventHandler("_LCLF_SpellAuraRemoved", "OnAuraRemoved", self);
		Apollo.RegisterEventHandler("_LCLF_SpellAuraRemovedDose", "OnAuraStackRemoved", self);
		Apollo.RegisterEventHandler("_LCLF_SpellCastStart", "OnCastStart", self);


		--Color library, can't be stored in constants
		self.color = {
			red = "ffb8413d",
			orange = "ffdd7649",
			yellow = "fff8fd6b",
			green = "ff58cc5d",
			blue = "ff5196ec",
			purple = "ff915fc2",
			black = "black",
			white = "white",
		}

		--This timer drives alerts exclusively, in game checks are fired on a seperate timer
		self.alertTimer = ApolloTimer.Create(0.1, true, "OnAlarmTick", self);
		self.alertTimer:Stop();

		--This timer drives alerts exclusively, in game checks are fired on a seperate timer
		self.healthTimer = ApolloTimer.Create(0.25, true, "OnHealthTick", self);
		self.healthTimer:Stop();

		--This timer drives in game logging and event handling
		self.gameTimer = ApolloTimer.Create(0.1, true, "OnGameTick", self);
		self.gameTimer:Stop();

		--This time drives pop appearances
		self.popTimer = ApolloTimer.Create(0.75, true, "OnPopTick", self);
		self.popTimer:Stop();

		--Drives pull itmers
		self.pullTimer = ApolloTimer.Create(1, true, "OnPullTimer", self);
		self.pullTimer:Stop();

		--Drives getting buffs
		self.buffTimer = ApolloTimer.Create(.05, true, "OnBuffTimer", self);
		self.buffTimer:Stop();

		--Variables, tables, etc.
		self.tAlerts = {};
		self.tHealths = {};
		self.tUnits = {};
		self.bInCombat = false;
		self.fPopCallback = nil;
		self.bPopTicked = false;
		self.tWatchedCasts = {};
		self.tWatchedAuras = {};
		self.tZones = {};
		self.combatTimer = nil;
		self.combatStarted = nil;
		self.combatLog = {};
		self.tSpellTriggers = {};
		self.tAuraCache = {};
		self.tPins = {};
		self.tPinAuras = {};
		self.tEncounterVariables = {};
		self.tDatachron = {};
		self.tLandmarks = {};

		--If we haven't initiated encounters
		if not self.tEncounters then
			self.tEncounters = {}
		end

		if not self.tPublicEvents then
			self.tPublicEvents = {}
		end

		--If this is our first time loading in
		if not self.tSettings then
			self.tSettings = {
				combatlog = { auras = true, casts = true, enemyauras = true, enemycasts = true }
			}
		end

		if DEBUG then self:HookCombatLog() end --this is hella performance intensive
		self.bLoaded = false;
	end
end

-----------------------------------------------------------------------------------------------
-- ReStrat Functions
-----------------------------------------------------------------------------------------------
--Add windows to carbines window management
function ReStrat:OnWindowManagementReady()
	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndAlerts, strName = "reStratAlert"})
	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndHealths, strName = "reStratHealth"})
	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndPop, strName = "ReStratPop"})
end

--Save data between sessions
function ReStrat:OnSave(eLevel)
  if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
    return nil
  end

  local tSavedData = { }

	-- TODO save between session enabled? Is this just o allow reload in combat or what? I don't understand.
  tSavedData = {
     encounters = self.tEncounters;
  }

  return tSavedData
end

-- TODO
--Restore data on session
function ReStrat:OnRestore(eType, savedData)
		local encounterCache = nil;

		if true then return end

		if self.tEncounters then
			encounterCache = self.tEncounters;
		end

		if savedData.encounters then
			self.tEncounters = savedData.encounters;

			if encounterCache then
				for k,v in pairs(encounterCache) do
					local newEntry = true;

					for q,t in pairs(self.tEncounters) do
						if k == q then newEntry = false end
					end

					if newEntry then
						self.tEncounters[k] = v;
					end
				end
			end

			--Functions can't be stored between sessions, retrieve from cache
			for k,v in pairs(self.tEncounters) do
				self.tEncounters[k].fInitFunction = encounterCache[k].fInitFunction;
				self.tEncounters[k].fSpamFunction = encounterCache[k].fSpamFunction;
			end
		else
			self.tEncounters = {}
		end
end

--On Game Tick
function ReStrat:OnGameTick()
	if self.bInCombat then
		self:UpdateCombatTime();
	end
end

--Update time in combat
function ReStrat:UpdateCombatTime()
	self.combatTimer = round(GameLib.GetGameTime() - self.combatStarted,2);
end


--If the unit is in tEncounters
function ReStrat:isWatchedUnit(unit)
	for k,v in pairs(self.tEncounters) do
		if unit:GetName() == k then
			return true;
		end
	end
end

--Initiate a unit
function ReStrat:initUnit(unit)
	self.tEncounters[unit:GetName()].fInitFunction(unit); --Initiate pull function
end

--Here to add the unit back if it's created in combat
function ReStrat:OnUnitCreated(unit)
	if not self.bInCombat then return end

	--Check if unit exists in our library
	for i=1, #self.tUnits do while(1) do
		if self.tUnits[i] then break end
		if self.tUnits[i].id == unit:GetId() then
			self.tUnits[i].unit = unit;
			return
		end
	break end end
end

function ReStrat:OnUnitDestroyed(unit)
	--Check if unit exists in our library
	for i,v in ipairs(self.tUnits) do
		if self.tUnits[i].id == unit:GetId() then
			--Since the unit has been destroyed we set it to non active and remove unit reference
			self.tUnits[i].bActive = false;
			self.tUnits[i].unit = nil;

			return
		end
	end
end

function ReStrat:OnPublicEvent(event)
	if not self:isWatchedPublicEvent(event) then return end -- TODO add it to debugging stuff?
	--Print(event:GetShortDescription() .. " - " .. event:GetRequiredCount() .. " - " .. event:GetObjectiveId() )

	local eventBar = self:GetHealths(event:GetShortDescription())

	-- If the bar is already available, update it. Otherwise make it.
	if eventBar then
		self:OnHealthEvent("PublicEventObjectiveUpdate",event,eventBar)
	else
		self:initPubEvent(event)
	end
end


--If the unit is in tEncounters
function ReStrat:isWatchedPublicEvent(event)
	for k,v in pairs(self.tPublicEvents) do
		if event:GetObjectiveId() == k then
			return true;
		end
	end
end

--Initiate a public Event
function ReStrat:initPubEvent(event)
	self.tPublicEvents[event:GetObjectiveId()].fInitFunction(event); --Initiate pull function
end


function ReStrat:OnEnteredCombat(unit, combat)
	--Is it the player?
	if GameLib.GetPlayerUnit() then
		if unit == GameLib.GetPlayerUnit() then
			if combat then
				--Clear combat log
				self.combatLog = {};

				--Start/stop timers
				self.bInCombat = true;
				self.combatStarted = GameLib.GetGameTime();
				self.alertTimer:Start();
				self.healthTimer:Start();
				self.gameTimer:Start();
				return
			else
				self.wndAlerts:DestroyChildren();
				self.wndHealths:DestroyChildren();
				self.tAlerts = {};
				self.tHealths = {};
				self.tWatchedAuras = {};
				self.tWatchedCasts = {};
				self.tEncounterVariables = {};
				self.tSpellTriggers = {};
				self.tDatachron = {};

				--Destroy pins
				for k,v in pairs(self.tPins) do
					v:Destroy();
				end

				self.tPins = {};

				--Stop/start timers
				self.bInCombat = false;
				self.alertTimer:Stop();
				self.healthTimer:Stop();
				self.gameTimer:Stop();
				return
			end
		end
	end

	--If it's a unit in our watched list
	if self:isWatchedUnit(unit) and combat then
		self:initUnit(unit);
	end

	--Check if we have the unit in our library
	for i,v in ipairs(self.tUnits) do
		if self.tUnits[i].unit == unit then
			return
		end
	end

	--If not then we add it
	self.tUnits[#self.tUnits+1]  = {
			unit = unit,
			name = unit:GetName(),
			id = unit:GetId(),
			health = unit:GetMaxHealth(),
			shield = unit:GetShieldCapacityMax(),
			absorb = unit:GetAbsorptionMax(),
			baseIA = unit:GetInterruptArmorMax(),
			assault = unit:GetAssaultPower(),
			bActive = true
	}
end

--Test arrange function
function ReStrat:arrangeChildren(frm)
	local tChildren = frm:GetChildren()

	for i,v in ipairs(tChildren) do
		local wndHeight = v:GetHeight();
		local wndWidth = v:GetWidth();
		local vOffset = wndHeight*(i-1) + BAR_SPACING+BAR_SPACING*(i-1);

		v:SetAnchorOffsets(-wndWidth/2,vOffset,wndWidth/2,vOffset+wndHeight);
	end
end

--/restrat
function ReStrat:OnReStratOn(msg, cmd)
	if cmd == "setting" or cmd == "" then
		--Show Window
		self.wndMain:Invoke()

		--Init UI
		self:OnInitUI()
	elseif cmd == "help" then
		Print(COMMANDS)
	else
		Print("/rs help for list of commands")
	end
end

--UI Init
function ReStrat:OnInitUI()
	if not self.bLoaded then
		local zoneList = self.wndMain:FindChild("zoneList");

		--Go through our encounters and populate zone list
		for k,v in pairs(self.tEncounters) do
			--Create the list
			if not self.tZones[v.strCategory] then
				self.tZones[v.strCategory] = {};
			end

			table.insert(self.tZones[v.strCategory], k);
		end

		--Create zone buttons
		for k,v in pairs(self.tZones) do
			local btnZone = Apollo.LoadForm(self.xmlDoc, "btnZone", zoneList, self);
			btnZone:SetText(k);
			btnZone:SetData(k);
		end

		self:arrangeChildren(zoneList);

		self.bLoaded = true;
	end
end

function ReStrat:stopTimers()
	self = self or _G["ReStrat"]
	if not self.bInCombat and #self.tAlerts <= 1 then
		self.gameTimer:Stop();
		self.healthTimer:Stop();
		self.alertTimer:Stop();

		self.wndAlerts:DestroyChildren();
		self.wndHealths:DestroyChildren();

		self.tAlerts = {}
		self.tHealths = {}
	end
end

function round(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

-----------------------------------------------------------------------------------------------
-- Public Event Functions
-----------------------------------------------------------------------------------------------

-- Another sort of tracking. Based on public events solely atm but shows up in the health bar tracking.
function ReStrat:createTracker(strLabel, event, persist, strColor, fCallback)
	if not event then return end
	local healthBar = Apollo.LoadForm("ReStrat.xml", "healthInstance", self.wndHealths, self);
	local progressbar = healthBar:FindChild("HealthProgressBarContainer"):FindChild("healthProgressBar");

	local maxVal = event:GetRequiredCount()
	local curVal = event:GetCount()

	--Set bar label
	healthBar:FindChild("HealthProgressBarContainer"):FindChild("bossName"):SetText(strLabel);

	--Set max for pBar
	progressbar:SetMax(maxVal);

	--Set to 0
	progressbar:SetProgress(curVal);

	--Handle optional color
	if not strColor then
		progressbar:SetBarColor(self.color.red);
	else
		progressbar:SetBarColor(strColor);
	end

	--Handle callback function
	if not fCallback then
		fCallback = nil
	end

	--Add to tAlerts
	self.tHealths[#self.tHealths+1] = {health = healthBar, name = strLabel, callback = fCallback, persist = persist, event = event}

	--Arrange vertically
	self:arrangeHealths();
end

-----------------------------------------------------------------------------------------------
-- Health Functions
-----------------------------------------------------------------------------------------------

--On event tick
function ReStrat:OnHealthEvent(eventStr, event, healthsBar)
	if not (event and healthsBar) then return end

	local healthInstance = healthsBar;
	local progressbar = healthInstance.health:FindChild("HealthProgressBarContainer"):FindChild("healthProgressBar");
	local health = healthInstance.health:FindChild("HealthProgressBarContainer"):FindChild("health");
	local healthPercent = healthInstance.health:FindChild("HealthProgressBarContainer"):FindChild("healthPercent");

	local progress = 0
	local sHealthStr = ""
	local sHealthPer = "0%"
	local bExitStatus = false

	-- Can either be a unit or an event. Adjust accordingly.
	if eventStr == "PublicEventObjectiveUpdate" then
		local event = healthInstance.event
		local maxVal = event:GetRequiredCount()
		local curVal = event:GetCount()

		progress = curVal
		sHealthStr = tostring(curVal) .. "/" .. tostring(maxVal);
		sHealthPer = tostring(round((curVal/maxVal)*100,1)) .. "%";

		bExitStatus = (curVal >= maxVal)
	else
		-- Add other event based bars.
		return
	end

	progressbar:SetProgress(progress);

	--Update time, callback if expired
	health:SetText(sHealthStr);
	healthPercent:SetText(sHealthPer);

	if bExitStatus then

		--Execute callback
		if healthInstance.callback then
			healthInstance.callback()
			healthInstance.callback = nil		-- Only want to do the callback once
		end

		if not healthInstance.persist then
			--Close bar
			healthInstance.health:Destroy();

			--Remove from table
			for i=1, #self.tHealths do while(1) do
				if not self.tHealths[i] then break end
				if not self.tHealths[i].name then break end

				if self.tHealths[i].name == healthsBar.name then
					table.remove(self.tHealths, i);
				end
			break end end

			--Reshuffle windows
			self:arrangeHealths();
		end
	end
end

--On healthbar tick
function ReStrat:OnHealthTick()
	if #self.tHealths <= 0 then return end

	--This counts down all health bars registered to self.tHealths
	for i,v in ipairs(self.tHealths) do while(1) do
		local healthInstance = self.tHealths[i];
		local progressbar = healthInstance.health:FindChild("HealthProgressBarContainer"):FindChild("healthProgressBar");
		local health = healthInstance.health:FindChild("HealthProgressBarContainer"):FindChild("health");
		local healthPercent = healthInstance.health:FindChild("HealthProgressBarContainer"):FindChild("healthPercent");

		local progress = 0
		local sHealthStr = ""
		local sHealthPer = "0%"
		local bExitStatus = false

		-- Can either be a unit or an event. Adjust accordingly.
		if healthInstance.unit then
			local unit = healthInstance.unit
			local maxHp = unit:GetMaxHealth()
			local curHp = unit:GetHealth()
			if not (maxHp and curHp) then break end

			progress = curHp
			sHealthStr = tostring(round(curHp/1000,1)) .. "k/" .. tostring(round(maxHp/1000,1)) .. "k";
			sHealthPer = tostring(round((curHp/maxHp)*100,1)) .. "%";

			-- TODO shield?

			bExitStatus = (curHp <= 0)
		-- Can add any other bars to be handled as long as they are time based.
		else

			break
		end
		--[[
		-- don't want to do events
		elseif healthInstance.event then
			local event = healthInstance.event
			local maxVal = event:GetRequiredCount()
			local curVal = event:GetCount()

			progress = curVal
			sHealthStr = tostring(curVal) .. "/" .. tostring(maxVal);
			sHealthPer = tostring(round((curHp/maxHp)*100,1)) .. "%";

			bExitStatus = (curVal >= maxVal)
		end
		--]]



		progressbar:SetProgress(progress);

		--Update time, callback if expired
		health:SetText(sHealthStr);
		healthPercent:SetText(sHealthPer);

		if bExitStatus then

			--Execute callback
			if healthInstance.callback then
				healthInstance.callback()
				healthInstance.callback = nil		-- Only want to do the callback once
			end

			if not healthInstance.persist then
				--Close bar
				healthInstance.health:Destroy();

				--Remove from table
				table.remove(self.tHealths, i);

				--Reshuffle windows
				self:arrangeHealths();
			end
		end
	break end end
end

--Generate health bar
function ReStrat:createHealth(strLabel, unit, persist, strColor, fCallback)
	if not unit then return end
	local healthBar = Apollo.LoadForm("ReStrat.xml", "healthInstance", self.wndHealths, self);
	local progressbar = healthBar:FindChild("HealthProgressBarContainer"):FindChild("healthProgressBar");

	local maxHp = unit:GetMaxHealth()
	local curHp = unit:GetHealth()
	--TODO shield?

	--Set bar label
	healthBar:FindChild("HealthProgressBarContainer"):FindChild("bossName"):SetText(strLabel);

	--Set max for pBar
	progressbar:SetMax(maxHp);

	--Set to 0
	progressbar:SetProgress(curHp);

	--Handle optional color
	if not strColor then
		progressbar:SetBarColor(self.color.red);
	else
		progressbar:SetBarColor(strColor);
	end

	--Handle callback function
	if not fCallback then
		fCallback = nil
	end

	--Add to tAlerts
	self.tHealths[#self.tHealths+1] = {health = healthBar, name = strLabel, callback = fCallback, persist = persist, unit = unit}

	--Arrange vertically
	self:arrangeHealths();
end

--Destroy health bar
function ReStrat:DestroyHealth(name, bExecCallback)
	if not self.tHealths then return end

	for i=1, #self.tHealths do while(1) do
		if not self.tHealths[i] then break end
		if not self.tHealths[i].name then break end

		if self.tHealths[i].name == name then
			if bExecCallback then
				self.tHealths[i].callback();
			end

			--Destroy and remove
			self.tHealths[i].health:Destroy();
			table.remove(self.tHealths, i);
			self:arrangeHealths();
		end
	break end end
end

--Destroy health bar
function ReStrat:GetHealths(name)
	if not self.tHealths then return end

	for i=1, #self.tHealths do while(1) do
		if not self.tHealths[i] then break end
		if not self.tHealths[i].name then break end

		if self.tHealths[i].name == name then
			return self.tHealths[i]
		end
	break end end
end

--[TODO] make this a lot more customizable
function ReStrat:arrangeHealths()
	for i,v in ipairs(self.tHealths) do
		local wndHeight = self.tHealths[i].health:GetHeight();
		local vOffset = wndHeight*(i-1) + BAR_SPACING*(i-1);

		self.tHealths[i].health:SetAnchorOffsets(0,vOffset,0,vOffset+wndHeight);
	end
end

-----------------------------------------------------------------------------------------------
-- Alert Functions
-----------------------------------------------------------------------------------------------

--On alarm tick
function ReStrat:OnAlarmTick()
	if #self.tAlerts <= 0 then return end

	--This counts down all alarms registered to self.tAlerts
	for i,v in ipairs(self.tAlerts) do
		local alertInstance = self.tAlerts[i];
		local timer = alertInstance.alert:FindChild("ProgressBarContainer"):FindChild("timeLeft");

		--Manage actual time degradation, this accounts for lag spikes etc.
		if alertInstance.lastTime then
			alertInstance.currDuration = alertInstance.currDuration-(GameLib.GetGameTime()-alertInstance.lastTime);
		end

		alertInstance.lastTime = GameLib.GetGameTime();

		--Update time, callback if expired
		if alertInstance.currDuration >= 0 then
			timer:SetText(tostring(round(alertInstance.currDuration, 1)) .. "s");
		else

			--Close bar
			alertInstance.alert:Destroy();

			--Execute callback
			if alertInstance.callback then
				alertInstance.callback()
			end

			--Remove from table
			table.remove(self.tAlerts, i);

			--Reshuffle windows
			self:arrangeAlerts();
		end
	end
end

--ReStrat:createAlert("timer", 5, nil, nil, nil)
--Generate alert
function ReStrat:createAlert(strLabel, duration, strIcon, strColor, fCallback)
	local alertBar = Apollo.LoadForm("ReStrat.xml", "alertInstance", self.wndAlerts, self);
	local progressbar = alertBar:FindChild("ProgressBarContainer"):FindChild("progressBar");
	local icon = alertBar:FindChild("IconContainer");

	--Set bar label
	alertBar:FindChild("ProgressBarContainer"):FindChild("spellName"):SetText(strLabel);

	--Set max for pBar
	progressbar:SetMax(duration);

	--Set to 0
	progressbar:SetProgress(duration);
	progressbar:SetProgress(0, 1);

	--Handle optional color
	if not strColor then
		progressbar:SetBarColor(self.color.red);
	else
		progressbar:SetBarColor(strColor);
	end

	--Handle optional icon
	if not strIcon then
		icon:Close();
	else
		icon:FindChild("Icon"):SetSprite(strIcon);
	end

	--Handle callback function
	if not fCallback then
		fCallback = nil
	end

	--Add to tAlerts
	self.tAlerts[#self.tAlerts+1] = {alert = alertBar, name = strLabel, callback = fCallback, currDuration = duration, maxDuration = duration}

	--Arrange vertically
	self:arrangeAlerts();
end

--Destroy alert
function ReStrat:DestroyAlert(name, bExecCallback)
	if not self.tAlerts then return end

	for i=1, #self.tAlerts do while(1) do
		if not self.tAlerts[i] then break end
		if not self.tAlerts[i].name then break end

		if self.tAlerts[i].name == name then
			if bExecCallback then
				self.tAlerts[i].callback();
			end

			--Destroy and remove
			self.tAlerts[i].alert:Destroy();
			table.remove(self.tAlerts, i);
			self:arrangeAlerts();
		end
	break end end
end

--[TODO] make this a lot more customizable
function ReStrat:arrangeAlerts()
	for i,v in ipairs(self.tAlerts) do
		local wndHeight = self.tAlerts[i].alert:GetHeight();
		local vOffset = wndHeight*(i-1) + BAR_SPACING*(i-1);

		self.tAlerts[i].alert:SetAnchorOffsets(0,vOffset,0,vOffset+wndHeight);
	end
end


-----------------------------------------------------------------------------------------------
-- Pin Functions
-----------------------------------------------------------------------------------------------

--Create pin
function ReStrat:createPin(strLabel, unit, graphic)
	local pin = Apollo.LoadForm(self.xmlDoc, "pinForm", "FixedHudStratumHigh", self);
	local label = pin:FindChild("label");
	local graphicform = pin:FindChild("graphic");

	if graphic then graphicform:SetSprite(graphic); end --override the graphic if need be

	label:SetText(strLabel); --set label

	pin:SetUnit(unit, 0); --attach to unit

	if self.tPins[unit:GetName()] then self.tPins[unit:GetName()]:Destroy(); end --Overwrite existing pin

	self.tPins[unit:GetName()] = pin; --Create the new pin
end

--Destroy pin
function ReStrat:destroyPin(unit)
	if self.tPins[unit:GetName()] then self.tPins[unit:GetName()]:Destroy(); self.tPins[unit:GetName()] = nil end
end

-----------------------------------------------------------------------------------------------
-- Pop Functions
-----------------------------------------------------------------------------------------------

--On pop tick
function ReStrat:OnPopTick()
	if self.bPopTicked then
		--We've ticked before
		--Set text
		self.wndPop:SetText("");

		--Execute callback if exists
		if self.fPopCallback then
			self.fPopCallback();
			self.fPopCallback = nil;
		end

		self.popTimer:Stop();
		self.bPopTicked = false;
	else
		self.bPopTicked = true;
	end
end

--Create pop
function ReStrat:createPop(strLabel, fCallback)
	--If we're overriding an existing pop
	if self.wndPop:GetText() ~= "" and self.fPopCallback then
		self.fPopCallback();
		self.fPopCallback = nil;
	end

	--Set our text
	self.wndPop:SetText(tostring(strLabel));

	--Cache our callback
	self.fPopCallback = fCallback;

	--Initiate our timer to close
	self.popTimer:Start();
end

-----------------------------------------------------------------------------------------------
-- Landmark Functions
-----------------------------------------------------------------------------------------------

--Create Landmark
function ReStrat:createLandmark(strLabel, tLocation, graphic)
	local landmark = Apollo.LoadForm(self.xmlDoc, "landmarkForm", "InWorldHudStratum", self);

	--Set position
	landmark:SetWorldLocation(Vector3.New(tLocation));

	--Set label
	landmark:FindChild("label"):SetText(strLabel);

	--Set graphic if need be
	if graphic then landmark:FindChild("graphic"):SetSprite(graphic) end

	--Add to tLandmarks
	self.tLandmarks[#self.tLandmarks+1] = {label = strLabel, form = landmark};
end

--Destroy Landmark
function ReStrat:destroyLandmark(strLabel)
	for i = 1, #self.tLandmarks do
		if self.tLandmarks[i].label == strLabel then
			self.tLandmarks[i].form:Destroy();
			table.remove(self.tLandmarks, i);
		end
	end
end

---------------------------------------------------------------------------------------------------
-- btnEncounter Functions
---------------------------------------------------------------------------------------------------
--Handles zone selection for main menu
function ReStrat:onZoneSelected(wndHandler, wndControl)
	local zoneName = wndHandler:GetData();
	local encounterList = self.wndMain:FindChild("encounterList");

	encounterList:DestroyChildren();

	for i,v in ipairs(self.tZones[zoneName]) do
		local encounterButton = Apollo.LoadForm(self.xmlDoc, "btnEncounter", encounterList, self);

		encounterButton:SetText(v);
		encounterButton:SetData(v);
	end

	self:arrangeChildren(encounterList);
end


--Handles encounter selection for main menu
function ReStrat:onEncounterSelected(wndHandler, wndControl)
	local encounterName = wndHandler:GetData();
	local moduleList = self.wndMain:FindChild("moduleList");

	moduleList:DestroyChildren();

	for k,v in pairs(self.tEncounters[encounterName].tModules) do
		local moduleButton = Apollo.LoadForm(self.xmlDoc, "btnModule", moduleList, self);

		moduleButton:SetText(v.strLabel);
		moduleButton:SetData({encounter = encounterName, module = k});

		--Gray out if disabled
		if not self.tEncounters[encounterName].tModules[k].bEnabled then
			moduleButton:SetBGColor("vdarkgray");
		end

	end

	self:arrangeChildren(moduleList);
end

--Handles module toggling
function ReStrat:onModuleToggled(wndHandler, wndControl)
	local encounterName = wndHandler:GetData().encounter;
	local moduleName = wndHandler:GetData().module;
	local bIsEnabled = self.tEncounters[encounterName].tModules[moduleName].bEnabled;

	if bIsEnabled then
		self.tEncounters[encounterName].tModules[moduleName].bEnabled = false;
		wndHandler:SetBGColor("vdarkgray");
	else
		self.tEncounters[encounterName].tModules[moduleName].bEnabled = true;
		wndHandler:SetBGColor(self.color.green);
	end

end

---------------------------------------------------------------------------------------------------
-- mainForm Functions
---------------------------------------------------------------------------------------------------

function ReStrat:onClose()
	self.wndMain:Close();
end

function ReStrat:onShowIcons()
	self.wndIcon:Invoke(); -- open macro window

	local iconList = self.wndIcon:FindChild("iconList");
	local icons = MacrosLib.GetMacroIconList();

	for i = 0, #icons do
		if icons[i] then
			local icon = Apollo.LoadForm(self.xmlDoc, "iconPreview", iconList, self);
			local iconWindow = icon:FindChild("IconContainer"):FindChild("Icon");
			local iconStringContainer = icon:FindChild("ProgressBarContainer"):FindChild("macroString");
			local iconBtn = icon:FindChild("ProgressBarContainer"):FindChild("btn_copyIconString");
			iconBtn:SetActionData(GameLib.CodeEnumConfirmButtonType.CopyToClipboard, icons[i])
			iconBtn:SetSprite("respr:bartex1");

			iconWindow:SetSprite(icons[i]);
			iconStringContainer:SetText(icons[i]);
		end
	end

	iconList:ArrangeChildrenVert();
end

function ReStrat:onShowLog()
	self.wndLog:Show(true, true); --show the window, duh

	----------------------------
	--Unit Tab
	----------------------------
	--Grab our labels/forms
	local unitList     = self.wndLog:FindChild("formContainer"):FindChild("unitForm"):FindChild("unitList");

	--Create a unit for each unit in tUnits
	for i=1, #self.tUnits do
		local unitItem = Apollo.LoadForm(self.xmlDoc, "unitItem", unitList, self);
		local unitString = unitItem:FindChild("unitString");

		unitString:SetText(self.tUnits[i].name);
		unitItem:SetData(i);
	end

	unitList:ArrangeChildrenVert();
end

--When we switch unit
function ReStrat:onUnitSwitch(wndHandler, wndControl)
	--Grab our labels/forms
	local unitForm     = self.wndLog:FindChild("formContainer"):FindChild("unitForm");
	local portrait     = unitForm:FindChild("CostumeWindow");
	local health       = unitForm:FindChild("strHealth");
	local name         = unitForm:FindChild("strName");
	local power        = unitForm:FindChild("strPower");
	local absorb       = unitForm:FindChild("strAbsorb");
	local shield       = unitForm:FindChild("strShield");
	local assaultpower = unitForm:FindChild("strAssault");
	local count        = unitForm:FindChild("strCount");
	local ia           = unitForm:FindChild("strIA");

	local unitCache = self.tUnits[wndHandler:GetParent():GetData()];
	if unitCache.unit then
		portrait:SetCostume(unitCache.unit);
	else
		portrait:SetCostumeToCreatureId(1);
	end
	if unitCache.health then
		health:SetText("Health: " .. unitCache.health);
	else
		health:SetText("Health: N/A");
	end
	--power:SetText("Health: " .. unitCache.health);
	if unitCache.shield then
		shield:SetText("Shield: " .. unitCache.shield);
	else
		shield:SetText("Shield: N/A");
	end
	if unitCache.absorb then
		absorb:SetText("Absorb: " .. unitCache.absorb);
	else
		absorb:SetText("Absorb: N/A");
	end
	--count:SetText("Health: " .. unitCache.health);
	ia:SetText("Interrupt Armor: " .. unitCache.baseIA);
	if unitCache.assault then
		assaultpower:SetText("Assault Power: " .. round(unitCache.assault,2));
	else
		assaultpower:SetText("Assault Power: N/A");
	end
	name:SetText("Name: " .. unitCache.name);

end

function ReStrat:onSettingsShow(wndControl, eMouseButton)
	self.wndSettings:Show(true, true);
end

---------------------------------------------------------------------------------------------------
-- iconForm Functions
---------------------------------------------------------------------------------------------------

function ReStrat:onCloseIcons()
	local iconList = self.wndIcon:FindChild("iconList");
	local icons = iconList:GetChildren()

	for i = 0, #icons do
		if icons[i] then
			icons[i]:Destroy();
		end
	end

	self.wndIcon:Close();
end

---------------------------------------------------------------------------------------------------
-- iconPreview Functions
---------------------------------------------------------------------------------------------------

function ReStrat:onIconStringCopy(wndHandler)
	local iconString = wndHandler:GetData();
end

---------------------------------------------------------------------------------------------------
-- logForm Functions
---------------------------------------------------------------------------------------------------

function ReStrat:onCloseLog(wndHandler, wndControl)
	self.wndLog:Close();
	local unitList     = self.wndLog:FindChild("formContainer"):FindChild("unitForm"):FindChild("unitList");
	unitList:DestroyChildren();

end

---------------------------------------------------------------------------------------------------
-- settingsForm Functions
---------------------------------------------------------------------------------------------------

function ReStrat:onToggleSettings(wndHandler, wndControl)
	if wndControl:GetText() == "Enabled" then
		wndControl:SetText("Disabled");
		wndControl:SetBGColor(self.color.red);
	else
		wndControl:SetText("Enabled");
		wndControl:SetBGColor(self.color.green);
	end
end

function ReStrat:onCloseSettings()
	self.wndSettings:Close();
end

function ReStrat:onToggleMoving(wndHandler, wndControl)
	if wndControl:GetText() == "Enabled" then
		--Display
		self.wndAlerts:SetBGColor("90000000");
		self.wndAlerts:SetText("Alerts Frame");
		self.wndHealths:SetBGColor("90000000");
		self.wndHealths:SetText("Health Bar Frame");
		self.wndPop:SetBGColor("90000000");
		self.wndPop:SetText("Pop Frame");

		--Set properties
		self.wndAlerts:SetStyle("Moveable", true);
		self.wndHealths:SetStyle("Moveable", true);
		self.wndPop:SetStyle("Moveable", true);
	else
		--Display
		self.wndAlerts:SetText("");
		self.wndAlerts:SetBGColor("00ffffff");
		self.wndHealths:SetText("");
		self.wndHealths:SetBGColor("00ffffff");
		self.wndPop:SetText("");
		self.wndPop:SetBGColor("00ffffff");

		--Set properties
		self.wndAlerts:SetStyle("Moveable", false);
		self.wndHealths:SetStyle("Moveable", false);
		self.wndPop:SetStyle("Moveable", false);
	end
end

--Create our fake timers on request
function ReStrat:onCreateTestAlarms(wndHandler, wndControl)
	--Start alert timer
	self.alertTimer:Start();
	self.healthTimer:Start();
	self.gameTimer:Start();
	wndControl:Enable(false);

	self:createAlert("Energon Cubes", 15.5, "Icon_SkillMedic_repairstation", self.color.purple, function() self:stopTimers() wndControl:Enable(true) end );
	self:createAlert("Flame Walk", 10, "Icon_SkillMisc_Soldier_March", self.color.red, nil)
	self:createAlert("Knockback", 5, "Icon_SkillSbuff_higherjumpbuff", self.color.blue, function() self:createPop("Knockback!", nil) end)

	local selfUnit = GameLib.GetPlayerUnit()

	self:createHealth(selfUnit:GetName(), selfUnit, nil, self.color.white, nil)
end

--OnChatMessages
function ReStrat:OnChatMessage(channelCurrent, tMessage)
	if not tMessage then return end --Shouldn't happen but hey this game

	local command = tMessage.arMessageSegments[1].strText;

	if (command=="invite" or command=="tugga") and GameLib.GetPlayerUnit():GetName()~=tMessage.strSender then
		if GroupLib.GetMemberCount() == 40 then
			--ChatSystemLib.Command('/w ' .. tMessage.strSender .. " Raid is full.")
			return
		elseif GroupLib.GetMemberCount() == 0 then
			--ChatSystemLib.Command('/invite ' .. tMessage.strSender)
			--ChatSystemLib.Command('/w ' .. tMessage.strSender .. " Welcome in!")
			return
		end
		for i = 1, GroupLib.GetMemberCount() do
			if GroupLib.GetGroupMember(i).strCharacterName == GameLib.GetPlayerUnit():GetName() and
			GroupLib.GetGroupMember(i).bIsLeader or GroupLib.GetGroupMember(i).bRaidAssistant or GroupLib.GetGroupMember(i).bMainAssist then
				--ChatSystemLib.Command('/invite ' .. tMessage.strSender)
				--ChatSystemLib.Command('/w ' .. tMessage.strSender .. " Welcome in!")
				return
			end
		end
		--ChatSystemLib.Command('/w ' .. tMessage.strSender .. " I can't invite. Please try again.")
	end


	--Get Datachron Messages
	if channelCurrent:GetName() == "Datachron" then
		for i=1, #self.tDatachron do
			if self.tDatachron[i].strText == command then
				self.tDatachron[i].fCallback();
			end
		end
	end

	--Destroy break
	if string.lower(command) == "stop break" then
		for i = 1, GroupLib.GetMemberCount() do
			if GroupLib.GetGroupMember(i).strCharacterName == tMessage.strSender then
				if GroupLib.GetGroupMember(i).bIsLeader or GroupLib.GetGroupMember(i).bRaidAssistant or GroupLib.GetGroupMember(i).bMainAssist then
					self:DestroyAlert("Break HYPE!");
					return
				end
			end
		end
	end

	--Create pull timer
	if string.match(string.lower(command), "pull in") then
		for i = 1, GroupLib.GetMemberCount() do
			if GroupLib.GetGroupMember(i).strCharacterName == tMessage.strSender then
				if GroupLib.GetGroupMember(i).bIsLeader or GroupLib.GetGroupMember(i).bRaidAssistant or GroupLib.GetGroupMember(i).bMainAssist then
					--Start alert timer
					self.alertTimer:Start();
					self.gameTimer:Start();

					self:createAlert("Pull!", tonumber(string.match(command, "%d+")), "Icon_SkillMisc_Explorer_safefail", self.color.green, self.stopTimers)

					return
				end
			end
		end
	end

	--Create break timer
	if string.match(string.lower(command), "break for") then
		for i = 1, GroupLib.GetMemberCount() do
			if GroupLib.GetGroupMember(i).strCharacterName == tMessage.strSender then
				if GroupLib.GetGroupMember(i).bIsLeader or GroupLib.GetGroupMember(i).bRaidAssistant or GroupLib.GetGroupMember(i).bMainAssist then
					--Start alert timer
					self.alertTimer:Start();
					self.gameTimer:Start();

					self:createAlert("Break HYPE!", tonumber(string.match(command, "%d+")), "Icon_SkillMedic_energize", self.color.purple, self.stopTimers)

					return
				end
			end
		end
	end

end

--Pull timer
function ReStrat:OnPullTimer()
	if self.pulltime > 1 then
		self.pulltime = self.pulltime-1;
		ChatSystemLib.Command('/p ' .. self.pulltime)
	else
		self.pullTimer:Stop();
		ChatSystemLib.Command("/p Pull!")
	end
end

function ReStrat:OnSpeed()
	for i=0,5 do
		ChatSystemLib.Command("/g SPEED FLASKS!!!")
	end
end

--On /pull
function ReStrat:OnPull(cmd, arg)
	local arg = tonumber(arg);

	for i = 1, GroupLib.GetMemberCount() do
		if GroupLib.GetGroupMember(i).strCharacterName == GameLib.GetPlayerUnit():GetName() then
			if GroupLib.GetGroupMember(i).bIsLeader or GroupLib.GetGroupMember(i).bRaidAssistant or GroupLib.GetGroupMember(i).bMainAssist then
				--Pull timer
				if type(arg) == "number" then
					ChatSystemLib.Command('/p Pull in ' .. arg)
					self.pulltime = arg;
					self.pullTimer:Start();
				else
					Print("Please enter a number.");
				end

				return
			end
		end
	end

	Print("You are not a Leader/Assistant");
end

--On /break
function ReStrat:OnBreak(cmd, arg)

	if arg == "end" then
		ChatSystemLib.Command('/p stop break')
	else
		local arg = tonumber(arg);

		for i = 1, GroupLib.GetMemberCount() do
			if GroupLib.GetGroupMember(i).strCharacterName == GameLib.GetPlayerUnit():GetName() then
				if GroupLib.GetGroupMember(i).bIsLeader or GroupLib.GetGroupMember(i).bRaidAssistant or GroupLib.GetGroupMember(i).bMainAssist then
					--Break timer
					if type(arg) == "number" then
						ChatSystemLib.Command('/p Break for ' .. arg)
					else
						Print("Please enter a number.");
					end

					return
				end
			end
		end

		Print("You are not a Leader/Assistant");
	end
end

local buffs = "";
local curPartyMember = 1
local missing = {}
--buffTimer
-- On /buff
function ReStrat:OnBuff(cmd,arg)
	if not arg or arg == "" then Print("See /rs help for use") return end
	curPartyMember = 1;
	missing = {
		['members'] = {
			"Missing: ",
		},
		['flask'] = {
			"No Flask: ",
		},
		['food'] = {
			"No Food: ",
		},
		['pot']= {
			"No Pot: ",
		},

	}

	for i = 1, GroupLib.GetMemberCount() do
		if GroupLib.GetGroupMember(i).strCharacterName == GameLib.GetPlayerUnit():GetName() then
			if GroupLib.GetGroupMember(i).bIsLeader or GroupLib.GetGroupMember(i).bRaidAssistant or GroupLib.GetGroupMember(i).bMainAssist then

				buffs = arg;
				self.buffTimer:Start();

				return
			end
		end
	end

	Print("You are not a Leader/Assistant");
end

function ReStrat:OnBuffTimer()
	-- If we have gone through all members, do printout and stop
	if curPartyMember > GroupLib.GetMemberCount() then

		for i,v in pairs(missing) do
			local str = ""
			for k,s in ipairs(v) do
				str = str .. s .. (k>1 and ", " or "")
			end
			ChatSystemLib.Command('/p ' .. str)
		end

		self.buffTimer:Stop();
		return
	end

	local curUnit =	GroupLib.GetUnitForGroupMember(curPartyMember)

	if not curUnit then
		table.insert(missing['members'], GroupLib.GetGroupMember(curPartyMember).strCharacterName)
	else
		--Very costly call, this is why the check is on a timer
		local tBuffs = curUnit:GetBuffs().arBeneficial
		if not tBuffs then
			Print("Error: No buffs on: ".. curUnit:GetName())
		else
			local hasFlask = false
			local hasFood = false
			local hasPot = false

			for k, v in pairs(tBuffs) do
				local spellname = v.splEffect:GetName()
				if spellname == "Flask of Speed" then
					hasFlask = true
				elseif spellname == "Stuffed!" then
					hasFood = true
				elseif spellname:find("Boost") then
					hasPot = true
				end
			end

			if (buffs=="all" or buffs =="flask") and not hasFlask then
				table.insert(missing['flask'], curUnit:GetName())
			end
			if (buffs=="all" or buffs =="food") and not hasFood then
				table.insert(missing['food'], curUnit:GetName())
			end
			if (buffs=="all" or buffs =="pot") and not hasPot then
				table.insert(missing['pot'], curUnit:GetName())
			end
		end
	end
	curPartyMember = curPartyMember + 1
end


-----------------------------------------------------------------------------------------------
-- ReStrat Instance
-----------------------------------------------------------------------------------------------
local ReStratInst = ReStrat:new()
ReStratInst:Init()
_G["ReStrat"] = ReStratInst
