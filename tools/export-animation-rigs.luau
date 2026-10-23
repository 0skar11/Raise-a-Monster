-- Save the place in Studio first, then run with Lune and pass the saved place path.
local fs=require('@lune/fs')
local roblox=require('@lune/roblox')
local process=require('@lune/process')
local game=roblox.deserializePlace(fs.readFile(process.args[1] or 'RaiseAMonster_fixed.rbxlx'))
local rigs=game:GetService('Workspace'):FindFirstChild('AnimationRigs')
assert(rigs,'AnimationRigs is missing. Save the place outside Play mode first.')
fs.writeFile('assets/AnimationRigs.rbxmx',roblox.serializeModel({rigs},true))
print('Exported authored rigs. Run tools/rojo-xml-compat.py before reconnecting Rojo.')
