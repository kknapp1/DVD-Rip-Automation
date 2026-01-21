# ============================
# HandBrake Docker Encode Script
# Encodes largest MKV from each rip folder
# ============================

$InboxRoot       = "C:\DVD_Rip_Work\INBOX"
$EncodedRoot     = "C:\DVD_Rip_Work\ENCODED"
$PresetDVD       = "HQ 480p30 Surround"
$PresetBluRay    = "HQ 1080p30 Surround"
$Container       = "jlesage/handbrake"
function Get-PresetForSource([string]$ripFolder, [string]$mkvFile) {
    # Check for titleinfo.json metadata file
    $titleInfoFile = Join-Path $ripFolder "titleinfo.json"
    if (Test-Path $titleInfoFile) {
        try {
            $titleInfo = Get-Content $titleInfoFile -Raw | ConvertFrom-Json
            $discType = $titleInfo.disctype
            
            if ($discType -eq "BLURAY") {
                Write-Host "  Source: Blu-ray (from metadata)" -ForegroundColor Cyan
                return $PresetBluRay
            } elseif ($discType -eq "DVD") {
                Write-Host "  Source: DVD (from metadata)" -ForegroundColor Cyan
                return $PresetDVD
            }
        } catch {
            Write-Warning "  Failed to parse titleinfo.json: $($_.Exception.Message)"
        }
    }
    
    # Fallback: check for old .disctype file for backward compatibility
    $discTypeFile = Join-Path $ripFolder ".disctype"
    if (Test-Path $discTypeFile) {
        $discType = Get-Content $discTypeFile -Raw
        $discType = $discType.Trim()
        
        if ($discType -eq "BLURAY") {
            Write-Host "  Source: Blu-ray (from legacy metadata)" -ForegroundColor Cyan
            return $PresetBluRay
        } elseif ($discType -eq "DVD") {
            Write-Host "  Source: DVD (from legacy metadata)" -ForegroundColor Cyan
            return $PresetDVD
        }
    }
    
    # Ultimate fallback: DVD preset
    Write-Host "  Source: Unknown, using DVD preset" -ForegroundColor Yellow
    return $PresetDVD
}
New-Item -ItemType Directory -Force -Path $EncodedRoot | Out-Null

Write-Host "Starting HandBrake encode pass..."

Get-ChildItem -Path $InboxRoot -Directory | ForEach-Object {

    $ripFolder = $_.FullName
    $ripName   = $_.Name

    # Create output folder for this rip
    $outFolder = Join-Path $EncodedRoot $ripName
    New-Item -ItemType Directory -Force -Path $outFolder | Out-Null

    # Always copy additional asset files (excluding .mkv files)
    Write-Host "Copying additional asset files for $ripName..." -ForegroundColor Cyan
    $assetFiles = Get-ChildItem -Path $ripFolder -File | Where-Object { $_.Extension -ne ".mkv" }
    
    if ($assetFiles) {
        foreach ($asset in $assetFiles) {
            $destPath = Join-Path $outFolder $asset.Name
            Copy-Item -Path $asset.FullName -Destination $destPath -Force
            Write-Host "  Copied: $($asset.Name)" -ForegroundColor Green
        }
    } else {
        Write-Host "  No additional assets to copy" -ForegroundColor Gray
    }

    $outFile = Join-Path $outFolder "$ripName.mp4"

    if (Test-Path $outFile) {
        Write-Host "Skipping $ripName (already encoded)"
        return
    }

    $source = Get-ChildItem -Path $ripFolder -Filter *.mkv |
              Sort-Object Length -Descending |
              Select-Object -First 1

    if (-not $source) {
        Write-Warning "No MKV found in $ripName. Skipping."
        return
    }

    # Determine appropriate preset
    $preset = Get-PresetForSource -ripFolder $ripFolder -mkvFile $source

    Write-Host "Encoding $ripName"
    Write-Host "  Input: $($source.Name)"
    Write-Host "  Output: $outFile"
    Write-Host "  Preset: $preset" -ForegroundColor Yellow

    docker run --rm `
      -v "${ripFolder}:/input:ro" `
      -v "${outFolder}:/output" `
      $Container `
      HandBrakeCLI `
        -i "/input/$($source.Name)" `
        -o "/output/$ripName.mp4" `
        --preset "$preset" `
        --markers

    Write-Host "Finished $ripName"
    
}

Write-Host "Encode pass complete."
