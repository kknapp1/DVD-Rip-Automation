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
            
            $formattedTitle = if ($bestYear) { "$bestTitle ($bestYear)" } else { $bestTitle }
            
            # Return object with title and ID
            return [PSCustomObject]@{
                Title = $formattedTitle
                MovieId = $bestMatch.id
            }
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

function Get-TMDbMovieDetails([int]$movieId) {
    if ($TMDbApiKey -eq "YOUR_TMDB_API_KEY_HERE") {
        Write-Error "Please set your TMDb API key in the script first!"
        return $null
    }
    
    if (-not $movieId -or $movieId -le 0) {
        Write-Error "Invalid movie ID: $movieId"
        return $null
    }

    try {
        $url = "https://api.themoviedb.org/3/movie/${movieId}?api_key=$TMDbApiKey&language=en-US"
        
        Write-Host "`nQuerying TMDb API for movie details..." -ForegroundColor Cyan
        Write-Host "Movie ID: $movieId" -ForegroundColor Gray
        Write-Host "URL: $($url -replace $TMDbApiKey, '***API_KEY***')" -ForegroundColor Gray

        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        return $response
    } catch {
        Write-Host "`nError fetching movie details: $($_.Exception.Message)" -ForegroundColor Red
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
    Write-Host "3. Test detailed movie info (by ID)"
    Write-Host "4. Test search + detailed info flow"
    Write-Host "5. Test API connection"
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
            Write-Host "`n[MATCH] $($result.Title)" -ForegroundColor Green -BackgroundColor Black
            Write-Host "[ID] Movie ID: $($result.MovieId)" -ForegroundColor Gray
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
        Write-Host "`n[MATCH] $($result.Title)" -ForegroundColor Green -BackgroundColor Black
        Write-Host "[ID] Movie ID: $($result.MovieId)" -ForegroundColor Gray
    } else {
        Write-Host "`n[NO MATCH] No match found" -ForegroundColor Red
    }
}

function Test-MovieDetails {
    Write-Host "`n==================================" -ForegroundColor Cyan
    Write-Host "Test Get-TMDbMovieDetails" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    
    $movieIdInput = Read-Host "`nEnter TMDb Movie ID (or press Enter for Die Hard = 562)"
    $movieId = if ([string]::IsNullOrWhiteSpace($movieIdInput)) { 562 } else { [int]$movieIdInput }
    
    Write-Host "`nFetching detailed info for Movie ID: $movieId" -ForegroundColor Yellow
    
    $details = Get-TMDbMovieDetails -movieId $movieId
    
    if ($details) {
        Write-Host "`n==================================" -ForegroundColor Green
        Write-Host "Movie Details Retrieved Successfully" -ForegroundColor Green
        Write-Host "==================================" -ForegroundColor Green
        
        Write-Host "`nBasic Info:" -ForegroundColor Cyan
        Write-Host "  Title: $($details.title)" -ForegroundColor White
        Write-Host "  Original Title: $($details.original_title)" -ForegroundColor Gray
        Write-Host "  Release Date: $($details.release_date)" -ForegroundColor White
        Write-Host "  Runtime: $($details.runtime) minutes" -ForegroundColor White
        Write-Host "  Status: $($details.status)" -ForegroundColor White
        Write-Host "  Tagline: $($details.tagline)" -ForegroundColor Gray
        
        Write-Host "`nRatings:" -ForegroundColor Cyan
        Write-Host "  Vote Average: $($details.vote_average)/10" -ForegroundColor White
        Write-Host "  Vote Count: $($details.vote_count)" -ForegroundColor White
        Write-Host "  Popularity: $($details.popularity)" -ForegroundColor White
        
        Write-Host "`nFinancials:" -ForegroundColor Cyan
        Write-Host "  Budget: `$$($details.budget.ToString('N0'))" -ForegroundColor White
        Write-Host "  Revenue: `$$($details.revenue.ToString('N0'))" -ForegroundColor White
        
        if ($details.genres -and $details.genres.Count -gt 0) {
            Write-Host "`nGenres:" -ForegroundColor Cyan
            foreach ($genre in $details.genres) {
                Write-Host "  - $($genre.name)" -ForegroundColor White
            }
        }
        
        if ($details.production_companies -and $details.production_companies.Count -gt 0) {
            Write-Host "`nProduction Companies:" -ForegroundColor Cyan
            foreach ($company in $details.production_companies) {
                Write-Host "  - $($company.name)" -ForegroundColor White
            }
        }
        
        if ($details.spoken_languages -and $details.spoken_languages.Count -gt 0) {
            Write-Host "`nLanguages:" -ForegroundColor Cyan
            $languages = ($details.spoken_languages | ForEach-Object { $_.english_name }) -join ", "
            Write-Host "  $languages" -ForegroundColor White
        }
        
        Write-Host "`nOverview:" -ForegroundColor Cyan
        Write-Host "  $($details.overview)" -ForegroundColor White
        
        Write-Host "`nAPI Response Keys:" -ForegroundColor Cyan
        $keys = ($details.PSObject.Properties | Select-Object -ExpandProperty Name) -join ", "
        Write-Host "  $keys" -ForegroundColor Gray
        
    } else {
        Write-Host "`n[ERROR] Failed to retrieve movie details" -ForegroundColor Red
    }
}

