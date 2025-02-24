# DocumentProcessor.ps1
# Enhanced document processing with embedding generation

# Load required assemblies using direct assembly loading
$assemblyList = @(
    'System.IO.Compression, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
    'System.IO.Compression.FileSystem, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089',
    'System.Xml.Linq, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089'
)

foreach ($assembly in $assemblyList) {
    try {
        [System.Reflection.Assembly]::Load($assembly) | Out-Null
        Write-Host "Successfully loaded assembly: $assembly"
    }
    catch {
        Write-Host "Warning loading assembly $assembly : $_"
    }
}

function ConvertTo-Hashtable {
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
    process {
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.Hashtable]) { return $InputObject }
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) {
                    ConvertTo-Hashtable $object
                }
            )
            return $collection
        }
        if ($InputObject -is [psobject]) {
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = ConvertTo-Hashtable $property.Value
            }
            return $hash
        }
        return $InputObject
    }
}

# Import configuration
$configPath = "F:\KnowledgeBase\config\settings.json"
$config = Get-Content $configPath | ConvertFrom-Json | ConvertTo-Hashtable
Write-Host "Configured supported types: $($config.FileProcessing.SupportedTypes -join ', ')"


# Import required modules
. .\VectorUtils.ps1

# Base document processor class
class DocumentProcessor {
    [string]$FilePath
    [hashtable]$Config
    [array]$Embeddings
    
    DocumentProcessor([string]$path, [hashtable]$config) {
        $this.FilePath = $path
        $this.Config = $config
        $this.Embeddings = @()
    }
    
