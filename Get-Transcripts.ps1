# Import configuration
$configPath = "F:\KnowledgeBase\config\settings.json"
$config = Get-Content $configPath | ConvertFrom-Json

# Test-AI-Training.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


# Show progress messages with color coding
function Show-Progress {
    param(
        [string]$Message,
        [switch]$myError
    )
    if ($myError) {
        Write-Host "$Message" -ForegroundColor Red
    } else {
        Write-Host "$Message" -ForegroundColor Cyan
    }
}

function Write-YouTubeLog {
    param(
        [string]$VideoId,
        [string]$Url,
        [string]$YtDlpPath
    )
    
    try {
        # Define log file path
        $logFilePath = Join-Path $config.Paths.Base "logs\video_history.csv"
        
        # Create directory if it doesn't exist
        $logDir = Split-Path -Parent $logFilePath
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        }
        
        # Create CSV if it doesn't exist
        if (-not (Test-Path $logFilePath)) {
            "ChannelName,YoutubeUrl,Title,VideoId" | Set-Content $logFilePath
        }
        
        # Get video information using yt-dlp
        Show-Progress "Fetching video metadata..."
        $videoInfo = & $YtDlpPath --quiet --print "%(channel)s|%(title)s" $Url 2>> (Join-Path $config.Paths.Base "logs\download.log")
        
        if ($videoInfo) {
            # Split the piped output
            $channelName, $title = $videoInfo -split '\|'
            
            # Clean the strings (remove commas and any potential CSV-breaking characters)
            $channelName = $channelName -replace '[,"\r\n]', ' ' -replace '\s+', ' ' -replace '^\s+|\s+$', ''
            $title = $title -replace '[,"\r\n]', ' ' -replace '\s+', ' ' -replace '^\s+|\s+$', ''
            
            # Create CSV line
            $csvLine = "{0},{1},{2},{3}" -f $channelName, $Url, $title, $VideoId
            
            # Append to CSV
            Add-Content -Path $logFilePath -Value $csvLine
            Show-Progress "Video information logged to: $logFilePath"
        }
        else {
            Show-Progress -Error "Failed to fetch video metadata"
        }
    }
    catch {
        Show-Progress -Error "Failed to log video information: $_"
    }
}


function Format-ChunkContent {
    param([string]$Content)
    
    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw "Empty content provided"
    }
    
    # Clean up the content
    $cleaned = $Content.Trim()
    $cleaned = $cleaned -replace '\r\n', "`n"  # Normalize line endings
    $cleaned = $cleaned -replace '\n{3,}', "`n`n"  # Remove excessive blank lines
    
    return $cleaned
}

function Show-Message {
    param(
        [string]$Message,
        [string]$Type = "Info"  # Info, Success, Error
    )
    $emoji = switch($Type) {
        "Info"    { "💭" }
        "Success" { "✨" }
        "Error"   { "❌" }
    }
    $color = switch($Type) {
        "Info"    { "Cyan" }
        "Success" { "Green" }
        "Error"   { "Red" }
    }
    Write-Host "`n$emoji $Message" -ForegroundColor $color
}

# Detect if URL is a video or playlist
function Test-YouTubeUrl {
    param([string]$Url)
    try {
        if ($Url -match 'playlist\?list=') {
            return @{
                Type = 'playlist'
                Id = [regex]::Match($Url, 'list=([^&]+)').Groups[1].Value
            }
        }
        elseif ($Url -match 'v=([^&]+)' -or $Url -match 'youtu\.be/([^?&]+)') {
            return @{
                Type = 'video'
                Id = $Matches[1]
            }
        }
        else {
            throw "Invalid YouTube URL format"
        }
    }
    catch {
        throw "Failed to parse YouTube URL: $_"
    }
}


