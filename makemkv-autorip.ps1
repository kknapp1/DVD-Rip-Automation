# ============================
# MakeMKV Auto-Rip Script
# Insert disc -> rip main movie -> eject -> repeat
# ============================

param(
    [int]$MinLengthSeconds = 3600  # 1 hour: main movie heuristic
)

# Load settings from JSON file or use defaults
$settingsFile = Join-Path $PSScriptRoot "settings.json"
$defaultSettings = @{
    MakeMKV = "C:\Program Files (x86)\MakeMKV\makemkvcon64.exe"
    RipRoot = "C:\DVD_Rip_Work\INBOX"
    PollSeconds = 5
    TitlePromptSeconds = 15
    TMDbApiKey = "YOUR_TMDB_API_KEY_HERE"
    UseTMDbLookup = $false
}

if (Test-Path $settingsFile) {
    try {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
        Write-Host "Loaded settings from $settingsFile" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to load settings file. Using defaults. Error: $($_.Exception.Message)"
        $settings = [PSCustomObject]$defaultSettings
    }
} else {
    Write-Warning "Settings file not found at $settingsFile. Using defaults."
    Write-Host "To customize settings, copy settings.example.json to settings.json and edit it." -ForegroundColor Yellow
    $settings = [PSCustomObject]$defaultSettings
}

# Apply settings
$MakeMKV = $settings.MakeMKV
$RipRoot = $settings.RipRoot
$PollSeconds = $settings.PollSeconds
$TitlePromptSeconds = $settings.TitlePromptSeconds
$TMDbApiKey = $settings.TMDbApiKey
$UseTMDbLookup = $settings.UseTMDbLookup

if (-not (Test-Path $MakeMKV)) {
    Write-Error "MakeMKV not found at $MakeMKV"
    exit 1
}

New-Item -ItemType Directory -Force -Path $RipRoot | Out-Null

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

function Eject-Dvd($driveLetter) {
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.NameSpace(17).ParseName("$driveLetter\").InvokeVerb("Eject")
    } catch {
        Write-Warning "Failed to eject disc. You may need to eject manually."
    }
}

function Get-TMDbMovieTitle([string]$searchQuery, [int]$year) {
    if (-not $UseTMDbLookup -or $TMDbApiKey -eq "YOUR_TMDB_API_KEY_HERE") {
        return $null
    }

    try {
        $encodedQuery = [System.Web.HttpUtility]::UrlEncode($searchQuery)
        $url = "https://api.themoviedb.org/3/search/movie?api_key=$TMDbApiKey&query=$encodedQuery&include_adult=false&language=en-US"
        
        if ($year) {
            $url += "&primary_release_year=$year"
        }

        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        
        if ($response.results -and $response.results.Count -gt 0) {
            $movie = $response.results[0]
            $title = $movie.title
            $releaseYear = $null
            
            if ($movie.release_date -and $movie.release_date -match '^(\d{4})') {
                $releaseYear = $matches[1]
            }
            
            if ($releaseYear) {
                return "$title ($releaseYear)"
            }
            return $title
        }
    } catch {
        Write-Warning "TMDb lookup failed: $($_.Exception.Message)"
    }

    return $null
}

function Get-ProposedTitle {
    $dvd = Get-DvdDrive
    if (-not $dvd) {
        return $null
    }

    # Get volume label
    $volumeLabel = $dvd.VolumeName
    if (-not $volumeLabel -or $volumeLabel -eq "") {
        $volumeLabel = $null
    }

    # Get year from disc creation timestamp
    $year = $null
    try {
        $drive = Get-PSDrive -Name $dvd.Drive.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($drive -and $drive.Root) {
            $rootInfo = Get-Item -Path $drive.Root -ErrorAction SilentlyContinue
            if ($rootInfo -and $rootInfo.CreationTime) {
                $year = $rootInfo.CreationTime.Year
            }
        }
    } catch {
        # Fallback: try to get any video file timestamp
        try {
            $videoFile = Get-ChildItem -Path "$($dvd.Drive)\VIDEO_TS" -Filter *.VOB -File -ErrorAction SilentlyContinue |
                Sort-Object CreationTime |
                Select-Object -First 1
            if ($videoFile) {
                $year = $videoFile.CreationTime.Year
            }
        } catch {
            # Year remains null
        }
    }

    # Try TMDb lookup if we have a volume label
    $tmdbTitle = $null
    if ($volumeLabel) {
        Write-Host "Disc label: $volumeLabel" -ForegroundColor Cyan
        if ($year) {
            Write-Host "Disc year: $year" -ForegroundColor Cyan
        }
        
        # Clean up volume label for better search results
        # Replace underscores with spaces and trim whitespace
        $cleanedLabel = $volumeLabel -replace '_', ' '
        $cleanedLabel = $cleanedLabel.Trim()
        
        if ($cleanedLabel -ne $volumeLabel) {
            Write-Host "Cleaned label for search: $cleanedLabel" -ForegroundColor Cyan
        }
        
        $tmdbTitle = Get-TMDbMovieTitle -searchQuery $cleanedLabel -year $year
        if ($tmdbTitle) {
            Write-Host "TMDb lookup found: $tmdbTitle" -ForegroundColor Green
            return $tmdbTitle
        } else {
            Write-Host "TMDb lookup found no results for disc label" -ForegroundColor Yellow
        }
    }

    # If TMDb lookup failed, offer manual search
    if ($UseTMDbLookup -and $TMDbApiKey -ne "YOUR_TMDB_API_KEY_HERE") {
        Write-Host "`nWould you like to search TMDb manually? (Y/N or press Enter to skip):" -ForegroundColor Yellow
        $manualSearch = Read-Host
        
        if ($manualSearch -eq "Y" -or $manualSearch -eq "y") {
            $searchTitle = Read-Host "Enter movie title to search"
            if (![string]::IsNullOrWhiteSpace($searchTitle)) {
                $searchYear = Read-Host "Enter year (optional - press Enter to skip)"
                $searchYearInt = $null
                if (![string]::IsNullOrWhiteSpace($searchYear) -and $searchYear -match '^\d{4}$') {
                    $searchYearInt = [int]$searchYear
                }
                
                $tmdbTitle = Get-TMDbMovieTitle -searchQuery $searchTitle -year $searchYearInt
                if ($tmdbTitle) {
                    Write-Host "TMDb lookup found: $tmdbTitle" -ForegroundColor Green
                    return $tmdbTitle
                } else {
                    Write-Host "No results found for manual search" -ForegroundColor Yellow
                }
            }
        }
    }

    # Fallback to disc info
    if ($volumeLabel -and $year) {
        return "$volumeLabel ($year)"
    } elseif ($volumeLabel) {
        return $volumeLabel
    }

    return $null
}

