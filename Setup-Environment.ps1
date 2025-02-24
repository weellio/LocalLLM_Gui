#winget install Microsoft.PowerShell


# Combined setup script for Knowledge Base system

# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Show status messages with consistency
function Show-Status {
    param(
        [string]$Message,
        [string]$Type = "Info"  # Info, Success, Warning, Error
    )
    $colors = @{
        Info = "Cyan"
        Success = "Green"
        Warning = "Yellow"
        Error = "Red"
    }
    
    $symbol = switch($Type) {
        "Info"    { ">" }
        "Success" { "+" }
        "Warning" { "!" }
        "Error"   { "x" }
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$symbol] $Message" -ForegroundColor $colors[$Type]
}

# Show progress bar
function Show-Progress {
    param(
        [int]$Percent,
        [string]$Activity
    )
    $width = 50  # Fixed width for better compatibility
    $completed = [math]::Floor($width * ($Percent / 100))
    $remaining = $width - $completed
    
    $bar = "[" + ("#" * $completed) + ("-" * $remaining) + "]"
    Write-Host "`r$Activity $bar $Percent%" -NoNewline
}

# Select installation drive
function Select-InstallDrive {
    Clear-Host
    Write-Host "Welcome to the Knowledge Base Setup! `n" -ForegroundColor Green
    Write-Host "Let's pick where to install everything." -ForegroundColor Cyan
    Write-Host "The system needs space for models and data storage.`n"
    
    $drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    $menu = @{}
    $i = 1
    
    foreach ($drive in $drives) {
        $freeSpace = [math]::Round($drive.FreeSpace / 1GB, 2)
        Write-Host "$i. Drive $($drive.DeviceID) - $freeSpace GB free" -ForegroundColor Yellow
        $menu.Add($i, $drive.DeviceID)
        $i++
    }
    
    Write-Host "`nType a number and press Enter" -ForegroundColor Cyan
    $choice = Read-Host
    
    # Add debug output
    Write-Host "Selected choice: $choice"
    Write-Host "Available menu items: $($menu.Keys -join ', ')"
    
    if ($menu.ContainsKey([int]$choice)) {
        Write-Host "Returning drive: $($menu[[int]$choice])"
        return $menu[[int]$choice]
    } else {
        Write-Host "Invalid selection: $choice"
        return $null
    }
}

# Create directory structure
function Initialize-Environment {
    param(
        [string]$BasePath
    )
    
    Show-Status "Creating Knowledge Base folders..."
    
    # Core folders needed
    $folders = @{
        Input = "input"              # For new files
        Processing = "processing"    # During conversion
        Completed = "completed"      # Successfully processed
        Error = "error"              # Failed processing
        Storage = "storage"          # Processed content
        Config = "config"            # Settings
        Logs = "logs"                # System logs
        Models = "models"            # Model files
        training = "training"        # Training data before processing
        tools = "tools"              # Tools for processing
    }
    
    try {
        # Create base directory
        if (-not (Test-Path $BasePath)) {
            New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
            Show-Status "Created main directory: $BasePath" -Type "Success"
        }
        
        # Create each folder
        foreach ($folder in $folders.Keys) {
            $path = Join-Path $BasePath $folders[$folder]
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Show-Status "Created: $folder" -Type "Success"
            }
        }
        
        return $true
    }
    catch {
        Show-Status "Couldn't create folders: $_" -Type "Error"
        return $false
    }
}

