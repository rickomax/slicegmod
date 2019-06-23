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

local cachedMaterials = {}

function SWEP:Initialize()
	self:SetHoldType( "slam" )
end

function SWEP:SetupDataTables()
	self:NetworkVar("Entity", 1, "SideEntity")
	self:NetworkVar("Entity", 2, "NotSideEntity")
	self:NetworkVar("Vector", 3, "SlicePlaneDirection")
	self:NetworkVar("Float",  4, "SlicePlaneDistance")
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
			local sideEntity = trace.Entity
			sidePhysObject = sideEntity:GetPhysicsObject()
			sidePhysMesh = sidePhysObject:GetMesh()
			if (sidePhysMesh) then
				local planePosition = trace.HitPos
				local planeDirection = self.Owner:GetAngles():Right()
				local planeDistance = GetPlaneDistance(planeDirection, planePosition)
				local sideMesh, notSideMesh = SplitMesh(sidePhysMesh, sidePhysObject:GetPositionMatrix(), planeDirection, planeDistance)	
				sideEntity:PhysicsFromMesh(sideMesh)
				sidePhysObject = sideEntity:GetPhysicsObject()
				sidePhysObject:ApplyForceCenter(-planeDirection * sidePhysObject:GetMass())
				local notSideEntity = ents.Create(sideEntity:GetClass())
				notSideEntity:SetModel(sideEntity:GetModel())
				notSideEntity:SetPos(sideEntity:GetPos())
				notSideEntity:SetAngles(sideEntity:GetAngles())
				notSideEntity:Spawn()
				notSideEntity:PhysicsFromMesh(notSideMesh)	
				local notSidePhysObject = notSideEntity:GetPhysicsObject()
				notSidePhysObject:ApplyForceCenter(planeDirection * notSidePhysObject:GetMass())
				self:SetSlicePlaneDirection(planeDirection)
				self:SetSlicePlaneDistance(planeDistance)
				self:SetSideEntity(sideEntity)
				self:SetNotSideEntity(notSideEntity)
			end
		end
	else
		local sideEntity = self:GetSideEntity()
		if (sideEntity) then
			local planeDirection = self:GetSlicePlaneDirection()
			local planeDistance = self:GetSlicePlaneDistance()
			local matrix = sideEntity:GetWorldTransformMatrix()
			local model = sideEntity:GetModel()	
			local meshes = sideEntity.meshes or util.GetModelMeshes(model)
			local notSideEntity = self:GetNotSideEntity()
			sideEntity.meshes, notSideEntity.meshes = SplitMultiMesh(meshes, matrix, planeDirection, planeDistance)
			sideEntity.RenderOverride = function()
				RenderSlice(sideEntity)
			end
			notSideEntity.RenderOverride = function()
				RenderSlice(notSideEntity)
			end
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

function IntersectRayWithPlane(a, b, planeNormal, planeDistance)
	local enter, point = PlaneRaycast((b-a):GetNormalized(), a, planeNormal, planeDistance)
	if (enter > 0.0) then
		local distance = a:Distance(point) / a:Distance(b)
		return point, distance 
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
	local innerTriangles = {}
	local innerPlaneTriangles = {}
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
			local vertex1 = points[index1]
			local vertex2 = points[index1+1]
			local vertex3 = points[index1+2]
			local point1 = matrix * vertex1.pos
			local point2 = matrix * vertex2.pos
			local point3 = matrix * vertex3.pos
			local point12, point12Dist = IntersectRayWithPlane(point1, point2, planeDirection, planeDistance)
			local point31, point31Dist = IntersectRayWithPlane(point3, point1, planeDirection, planeDistance)
			if (point12 && point31) then
				local vertex12 = {pos = invMatrix * point12}
				if (vertex1.normal and vertex2.normal) then
					vertex12.normal = LerpVector(point12Dist, vertex1.normal, vertex2.normal)
				end
				if (vertex1.tangent and vertex2.tangent) then
					vertex12.tangent = LerpVector(point12Dist, vertex1.tangent, vertex2.tangent)
				end
				if (vertex1.binormal and vertex2.binormal) then
					vertex12.binormal = LerpVector(point12Dist, vertex1.binormal, vertex2.binormal)
				end
				if (vertex1.u and vertex2.u) then
					vertex12.u = Lerp(point12Dist, vertex1.u, vertex2.u)
				end
				if (vertex1.v and vertex2.v) then
					vertex12.v = Lerp(point12Dist, vertex1.v, vertex2.v)
				end
				local vertex31 = {pos = invMatrix * point31}
				if (vertex3.normal and vertex1.normal) then
					vertex31.normal = LerpVector(point31Dist, vertex3.normal, vertex1.normal)
				end
				if (vertex3.tangent and vertex1.tangent) then
					vertex31.tangent = LerpVector(point31Dist, vertex3.tangent, vertex1.tangent)
				end
				if (vertex3.binormal and vertex1.binormal) then
					vertex31.binormal = LerpVector(point31Dist, vertex3.binormal, vertex1.binormal)
				end
				if (vertex3.u and vertex1.u) then
					vertex31.u = Lerp(point31Dist, vertex3.u, vertex1.u)
				end
				if (vertex3.v and vertex1.v) then
					vertex31.v = Lerp(point31Dist, vertex3.v, vertex1.v)
				end
				table.insert(triangleMesh, vertex1)
				table.insert(triangleMesh, vertex12)
				table.insert(triangleMesh, vertex31)
				table.insert(quadMesh, vertex12)
				table.insert(quadMesh, vertex2)
				table.insert(quadMesh, vertex3)
				table.insert(quadMesh, vertex3)
				table.insert(quadMesh, vertex31)
				table.insert(quadMesh, vertex12)
			end
		end
	end
	return sideMesh, notSideMesh
end

function SplitMultiMesh(meshes, matrix, planeDirection, planeDistance)
	local sideMeshes, notSideMeshes = {}, {}
	for index = 1, #meshes do
		local mesh = meshes[index]
		local sideMesh = Mesh()
		local notSideMesh = Mesh()
		local sideTriangles, notSideTriangles = SplitMesh(mesh.originalTriangles or mesh.triangles, matrix, planeDirection, planeDistance)
		sideMesh:BuildFromTriangles(sideTriangles)
		notSideMesh:BuildFromTriangles(notSideTriangles)
		table.insert(sideMeshes, {originalTriangles = sideTriangles, triangles = sideMesh, material = mesh.material})
		table.insert(notSideMeshes, {originalTriangles = notSideTriangles, triangles = notSideMesh, material = mesh.material})
	end
	return sideMeshes, notSideMeshes
end

function Duplicate(entity, owner)
	local copied = duplicator.Copy(entity)
	local pastedEntities, pastedConstraints = duplicator.Paste(owner, copied.Entities, copied.Constraints)
	local firstKey, firstValue = next(pastedEntities)
	return firstValue
end

function RenderSlice(entity)
	if (entity.meshes) then
		cam.PushModelMatrix(entity:GetWorldTransformMatrix())
		for index = 1, #entity.meshes do
			local mesh = entity.meshes[index]
			local material
			if (cachedMaterials[mesh.material]) then
				material = cachedMaterials[mesh.material]
			else
				material = Material(mesh.material)
				cachedMaterials[mesh.material] = material
			end
			render.SetMaterial(material)
			mesh.triangles:Draw()
		end
		entity:CreateShadow()
		cam.PopModelMatrix()
	end
end
