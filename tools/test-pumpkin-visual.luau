local fs, luau, r = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local env = table.clone(getfenv())
for k,v in r do env[k]=v end
local visual = luau.load(fs.readFile("src/shared/PumpkinVisual.luau"), {environment=env})()
local checks = 0
local function check(value, label) checks+=1; assert(value, label) end
local body = r.Instance.new("Part")
body.CFrame=r.CFrame.new(12,4,-8)*r.CFrame.Angles(.2,.5,.1)
body.Anchored=false;body.CanQuery=true;body.CanTouch=true;body.CanCollide=true
local cf=body.CFrame
local prompt=r.Instance.new("ProximityPrompt");prompt.Parent=body
local attachment=r.Instance.new("Attachment");attachment.Position=r.Vector3.new(0,1,0);attachment.Parent=body
local weld=r.Instance.new("WeldConstraint");weld.Parent=body
visual.Apply(body,3.2)
check(body.CFrame==cf,"Appearance change moved the gameplay body")
check(not body.Anchored and body.CanQuery and body.CanTouch and body.CanCollide,"Appearance change altered gameplay physics")
check(prompt.Parent==body and attachment.Parent==body and weld.Parent==body,"Appearance change removed gameplay or rig instances")
check(body.Color==r.Color3.new(1,1,1),"Natural texture is tinted")
visual.Apply(body,3.8,r.Color3.fromRGB(255,225,120))
check(body.Color==r.Color3.fromRGB(255,225,120),"Golden visual tint lost")
local meshes=0
for _,child in body:GetChildren() do if child:IsA("SpecialMesh") then meshes+=1;check(child.MeshId==visual.MeshId and child.TextureId==visual.TextureId,"Canonical mesh missing") end end
check(meshes==1,"Repeated Apply accumulated meshes")
local size=r.Vector3.new(2,1,1);body.Size=size
visual.Fit(body)
check(body.Size==size and body.CFrame==cf,"Fitted merchant head changed rig bounds")
check(attachment.Position==r.Vector3.new(0,1,0) and weld.Parent==body,"Fitted head moved attachment or removed joint")
local mesh=body:FindFirstChildOfClass("SpecialMesh")
check((mesh.Scale*visual.MeshSize-size).Magnitude<.0001,"Fitted mesh does not match authored head bounds")
local created=visual.Create("PumpkinHat",1.7,cf)
check(created.Name=="PumpkinHat" and created.Anchored and not created.CanTouch and created.Parent==nil,"Detached creator defaults invalid")
print(string.format("PASS: %d canonical pumpkin appearance, identity, golden tint and rig preservation checks",checks))