# Setup configuration
# Update the Initialize-Configuration function
function Initialize-Configuration {
    param(
        [string]$BasePath
    )
    
    Show-Status "Setting up configuration..."
    
    $configPath = Join-Path $BasePath "config\settings.json"
    
    # Enhanced configuration
    $config = @{
        Version = "1.0"
        LastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Paths = @{
            Base = $BasePath
            Logs = Join-Path $BasePath "logs"
            Input = Join-Path $BasePath "input"
            Storage = Join-Path $BasePath "storage"
            Embeddings = Join-Path $BasePath "storage\embeddings"  

        }
        Ollama = @{
            Path = Join-Path $BasePath "models\ollama.exe"
            Models = @{
                Embedding = "nomic-embed-text"    
                General = "llama2:13b"            
                Reasoning = "deepseek-r1:8b"
            }
        }
        FileProcessing = @{
            MaxFileSizeMB = 50
            ChunkSizeTokens = 2000
            OverlapTokens = 200
            SupportedTypes = @(
                ".txt", ".docx", ".pdf", ".xlsx",
                ".xls", ".doc", ".vtt", ".srt", ".epub"
            )
        }
        Embedding = @{                           
            BatchSize = 10
            StorageFormat = "json"
            IndexTypes = @(
                "books",
                "documents",
                "transcripts"
            )
        }
    }
    
    try {
        # Save configuration
        $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
        Show-Status "Configuration saved" -Type "Success"
        
        # Create embedding storage directories
        foreach ($type in $config.Embedding.IndexTypes) {
            $typePath = Join-Path $config.Paths.Embeddings $type
            if (-not (Test-Path $typePath)) {
                New-Item -ItemType Directory -Path $typePath -Force | Out-Null
                Show-Status "Created embedding storage for: $type" -Type "Success"
            }
        }
        
        return $true
    }
    catch {
        Show-Status "Couldn't save configuration: $_" -Type "Error"
        return $false
    }
}

# Install Ollama
function Install-Ollama {
    param(
        [string]$BasePath
    )
    
    Show-Status "Checking Ollama installation..."
    
    try {
        # Check if ollama command is available
        $ollamaExists = Get-Command "ollama" -ErrorAction SilentlyContinue
        
        if ($ollamaExists) {
            Show-Status "Ollama is already installed" -Type "Success"
            
            # Verify it's working
            $testResult = & ollama list 2>&1
            
            # Show-Status "$testResult" -Type "Success"

            if ($LASTEXITCODE -eq 0) {
                Show-Status "Ollama is functioning correctly" -Type "Success"
                return $true
            } else {
                Show-Status "Ollama is installed but not responding correctly" -Type "Warning"
                throw "Existing Ollama installation may be corrupted"
            }
        }
        
        # If not installed, proceed with installation
        Show-Status "Installing Ollama..." -Type "Info"
        $installPath = Join-Path $BasePath "models"
        #$installer = Join-Path $installPath "ollama_installer.exe"
        
        #set environment variable
        [System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $installPath, [System.EnvironmentVariableTarget]::Machine)

        # Download
        #Show-Status "Downloading Ollama..." -Type "Info"
        #Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $installer
        
        # Install
        Show-Status "Installing..." -Type "Info"
        
        # Run winget install with specified location
        winget install -e --id Ollama.Ollama --location $installPath --accept-package-agreements --accept-source-agreements
        # Confirm installation
        & "$installPath\ollama.exe" --version

        
        #Start-Process -FilePath $installer -ArgumentList "/S" -Wait
        #Remove-Item $installer -Force
        
        #winget install -e --id Ollama.Ollama --location $installPath
        #winget upgrade -e --id Ollama.Ollama --location $installPath

        return $true
    }
    catch {
        Show-Status "Ollama setup error: $_" -Type "Error"
        return $false
    }
}