# Download and setup required tools
function Initialize-Dependencies {
    param([string]$ToolsPath)
    
    New-Item -ItemType Directory -Force -Path $ToolsPath | Out-Null
    
    # Download yt-dlp if needed
    $ytDlpPath = Join-Path $ToolsPath "yt-dlp.exe"
    if (-not (Test-Path $ytDlpPath)) {
        Show-Progress "Downloading yt-dlp..."
        $url = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        Invoke-WebRequest -Uri $url -OutFile $ytDlpPath
    }
    
    # Download ffmpeg if needed
    $ffmpegPath = Join-Path $ToolsPath "ffmpeg.exe"
    if (-not (Test-Path $ffmpegPath)) {
        Show-Progress "Downloading ffmpeg..."
        $url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
        $zipPath = Join-Path $ToolsPath "ffmpeg.zip"
        
        # Download and extract ffmpeg
        Invoke-WebRequest -Uri $url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $ToolsPath -Force
        
        # Move ffmpeg.exe to tools directory
        $extractedPath = Get-ChildItem -Path $ToolsPath -Filter "ffmpeg-master-latest-win64-gpl" -Directory
        Move-Item -Path (Join-Path $extractedPath.FullName "bin\ffmpeg.exe") -Destination $ffmpegPath -Force
        
        # Cleanup
        Remove-Item $zipPath -Force
        Remove-Item $extractedPath.FullName -Recurse -Force
    }
    
    # Add tools directory to PATH for this session
    $env:Path = "$ToolsPath;" + $env:Path
    return $ytDlpPath
}



# Clean up VTT transcript into plain text
function ProcessTranscript {
    param([string]$InputPath)
    
    try {
        Show-Progress "Processing transcript..."
        
        # Check if file exists first
        if (-not (Test-Path $InputPath)) {
            throw "Input file not found: $InputPath"
        }
        
        # Read the content
        try {
            $lines = Get-Content -Path $InputPath -ErrorAction Stop
        } catch {
            throw "Failed to read file: $_"
        }
        
        $cleanLines = New-Object System.Collections.ArrayList

        # Debug information
        Write-Host "Processing file: $InputPath"
        Write-Host "Found $($lines.Count) lines"

        $isHeader = $true
        foreach ($line in $lines) {
            # Skip header section
            if ($isHeader) {
                if ($line -match '^\s*$') {
                    $isHeader = $false
                }
                continue
            }

            # Skip timestamp lines and alignment info
            if ($line -match '^\d{2}:\d{2}:\d{2}' -or $line -match 'align:start position:0%') {
                continue
            }

            # Skip empty lines
            if ($line -match '^\s*$') {
                continue
            }

            # Clean up text content
            $text = $line -replace '<[^>]+>', ''    # Remove HTML tags
            $text = $text -replace '<.*$', ''       # Remove partial tags
            $text = $text -replace '\[.*?\]', ''    # Remove [Music], [Applause], etc.
            $text = $text.Trim()

            if ($text -ne '' -and -not ($text -match '(a|to|the|and|or|but|in|that|is|of|for)$')) {
                [void]$cleanLines.Add($text)
            }
        }

        # Debug information
        Write-Host "Cleaned lines: $($cleanLines.Count)"

        # Join lines using traditional method
        $finalText = ($cleanLines | Select-Object -Unique) -join " "
        $finalText = $finalText -replace '\s+', ' '  # Replace multiple spaces with single space
        $finalText = $finalText.Trim()
        
        # Create proper output filename and ensure directory exists
        $outputPath = $InputPath -replace '\.en\.vtt$', '.txt'
        $outputDir = Split-Path -Parent $outputPath
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Save the cleaned text
        Set-Content -Path $outputPath -Value $finalText -Force
        
        # Remove the original VTT file if it exists
        if (Test-Path $InputPath) {
            Remove-Item -Path $InputPath -Force
        }
        
        Show-Progress "Transcript cleaned and saved to: $outputPath"
        return $outputPath
    }
    catch {
        Show-Progress -Error "Failed to process transcript: $_"
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        throw
    }
}