    # Process document into chunks with embeddings
    [hashtable] ProcessDocument() {
        try {
            # Extract text
            $text = $this.ExtractText()
            if (-not $text) { throw "No text extracted" }
            
            # Create chunks
            $chunks = $this.CreateChunks($text)
            if (-not $chunks) { throw "No chunks created" }
            
            # Generate embeddings for chunks
            $processedChunks = @()

            Write-Host "Generating embeddings for chunks..."
           
            foreach ($chunk in $chunks) {
                Write-Host "`nProcessing chunk $($chunk.Metadata.ChunkNumber) of text: $($chunk.Content.Substring(0, [Math]::Min(50, $chunk.Content.Length)))..."  # Debug line
                
                $embedding = Get-TextEmbedding -Text $chunk.Content
                
                if ($embedding) {
                    #Write-Host "Generated embedding of length: $($embedding.Count)"  # Debug line
                    $processedChunk = @{
                        Id       = $chunk.Id
                        Content  = $chunk.Content
                        Embedding = $embedding
                        Metadata = $chunk.Metadata
                    }
                    $processedChunks += $processedChunk
                }
                else {
                    Write-Warning "Failed to generate embedding for chunk $($chunk.Metadata.ChunkNumber) after retries."  # Debug line
                }
            
                # Optional delay between chunks to prevent server overload
                Start-Sleep -Milliseconds 500  # Adjust if needed
            }

            Write-Host "--------------------------------------"
            Write-Host "All chunks processed."
            Write-Host "Successful embeddings: $($processedChunks.Count)"
            Write-Host "Failed embeddings: $($chunks.Count - $processedChunks.Count)"
            Write-Host "--------------------------------------"

            return @{
                Success = $true
                Chunks = $processedChunks
            }
        }
        catch {
            Write-Error "Processing failed: $_"
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
    
    # Create chunks from text with metadata
    [array] CreateChunks([string]$text) {
        $chunks = @()
        $words = $text -split '\s+'
        $chunkSize = $this.Config.FileProcessing.ChunkSizeTokens  # From config
        $overlap = $this.Config.FileProcessing.OverlapTokens      # From config
        
        Write-Host "Total words: $($words.Count)"
        Write-Host "Chunk size from config: $chunkSize"
        Write-Host "Overlap from config: $overlap"
        
        for ($i = 0; $i -lt $words.Count; $i += $chunkSize - $overlap) {
            $chunkWords = $words[$i..([Math]::Min($i + $chunkSize - 1, $words.Count - 1))]
            $chunkText = $chunkWords -join ' '
            
            Write-Host "Created chunk of $($chunkWords.Count) words ($($chunkText.Length) characters)"
            
            $chunks += @{
                Id = [guid]::NewGuid().ToString()
                Content = $chunkText
                Metadata = @{
                    SourceFile = Split-Path $this.FilePath -Leaf
                    FileType = [System.IO.Path]::GetExtension($this.FilePath)
                    ProcessedTime = Get-Date -Format "o"
                    StartIndex = $i
                    WordCount = $chunkWords.Count
                    TotalWords = $words.Count
                    ChunkNumber = [math]::Floor($i / ($chunkSize - $overlap)) + 1
                }
            }
        }
        
        Write-Host "Created $($chunks.Count) chunks"
        return $chunks
    }
    
    # Basic CanProcess implementation
    [bool] CanProcess([string]$extension) {
        return $false
    }
    
    # To be implemented by derived classes
    [string] ExtractText() {
        throw "ExtractText method must be implemented by derived classes"
    }
}

class WordProcessor : DocumentProcessor {
    hidden [Object]$word
    hidden [Object]$doc
    
    WordProcessor([string]$path, [hashtable]$config) : base($path, $config) {
        $this.word = $null
        $this.doc = $null
    }
    
    [bool] CanProcess([string]$extension) {
        return $extension -in @('.doc', '.docx')
    }
    
    [string] ExtractText() {
        $text = ""
        try {
            $this.word = New-Object -ComObject Word.Application
            $this.word.Visible = $false
            
            Write-Host "Processing Word document: $($this.FilePath)"
            $this.doc = $this.word.Documents.Open($this.FilePath)
            $text = $this.doc.Content.Text
            return $text
        }
        catch {
            Write-Error "Failed to process Word document: $_"
            return ""
        }
        finally {
            if ($this.doc) { 
                $this.doc.Close()
                $this.doc = $null
            }
            if ($this.word) {
                $this.word.Quit()
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($this.word) | Out-Null
                $this.word = $null
            }
        }
    }
}


function Debug-TextCleaning {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Text,
        [string]$Label = "Text"
    )
    
    #Write-Host "`n=== Starting $Label Debug ===" -ForegroundColor Cyan
    #Write-Host "Original length: $($Text.Length)"
    #Write-Host "Initial sample: '$($Text.Substring(0, [Math]::Min(50, $Text.Length)))...'"
    
    $cleanText = $Text
    
    # Step 1: More aggressive newline and quote cleaning
    $cleanText = $cleanText -replace '["''"]', ' ' # Remove various quote types
    $cleanText = $cleanText -replace '[\r\n\t\f\v]+', ' '
    # Write-Host "`nAfter newline cleanup:" -ForegroundColor Yellow
    # Write-Host "Length: $($cleanText.Length)"
    # Write-Host "Sample: '$($cleanText.Substring(0, [Math]::Min(50, $cleanText.Length)))...'"
    
    # Step 2: Clean control and special characters
    $cleanText = [System.Text.RegularExpressions.Regex]::Replace($cleanText, '[\x00-\x1F\x7F\u0080-\u009F]', ' ')
    # Write-Host "`nAfter control char cleanup:" -ForegroundColor Yellow
    # Write-Host "Length: $($cleanText.Length)"
    # Write-Host "Sample: '$($cleanText.Substring(0, [Math]::Min(50, $cleanText.Length)))...'"
    
    # Step 3: Clean multiple spaces and special whitespace
    $cleanText = $cleanText -replace '[\u00A0\u1680\u180E\u2000-\u200B\u2028\u2029\u202F\u205F\u3000]', ' '
    $cleanText = $cleanText -replace '\s{2,}', ' '
    # Write-Host "`nAfter space cleanup:" -ForegroundColor Yellow
    # Write-Host "Length: $($cleanText.Length)"
    # Write-Host "Sample: '$($cleanText.Substring(0, [Math]::Min(50, $cleanText.Length)))...'"
    
    # Step 4: Remove any remaining problematic characters and trim
    $cleanText = $cleanText -replace '[^\x20-\x7E]', '' # Keep only printable ASCII
    $cleanText = $cleanText.Trim()
    # Write-Host "`nAfter final trim:" -ForegroundColor Yellow
    # Write-Host "Length: $($cleanText.Length)"
    # Write-Host "Sample: '$($cleanText.Substring(0, [Math]::Min(50, $cleanText.Length)))...'"
    
    # Add hexdump of first few characters for debugging
    # Write-Host "`nHex dump of first 20 characters:" -ForegroundColor Yellow
    # $bytes = [System.Text.Encoding]::UTF8.GetBytes($cleanText.Substring(0, [Math]::Min(20, $cleanText.Length)))
    # Write-Host ([BitConverter]::ToString($bytes) -replace '-',' ')
    
    #Write-Host "`n=== End $Label Debug ===" -ForegroundColor Cyan
    
    return $cleanText
}


function Get-TextEmbedding {
    param (
        [string]$Text,
        [string]$Model = "nomic-embed-text"
    )
    
    $maxRetries = 3
    $retryDelaySeconds = 3
    $attempt = 0

    do {
        try {
            $attempt++
            Write-Host "`nAttempt $attempt to generate embedding" -ForegroundColor Green
            
            # Clean and debug the text
            $cleanText = Debug-TextCleaning -Text $Text -Label "Embedding Text"
            

            # Prepare request body
            $body = @{
                model = $Model
                prompt = $cleanText.Trim()
                stream = $false
                keep_alive = '1h'
            }

            # Convert to JSON and debug
            $jsonBody = $body | ConvertTo-Json -Compress
            Write-Host "`nRequest Details:" -ForegroundColor Yellow
            Write-Host "JSON Length: $($jsonBody.Length)"
            Write-Host "First 100 chars of JSON: $($jsonBody.Substring(0, [Math]::Min(100, $jsonBody.Length)))"
            

            # Make synchronous API call
            $response = Invoke-WebRequest -Method Post `
                                          -Uri "http://localhost:11434/api/embeddings" `
                                          -Body $jsonBody `
                                          -ContentType "application/json" `
                                          -ErrorVariable responseError

            if ($response.StatusCode -eq 200) {
                $result = $response.Content | ConvertFrom-Json
                Write-Host "Embedding generated successfully" -ForegroundColor Green
                return $result.embedding
            } elseif ($response.StatusCode -eq 400) {
                Write-Warning "400 Bad Request encountered on attempt $attempt. Retrying after $retryDelaySeconds seconds..."
                write-host "returned from ollama = $($response.Content)"
                Start-Sleep -Seconds $retryDelaySeconds
            } else {
                Write-Host "API call failed with status: $($response.StatusCode)"
                return $null
            }
        }
        catch {
            Write-Error "Failed to generate embedding: $_"
            Write-Host "Exception details: $($_.Exception.Message)"
            
            exit

            if ($attempt -lt $maxRetries) {
                Write-Host "Retrying after $retryDelaySeconds seconds..."
                Start-Sleep -Seconds $retryDelaySeconds
            }
        }
    } while ($attempt -lt $maxRetries)

    Write-Warning "Failed to generate embedding after $maxRetries attempts."
    return $null
}


# Excel processor
class ExcelProcessor : DocumentProcessor {
    hidden [Object]$excel
    hidden [Object]$workbook
    
