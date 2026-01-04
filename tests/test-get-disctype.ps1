# ============================
# Test Script for Get-DiscType Function
# ============================

# Load the functions from the main script
$scriptPath = Join-Path $PSScriptRoot "makemkv-autorip.ps1"

# Extract just the functions we need
function Get-DvdDrive {
    Get-WmiObject Win32_CDROMDrive |
        Where-Object { $_.MediaLoaded -eq $true } |
        Select-Object -First 1
}

function Get-DiscType {
    $dvd = Get-DvdDrive
    if (-not $dvd) {
        return "UNKNOWN"
    }

    # Check the MediaType property exposed by the drive
    $mediaType = $dvd.MediaType
    
    if ($mediaType -like "*BD-ROM*" -or $mediaType -like "*Blu-ray*") {
        return "BLURAY"
    }
    
    if ($mediaType -like "*DVD-ROM*" -or $mediaType -like "*DVD*") {
        return "DVD"
    }
    
    # Fallback: Check for disc structure if MediaType is unclear
    $drivePath = $dvd.Drive
    
    if (Test-Path "$drivePath\BDMV") {
        return "BLURAY"
    }
    
    if (Test-Path "$drivePath\VIDEO_TS") {
        return "DVD"
    }
    
    return "UNKNOWN"
}

# ==========================
# Diagnostic Tests
# ==========================

Write-Host "=== Testing Get-DiscType Function ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check for disc
Write-Host "Test 1: Checking for loaded disc..." -ForegroundColor Yellow
$dvd = Get-DvdDrive

if (-not $dvd) {
    Write-Host "FAILED: No disc detected in any drive" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please insert a disc and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "SUCCESS: Disc detected" -ForegroundColor Green
Write-Host ""

# Test 2: Show drive details
Write-Host "Test 2: Drive Information" -ForegroundColor Yellow
Write-Host "Drive Letter: $($dvd.Drive)" -ForegroundColor White
Write-Host "Volume Name: $($dvd.VolumeName)" -ForegroundColor White
Write-Host "Media Type: $($dvd.MediaType)" -ForegroundColor White
Write-Host "Media Loaded: $($dvd.MediaLoaded)" -ForegroundColor White
Write-Host "Drive Type: $($dvd.DriveType)" -ForegroundColor White
Write-Host "Manufacturer: $($dvd.Manufacturer)" -ForegroundColor White
Write-Host "Caption: $($dvd.Caption)" -ForegroundColor White
Write-Host ""

# Test 3: Check all properties
Write-Host "Test 3: All Drive Properties" -ForegroundColor Yellow
$dvd | Get-Member -MemberType Property | ForEach-Object {
    $propName = $_.Name
    $propValue = $dvd.$propName
    Write-Host "  $propName : $propValue" -ForegroundColor Gray
}
Write-Host ""

# Test 4: Check for disc structure
Write-Host "Test 4: Checking Disc Structure" -ForegroundColor Yellow
$drivePath = $dvd.Drive

Write-Host "Checking for BDMV folder: $drivePath\BDMV" -ForegroundColor White
if (Test-Path "$drivePath\BDMV") {
    Write-Host "  EXISTS - This is likely a Blu-ray disc" -ForegroundColor Green
} else {
    Write-Host "  NOT FOUND" -ForegroundColor Gray
}

Write-Host "Checking for VIDEO_TS folder: $drivePath\VIDEO_TS" -ForegroundColor White
if (Test-Path "$drivePath\VIDEO_TS") {
    Write-Host "  EXISTS - This is likely a DVD" -ForegroundColor Green
} else {
    Write-Host "  NOT FOUND" -ForegroundColor Gray
}

Write-Host "Checking for AUDIO_TS folder: $drivePath\AUDIO_TS" -ForegroundColor White
if (Test-Path "$drivePath\AUDIO_TS") {
    Write-Host "  EXISTS (DVD audio content)" -ForegroundColor Green
} else {
    Write-Host "  NOT FOUND" -ForegroundColor Gray
}

Write-Host ""

# Test 5: List root directory contents
Write-Host "Test 5: Root Directory Contents" -ForegroundColor Yellow
try {
    $items = Get-ChildItem -Path $drivePath -ErrorAction Stop
    foreach ($item in $items) {
        $type = if ($item.PSIsContainer) { "DIR " } else { "FILE" }
        Write-Host "  [$type] $($item.Name)" -ForegroundColor White
    }
} catch {
    Write-Host "  ERROR: Could not list directory contents: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 6: Run the actual function
Write-Host "Test 6: Running Get-DiscType Function" -ForegroundColor Yellow
$detectedType = Get-DiscType
Write-Host "Result: $detectedType" -ForegroundColor Cyan
Write-Host ""

# Test 7: Verify the result
Write-Host "Test 7: Analysis" -ForegroundColor Yellow
$mediaType = $dvd.MediaType

Write-Host "MediaType property check:" -ForegroundColor White
if ($mediaType -like "*BD-ROM*" -or $mediaType -like "*Blu-ray*") {
    Write-Host "  MediaType matches Blu-ray pattern: '$mediaType'" -ForegroundColor Green
} elseif ($mediaType -like "*DVD-ROM*" -or $mediaType -like "*DVD*") {
    Write-Host "  MediaType matches DVD pattern: '$mediaType'" -ForegroundColor Green
} else {
    Write-Host "  MediaType does NOT match any pattern: '$mediaType'" -ForegroundColor Yellow
    Write-Host "  Function will fall back to checking disc structure" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Detected Type: $detectedType" -ForegroundColor White

if ($detectedType -eq "UNKNOWN") {
    Write-Host "STATUS: FAILED - Disc type could not be determined" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible issues:" -ForegroundColor Yellow
    Write-Host "  1. MediaType property doesn't match expected patterns" -ForegroundColor White
    Write-Host "  2. Neither VIDEO_TS nor BDMV folders exist on disc" -ForegroundColor White
    Write-Host "  3. Disc may not be a standard DVD or Blu-ray" -ForegroundColor White
} else {
    Write-Host "STATUS: SUCCESS - Disc type detected as $detectedType" -ForegroundColor Green
}
Write-Host ""
