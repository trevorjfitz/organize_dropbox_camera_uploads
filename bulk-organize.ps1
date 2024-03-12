param (
    [int]$MaxFilesToProcess = 50, # Default to 50 if no value is provided
    [string]$AccessToken = "" #obtain from https://www.dropbox.com/developers/apps/info/8ku189tj0ib5gzr#settings
)

$FOLDER_TO_ORGANIZE = "/Camera Uploads"

$headers = @{
    Authorization = "Bearer $AccessToken"
    "Content-Type" = "application/json"
}

# Function to parse date from filename
function Parse-DateFromFilename {
    param ([string]$filename)

    $patterns = @(
        @{Regex = "(\d{4})-(\d{2})-(\d{2})";}, # Standard YYYY-MM-DD
        @{Regex = "IMG_(\d{4})(\d{2})(\d{2})";}, # IMG_YYYYMMDD
        @{Regex = "(\d{4})(\d{2})(\d{2})_";} # YYYYMMDD_HHMMSS.jpg
    )

    foreach ($pattern in $patterns) {
        if ($filename -match $pattern.Regex) {
            return [PSCustomObject]@{
                Year = $matches[1]
                Month = $matches[2]
            }
        }
    }

    return $null
}

# Updated logic to move files in batch and based on month-year
function Move-FilesByMonthYear {
    param (
        [System.Collections.Generic.Dictionary[string,System.Collections.ArrayList]]$filesToMove
    )

    $moveBatchUri = "https://api.dropboxapi.com/2/files/move_batch_v2"
    $checkJobStatusUri = "https://api.dropboxapi.com/2/files/move_batch/check_v2"

    # Debug print to see the files grouped before moving
    Write-Host "`nThis batch includes files for the following year/months:"
    foreach ($key in $filesToMove.Keys) {
        Write-Host "`t$key - $($filesToMove[$key].Count) files"
    }

    $keysProcessed = 0
    foreach ($key in $filesToMove.Keys) {
        Write-Host "`nMoving files for Year-Month: $key"
        foreach ($filename in $filesToMove[$key]) {
            Write-Host "`t$filename"
        }

        $year, $month = $key -split '-'
        $monthName = (Get-Culture).DateTimeFormat.GetMonthName([int]$month)
        $folderPath = "$FOLDER_TO_ORGANIZE/$year/$monthName"

        $entries = @()
        foreach ($filename in $filesToMove[$key]) {
            $entries += @{
                "from_path" = "$FOLDER_TO_ORGANIZE/$filename"
                "to_path" = "$folderPath/$filename"
            }
        }

        $moveBatchBody = @{
            "entries" = $entries
            "autorename" = $false
        } | ConvertTo-Json -Depth 10

        $response = Invoke-RestMethod -Uri $moveBatchUri -Method Post -Headers $headers -Body $moveBatchBody
        $jobId = $response.async_job_id
        $jobIdFriendly = "$($jobId.Substring(0, 15))...$($jobId.Substring($jobId.Length - 5, 5))"

        Write-Host "Job Summary"
        Write-Host "`tJob ID: $jobId"
        Write-Host "`tDestination: $folderPath"
        Write-Host "`tFiles to move: $($filesToMove[$key].Count)"
        Write-Host "`tJob $($keysProcessed + 1) of $($filesToMove.Keys.Count)"
        Write-Host "File transfer (Job ID $jobIdFriendly) initiated."
        
        # Initialize job status checking variables
        $startTime = Get-Date
        $jobComplete = $false
        $checkStatusBody = @{ async_job_id = $jobId } | ConvertTo-Json

        while (-not $jobComplete) {
            Start-Sleep -Seconds 2 # Wait for 2 seconds before checking the status again
            $statusResponse = Invoke-RestMethod -Uri $checkJobStatusUri -Method Post -Headers $headers -Body $checkStatusBody

            if ($statusResponse.'.tag' -eq "complete") {
                Write-Host "`nFile transfer (Job ID $jobIdFriendly) completed successfully!"
                Write-Host "`nYear-Month groups left to process: $($filesToMove.Keys.Count - $keysProcessed - 1)"
                $jobComplete = $true
            } elseif ($statusResponse.'.tag' -eq "failed") {
                Write-Host "`nFile transfer (Job ID $jobIdFriendly) failed: $($statusResponse)."
                $jobComplete = $true # Exit loop on failure, but ideally handle retry or error analysis
            } else {
                $elapsed = (Get-Date) - $startTime
                Write-Host "`rFile transfer (Job ID $jobIdFriendly) in progress... Time elapsed: $($elapsed.ToString('hh\:mm\:ss'))" -NoNewline
            }
        }
        $keysProcessed++
    }
}

function Process-Files {
    $listFolderUri = "https://api.dropboxapi.com/2/files/list_folder"
    $continueUri = "https://api.dropboxapi.com/2/files/list_folder/continue"
    $body = @{
        path = $FOLDER_TO_ORGANIZE
        recursive = $false
    } | ConvertTo-Json

    $filesToMove = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.ArrayList]'
    $subFolders = New-Object System.Collections.ArrayList
    $unparseableFileNames = New-Object System.Collections.ArrayList
    $processedCount = 0
    $hasMore = $true
    $cursor = $null

    Write-Host "`nScanning $FOLDER_TO_ORGANIZE for files..."
    
    while ($hasMore -and $processedCount -lt $MaxFilesToProcess) {
        if ($null -ne $cursor) {
            $response = Invoke-RestMethod -Uri $continueUri -Method Post -Headers $headers -Body (@{cursor = $cursor} | ConvertTo-Json)
        } else {
            $response = Invoke-RestMethod -Uri $listFolderUri -Method Post -Headers $headers -Body $body
        }

        foreach ($entry in $response.entries) {
            # Check if the entry is a file; ignore if it's a folder
            if ($entry.'.tag' -eq "file") {
                if ($processedCount -ge $MaxFilesToProcess) { break }

                $dateInfo = Parse-DateFromFilename -filename $entry.name
                if ($null -ne $dateInfo) {
                    # Date was parsed, organize it into the dictionary
                    $key = "$($dateInfo.Year)-$($dateInfo.Month)"
                    if (-not $filesToMove.ContainsKey($key)) {
                        $filesToMove[$key] = New-Object System.Collections.ArrayList
                    }

                    [void]$filesToMove[$key].Add($entry.name)
                    $processedCount++
                } else {
                    # Date not parseable, add to list
                    [void]$unparseableFileNames.Add($entry.name)
                }
            } else {
                # Entry wasn't a file, it was a folder
                [void]$subFolders.Add($entry.name)
            }
        }

        $cursor = $response.cursor
        $hasMore = $response.has_more
    }


    if ($subFolders.Count -gt 0) {
        Write-Host "`n$FOLDER_TO_ORGANIZE contains these subfolders (and maybe others) which will not be organized:"
        $subFolders | ForEach-Object { Write-Host "`t$_" }
    }

    if ($unparseableFileNames.Count -gt 0) {
        Write-Host "`nFiles with unparseable filenames:"
        $unparseableEntries | ForEach-Object { Write-Host "`t$_" }
    }

    Move-FilesByMonthYear -filesToMove $filesToMove
    return $processedCount
}


# Execution
try {
    $processedCount = Process-Files
    Write-Host "Batch complete! $processedCount files have were moved with love.`n"
} catch {
    Write-Host "Error: $_"
}
