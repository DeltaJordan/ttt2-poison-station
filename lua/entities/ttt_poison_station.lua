---- Poison Dispenser
AddCSLuaFile()
if SERVER then
	CreateConVar("ttt_poison_station_amount_tick", "5")
	CreateConVar("ttt_poison_station_hurt_traitors", "true")
end

if CLIENT then
	-- this entity can be DNA-sampled so we need some display info
	ENT.Icon = "vgui/ttt/icon_health"
	ENT.PrintName = "Health Station"
	local GetPTranslation = LANG.GetParamTranslation
	ENT.TargetIDHint = {
		name = "hstation_name",
		hint = "hstation_hint",
		fmt = function(ent, txt)
			return GetPTranslation(txt, {
				usekey = Key("+use", "USE"),
				num = ent:GetStoredHealth() or 0
			})
		end
	}
end

ENT.Type = "anim"
ENT.Model = Model("models/props/cs_office/microwave.mdl")
--ENT.CanUseKey = true
ENT.CanHavePrints = true
ENT.MaxHeal = 25
ENT.MaxStored = 200
ENT.RechargeRate = 1
ENT.RechargeFreq = 2 -- in seconds
ENT.NextHeal = 0
ENT.HealRate = 1
ENT.HealFreq = 0.2

AccessorFunc(ENT, "Placer", "Placer")
function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "StoredHealth")
end

function ENT:Initialize()
	self:SetModel(self.Model)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_BBOX)
	local b = 32
	self:SetCollisionBounds(Vector(-b, -b, -b), Vector(b, b, b))
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	if SERVER then
		self:SetMaxHealth(200)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:SetMass(200) end
		self:SetUseType(CONTINUOUS_USE)
	end

	self:SetHealth(200)
	self:SetColor(Color(180, 180, 250, 255))
	self:SetStoredHealth(200)
	self:SetPlacer(nil)
	self.NextHeal = 0
	self.fingerprints = {}
end

function ENT:AddToStorage(amount)
	self:SetStoredHealth(math.min(self.MaxStored, self:GetStoredHealth() + amount))
end

function ENT:TakeFromStorage(amount)
	-- if we only have 5 healthpts in store, that is the amount we heal
	amount = math.min(amount, self:GetStoredHealth())
	self:SetStoredHealth(math.max(0, self:GetStoredHealth() - amount))
	return amount
end

local healsound = Sound("items/medshot4.wav")
local failsound = Sound("items/medshotno1.wav")
local last_sound_time = 0
function ENT:GiveHealth(ply, max_heal)
	if self:GetStoredHealth() > 0 then
		max_heal = max_heal or self.MaxHeal
		local dmg = ply:Health()
		local tickAmount = GetConVar("ttt_poison_station_amount_tick"):GetInt()
		if ply:Health() > tickAmount then
			-- constant clamping, no risks
			local healed = self:TakeFromStorage(math.min(max_heal, dmg))
			local new = math.min(ply:GetMaxHealth(), ply:Health() - tickAmount)
			local hurtTraitors = string.lower(GetConVar("ttt_poison_station_hurt_traitors"):GetString())
			if ply:IsTraitor() and hurtTraitors == "true" then
				ply:SetHealth(new)
			elseif not ply:IsTraitor() then
				ply:SetHealth(new)
			end

			hook.Run("TTTPlayerUsedPoisonStation", ply, self, healed)
			if last_sound_time + 2 < CurTime() then
				self:EmitSound(healsound)
				last_sound_time = CurTime()
			end

			if not table.HasValue(self.fingerprints, ply) then table.insert(self.fingerprints, ply) end
			return true
		else
			self:EmitSound(failsound)
		end
	else
		self:EmitSound(failsound)
	end
	return false
end

function ENT:Use(ply)
	if IsValid(ply) and ply:IsPlayer() and ply:IsActive() then
		local t = CurTime()
		if t > self.NextHeal then
			local healed = self:GiveHealth(ply, self.HealRate)
			self.NextHeal = t + (self.HealFreq * (healed and 1 or 2))
		end
	end
end

-- traditional equipment destruction effects
function ENT:OnTakeDamage(dmginfo)
	if dmginfo:GetAttacker() == self:GetPlacer() then return end
	self:TakePhysicsDamage(dmginfo)
	self:SetHealth(self:Health() - dmginfo:GetDamage())
	local att = dmginfo:GetAttacker()
	if IsPlayer(att) then DamageLog(Format("%s damaged health station for %d dmg", att:Nick(), dmginfo:GetDamage())) end
	if self:Health() < 0 then
		self:Remove()
		util.EquipmentDestroyed(self:GetPos())
		if IsValid(self:GetPlacer()) then LANG.Msg(self:GetPlacer(), "pstation_broken") end
	end
end

if SERVER then
	-- recharge
	local nextcharge = 0
	function ENT:Think()
		if nextcharge < CurTime() then
			self:AddToStorage(self.RechargeRate)
			nextcharge = CurTime() + self.RechargeFreq
		end
	end
else
	local TryT = LANG.TryTranslation
	local ParT = LANG.GetParamTranslation

	local key_params = {
		usekey = Key("+use", "USE"),
		walkkey = Key("+walk", "WALK"),
	}

	 -- Emulate healthstation TargetID
	hook.Add("TTTRenderEntityInfo", "HUDDrawTargetIDPoisonStation", function(tData)
		local client = LocalPlayer()
		local ent = tData:GetEntity()

		if
			not IsValid(client)
			or not client:IsTerror()
			or not client:Alive()
			or not IsValid(ent)
			or tData:GetEntityDistance() > 100
			or ent:GetClass() ~= "ttt_poison_station"
		then
			return
		end

		if (client:GetBaseRole() == ROLE_TRAITOR) then
			tData:EnableText()
			tData:EnableOutline()
			tData:SetOutlineColor(client:GetRoleColor())

			tData:SetTitle("WARNING: Poison Station")
			return
		end

		-- enable targetID rendering
		tData:EnableText()
		tData:EnableOutline()
		tData:SetOutlineColor(client:GetRoleColor())

		tData:SetTitle(TryT("hstation_name"))
		tData:SetSubtitle(ParT("hstation_subtitle", key_params))
		tData:SetKeyBinding("+use")

		local hstation_charge = ent:GetStoredHealth() or 0

		tData:AddDescriptionLine(TryT("hstation_short_desc"))

		tData:AddDescriptionLine(
			(hstation_charge > 0) and ParT("hstation_charge", { charge = hstation_charge })
				or TryT("hstation_empty"),
			(hstation_charge > 0) and roles.DETECTIVE.ltcolor or COLOR_ORANGE
		)

		if client:Health() < client:GetMaxHealth() then
			return
		end

		tData:AddDescriptionLine(TryT("hstation_maxhealth"), COLOR_ORANGE)
	end)
end
