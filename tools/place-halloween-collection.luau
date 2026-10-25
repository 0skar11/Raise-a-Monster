-- Places the imported static collection in the verified Halloween plaza.
-- Run in Studio Edit after importing HalloweenCollection_Studio.fbx with scale 0.01.
assert(game.PlaceId == 134442007298395, "Wrong place")
local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local palette = HttpService:JSONDecode([==[{"PearlLight":{"rgb":[224,186,252],"glow":false,"metallic":0.07999999821186066},"GhostGlow":{"rgb":[207,69,255],"glow":true,"metallic":0},"Void":{"rgb":[6,3,12],"glow":false,"metallic":0},"Pearl":{"rgb":[176,125,227],"glow":false,"metallic":0.07000000029802322},"PearlShade":{"rgb":[115,56,173],"glow":false,"metallic":0},"Bone":{"rgb":[199,166,112],"glow":false,"metallic":0},"Violet":{"rgb":[56,14,97],"glow":false,"metallic":0.05000000074505806},"Ivory":{"rgb":[245,212,156],"glow":false,"metallic":0},"Amber":{"rgb":[255,115,6],"glow":true,"metallic":0},"Leaf":{"rgb":[82,107,14],"glow":false,"metallic":0},"WoodLight":{"rgb":[110,54,17],"glow":false,"metallic":0},"Vine":{"rgb":[46,69,11],"glow":false,"metallic":0},"Gold":{"rgb":[242,122,14],"glow":false,"metallic":0.6499999761581421},"Wood":{"rgb":[66,27,9],"glow":false,"metallic":0},"Purple":{"rgb":[92,20,143],"glow":false,"metallic":0},"PurpleLight":{"rgb":[135,41,186],"glow":false,"metallic":0.05000000074505806},"Bronze":{"rgb":[140,69,17],"glow":false,"metallic":0.6000000238418579},"Orange":{"rgb":[240,59,6],"glow":false,"metallic":0},"IndigoLight":{"rgb":[46,31,82],"glow":false,"metallic":0},"Magenta":{"rgb":[166,9,51],"glow":false,"metallic":0},"Red":{"rgb":[135,5,19],"glow":false,"metallic":0},"Indigo":{"rgb":[27,19,54],"glow":false,"metallic":0},"BlackFur":{"rgb":[12,10,22],"glow":false,"metallic":0},"Ruby":{"rgb":[242,6,14],"glow":true,"metallic":0.25},"OrangeLight":{"rgb":[255,99,9],"glow":false,"metallic":0},"Lime":{"rgb":[92,255,6],"glow":true,"metallic":0},"WoodDark":{"rgb":[32,11,5],"glow":false,"metallic":0},"Bandage":{"rgb":[186,145,97],"glow":false,"metallic":0},"BandageLight":{"rgb":[240,207,150],"glow":false,"metallic":0},"BandageDark":{"rgb":[135,99,64],"glow":false,"metallic":0},"Cyan":{"rgb":[9,209,255],"glow":true,"metallic":0.10000000149011612},"Scarab":{"rgb":[79,14,201],"glow":true,"metallic":0.5},"Moss":{"rgb":[56,79,9],"glow":false,"metallic":0},"Mint":{"rgb":[13,255,122],"glow":true,"metallic":0},"StoneDark":{"rgb":[43,46,54],"glow":false,"metallic":0},"Stone":{"rgb":[76,82,87],"glow":false,"metallic":0},"MossLight":{"rgb":[99,115,18],"glow":false,"metallic":0},"StoneLight":{"rgb":[110,112,115],"glow":false,"metallic":0}}]==])
local names = {"GhostSlime", "SkeletonImp", "PumpkinKing", "CountFang", "HexCat", "CryptMummy", "GraveGolem", "WraithReaper"}
local titles = {"Ghost Slime", "Skeleton Imp", "Pumpkin King", "Count Fang", "Hex Cat", "Crypt Mummy", "Grave Golem", "Wraith Reaper"}
local heights = {7.5, 8, 9, 8, 7, 8, 9, 9}
local world = assert(workspace:FindFirstChild("HalloweenWorld"), "Missing Halloween world")
local collection = workspace:FindFirstChild("HalloweenCollection_Studio") or world:FindFirstChild("MonsterCollection")
assert(collection and collection:IsA("Model"), "Import the FBX first")
assert(not world:FindFirstChild("MonsterCollection") or world.MonsterCollection == collection, "Existing collection conflict")
for _,name in names do
    assert(collection:FindFirstChild(name.."_ROOT") or collection:FindFirstChild(name), "Missing "..name)