# Download models
# Update the Install-Models function
function Install-Models {
    Show-Status "Setting up AI models..."
    
    $models = @(
        @{
            Name = "nomic-embed-text"
            Description = "Embedding Model"
            Size = "4.1GB"
        },
        @{
            Name = "llama2:13b"
            Description = "Primary LLM"
            Size = "7.3GB"
        },
        @{
            Name = "llama3.2"
            Description = "Transcript LLM"
            Size = "2.0GB"
        },
        @{
            Name = "deepseek-r1:8b"
            Description = "Reasoning Model"
            Size = "4.8GB"
        }
    )

    $totalModels = $models.Count
    $currentModel = 0
    
    try {
        # Get list of installed models
        $installedModels = & ollama list 2>$null
        
        foreach ($model in $models) {
            $currentModel++
            
            # Check if model is already installed
            if ($installedModels -match $model.Name) {
                Show-Status "Model $($model.Description) already installed" -Type "Info"
                continue
            }
            
            Show-Status "Downloading $($model.Description) ($($model.Size))..." -Type "Info"
            Write-Host "Model $currentModel of $totalModels"
            
            # Start download with error suppression
            $downloadJob = Start-Job -ScriptBlock {
                param($modelName)
                $ErrorActionPreference = 'SilentlyContinue'
                & ollama pull $modelName 2>$null
            } -ArgumentList $model.Name
            
            # Show simple progress indicator
            while ($downloadJob.State -eq 'Running') {
                Write-Host "." -NoNewline
                Start-Sleep -Seconds 1
            }
            Write-Host ""
            
            # Get results and cleanup
            Receive-Job -Job $downloadJob | Where-Object { $_ -notmatch '^pulling manifest$' }
            Remove-Job -Job $downloadJob
            
            $percentComplete = [math]::Floor($currentModel / $totalModels * 100)
            Show-Progress -Percent $percentComplete -Activity "Installing Models"
            
            Show-Status "Completed download of $($model.Description)" -Type "Success"
        }
        
        Show-Status "Model setup completed" -Type "Success"
        return $true
    }
    catch {
        Show-Status "Model setup error: $_" -Type "Error"
        return $false
    }
}

# Test Office
function Test-Office {
    Show-Status "Checking Microsoft Office..."
    
    $tests = @(
        @{Name = "Word"; ProgID = "Word.Application"}
        @{Name = "Excel"; ProgID = "Excel.Application"}
    )
    
    $allPassed = $true
    
    foreach ($test in $tests) {
        try {
            $app = New-Object -ComObject $test.ProgID
            $app.Quit()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($app) | Out-Null
            Show-Status "$($test.Name) available" -Type "Success"
        }
        catch {
            Show-Status "$($test.Name) not available" -Type "Warning"
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# Main setup process
try {
    # Get install location
    $selectedDrive = Select-InstallDrive
    if (-not $selectedDrive) {
        throw "No drive selected"
    }
    
    Write-Host "Selected drive: $selectedDrive"  # Debug line
    $basePath = Join-Path $selectedDrive "KnowledgeBase"
    Write-Host "Base path will be: $basePath"    # Debug line
    
    # Create environment
    Write-Host "Attempting to initialize environment..."  # Debug line
    $envResult = Initialize-Environment $basePath
    if (-not $envResult) {
        throw "Environment setup failed - could not create required directories"
    }
    
    # Create configuration
    Write-Host "Attempting to initialize configuration..."  # Debug line
    $configResult = Initialize-Configuration $basePath
    if (-not $configResult) {
        throw "Configuration setup failed - could not create settings file"
    }
    
    # Install/Verify Ollama
    Write-Host "Checking Ollama installation..."  # Debug line
    $ollamaResult = Install-Ollama $basePath
    if (-not $ollamaResult) {
        throw "Ollama setup verification failed"
    }
    
    # Install/Verify models
    Write-Host "Checking model installation..."  # Debug line
    $modelResult = Install-Models
    if (-not $modelResult) {
        throw "Model installation failed"
    }
    
    # Test Office
    Write-Host "Testing Office installation..."  # Debug line
    if (-not (Test-Office)) {
        Show-Status "Office tests incomplete - some features may be limited" -Type "Warning"
    }
    
    Show-Status "Setup completed successfully!" -Type "Success"
    Write-Host "`nYour Knowledge Base system is ready to use." -ForegroundColor Green
    Write-Host "Start the DocumentProcessor and place files in the 'input' folder to begin processing." -ForegroundColor Yellow
}
catch {
    Show-Status "Setup failed with error: $($_.Exception.Message)" -Type "Error"
    Write-Host "Error occurred at line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Error details: $($_.Exception.StackTrace)" -ForegroundColor Red
    Write-Host "`nTry running the setup again. If the problem continues, check the logs." -ForegroundColor Yellow
}

Write-Host "`nPress Enter to exit..." -ForegroundColor Cyan
Read-Host