# Main function to download and process transcripts
function Get-YouTubeTranscripts {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        # Setup environment
        $toolsPath = Join-Path $OutputPath "tools"
        $ytDlp = Initialize-Dependencies $toolsPath
        $transcriptPath = Join-Path $OutputPath "training"
        New-Item -ItemType Directory -Force -Path $transcriptPath | Out-Null
        
        # Get video information
        $urlInfo = Test-YouTubeUrl $Url
        $logFile = Join-Path $config.Paths.Base "logs\download.log"
        
        # Get video IDs
        $videoIds = @()
        if ($urlInfo.Type -eq 'playlist') {
            Show-Progress "Getting playlist information..."
            $playlistInfo = & $ytDlp --quiet --flat-playlist --print "%(id)s" $Url 2>> $logFile
            $videoIds = $playlistInfo -split "`n" | Where-Object { $_ }
        }
        else {
            Show-Progress "Processing single video..."
            $videoIds = @($urlInfo.Id)
        }
        
        Show-Progress "Found $($videoIds.Count) video(s) to process"
        
        # Process each video
        # In the Get-YouTubeTranscripts function:
        foreach ($videoId in $videoIds) {
            $baseFile = Join-Path $transcriptPath $videoId
            
            Show-Progress "Downloading transcript for video $videoId..."
            
            # Try to get auto-generated captions
            $myresult = & $ytDlp --quiet --skip-download --write-auto-sub --sub-format vtt --output "$baseFile" --sub-lang en "https://www.youtube.com/watch?v=$videoId" 2>> $logFile
            
            $myresult = Write-YouTubeLog -VideoId $videoId -Url "https://www.youtube.com/watch?v=$videoId" -YtDlpPath $ytDlp

            # Check for the VTT file
            $vttFile = "$baseFile.en.vtt"
            if (Test-Path $vttFile) {
                Show-Progress "Found transcript"
                $baseFile = ProcessTranscript -InputPath $vttFile
            } else {
                # Try manual captions as fallback
                $myresult = & $ytDlp --quiet --skip-download --write-sub --sub-format vtt --output "$baseFile" --sub-lang en "https://www.youtube.com/watch?v=$videoId" 2>> $logFile
                $vttFile = "$baseFile.en.vtt"
                
                if (Test-Path $vttFile) {
                    Show-Progress "Found manual transcript"
                    $baseFile = ProcessTranscript -InputPath $vttFile
                } else {
                    Show-Progress -Error "No transcript available for this video. Possible reasons:"
                    Write-Host "- Video has no auto-generated captions"
                    Write-Host "- Video has no manual captions"
                    Write-Host "- Captions are disabled for this video"
                    Write-Host "- Video might be music-only or non-verbal content"
                    throw "No transcript found for video $videoId"
                }
            }
        }
        
        Show-Progress "Transcripts downloaded successfully!"
        return $baseFile
    }
    catch {
        Show-Progress -Error "Failed to get transcripts: $_"
        throw
    }
}


function Test-QAFormat {
    param(
        [string]$Content,
        [switch]$Detailed
    )
    
    try {
        $lines = $Content -split "`n" | Where-Object { $_ -match '\S' }
        $isValid = $true
        $errors = @()
        $questionCount = 0
        $currentLine = 0
        
        while ($currentLine -lt $lines.Count) {
            $line = $lines[$currentLine].Trim()
            
            # Check for question format
            if ($line -match '^Question:\s+') {
                $questionCount++
                
                # Check if there's a next line and it's an answer
                if ($currentLine + 1 -ge $lines.Count) {
                    $errors += "Question at line $currentLine has no answer"
                    $isValid = $false
                    break
                }
                
                $nextLine = $lines[$currentLine + 1].Trim()
                if (-not ($nextLine -match '^Answer:\s+')) {
                    $errors += "Question at line $currentLine is not followed by an answer"
                    $isValid = $false
                }
                
                $currentLine += 2  # Move to next pair
            }
            else {
                $errors += "Line $currentLine does not start with 'Question:'"
                $isValid = $false
                $currentLine++
            }
        }
        
        $result = @{
            IsValid = $isValid
            QuestionCount = $questionCount
            Errors = $errors
        }
        
        if ($Detailed) {
            Show-Progress $(if ($isValid) { "Format validation passed: $questionCount Q&A pairs" } else { "Format validation failed" })
            if (-not $isValid) {
                $errors | ForEach-Object { Show-Progress -Error $_ }
            }
        }
        
        return $result
    }
    catch {
        Show-Progress -Error "Validation error: $_"
        return @{
            IsValid = $false
            QuestionCount = 0
            Errors = @("Validation failed: $($_.Exception.Message)")
        }
    }
}