    ExcelProcessor([string]$path, [hashtable]$config) : base($path, $config) {
        $this.excel = $null
        $this.workbook = $null
    }
    
    [bool] CanProcess([string]$extension) {
        return $extension -in @('.xls', '.xlsx', '.csv')
    }
    
    [string] ExtractText() {
        $text = ""
        try {
            $this.excel = New-Object -ComObject Excel.Application
            $this.excel.Visible = $false
            $this.excel.DisplayAlerts = $false
            
            Write-Host "Processing Excel document: $($this.FilePath)"
            $this.workbook = $this.excel.Workbooks.Open($this.FilePath)
            
            foreach ($worksheet in $this.workbook.Worksheets) {
                $text += "`nSheet: $($worksheet.Name)`n"
                $usedRange = $worksheet.UsedRange
                
                # Get column headers
                $headerRow = $usedRange.Rows(1)
                $headers = @()
                for ($col = 1; $col -le $usedRange.Columns.Count; $col++) {
                    $headers += $headerRow.Cells($col).Text
                }
                
                # Process data rows
                for ($row = 2; $row -le $usedRange.Rows.Count; $row++) {
                    $rowData = @()
                    for ($col = 1; $col -le $usedRange.Columns.Count; $col++) {
                        $cellValue = $usedRange.Cells($row, $col).Text
                        $rowData += "$($headers[$col-1]): $cellValue"
                    }
                    $text += $rowData -join " | "
                    $text += "`n"
                }
            }
            
            return $text
        }
        finally {
            if ($this.workbook) { 
                $this.workbook.Close()
                $this.workbook = $null
            }
            if ($this.excel) {
                $this.excel.Quit()
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($this.excel) | Out-Null
                $this.excel = $null
            }
        }
    }
}

# PDF processor using Word's PDF capabilities
class PDFProcessor : DocumentProcessor {
    hidden [Object]$word
    hidden [Object]$doc
    
