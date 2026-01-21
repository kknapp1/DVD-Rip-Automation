# ============================
# MakeMKV Auto-Rip Script
# Insert disc -> rip main movie -> eject -> repeat
# ============================

param(
    [int]$MinLengthSeconds = 3600,  # 1 hour: main movie heuristic
    [switch]$UpdateTitleInfo,       # Update titleinfo.json for existing rips
    [switch]$Help                   # Display help information
)

# Display help if requested
if ($Help) {
    Write-Host "`nMakeMKV Auto-Rip Script" -ForegroundColor Cyan
    Write-Host "========================`n" -ForegroundColor Cyan
    Write-Host "DESCRIPTION:" -ForegroundColor Yellow
    Write-Host "  Automatically rips DVDs and Blu-rays using MakeMKV."
    Write-Host "  Detects disc insertion, extracts main movie, ejects, and waits for next disc.`n"
    
    Write-Host "PARAMETERS:" -ForegroundColor Yellow
    Write-Host "  -MinLengthSeconds <int>" -ForegroundColor Green
    Write-Host "      Minimum track length in seconds to consider as main movie."
    Write-Host "      Default: 3600 (1 hour)"
    Write-Host "      Example: .\makemkv-autorip.ps1 -MinLengthSeconds 5400`n"
    
    Write-Host "  -UpdateTitleInfo" -ForegroundColor Green
    Write-Host "      Update titleinfo.json files for existing rips in the rip root directory."
    Write-Host "      Searches TMDb for each folder and creates titleinfo.json if missing."
    Write-Host "      Requires TMDb lookup to be enabled in settings.json."
    Write-Host "      Example: .\makemkv-autorip.ps1 -UpdateTitleInfo`n"
    
    Write-Host "  -Help" -ForegroundColor Green
    Write-Host "      Display this help information.`n"
    
    Write-Host "CONFIGURATION:" -ForegroundColor Yellow
    Write-Host "  Settings are loaded from settings.json (copy from settings.example.json)"
    Write-Host "  Configure MakeMKV path, rip directory, TMDb API key, and other options.`n"
    
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\makemkv-autorip.ps1"
    Write-Host "      Start auto-rip with default settings`n"
    
    Write-Host "  .\makemkv-autorip.ps1 -MinLengthSeconds 5400"
    Write-Host "      Start auto-rip requiring 90-minute minimum track length`n"
    
    Write-Host "  .\makemkv-autorip.ps1 -UpdateTitleInfo"
    Write-Host "      Update titleinfo.json for all existing rips`n"
    
    exit 0
}

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

# Cache for TMDb image base URL (fetched once per session)
$script:TMDbImageBaseUrl = $null

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
            
            $formattedTitle = if ($releaseYear) { "$title ($releaseYear)" } else { $title }
            
            # Return the formatted title, movie ID, and basic movie data
            return [PSCustomObject]@{
                Title = $formattedTitle
                MovieId = $movie.id
                MovieData = $movie
            }
        }
    } catch {
        Write-Warning "TMDb lookup failed: $($_.Exception.Message)"
    }

    return $null
}

function Get-TMDbMovieDetails([int]$movieId) {
    if (-not $UseTMDbLookup -or $TMDbApiKey -eq "YOUR_TMDB_API_KEY_HERE") {
        return $null
    }
    
    if (-not $movieId -or $movieId -le 0) {
        Write-Warning "Invalid movie ID provided to Get-TMDbMovieDetails"
        return $null
    }

    try {
        $url = "https://api.themoviedb.org/3/movie/${movieId}?api_key=$TMDbApiKey&language=en-US"
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        return $response
    } catch {
        Write-Warning "TMDb details lookup failed: $($_.Exception.Message)"
    }

    return $null
}