function Get-SafeName([string]$name) {
    if (-not $name) {
        return $null
    }

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = ($name.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { '_' } else { $_ }
    }) -join ''

    return $safe.Trim()
}

function Read-HostWithTimeout([int]$seconds) {
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.ElapsedMilliseconds -lt ($seconds * 1000) -and -not [Console]::KeyAvailable) {
        Start-Sleep -Milliseconds 100
    }

    if ([Console]::KeyAvailable) {
        return [Console]::ReadLine()
    }

    return $null
}

function Get-UserTitle([string]$proposedTitle) {
    if ($proposedTitle) {
        Write-Host "Proposed title: $proposedTitle"
        Write-Host "Press Enter to accept, wait $TitlePromptSeconds seconds to auto-accept, or type a new title:"
        $input = Read-HostWithTimeout -seconds $TitlePromptSeconds
        if ($null -eq $input -or $input -eq "") {
            return $proposedTitle
        }
        return $input
    }

    return Read-Host "Enter title (e.g., Die Hard (2004))"
}

function Get-UniqueDirectory([string]$root, [string]$name) {
    $candidate = Join-Path $root $name
    if (-not (Test-Path $candidate)) {
        return $candidate
    }

    $i = 2
    while ($true) {
        $candidate = Join-Path $root "$name ($i)"
        if (-not (Test-Path $candidate)) {
            return $candidate
        }
        $i++
    }
}

function Rename-MkvToTitle([string]$jobDir, [string]$safeTitle) {
    $mkv = Get-ChildItem -Path $jobDir -Filter *.mkv -File |
        Sort-Object Length -Descending |
        Select-Object -First 1

    if (-not $mkv) {
        Write-Warning "No MKV files found to rename."
        return
    }

    $targetPath = Join-Path $jobDir "$safeTitle.mkv"
    if ($mkv.FullName -ne $targetPath) {
        Move-Item -Path $mkv.FullName -Destination $targetPath -Force
    }
}

Write-Host "MakeMKV auto-rip started. Waiting for disc..."

while ($true) {
    $dvd = Get-DvdDrive

    if ($dvd) {
        $proposedTitle = Get-ProposedTitle
        $userTitle = Get-UserTitle -proposedTitle $proposedTitle
        $safeTitle = Get-SafeName $userTitle

        if (-not $safeTitle) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $safeTitle = "DISC_$timestamp"
        }

        $jobDir = Get-UniqueDirectory -root $RipRoot -name $safeTitle
        New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

        # Detect and save disc type
        $discType = Get-DiscType
        $discTypeFile = Join-Path $jobDir ".disctype"
        Set-Content -Path $discTypeFile -Value $discType
        Write-Host "Detected disc type: $discType" -ForegroundColor Cyan

        Write-Host "Disc detected in $($dvd.Drive). Ripping to $jobDir"

        & $MakeMKV `
            "--robot" `
            "--minlength=$MinLengthSeconds" `
            "mkv" `
            "disc:0" `
            "all" `
            "$jobDir"

        Rename-MkvToTitle -jobDir $jobDir -safeTitle $safeTitle

        Write-Host "Rip complete. Ejecting disc..."
        Eject-Dvd $dvd.Drive

        Write-Host "Insert next disc."
    }
    else {
        Start-Sleep -Seconds $PollSeconds
    }
}

