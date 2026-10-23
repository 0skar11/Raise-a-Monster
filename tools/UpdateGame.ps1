$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$taskPython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$taskRojo = Join-Path $env:USERPROFILE '.rokit/tool-storage/rojo-rbx/rojo/7.4.4/rojo.exe'
$stageFile = Join-Path $env:TEMP 'RaiseAMonster-current-build.rbxlx'
Push-Location $projectRoot
try {
    & $taskRojo build default.project.json -o $stageFile
    if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed; game file was not changed.' }
    & $taskPython "$PSScriptRoot/update-place.py" $stageFile
    if ($LASTEXITCODE -ne 0) { throw 'Place update failed.' }
    Write-Host 'Reopen RaiseAMonster_fixed.rbxlx in Studio to load the updated file.'
} finally { Pop-Location }
