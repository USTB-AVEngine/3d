[CmdletBinding()]
param(
    [string]$SshAlias = "avengine-lab",
    [string]$RemoteRoot = "/data/datasets/avengine_workspaces/users/lx/human_sound_source_assets_v1"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BatchRunner = Join-Path $PSScriptRoot "run_human_flux2_batch.py"
$Jobs = Join-Path $ProjectRoot "assets\human_sound_sources\human_sound_source_flux2_expansion_v3.json"
$Plan = Join-Path $ProjectRoot "assets\human_sound_sources\human_sound_source_expansion_v3_plan.json"
$AssetIds = @(
    "saxophone_player",
    "flute_player",
    "hand_drum_player",
    "megaphone_speaker",
    "clapping_person",
    "coughing_person"
)

foreach ($Path in @($BatchRunner, $Jobs, $Plan)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required local file is missing: $Path"
    }
}

$RemoteDirectories = @("$RemoteRoot/_tools", "$RemoteRoot/_plans", "$RemoteRoot/_review")
foreach ($AssetId in $AssetIds) {
    $RemoteDirectories += @(
        "$RemoteRoot/$AssetId/generation",
        "$RemoteRoot/$AssetId/source",
        "$RemoteRoot/$AssetId/review",
        "$RemoteRoot/$AssetId/segmentation",
        "$RemoteRoot/$AssetId/pixal",
        "$RemoteRoot/$AssetId/runtime",
        "$RemoteRoot/$AssetId/metadata"
    )
}

$QuotedDirectories = ($RemoteDirectories | ForEach-Object { "'$_'" }) -join " "
ssh $SshAlias "mkdir -p $QuotedDirectories"
if ($LASTEXITCODE -ne 0) { throw "Remote directory preparation failed" }

scp $BatchRunner "${SshAlias}:$RemoteRoot/_tools/run_human_flux2_batch.py"
if ($LASTEXITCODE -ne 0) { throw "Batch runner upload failed" }
scp $Jobs "${SshAlias}:$RemoteRoot/_plans/human_sound_source_flux2_expansion_v3.json"
if ($LASTEXITCODE -ne 0) { throw "Jobs upload failed" }
scp $Plan "${SshAlias}:$RemoteRoot/_plans/human_sound_source_expansion_v3_plan.json"
if ($LASTEXITCODE -ne 0) { throw "Plan upload failed" }

$RemoteCheck = "python3 -m py_compile '$RemoteRoot/_tools/run_human_flux2_batch.py' && " +
    "python3 -m json.tool '$RemoteRoot/_plans/human_sound_source_flux2_expansion_v3.json' >/dev/null && " +
    "sha256sum '$RemoteRoot/_tools/run_human_flux2_batch.py' " +
    "'$RemoteRoot/_plans/human_sound_source_flux2_expansion_v3.json' " +
    "'$RemoteRoot/_plans/human_sound_source_expansion_v3_plan.json'"
ssh $SshAlias $RemoteCheck
if ($LASTEXITCODE -ne 0) { throw "Remote validation failed" }

Write-Host "HUMAN_SOUND_SOURCE_EXPANSION_V3_PREPARED assets=$($AssetIds.Count)"
Write-Host "NEXT_ASSET=saxophone_player seed=43001"