function Get-TMDbConfiguration {
    if (-not $UseTMDbLookup -or $TMDbApiKey -eq "YOUR_TMDB_API_KEY_HERE") {
        return $null
    }

    # Return cached value if already fetched
    if ($script:TMDbImageBaseUrl) {
        return $script:TMDbImageBaseUrl
    }

    try {
        $url = "https://api.themoviedb.org/3/configuration?api_key=$TMDbApiKey"
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        
        if ($response.images -and $response.images.secure_base_url) {
            $script:TMDbImageBaseUrl = $response.images.secure_base_url
            Write-Host "TMDb image base URL: $script:TMDbImageBaseUrl" -ForegroundColor Cyan
            return $script:TMDbImageBaseUrl
        }
    } catch {
        Write-Warning "TMDb configuration lookup failed: $($_.Exception.Message)"
    }

    return $null
}

function Download-MoviePoster([string]$folderPath, [string]$posterPath) {
    if (-not $UseTMDbLookup -or $TMDbApiKey -eq "YOUR_TMDB_API_KEY_HERE") {
        return $false
    }
    
    if ([string]::IsNullOrWhiteSpace($posterPath)) {
        Write-Host "  No poster path available" -ForegroundColor Yellow
        return $false
    }
    
    # Check if poster already exists
    $existingPoster = Get-ChildItem -Path $folderPath -Filter "poster.*" -File -ErrorAction SilentlyContinue
    if ($existingPoster) {
        Write-Host "  Poster already exists: $($existingPoster.Name)" -ForegroundColor Gray
        return $true
    }
    
    # Get TMDb configuration for base URL
    $baseUrl = Get-TMDbConfiguration
    if (-not $baseUrl) {
        Write-Warning "  Failed to get TMDb image base URL"
        return $false
    }
    
    try {
        # Build the full poster URL (using 'original' size)
        $posterUrl = "${baseUrl}original${posterPath}"
        Write-Host "  Downloading poster from: $posterUrl" -ForegroundColor Cyan
        
        # Get the file extension from the poster path
        $extension = [System.IO.Path]::GetExtension($posterPath)
        if ([string]::IsNullOrWhiteSpace($extension)) {
            $extension = ".jpg"  # Default to jpg if no extension
        }
        
        # Create temporary file path
        $tempFile = Join-Path $folderPath "poster_temp$extension"
        $finalFile = Join-Path $folderPath "poster$extension"
        
        # Download the poster
        Invoke-WebRequest -Uri $posterUrl -OutFile $tempFile -ErrorAction Stop
        
        # Rename to final name
        Move-Item -Path $tempFile -Destination $finalFile -Force
        
        Write-Host "  Poster saved: poster$extension" -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "  Failed to download poster: $($_.Exception.Message)"
        
        # Clean up temp file if it exists
        $tempFile = Join-Path $folderPath "poster_temp*"
        Get-ChildItem -Path $tempFile -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        
        return $false
    }
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
    $tmdbResult = $null
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
        
        $tmdbResult = Get-TMDbMovieTitle -searchQuery $cleanedLabel -year $year
        if ($tmdbResult) {
            Write-Host "TMDb lookup found: $($tmdbResult.Title)" -ForegroundColor Green
            return [PSCustomObject]@{
                Title = $tmdbResult.Title
                MovieId = $tmdbResult.MovieId
                TMDbData = $tmdbResult.MovieData
            }
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
                
                $tmdbResult = Get-TMDbMovieTitle -searchQuery $searchTitle -year $searchYearInt
                if ($tmdbResult) {
                    Write-Host "TMDb lookup found: $($tmdbResult.Title)" -ForegroundColor Green
                    return [PSCustomObject]@{
                        Title = $tmdbResult.Title
                        MovieId = $tmdbResult.MovieId
                        TMDbData = $tmdbResult.MovieData
                    }
                } else {
                    Write-Host "No results found for manual search" -ForegroundColor Yellow
                }
            }
        }
    }

    # Fallback to disc info (no TMDb data)
    $fallbackTitle = $null
    if ($volumeLabel -and $year) {
        $fallbackTitle = "$volumeLabel ($year)"
    } elseif ($volumeLabel) {
        $fallbackTitle = $volumeLabel
    }
    
    if ($fallbackTitle) {
        return [PSCustomObject]@{
            Title = $fallbackTitle
            TMDbData = $null
        }
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

function Update-ExistingTitleInfo {
    Write-Host "Updating title info for existing rips in $RipRoot" -ForegroundColor Cyan
    Write-Host ""
    
    $folders = Get-ChildItem -Path $RipRoot -Directory
    $processed = 0
    $skipped = 0
    $updated = 0
    $postersDownloaded = 0
    
    foreach ($folder in $folders) {
        $folderPath = $folder.FullName
        $folderName = $folder.Name
        $titleInfoFile = Join-Path $folderPath "titleinfo.json"
        
        # Check if poster already exists
        $existingPoster = Get-ChildItem -Path $folderPath -Filter "poster.*" -File -ErrorAction SilentlyContinue
        
        # If titleinfo.json exists and poster exists, skip this folder
        if ((Test-Path $titleInfoFile) -and $existingPoster) {
            Write-Host "Skipping '$folderName' - titleinfo.json and poster already exist" -ForegroundColor Gray
            $skipped++
            continue
        }
        
        Write-Host "Processing '$folderName'..." -ForegroundColor Yellow
        
        # Case 1: titleinfo.json exists but no poster - just download poster
        if (Test-Path $titleInfoFile) {
            Write-Host "  titleinfo.json exists, fetching missing poster..." -ForegroundColor Cyan
            
            try {
                $existingTitleInfo = Get-Content $titleInfoFile -Raw | ConvertFrom-Json
                
                if ($existingTitleInfo.poster_path) {
                    $downloadSuccess = Download-MoviePoster -folderPath $folderPath -posterPath $existingTitleInfo.poster_path
                    if ($downloadSuccess) {
                        $postersDownloaded++
                    }
                } else {
                    Write-Host "  No poster_path in titleinfo.json" -ForegroundColor Yellow
                }
                
                $processed++
                Write-Host ""
                continue
            } catch {
                Write-Warning "  Failed to read titleinfo.json: $($_.Exception.Message)"
                $skipped++
                Write-Host ""
                continue
            }
        }
        
        # Case 2: titleinfo.json doesn't exist - full lookup and create titleinfo.json + download poster
        # Try to parse year from folder name if present
        $searchTitle = $folderName
        $searchYear = $null
        if ($folderName -match '(.+?)\s*\((\d{4})\)') {
            $searchTitle = $matches[1].Trim()
            $searchYear = [int]$matches[2]
            Write-Host "  Parsed title: $searchTitle, Year: $searchYear" -ForegroundColor Cyan
        }
        
        # Search TMDb
        $tmdbResult = Get-TMDbMovieTitle -searchQuery $searchTitle -year $searchYear
        
        if (-not $tmdbResult) {
            Write-Host "  No TMDb results found for '$searchTitle' - skipping" -ForegroundColor Yellow
            $skipped++
            Write-Host ""
            continue
        }
        
        Write-Host "  Found: $($tmdbResult.Title)" -ForegroundColor Green
        
        # Fetch detailed movie info
        Write-Host "  Fetching detailed movie info..." -ForegroundColor Cyan
        $detailedMovieData = Get-TMDbMovieDetails -movieId $tmdbResult.MovieId
        
        if (-not $detailedMovieData) {
            Write-Host "  Failed to fetch detailed movie info - skipping" -ForegroundColor Yellow
            $skipped++
            Write-Host ""
            continue
        }
        
        # Try to detect disc type from existing metadata or structure
        $discType = "UNKNOWN"
        
        # Check for old .disctype file
        $oldDiscTypeFile = Join-Path $folderPath ".disctype"
        if (Test-Path $oldDiscTypeFile) {
            $discType = (Get-Content $oldDiscTypeFile -Raw).Trim()
            Write-Host "  Disc type from legacy file: $discType" -ForegroundColor Cyan
        }
        
        # Build title info with detailed TMDb data
        $titleInfo = $detailedMovieData
        $titleInfo | Add-Member -NotePropertyName "disctype" -NotePropertyValue $discType -Force
        $titleInfo | Add-Member -NotePropertyName "title" -NotePropertyValue $tmdbResult.Title -Force
        
        # Save title info
        $titleInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $titleInfoFile
        Write-Host "  Created titleinfo.json" -ForegroundColor Green
        
        # Download poster if available
        if ($detailedMovieData.poster_path) {
            Write-Host "  Fetching movie poster..." -ForegroundColor Cyan
            $downloadSuccess = Download-MoviePoster -folderPath $folderPath -posterPath $detailedMovieData.poster_path
            if ($downloadSuccess) {
                $postersDownloaded++
            }
        } else {
            Write-Host "  No poster available for this movie" -ForegroundColor Yellow
        }
        
        $updated++
        $processed++
        Write-Host ""
    }
    
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host "Update complete!" -ForegroundColor Green
    Write-Host "  Processed: $processed"
    Write-Host "  Updated: $updated"
    Write-Host "  Posters downloaded: $postersDownloaded"
    Write-Host "  Skipped: $skipped"
    Write-Host "============================"
}

# Check if we're in update mode
if ($UpdateTitleInfo) {
    if (-not $UseTMDbLookup -or $TMDbApiKey -eq "YOUR_TMDB_API_KEY_HERE") {
        Write-Error "TMDb lookup must be enabled to update title info. Please configure TMDbApiKey in settings.json."
        exit 1
    }
    
    Update-ExistingTitleInfo
    exit 0
}

Write-Host "MakeMKV auto-rip started. Waiting for disc..."

while ($true) {
    $dvd = Get-DvdDrive

    if ($dvd) {
        $proposedTitleObj = Get-ProposedTitle
        $proposedTitle = if ($proposedTitleObj) { $proposedTitleObj.Title } else { $null }
        $movieId = if ($proposedTitleObj) { $proposedTitleObj.MovieId } else { $null }
        
        $userTitle = Get-UserTitle -proposedTitle $proposedTitle
        $safeTitle = Get-SafeName $userTitle

        if (-not $safeTitle) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $safeTitle = "DISC_$timestamp"
        }

        $jobDir = Get-UniqueDirectory -root $RipRoot -name $safeTitle
        New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

        # Detect disc type
        $discType = Get-DiscType
        Write-Host "Detected disc type: $discType" -ForegroundColor Cyan
        
        # Build comprehensive title info metadata
        $titleInfo = [PSCustomObject]@{
            disctype = $discType
            title = $userTitle
        }
        
        # If user accepted TMDb result, fetch detailed movie info
        if ($movieId -and ($userTitle -eq $proposedTitle)) {
            Write-Host "Fetching detailed movie info from TMDb..." -ForegroundColor Cyan
            $detailedMovieData = Get-TMDbMovieDetails -movieId $movieId
            
            if ($detailedMovieData) {
                # Use the detailed movie data and inject disctype and title
                $detailedMovieData | Add-Member -NotePropertyName "disctype" -NotePropertyValue $discType -Force
                $detailedMovieData | Add-Member -NotePropertyName "title" -NotePropertyValue $userTitle -Force
                $titleInfo = $detailedMovieData
                Write-Host "Detailed movie info retrieved" -ForegroundColor Green
            } else {
                Write-Warning "Failed to fetch detailed movie info, using basic metadata"
            }
        }
        
        # Save title info as JSON
        $titleInfoFile = Join-Path $jobDir "titleinfo.json"
        $titleInfo | ConvertTo-Json -Depth 10 | Set-Content -Path $titleInfoFile
        Write-Host "Saved title info to titleinfo.json" -ForegroundColor Cyan
        
        # Download poster if available
        if ($titleInfo.poster_path) {
            Write-Host "Downloading movie poster..." -ForegroundColor Cyan
            Download-MoviePoster -folderPath $jobDir -posterPath $titleInfo.poster_path | Out-Null
        }

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

