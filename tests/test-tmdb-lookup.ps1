# ============================
# TMDb API Test Harness
# Test movie lookups without needing a disc
# ============================

# TMDb API Configuration
$TMDbApiKey = "ffdf342eacb1301940a630aec612985a"  # Replace with your actual API key

function Get-TMDbMovieTitle([string]$searchQuery, [int]$year) {
    if ($TMDbApiKey -eq "YOUR_TMDB_API_KEY_HERE") {
        Write-Error "Please set your TMDb API key in the script first!"
        return $null
    }

    try {
        $encodedQuery = [System.Uri]::EscapeDataString($searchQuery)
        $url = "https://api.themoviedb.org/3/search/movie?api_key=$TMDbApiKey&query=$encodedQuery&include_adult=false&language=en-US"
        
        if ($year) {
            $url += "&primary_release_year=$year"
        }

        Write-Host "`nQuerying TMDb API..." -ForegroundColor Cyan
        Write-Host "URL: $($url -replace $TMDbApiKey, '***API_KEY***')" -ForegroundColor Gray

        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        
        if ($response.results -and $response.results.Count -gt 0) {
            Write-Host "`nFound $($response.results.Count) result(s):" -ForegroundColor Green
            
            # Show top 5 results
            for ($i = 0; $i -lt [Math]::Min(5, $response.results.Count); $i++) {
                $movie = $response.results[$i]
                $title = $movie.title
                $releaseYear = "Unknown"
                
                if ($movie.release_date -and $movie.release_date -match '^(\d{4})') {
                    $releaseYear = $matches[1]
                }
                
                $overview = $movie.overview
                if ($overview.Length -gt 100) {
                    $overview = $overview.Substring(0, 97) + "..."
                }
                
                Write-Host "`n[$($i+1)] $title ($releaseYear)" -ForegroundColor Yellow
                Write-Host "    Rating: $($movie.vote_average)/10 | Votes: $($movie.vote_count)" -ForegroundColor Gray
                Write-Host "    Overview: $overview" -ForegroundColor Gray
            }
            
            # Return the best match (first result)
            $bestMatch = $response.results[0]
            $bestTitle = $bestMatch.title
            $bestYear = $null
            
            if ($bestMatch.release_date -and $bestMatch.release_date -match '^(\d{4})') {
                $bestYear = $matches[1]
            }
            
            if ($bestYear) {
                return "$bestTitle ($bestYear)"
            }
            return $bestTitle
        } else {
            Write-Host "`nNo results found." -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            Write-Host "Status Code: $($_.Exception.Response.StatusCode.Value__)" -ForegroundColor Red
        }
        return $null
    }
}

function Test-TMDbConnection {
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "Testing TMDb API Connection" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    
    if ($TMDbApiKey -eq "YOUR_TMDB_API_KEY_HERE") {
        Write-Host "`nERROR: API key not set!" -ForegroundColor Red
        Write-Host "Please edit this script and replace YOUR_TMDB_API_KEY_HERE with your actual TMDb API key." -ForegroundColor Yellow
        Write-Host "Get a free API key at: https://www.themoviedb.org/settings/api" -ForegroundColor Yellow
        return $false
    }
    
    try {
        $testUrl = "https://api.themoviedb.org/3/configuration?api_key=$TMDbApiKey"
        $response = Invoke-RestMethod -Uri $testUrl -Method Get -ErrorAction Stop
        Write-Host "`n[OK] API Key Valid!" -ForegroundColor Green
        Write-Host "[OK] Connected to TMDb successfully!" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "`n[ERROR] Connection Failed!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Show-TestMenu {
    Write-Host "`n==================================" -ForegroundColor Cyan
    Write-Host "TMDb Movie Search Test Menu" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "1. Test predefined disc labels"
    Write-Host "2. Custom search"
    Write-Host "3. Test API connection"
    Write-Host "Q. Quit"
    Write-Host ""
}

function Test-PredefinedLabels {
    $testCases = @(
        @{ Label = "DIEHARD"; Year = 2007; Description = "Common abbreviated disc label" },
        @{ Label = "MATRIX"; Year = 2003; Description = "Single word title" },
        @{ Label = "LOTR_ROTK"; Year = 2004; Description = "Acronym-based label" },
        @{ Label = "INCEPTION"; Year = 2010; Description = "Full word match" },
        @{ Label = "SW_EMPIRE"; Year = 2004; Description = "Abbreviated franchise title" },
        @{ Label = "DARK_KNIGHT"; Year = 2008; Description = "Multi-word title" }
    )
    
    Write-Host "`n==================================" -ForegroundColor Cyan
    Write-Host "Testing Predefined Disc Labels" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    
    foreach ($test in $testCases) {
        Write-Host "`n----------------------------------" -ForegroundColor Cyan
        Write-Host "Test: $($test.Description)" -ForegroundColor Cyan
        Write-Host "Disc Label: '$($test.Label)' | Year: $($test.Year)" -ForegroundColor White
        
        $result = Get-TMDbMovieTitle -searchQuery $test.Label -year $test.Year
        
        if ($result) {
            Write-Host "`n[MATCH] $result" -ForegroundColor Green -BackgroundColor Black
        } else {
            Write-Host "`n[NO MATCH] No match found" -ForegroundColor Red
        }
        
        Write-Host "`nPress any key for next test..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}

function Test-CustomSearch {
    Write-Host "`n==================================" -ForegroundColor Cyan
    Write-Host "Custom Movie Search" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    
    $searchQuery = Read-Host "`nEnter disc label or movie title to search"
    if ([string]::IsNullOrWhiteSpace($searchQuery)) {
        Write-Host "Search cancelled." -ForegroundColor Yellow
        return
    }
    
    $yearInput = Read-Host "Enter year (optional - press Enter to skip)"
    $year = $null
    if (![string]::IsNullOrWhiteSpace($yearInput) -and $yearInput -match '^\d{4}$') {
        $year = [int]$yearInput
    }
    
    $result = Get-TMDbMovieTitle -searchQuery $searchQuery -year $year
    
    if ($result) {
        Write-Host "`n[MATCH] $result" -ForegroundColor Green -BackgroundColor Black
    } else {
        Write-Host "`n[NO MATCH] No match found" -ForegroundColor Red
    }
}

# Main test loop
Clear-Host
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "TMDb API Test Harness" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan

while ($true) {
    Show-TestMenu
    $choice = Read-Host "Select option"
    
    switch ($choice.ToUpper()) {
        "1" { Test-PredefinedLabels }
        "2" { Test-CustomSearch }
        "3" { Test-TMDbConnection }
        "Q" { 
            Write-Host "`nExiting test harness..." -ForegroundColor Yellow
            exit 
        }
        default { 
            Write-Host "`nInvalid option. Please try again." -ForegroundColor Red 
        }
    }
}