    PDFProcessor([string]$path, [hashtable]$config) : base($path, $config) {
        $this.word = $null
        $this.doc = $null
    }
    
    [bool] CanProcess([string]$extension) {
        return $extension -eq '.pdf'
    }
    
    [string] ExtractText() {
        $text = ""
        try {
            $this.word = New-Object -ComObject Word.Application
            $this.word.Visible = $false
            
            Write-Host "Processing PDF document: $($this.FilePath)"
            $this.doc = $this.word.Documents.Open($this.FilePath)
            $text = $this.doc.Content.Text
            
            return $text
        }
        catch {
            Write-Error "Failed to extract PDF text: $_"
            return ""
        }
        finally {
            if ($this.doc) { 
                $this.doc.Close()
                $this.doc = $null
            }
            if ($this.word) {
                $this.word.Quit()
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($this.word) | Out-Null
                $this.word = $null
            }
        }
    }
}

# Transcript processor
class TranscriptProcessor : DocumentProcessor {
    TranscriptProcessor([string]$path, [hashtable]$config) : base($path, $config) {}   
    [bool] CanProcess([string]$extension) {
        return $extension -in @('.txt', '.vtt', '.srt')
    }
    
    [string] ExtractText() {
        try {
            Write-Host "Processing transcript: $($this.FilePath)"
            $content = Get-Content $this.FilePath -Raw
            Write-Host "Content length: $($content.Length) characters"  # Debug line
            
            # Handle different transcript formats
            $result = switch ([System.IO.Path]::GetExtension($this.FilePath)) {
                '.vtt' { $this.ProcessVTT($content) }
                '.srt' { $this.ProcessSRT($content) }
                default { $content }
            }
            
            Write-Host "Processed text length: $($result.Length) characters"  # Debug line
            return $result
        }
        catch {
            Write-Error "Failed to process transcript: $_"
            return ""
        }
    }
    
