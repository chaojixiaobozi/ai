# PowerShell script to parse request_uri from CSV and count occurrences

$InputFile = "20250819applog.csv"
$OutputFile = "request_uri_counts.txt"

Write-Host "Starting to process file: $InputFile"

# Check if file exists
if (-not (Test-Path $InputFile)) {
    Write-Host "Error: File not found $InputFile"
    exit 1
}

# Create hashtable to count URI occurrences
$uriCounts = @{}

try {
    # Read CSV file
    $csvData = Import-Csv -Path $InputFile
    
    Write-Host "CSV columns: $($csvData[0].PSObject.Properties.Name -join ', ')"
    
    # Count request_uri occurrences
    $lineCount = 0
    foreach ($row in $csvData) {
        $lineCount++
        $requestUri = $row.request_uri
        
        if ($requestUri -and $requestUri.Trim() -ne "") {
            if ($uriCounts.ContainsKey($requestUri)) {
                $uriCounts[$requestUri]++
            } else {
                $uriCounts[$requestUri] = 1
            }
        }
        
        # Print progress every 10000 lines
        if ($lineCount % 10000 -eq 0) {
            Write-Host "Processed $lineCount lines..."
        }
    }
    
    Write-Host "Total processed: $lineCount lines"
    Write-Host "Found $($uriCounts.Count) unique request_uri"
    
    # Sort by count descending and write to output file
    $sortedUris = $uriCounts.GetEnumerator() | Sort-Object Value -Descending
    
    # Clear output file first
    if (Test-Path $OutputFile) {
        Remove-Item $OutputFile
    }
    
    $sortedUris | ForEach-Object {
        "$($_.Key):$($_.Value)" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
    }
    
    Write-Host "Results saved to: $OutputFile"
    
    # Show top 10 most common URIs
    Write-Host "`nTop 10 most common request_uri:"
    $i = 1
    $sortedUris | Select-Object -First 10 | ForEach-Object {
        Write-Host "$i. $($_.Key): $($_.Value)"
        $i++
    }
    
} catch {
    Write-Host "Error processing file: $($_.Exception.Message)"
}

Write-Host "Script execution completed" 