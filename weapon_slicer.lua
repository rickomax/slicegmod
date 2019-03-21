AddCSLuaFile()

SWEP.PrintName = "Slicer"
SWEP.Author = "rickomax"
SWEP.Purpose = "Slice :3"

SWEP.Slot = 5
SWEP.SlotPos = 3

SWEP.Spawnable = true

SWEP.ViewModel = Model( "models/weapons/c_crowbar.mdl" )
SWEP.WorldModel = Model( "models/weapons/w_crowbar.mdl" )
SWEP.ViewModelFOV = 54
SWEP.UseHands = true

SWEP.Primary.ClipSize = 100
SWEP.Primary.DefaultClip = 100
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.DrawAmmo = false

function SWEP:Initialize()
	self:SetHoldType( "slam" )
end

function SWEP:SetupDataTables()
	self:NetworkVar("Int", 0, "SlicedIndexA")
	self:NetworkVar("Int", 0, "SlicedIndexB")
	self:NetworkVar("Vector", 0, "TPlanePosition")
	self:NetworkVar("Float", 0.0, "TPlaneDistance")
end

function IntersectRayWithPlane(a, b, planeNormal, planeDistance)
	local enter, point = PlaneRaycast((b-a):GetNormalized(), a, planeNormal, planeDistance)
	if (enter > 0.0) then
		--local distance = a:Distance(point) / a:Distance(b)
		return point, 0 --TODo: distance (used for interpolation)
	end
	return nil, 0
end

function GetPlaneDistance(inNormal, inPoint)
	return -inNormal:Dot(inPoint)
end

function GetPlaneSide(point, onNormal, distance)
	return onNormal:Dot(point) + distance > 0.0
end

function PlaneRaycast(direction, origin, planeNormal, planeDistance)
	local vdot = direction:Dot(planeNormal)
	local ndot = -origin:Dot(planeNormal) - planeDistance
	if (vdot == 0) then
		return 0.0
	end
	local enter = ndot / vdot
	return enter, origin + direction * enter
end

function SplitMesh(mesh, matrix, planeDirection, planeDistance)
	local sideMesh = {}
	local notSideMesh = {}
	local invMatrix = matrix:GetInverse()
	for index = 1, #mesh, 3 do
		local a = mesh[index]
		local b = mesh[index+1]
		local c = mesh[index+2]
		local aPos = matrix * a.pos
		local bPos = matrix * b.pos
		local cPos = matrix * c.pos
		local aSide = GetPlaneSide(aPos, planeDirection, planeDistance)
		local bSide = GetPlaneSide(bPos, planeDirection, planeDistance)
		local cSide = GetPlaneSide(cPos, planeDirection, planeDistance)
		if (aSide && bSide && cSide) then
			table.insert(sideMesh, a)
			table.insert(sideMesh, b)
			table.insert(sideMesh, c)
		elseif (!aSide && !bSide && !cSide) then
			table.insert(notSideMesh, a)
			table.insert(notSideMesh, b)
			table.insert(notSideMesh, c)
		else
			local sidePoints = 0
			local firstSideIndex = 0
			local firstNonSideIndex = 0
			if (aSide) then
				sidePoints = sidePoints + 1
				if (firstSideIndex == 0) then
					firstSideIndex = 1
				end
			else
				if (firstNonSideIndex == 0) then
					firstNonSideIndex = 1
				end
			end
			if (bSide) then						
				sidePoints = sidePoints + 1
				if (firstSideIndex == 0) then
					firstSideIndex = 2
				end
			else
				if (firstNonSideIndex == 0) then
					firstNonSideIndex = 2
				end
			end
			if (cSide) then							
				sidePoints = sidePoints + 1
				if (firstSideIndex == 0) then
					firstSideIndex = 3
				end
			else
				if (firstNonSideIndex == 0) then
					firstNonSideIndex = 3
				end
			end
			local triangleMesh, quadMesh
			local index1
			if (sidePoints > 1) then
				quadMesh, triangleMesh = sideMesh, notSideMesh		
				index1 = firstNonSideIndex
			else
				quadMesh, triangleMesh = notSideMesh, sideMesh
				index1 = firstSideIndex
			end
			local points = {a,b,c,a,b,c} --dirty hack
			local point1 = points[index1]
			local point2 = points[index1+1]
			local point3 = points[index1+2]
			local point1Pos = matrix * point1.pos
			local point2Pos = matrix * point2.pos
			local point3Pos = matrix * point3.pos
			local point12, point4Dist = IntersectRayWithPlane(point1Pos, point2Pos, planeDirection, planeDistance)
			local point31, point5Dist = IntersectRayWithPlane(point3Pos, point1Pos, planeDirection, planeDistance)
			if (point12 && point31) then
				table.insert(triangleMesh, point1)
				table.insert(triangleMesh, {pos=invMatrix*point12})
				table.insert(triangleMesh, {pos=invMatrix*point31})
				
				table.insert(quadMesh, {pos=invMatrix*point12})
				table.insert(quadMesh, point2)
				table.insert(quadMesh, point3)
				
				table.insert(quadMesh, point3)
				table.insert(quadMesh, {pos=invMatrix*point31})
				table.insert(quadMesh, {pos=invMatrix*point12})
			end
		end
	end
	return sideMesh, notSideMesh
