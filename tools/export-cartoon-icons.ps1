$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskAssets = Join-Path $taskRoot 'assets/CartoonUI'
$taskOutput = Join-Path $taskAssets 'icons'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskAtlas = [System.Drawing.Bitmap]::FromFile((Join-Path $taskAssets 'icons-atlas.png'))
# Export the generated illustrations as separate assets. No runtime atlas/crop dependency.
$taskBounds = [ordered]@{
    Weapons = @(44,77,273,292); Accessories = @(311,55,549,297)
    Gamepasses = @(580,65,824,291); CoinsGrowth = @(850,73,1097,298)
    Owned = @(1125,59,1364,298); DoubleDamage = @(31,304,276,564)
    AutoCollect = @(296,327,548,563); ExtraSlots = @(568,337,831,564)
    AutoFeeder = @(849,339,1110,556); AutoMinigame = @(1125,336,1389,553)
    MonsterCollector = @(25,586,281,836); SummonBoss = @(294,577,563,837)
    Coins = @(578,592,836,822); Candy = @(847,610,1112,825)
    MythicEgg = @(1119,593,1387,830); RareEgg = @(48,844,260,1088)
    LuckyEgg = @(305,845,551,1088); Gift = @(579,842,825,1086)
    Health = @(852,863,1091,1073); Speed = @(1124,845,1375,1086)
}
try {
    foreach ($taskEntry in $taskBounds.GetEnumerator()) {
        $taskBox = $taskEntry.Value
        $taskRect = [System.Drawing.Rectangle]::new($taskBox[0],$taskBox[1],($taskBox[2]-$taskBox[0]),($taskBox[3]-$taskBox[1]))
        $taskIcon = $taskAtlas.Clone($taskRect,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try { $taskIcon.Save((Join-Path $taskOutput ($taskEntry.Key + '.png')),[System.Drawing.Imaging.ImageFormat]::Png) }
        finally { $taskIcon.Dispose() }
    }
} finally { $taskAtlas.Dispose() }
Write-Output ('Exported {0} independent RGBA icons to {1}' -f $taskBounds.Count,$taskOutput)