function Test-SearchAndDetails {
    Write-Host "`n==================================" -ForegroundColor Cyan
    Write-Host "Test Complete Search + Details Flow" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "This tests the full workflow: Search -> Get ID -> Fetch Details" -ForegroundColor Gray
    
    $searchQuery = Read-Host "`nEnter movie title to search"
    if ([string]::IsNullOrWhiteSpace($searchQuery)) {
        Write-Host "Search cancelled." -ForegroundColor Yellow
        return
    }
    
    $yearInput = Read-Host "Enter year (optional - press Enter to skip)"
    $year = $null
    if (![string]::IsNullOrWhiteSpace($yearInput) -and $yearInput -match '^\d{4}$') {
        $year = [int]$yearInput
    }
    
    # Step 1: Search for movie
    Write-Host "`n[STEP 1] Searching for movie..." -ForegroundColor Yellow
    $searchResult = Get-TMDbMovieTitle -searchQuery $searchQuery -year $year
    
    if (-not $searchResult) {
        Write-Host "`n[FAILED] No search results found" -ForegroundColor Red
        return
    }
    
    Write-Host "`n[SUCCESS] Found: $($searchResult.Title)" -ForegroundColor Green
    Write-Host "[SUCCESS] Movie ID: $($searchResult.MovieId)" -ForegroundColor Green
    
    # Step 2: Fetch detailed info
    Write-Host "`n[STEP 2] Fetching detailed movie info..." -ForegroundColor Yellow
    $details = Get-TMDbMovieDetails -movieId $searchResult.MovieId
    
    if (-not $details) {
        Write-Host "`n[FAILED] Could not fetch detailed info" -ForegroundColor Red
        return
    }
    
    Write-Host "`n[SUCCESS] Retrieved detailed info!" -ForegroundColor Green
    
    # Display key details
    Write-Host "`n==================================" -ForegroundColor Cyan
    Write-Host "Complete Movie Information" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "Title: $($details.title) ($($details.release_date))" -ForegroundColor White
    Write-Host "Runtime: $($details.runtime) min | Rating: $($details.vote_average)/10" -ForegroundColor White
    Write-Host "Budget: `$$($details.budget.ToString('N0')) | Revenue: `$$($details.revenue.ToString('N0'))" -ForegroundColor White
    
    if ($details.genres) {
        $genreNames = ($details.genres | ForEach-Object { $_.name }) -join ", "
        Write-Host "Genres: $genreNames" -ForegroundColor White
    }
    
    Write-Host "`nOverview: $($details.overview)" -ForegroundColor Gray
    
    Write-Host "`n[SUCCESS] Complete workflow validated!" -ForegroundColor Green -BackgroundColor Black
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
        "3" { Test-MovieDetails }
        "4" { Test-SearchAndDetails }
        "5" { Test-TMDbConnection }
        "Q" { 
            Write-Host "`nExiting test harness..." -ForegroundColor Yellow
            exit 
        }
        default { 
            Write-Host "`nInvalid option. Please try again." -ForegroundColor Red 
        }
    }
}