end


function SWEP:PrimaryAttack()
	if (game.SinglePlayer()) then 
		self:CallOnClient("PrimaryAttack")
	end
	if (!CLIENT) then 
		if (self.Owner:IsPlayer()) then
			self.Owner:LagCompensation(true)
		end
		local startpos = self.Owner:GetShootPos()
		local endpos = self.Owner:GetShootPos() + self.Owner:GetAimVector() * 100
		local trace = util.TraceLine({
			start = startpos,
			endpos = endpos,
			filter = self.Owner
		})
		if (self.Owner:IsPlayer()) then
			self.Owner:LagCompensation(false)
		end
		if (IsValid(trace.Entity)) then
			local planePosition = trace.HitPos
			local planeDirection = self.Owner:GetAngles():Right()
			local planeDistance = GetPlaneDistance(planeDirection, planePosition)
			self:SetTPlanePosition(planePosition)
			self:SetTPlaneDistance(planeDistance)
			local physicsObject = trace.Entity:GetPhysicsObject()
			local matrix = physicsObject:GetPositionMatrix()
			local mesh = physicsObject:GetMesh()
			if (mesh) then
				local sideMesh, notSideMesh = SplitMesh(mesh, matrix, planeDirection, planeDistance)
				local copied = duplicator.Copy(trace.Entity)
				local pastedEntities, pastedConstraints = duplicator.Paste(self.Owner, copied.Entities, copied.Constraints)
				trace.Entity:PhysicsFromMesh(sideMesh)
				local firstKey, firstValue = next(pastedEntities)
				firstValue:PhysicsFromMesh(notSideMesh)
				self:SetSlicedIndexA(trace.Entity:EntIndex())
				self:SetSlicedIndexB(firstValue:EntIndex())
			end
		end
	else
		local side = ents.GetByIndex(self:GetSlicedIndexA())
		local notSide = ents.GetByIndex(self:GetSlicedIndexB())
		if (side && notSide) then
			local planePosition = self:GetTPlanePosition()
			local planeDistance = self:GetTPlaneDistance()
			local matrix = side:GetWorldTransformMatrix()
			local mesh = side:GetRenderMesh()
			--TODO: GET CLIENT-SIDE MESH, WAITING THIS FEATURE FROM GMOD :C
		end
	end
end

function SWEP:SecondaryAttack()

end

function SWEP:OnRemove()


end

function SWEP:Holster()
	return true
end

function SWEP:CustomAmmoDisplay()
	return self.AmmoDisplay
end