function Split-TranscriptIntoChunks {
    param(
        [string]$Content,
        [int]$WordsPerChunk = 1000  # Adjustable chunk size
    )
    
    try {
        # Split content into words and remove empty entries
        $words = @($Content -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $chunks = [System.Collections.ArrayList]::new()
        
        # Debug output
        Show-Progress "Total words in transcript: $($words.Count)"
        
        if ($words.Count -eq 0) {
            throw "No content found in transcript"
        }
        
        # Calculate how many full chunks we'll have
        $totalChunks = [Math]::Ceiling($words.Count / $WordsPerChunk)
        
        # Process words into chunks
        for ($i = 0; $i -lt $totalChunks; $i++) {
            $startIndex = $i * $WordsPerChunk
            $endIndex = [Math]::Min($startIndex + $WordsPerChunk - 1, $words.Count - 1)
            
            # Get the words for this chunk
            $chunkWords = $words[$startIndex..$endIndex]
            $chunkText = $chunkWords -join ' '
            
            [void]$chunks.Add($chunkText)
            
            # Debug output for chunk
            Show-Progress "Created chunk $($chunks.Count) with $($chunkWords.Count) words"
        }
        
        # Final validation
        if ($chunks.Count -eq 0) {
            throw "No valid chunks created from content"
        }
        
        # Debug output for chunks
        foreach ($chunk in $chunks) {
            Write-Host "Chunk length: $($chunk.Length) characters" -ForegroundColor Yellow
        }
        
        Show-Progress "Successfully created $($chunks.Count) chunk(s)"
        return $chunks
    }
    catch {
        Show-Progress -Error "Failed to split transcript: $_"
        throw
    }
}

function Format-QAPairs {
    param([string]$Content)
    
    try {
        # Split into lines
        $lines = $Content -split "`n"
        
        # Filter to keep only Question/Answer lines and remove empty lines
        $cleanedLines = $lines | Where-Object { 
            $line = $_.Trim()
            ($line -match '^Question:\s+' -or $line -match '^Answer:\s+') -and $line -ne ''
        }
        
        return $cleanedLines -join "`n"
    }
    catch {
        Show-Progress -Error "Failed to clean Q&A pairs: $_"
        return $Content
    }
}
function Convert-TranscriptToQA {

    param(
        [string]$TranscriptPath,
        [int]$ChunkSize = 1000  # Words per chunk
    )
    
    try {
        Show-Progress "Converting transcript to Q&A format..."
        
        # Verify input path and read content
        if (-not (Test-Path -Path $TranscriptPath -PathType Leaf)) {
            throw "Input path must be a file: $TranscriptPath"
        }
        
        # Read the transcript
        $transcriptContent = Get-Content -Path $TranscriptPath -Raw
        if ([string]::IsNullOrWhiteSpace($transcriptContent)) {
            throw "No content found in transcript file"
        }
        
        # Split into chunks
        $chunks = Split-TranscriptIntoChunks -Content $transcriptContent -WordsPerChunk $ChunkSize
        Show-Progress "Split transcript into $($chunks.Count) chunks"
        
        # Process each chunk
        $allQAPairs = New-Object System.Collections.ArrayList
        
        foreach ($index in 0..($chunks.Count - 1)) {
            $chunk = $chunks[$index]
            if ([string]::IsNullOrWhiteSpace($chunk)) {
                Show-Progress -Error "Empty chunk detected at index $index, skipping..."
                continue
            }
            
            Show-Progress "Processing chunk $($index + 1) of $($chunks.Count)..."
            
            # Format the chunk content
            try {
                $formattedChunk = Format-ChunkContent -Content $chunk
                #Show-Progress "Formatted chunk preview:"
                #Write-Host ($formattedChunk.Substring(0, [Math]::Min(100, $formattedChunk.Length))) -ForegroundColor Cyan
            }
            catch {
                Show-Progress -Error "Failed to format chunk $($index + 1): $_"
                continue
            }
            
            # Construct the prompt
            $prompt = @"
            You are a knowledgeable test builder who is creating a Question and Answer study sheet for a course.
            
            Convert this educational content below into a series of question-answer pairs.
            Each pair should focus on teaching a specific concept from the text.
            Generate 5-10 high-quality pairs from this section of content.
            
            Remember:
            1. Questions should be clear and specific
            2. Answers should be accurate and detailed
            3. Each answer should be self-contained
            4. Keep the original meaning intact
            
            Format each question-answer pair EXACTLY like this:
            Question: [Question here]
            Answer: [Answer here]
            
            Content to convert:
            ##############################################
            $formattedChunk
            ##############################################
"@
            # Process with Ollama
            try {
                $body = @{
                    model = "llama3.2"
                    prompt = $prompt
                    stream = $false
                    options = @{
                        temperature = 0.7
                        top_p = 0.9
                    }
                } | ConvertTo-Json -Depth 10
                
                Show-Progress "Sending request to Ollama..."
                ##Show-Progress "Preview of content being sent:"
                #Write-Host ($formattedChunk.Substring(0, [Math]::Min(200, $formattedChunk.Length))) -ForegroundColor Yellow
                
                $response = Invoke-WebRequest -Method Post `
                    -Uri "http://localhost:11434/api/generate" `
                    -Body $body `
                    -ContentType "application/json"
                
                if ($response.StatusCode -eq 200) {
                    $result = $response.Content | ConvertFrom-Json
                    Show-Progress "Received response from Ollama"
                    
                    if (-not [string]::IsNullOrWhiteSpace($result.response)) {
                        #Show-Progress "Raw response preview:"
                        #Write-Host ($result.response.Substring(0, [Math]::Min(200, $result.response.Length))) -ForegroundColor Green
                        
                        $cleanResult = Format-QAPairs -Content $result.response
                        $validation = Test-QAFormat -Content $cleanResult
                        
                        if ($validation.IsValid) {
                            [void]$allQAPairs.Add($cleanResult)
                            Show-Progress "Successfully generated $($validation.QuestionCount) Q&A pairs"
                        }
                        else {
                            Show-Progress -Error "Invalid Q&A format in response"
                            $validation.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
                        }
                    }
                    else {
                        Show-Progress -Error "Empty response from Ollama"
                    }
                }else {
                    Show-Progress -Error "Failed to get response from Ollama: $($response.StatusCode)"
                }
            }
            catch {
                Show-Progress -Error "Error processing with Ollama: $_"
            }
        }
        Start-Sleep -Seconds 2
        
    }
    catch {
        Show-Progress -Error "Error processing with Ollama: $_"
    }

    if ($allQAPairs.Count -gt 0) {
        $processedPath = $TranscriptPath -replace '\.txt$', '_qa.txt'
        $combinedContent = $allQAPairs -join "`n`n"
        
        # Clean up formatting
        $combinedContent = $combinedContent -replace '\n{3,}', "`n`n"
        $combinedContent = $combinedContent.Trim()
        
        # Save to file
        Set-Content -Path $processedPath -Value $combinedContent
        Show-Progress "Successfully saved $($allQAPairs.Count) Q&A pairs to: $processedPath"
        
        return $processedPath
    }
    else {
        throw "No valid Q&A pairs were generated"
    }
}



# Main Process
try {
    
    Show-Progress "Starting AI Training Test Process"
    # Check environment
    Show-Progress "Checking environment..."
    Write-Host "OLLAMA_MODELS path: $env:OLLAMA_MODELS"
    Write-Host "Current models:"
    & F:\ollama\ollama.exe list
    
    $transcriptPath = $null
    while (-not $transcriptPath) {
        $youtubeUrl = Read-Host "Enter a YouTube URL (can be a video or playlist), or type 'exit' to quit"
        if ($youtubeUrl -eq 'exit') {
            Show-Progress "Exiting script..."
            return
        }
        
        try {
            $transcriptPath = Get-YouTubeTranscripts -Url $youtubeUrl -OutputPath $config.Paths.Base
            Show-Progress "Test completed successfully!"
            Show-Progress "Transcripts saved to: $transcriptPath"
        }
        catch {
            Show-Progress -Error $_.Exception.Message
            Write-Host "`nOptions:"
            Write-Host "1. Try another video URL (just paste a new URL)"
            Write-Host "2. Type 'manual' to enter transcript text manually"
            Write-Host "3. Type 'file' to load transcript from a local file"
            Write-Host "4. Type 'exit' to quit"
            
            $choice = Read-Host "What would you like to do"
            switch ($choice.ToLower()) {
                'manual' {
                    Show-Progress "Enter transcript text (press Ctrl+Z and Enter when done):"
                    $manualText = $input | Out-String
                    $manualFile = Join-Path $config.Paths.Base "training\manual_transcript.txt"
                    Set-Content -Path $manualFile -Value $manualText
                    $transcriptPath = $manualFile
                }
                'file' {
                    $filePath = Read-Host "Enter the path to your transcript file"
                    if (Test-Path $filePath) {
                        Copy-Item $filePath (Join-Path $config.Paths.Base "training\local_transcript.txt")
                        $transcriptPath = Join-Path $config.Paths.Base "training\local_transcript.txt"
                    }
                    else {
                        Show-Progress -Error "File not found: $filePath"
                    }
                }
                'exit' {
                    Show-Progress "Exiting script..."
                    return
                }
            }
        }
    }

    if ($transcriptPath) {
        $qaPath = Convert-TranscriptToQA -TranscriptPath $transcriptPath
        if (-not $qaPath) {
            throw "Failed to convert transcript to QA format"
        }
    }
    
}
catch {
    Show-Progress -Error $_.Exception.Message
}

Read-Host "Press Enter to exit"


