param(
    [switch]$OpenLauncher
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$modRoot = Join-Path $repo "Mod"
$template = Join-Path $repo "Launcher\alien_crisis_dev.mod.template"
$launcherModDirectory = Join-Path $HOME "Documents\Paradox Interactive\Hearts of Iron IV\mod"
$launcherDescriptor = Join-Path $launcherModDirectory "coi_alien_crisis_dev.mod"
$launcher = "C:\Program Files (x86)\Steam\steamapps\common\Hearts of Iron IV\dowser.exe"

foreach ($required in @(
    $template,
    (Join-Path $modRoot "descriptor.mod")
)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required file not found: $required"
    }
}

$modPath = $modRoot.Replace("\", "/")
$descriptorText = (Get-Content -LiteralPath $template -Raw).Replace("@MOD_PATH@", $modPath)

New-Item -ItemType Directory -Path $launcherModDirectory -Force | Out-Null
[IO.File]::WriteAllText(
    $launcherDescriptor,
    $descriptorText,
    [Text.UTF8Encoding]::new($false)
)

Write-Host "Installed local launcher descriptor:"
Write-Host "  $launcherDescriptor"
Write-Host "Source remains in:"
Write-Host "  $modRoot"

if ($OpenLauncher) {
    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "HOI4 launcher bootstrapper not found: $launcher"
    }
    Start-Process -FilePath $launcher -WorkingDirectory (Split-Path -Parent $launcher)
}
