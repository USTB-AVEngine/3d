[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AssetsRoot = Join-Path $ProjectRoot "assets\human_sound_sources"
$Assets = @(
    "flute_player",
    "hand_drum_player",
    "megaphone_speaker",
    "clapping_person",
    "coughing_person"
)
$Subdirectories = @("generation", "source", "review", "segmentation", "pixal", "runtime", "metadata")

foreach ($Asset in $Assets) {
    foreach ($Subdirectory in $Subdirectories) {
        New-Item -ItemType Directory -Force -Path (Join-Path $AssetsRoot "$Asset\$Subdirectory") | Out-Null
    }
}

Write-Host "HUMAN_SOUND_SOURCE_V3_LOCAL_PREPARED assets=$($Assets.Count)"
Write-Host "NEXT_ASSET=flute_player seed=43002"