    hidden [string] ProcessVTT($content) {
        $lines = $content -split "`n"
        $text = ""
        $isHeader = $true
        
        foreach ($line in $lines) {
            if ($isHeader -and $line -match "WEBVTT") {
                $isHeader = $false
                continue
            }
            if ($line -match '^\d{2}:\d{2}.*-->.*\d{2}:\d{2}' -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            $text += "$line`n"
        }
        
        return $text
    }
    
    hidden [string] ProcessSRT($content) {
        $lines = $content -split "`n"
        $text = ""
        
        foreach ($line in $lines) {
            if ($line -match '^\d+$' -or 
                $line -match '^\d{2}:\d{2}.*-->.*\d{2}:\d{2}' -or 
                [string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            $text += "$line`n"
        }
        
        return $text
    }
}

class EPUBProcessor : DocumentProcessor {
    EPUBProcessor([string]$path, [hashtable]$config) : base($path, $config) {}
    
    [bool] CanProcess([string]$extension) {
        return $extension -eq '.epub'
    }

    [string] ExtractText() {
        Write-Host "Processing EPUB document: $($this.FilePath)"
        $text = ""
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        
        try {
            # Create temp directory
            New-Item -ItemType Directory -Path $tempPath | Out-Null
            
            # Extract EPUB using Expand-Archive
            Copy-Item -Path $this.FilePath -Destination "$tempPath\temp.zip"
            Expand-Archive -Path "$tempPath\temp.zip" -DestinationPath $tempPath -Force
            
            # Find the OPF file
            $opfFile = Get-ChildItem -Path $tempPath -Recurse -Filter "*.opf" | Select-Object -First 1
            if (-not $opfFile) {
                throw "No OPF file found in EPUB"
            }
            
            # Read OPF content using XML
            [xml]$opfContent = Get-Content $opfFile.FullName
            
            # Get book metadata
            $title = $opfContent.package.metadata.title
            $author = $opfContent.package.metadata.creator
            $text = "Title: $title`nAuthor: $author`n`n"
            
            # Find all content documents
            $contentFiles = Get-ChildItem -Path $tempPath -Recurse -Filter "*.xhtml"
            if (-not $contentFiles) {
                $contentFiles = Get-ChildItem -Path $tempPath -Recurse -Filter "*.html"
            }
            
            foreach ($file in $contentFiles) {
                Write-Host "Processing content file: $($file.Name)"
                [xml]$content = Get-Content $file.FullName
                
                # Extract text from body
                $bodyText = $content.html.body.InnerText
                $text += "`n$bodyText`n"
            }
            
            return $text.Trim()
        }
        catch {
            Write-Error "Failed to process EPUB: $_"
            return ""
        }
        finally {
            # Clean up temp directory
            if (Test-Path $tempPath) {
                Remove-Item -Path $tempPath -Recurse -Force
            }
        }
    }
}

# Create the embedding storage system
class EmbeddingStorage {
    [string]$BasePath
    [hashtable]$Config
    
    EmbeddingStorage([hashtable]$config) {
        $this.Config = $config
        $this.BasePath = $config.Paths.Embeddings
    }
    
    [bool] SaveEmbeddings([array]$chunks) {
        try {
            $storagePath = Join-Path $this.BasePath "embeddings.json"
            
            # Load existing data if any
            $existingData = @()
            if (Test-Path $storagePath) {
                $existingData = Get-Content $storagePath | ConvertFrom-Json
            }
            
            # Add new chunks
            $existingData += $chunks
            
            # Save updated data
            $existingData | ConvertTo-Json -Depth 10 | Set-Content $storagePath
            
            Write-Host "Saved embeddings to: $storagePath"
            Write-Host "Total embeddings in storage: $($existingData.Count)"
            
            return $true
        }
        catch {
            Write-Error "Failed to save embeddings: $_"
            return $false
        }
    }
}

# Main processing function

class DocumentProcessorFactory {
    static [DocumentProcessor] CreateProcessor([string]$filePath, [hashtable]$config) {
        $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
        
        $processors = @(
            [WordProcessor]::new($filePath, $config)
            [ExcelProcessor]::new($filePath, $config)
            [PDFProcessor]::new($filePath, $config)
            [TranscriptProcessor]::new($filePath, $config)
            [EPUBProcessor]::new($filePath, $config)
        )
        
        foreach ($processor in $processors) {
            if ($processor.CanProcess($extension)) {
                return $processor
            }
        }
        
        throw "No processor found for extension: $extension"
    }
}

function Start-EmbeddingProcessor {
    param([hashtable]$Config)
    
    Write-Host "Starting Embedding Knowledge Base system..."
    
    if (-not (Test-OllamaSetup)) {
        Write-Host "Ollama setup verification failed - please check installation and models"
        return
    }

    # Ensure all required directories exist
    $requiredPaths = @(
        $Config.Paths.Input,
        $Config.Paths.Storage,
        $Config.Paths.Embeddings,
        (Join-Path $Config.Paths.Base "processing"),
        (Join-Path $Config.Paths.Base "completed"),
        (Join-Path $Config.Paths.Base "error"),
        (Join-Path $Config.Paths.Input "unsupported_types")
    )
    
    foreach ($path in $requiredPaths) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created directory: $path"
        }
    }
    
    # Process existing files first
    Write-Host "Checking for existing files in input directory..."
    Get-ChildItem -Path $Config.Paths.Input -File | ForEach-Object {
        Start-ProcessNewFile -FilePath $_.FullName -Config $Config
    }
    
    Write-Host "Monitoring directory: $($Config.Paths.Input)"
    
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $Config.Paths.Input
    $watcher.Filter = "*.*"
    $watcher.IncludeSubdirectories = $false
    
    # Handle new files
    $action = {
        $path = $Event.SourceEventArgs.FullPath
        $fileName = Split-Path $path -Leaf
        
        Write-Host "`nNew file detected: $fileName"
        
        # Skip temporary files
        if ($fileName -like "~$*" -or $fileName -like "*.tmp") {
            Write-Host "Skipping temporary file: $fileName"
            return
        }
        
        # Give the system time to finish writing the file
        Start-Sleep -Seconds 2
        
        # Process the file
        Start-ProcessNewFile -FilePath $path -Config $Config
    }
    
    # Register for new files
    Register-ObjectEvent $watcher "Created" -Action $action | Out-Null
    
    $watcher.EnableRaisingEvents = $true
    Write-Host "========== INFO ==========" -ForegroundColor Blue -BackgroundColor White
    Write-Host "System ready - waiting for files..."  -ForegroundColor Blue
    Write-Host "Configured supported types: $($config.FileProcessing.SupportedTypes -join ', ')" -ForegroundColor Green
    Write-Host "Place files into the folder - $($Config.Paths.Input)"  -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop the watcher." -ForegroundColor Blue

    try {
        while ($true) { 
            Start-Sleep -Seconds 10 
            Write-Host "." -NoNewline
        }
    }
    finally {
        $watcher.EnableRaisingEvents = $false
        $watcher.Dispose()
        Get-EventSubscriber | Unregister-Event
    }
}

function Start-ProcessNewFile {
    param(
        [string]$FilePath,
        [hashtable]$Config
    )
    
    $fileName = Split-Path $FilePath -Leaf
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    # Check if supported file type
    if ($extension -notin $Config.FileProcessing.SupportedTypes) {
        $unsupportedPath = Join-Path $Config.Paths.Input "unsupported_types"
        Move-Item -Path $FilePath -Destination $unsupportedPath
        Write-Host "Moved unsupported file to: $unsupportedPath\$fileName"
        return
    }
    
    try {
        # Move to processing directory
        $processingPath = Join-Path $Config.Paths.Base "processing\$fileName"
        Move-Item -Path $FilePath -Destination $processingPath -Force
        Write-Host "Moved file to processing: $processingPath"
        
        # Create processor through factory
        $processor = [DocumentProcessorFactory]::CreateProcessor($processingPath, $Config)
        
        # Process document
        $result = $processor.ProcessDocument()
        
        if ($result.Success) {
            Write-Host "Document processed successfully"
            Write-Host "Generated $($result.Chunks.Count) embeddings"
            
            # Save embeddings
            $storage = [EmbeddingStorage]::new($Config)
            if ($storage.SaveEmbeddings($result.Chunks)) {
                # Move to completed
                $completedPath = Join-Path $Config.Paths.Base "completed\$fileName"
                Move-Item -Path $processingPath -Destination $completedPath -Force
                Write-Host "Moved to completed: $completedPath"
                Write-Host "Embedding generation process complete. Exiting with code 0."
            } else {
                throw "Failed to save embeddings"
            }
        } else {
            throw $result.Error
        }
    }
    catch {
        Write-Error "Error processing file: $_"
        
        # Move to error directory
        $errorPath = Join-Path $Config.Paths.Base "error\$fileName"
        if (Test-Path $processingPath) {
            Move-Item -Path $processingPath -Destination $errorPath -Force
            Write-Host "Moved to error directory: $errorPath"
        }
    }
}

function Test-OllamaSetup {
    Write-Host "Testing Ollama setup..."
    try {
        # Pull model if not exists
        Write-Host "Ensuring nomic-embed-text model is available..."
        & ollama pull nomic-embed-text
        
        Write-Host "Available models:"
        & ollama list
        
        return $true
    }
    catch {
        Write-Error "Ollama test failed: $_"
        return $false
    }
}


Start-EmbeddingProcessor -Config $config