end
ChangeHistoryService:SetWaypoint("Before Halloween collection placement")
collection.Name = "MonsterCollection"
collection:SetAttribute("CollectionId", "Halloween2026_OriginalEight")
collection:SetAttribute("StaticDisplay", true)
collection.Parent = world
local displays = collection:FindFirstChild("Displays")
if not displays then displays = Instance.new("Folder"); displays.Name = "Displays"; displays.Parent = collection end
local report = {}
local parts = 0
for i,name in names do
    local model = collection:FindFirstChild(name.."_ROOT") or collection:FindFirstChild(name)
    model.Name = name
    model:SetAttribute("DisplayName", titles[i])
    model:SetAttribute("StaticDisplay", true)
    model.PrimaryPart = nil
    local box,size = model:GetBoundingBox()
    model.WorldPivot = box - Vector3.new(0,size.Y/2,0)
    model:ScaleTo(model:GetScale() * heights[i] / size.Y)
    local row = i <= 4 and 0 or 1
    local column = (i-1)%4
    local x,z = 69+row*13.5, -140+column*16
    local ground = 0.2
    local pedestalTop = ground + (row==0 and 0.65 or 1.4)
    model:PivotTo(CFrame.new(x,pedestalTop,z) * CFrame.Angles(0,math.pi/2,0))
    for _,part in model:GetDescendants() do
        if part:IsA("BasePart") then
            local key = part.Name:match("__(.+)$")
            local material = assert(palette[key], "Unknown palette "..tostring(key))
            part.Color = Color3.fromRGB(table.unpack(material.rgb))
            part.Material = material.glow and Enum.Material.Neon or Enum.Material.SmoothPlastic
            part.Reflectance = 0
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = true
            part.CastShadow = not material.glow
            part:SetAttribute("Palette",key)
            parts += 1
        end
    end
    local display = displays:FindFirstChild(name)
    if not display then
        display=Instance.new("Model");display.Name=name;display.Parent=displays
        local base=Instance.new("Part");base.Name="Pedestal"
        base.Shape=Enum.PartType.Cylinder
        base.Size=Vector3.new(pedestalTop-ground,11,11)
        base.CFrame=CFrame.new(x,ground+(pedestalTop-ground)/2,z)*CFrame.Angles(0,0,math.pi/2)
        base.Color=Color3.fromRGB(39,28,55);base.Material=Enum.Material.Slate
        base.Anchored=true;base.Parent=display
        local rim=Instance.new("Part");rim.Name="HalloweenRim";rim.Shape=Enum.PartType.Cylinder
        rim.Size=Vector3.new(0.09,11.08,11.08)
        rim.CFrame=CFrame.new(x,pedestalTop-0.07,z)*CFrame.Angles(0,0,math.pi/2)
        rim.Color=Color3.fromRGB(178,93,255);rim.Material=Enum.Material.Neon
        rim.Anchored=true;rim.CanCollide=false;rim.CanTouch=false;rim.Parent=display
        local plaque=Instance.new("Part");plaque.Name="Nameplate"
        plaque.Size=Vector3.new(0.16,1.15,9)
        plaque.CFrame=CFrame.new(x-5.15,pedestalTop+0.6,z)
        plaque.Color=Color3.fromRGB(30,22,39);plaque.Material=Enum.Material.SmoothPlastic
        plaque.Anchored=true;plaque.CanCollide=false;plaque.CanTouch=false;plaque.Parent=display
        local gui=Instance.new("SurfaceGui");gui.Name="MonsterName";gui.Face=Enum.NormalId.Left
        gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;gui.PixelsPerStud=45
        gui.LightInfluence=0;gui.Parent=plaque
        local text=Instance.new("TextLabel");text.Name="Name";text.BackgroundTransparency=1
        text.Size=UDim2.fromScale(1,1);text.Font=Enum.Font.GothamBold
        text.Text=titles[i];text.TextColor3=Color3.fromRGB(255,218,156)
        text.TextScaled=true;text.Parent=gui
    end
    display.Pedestal.Size=Vector3.new(pedestalTop-ground,11,11)
    display.Pedestal.CFrame=CFrame.new(x,ground+(pedestalTop-ground)/2,z)*CFrame.Angles(0,0,math.pi/2)
    display.HalloweenRim.CFrame=CFrame.new(x,pedestalTop-0.07,z)*CFrame.Angles(0,0,math.pi/2)
    display.Nameplate.CFrame=CFrame.new(x-5.15,pedestalTop+0.6,z)
    local finalBox,finalSize=model:GetBoundingBox()
    table.insert(report,{name=name,position={finalBox.X,finalBox.Y,finalBox.Z},height=finalSize.Y,meshes=#model:GetChildren()})
    task.wait()
end
assert(parts==82,"Expected 82 imported mesh parts")
game:GetService("Selection"):Set({collection})
workspace.CurrentCamera.Focus=CFrame.new(76,4,-116)
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(32,27,-114),Vector3.new(76,4,-116))
ChangeHistoryService:SetWaypoint("Placed eight Halloween monsters")
return HttpService:JSONEncode({collection=collection:GetFullName(),meshes=parts,models=report})

