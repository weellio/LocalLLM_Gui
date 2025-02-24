# DocumentsTab.ps1
# Module for Documents tab functionality in Knowledge Base GUI
# Style constants
$script:BUTTON_BLUE = [System.Drawing.Color]::FromArgb(52, 152, 219)
$script:BUTTON_GREEN = [System.Drawing.Color]::FromArgb(46, 204, 113)
$script:BUTTON_RED = [System.Drawing.Color]::FromArgb(231, 76, 60)
$script:BACKGROUND_WHITE = [System.Drawing.Color]::White
$script:BORDER_GRAY = [System.Drawing.Color]::FromArgb(224, 224, 224)

# State management
$script:processorJob = $null
$script:isProcessing = $false
$script:updateTimer = $null
$script:documentsList = $null
$script:processorButton = $null
$script:statusLabel = $null

function Initialize-DocumentsTab {
    param (
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.TabPage]$TabPage,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Configuration
    )
    
    Write-Host "DocumentsTab: Initializing with provided configuration..."
    
    if (-not $Configuration -or -not $Configuration.Paths) {
        Write-Host "Error: Invalid configuration provided to Documents tab"
        return $null
    }
    
    $global:KBConfig = $Configuration
    
    # Clear existing controls
    $TabPage.Controls.Clear()
    
    try {
        # Create controls
        $controls = New-DocumentsTabControls
        $TabPage.Controls.AddRange($controls)
        
        # Store documents list reference
        $script:documentsList = $controls | Where-Object { $_ -is [System.Windows.Forms.ListView] }
        
        # Initialize timer
        Initialize-UpdateTimer
        Update-DocumentsList
        Write-Host "Documents tab initialized successfully"
        return $script:documentsList
    }
    catch {
        Write-Host "Error initializing Documents tab: $_"
        return $null
    }
}
function Initialize-UpdateTimer {
    if ($script:updateTimer) {
        $script:updateTimer.Stop()
        $script:updateTimer.Dispose()
    }
    
    $script:updateTimer = New-Object System.Windows.Forms.Timer
    $script:updateTimer.Interval = 30000
    
    $script:updateTimer.Add_Tick({
        try {
            if ($global:KBConfig -and $script:documentsList) {
                Update-DocumentsList
            }
        }
        catch {
            Write-Host "Error in timer update: $_"
            # Stop timer if we encounter an error
            $script:updateTimer.Stop()
        }
    })
    
    $script:updateTimer.Start()
}

# function Update-DocumentsList {
#     if (-not $script:documentsList -or -not $global:KBConfig) { return }
    
#     try {
#         $script:documentsList.Items.Clear()
        
#         $completedPath = Join-Path $global:KBConfig.Paths.Base "completed"
#         $processingPath = Join-Path $global:KBConfig.Paths.Base "processing"
        
#         if (Test-Path $completedPath) {
#             Get-ChildItem $completedPath | ForEach-Object {
#                 $item = New-Object System.Windows.Forms.ListViewItem($_.Name)
#                 $item.SubItems.Add("Completed")
#                 $item.SubItems.Add($_.LastWriteTime.ToString("g"))
#                 $item.SubItems.Add("--")
#                 $script:documentsList.Items.Add($item)
#             }
#         }
        
#         if (Test-Path $processingPath) {
#             Get-ChildItem $processingPath | ForEach-Object {
#                 $item = New-Object System.Windows.Forms.ListViewItem($_.Name)
#                 $item.SubItems.Add("Processing")
#                 $item.SubItems.Add($_.LastWriteTime.ToString("g"))
#                 $item.SubItems.Add("--")
#                 $script:documentsList.Items.Add($item)
#             }
#         }
#     }
#     catch {
#         Write-Host "Error updating documents list: $_"
#     }
# }

function Update-DocumentsList {
    if (-not $script:documentsList -or -not $global:KBConfig) { return }
    
    # Static variable to track last update time
    if (-not $script:lastUpdateTime) {
        $script:lastUpdateTime = [DateTime]::MinValue
    }
    
    # Only update if it's been at least 30 seconds since the last update
    $now = [DateTime]::Now
    if (($now - $script:lastUpdateTime).TotalSeconds -lt 30) {
        return
    }
    
    $script:lastUpdateTime = $now
    
    try {
        $script:documentsList.Items.Clear()
        
        # Path to embeddings file
        $embeddingsPath = Join-Path $global:KBConfig.Paths.Embeddings "embeddings.json"
        
        if (Test-Path $embeddingsPath) {
            # Read and parse embeddings file
            $embeddingsContent = Get-Content $embeddingsPath | ConvertFrom-Json
            
            # Group chunks by source file and calculate statistics
            $documentStats = @{}
            
            foreach ($chunk in $embeddingsContent) {
                $sourceFile = $chunk.Metadata.SourceFile
                
                if (-not $documentStats.ContainsKey($sourceFile)) {
                    $documentStats[$sourceFile] = @{
                        ChunkCount = 0
                        LastProcessed = [DateTime]::MinValue
                        TotalWords = $chunk.Metadata.TotalWords
                    }
                }
                
                $documentStats[$sourceFile].ChunkCount++
                
                # Update last processed time if this chunk is newer
                $chunkTime = [DateTime]::Parse($chunk.Metadata.ProcessedTime)
                if ($chunkTime -gt $documentStats[$sourceFile].LastProcessed) {
                    $documentStats[$sourceFile].LastProcessed = $chunkTime
                }
            }
            
            # Add items to ListView
            foreach ($sourceFile in $documentStats.Keys) {
                $stats = $documentStats[$sourceFile]
                
                $item = New-Object System.Windows.Forms.ListViewItem($sourceFile)
                $item.SubItems.Add("Embedded") # Status
                $item.SubItems.Add($stats.LastProcessed.ToString("g"))
                $item.SubItems.Add($stats.ChunkCount.ToString())
                $script:documentsList.Items.Add($item)
            }
            
            # Only write to console when document count changes
            if (-not $script:lastDocumentCount -or $script:lastDocumentCount -ne $documentStats.Count) {
                Write-Host "Updated documents list from embeddings file"
                Write-Host "Found $($documentStats.Count) unique documents"
                $script:lastDocumentCount = $documentStats.Count
            }
        } else {
            Write-Host "No embeddings file found at: $embeddingsPath"
        }
    }
    catch {
        Write-Host "Error updating documents list: $_"
    }
}

function Get-DocumentStats {
    param (
        [string]$EmbeddingsPath,
        [string]$SourceFile
    )
    
    try {
        $stats = @{
            TotalChunks = 0
            TotalWords = 0
            LastProcessed = $null
            AverageChunkSize = 0
        }
        
        if (Test-Path $EmbeddingsPath) {
            $embeddings = Get-Content $EmbeddingsPath | ConvertFrom-Json
            $documentChunks = $embeddings | Where-Object { $_.Metadata.SourceFile -eq $SourceFile }
            
            if ($documentChunks) {
                $stats.TotalChunks = $documentChunks.Count
                $stats.TotalWords = $documentChunks[0].Metadata.TotalWords
                $stats.LastProcessed = ($documentChunks | ForEach-Object { [DateTime]::Parse($_.Metadata.ProcessedTime) } | Measure-Object -Maximum).Maximum
                $stats.AverageChunkSize = ($documentChunks | Measure-Object -Property { $_.Metadata.WordCount } -Average).Average
            }
        }
        
        return $stats
    }
    catch {
        Write-Host "Error getting document stats: $_"
        return $null
    }
}

function Start-CleanupDocumentsTab {
    if ($script:updateTimer) {
        $script:updateTimer.Stop()
        $script:updateTimer.Dispose()
    }
    
    if ($script:processorJob) {
        try {
            Stop-Process -Id $script:processorJob.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Error cleaning up processor: $_"
        }
    }
}

function New-DocumentsTabControls {
    # Control Panel (Processor Controls)
    $controlPanel = New-Object System.Windows.Forms.Panel
    $controlPanel.Location = New-Object System.Drawing.Point(10, 10)
    $controlPanel.Size = New-Object System.Drawing.Size(760, 50)
    $controlPanel.BackColor = $script:BACKGROUND_WHITE
    
    # Processor Button
    $processorButton = New-Object System.Windows.Forms.Button
    $processorButton.Location = New-Object System.Drawing.Point(10, 5)
    $processorButton.Size = New-Object System.Drawing.Size(150, 40)
    $processorButton.Text = "Start Document Processor"
    $processorButton.BackColor = $script:BUTTON_BLUE
    $processorButton.ForeColor = [System.Drawing.Color]::White
    $processorButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $processorButton.FlatAppearance.BorderSize = 0
    $processorButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    
    # Status Label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(170, 15)
    $statusLabel.Size = New-Object System.Drawing.Size(580, 20)
    $statusLabel.Text = "Processor Status: Not Running"
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    
    # Documents List
    $docsList = New-Object System.Windows.Forms.ListView
    $docsList.Location = New-Object System.Drawing.Point(10, 70)  # Moved up since drop zone is removed
    $docsList.Size = New-Object System.Drawing.Size(760, 470)    # Made taller since drop zone is removed
    $docsList.View = [System.Windows.Forms.View]::Details
    $docsList.FullRowSelect = $true
    $docsList.GridLines = $true
    $docsList.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    
    # Add columns to document list
    $docsList.Columns.Add("Document", 200) | Out-Null
    $docsList.Columns.Add("Status", 100) | Out-Null
    $docsList.Columns.Add("Processed Date", 150) | Out-Null
    $docsList.Columns.Add("Chunks", 80) | Out-Null
    
    # Add controls to panel
    $controlPanel.Controls.AddRange(@($processorButton, $statusLabel))
    
    # Add processor button handler
    Add-ProcessorButtonHandler -ProcessorButton $processorButton -StatusLabel $statusLabel
    
    # Return all top-level controls
    return @($controlPanel, $docsList)
}

function Get-ProcessorStatus {
    param($ProcessName = "powershell")
    
    try {
        if ($script:processorJob -and -not $script:processorJob.HasExited) {
            $process = Get-Process -Id $script:processorJob.Id -ErrorAction SilentlyContinue
            return $null -ne $process
        }
        return $false
    }
    catch {
        return $false
    }
}

function Update-ProcessorStatus {
    param($StatusLabel)
    
    $isRunning = Get-ProcessorStatus
    $statusText = if ($isRunning) { "Running" } else { "Not Running" }
    $StatusLabel.Text = "Processor Status: $statusText"
    return $isRunning
}

function Add-ProcessorButtonHandler {
    param($ProcessorButton, $StatusLabel)
    
    $ProcessorButton.Add_Click({
        try {
            if (-not $script:isProcessing) {
                # Get the PowerShell executable path
                $powershellPath = (Get-Command powershell).Source
                $processPath = Join-Path $PSScriptRoot "DocumentProcessor.ps1"
                
                # Construct the command to run
                $commandArgs = "-NoProfile -ExecutionPolicy Bypass -Command `"& { . '$processPath' }`""
                
                $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                $startInfo.FileName = $powershellPath
                $startInfo.Arguments = $commandArgs
                $startInfo.UseShellExecute = $false
                $startInfo.RedirectStandardOutput = $true
                $startInfo.RedirectStandardError = $true
                $startInfo.CreateNoWindow = $false
                
                Write-Host "Starting processor with path: $processPath"
                $script:processorJob = [System.Diagnostics.Process]::Start($startInfo)
                
                if ($script:processorJob) {
                    Write-Host "Process started with ID: $($script:processorJob.Id)"
                    $script:isProcessing = $true
                    $ProcessorButton.Text = "Stop Document Processor"
                    $ProcessorButton.BackColor = $script:BUTTON_RED
                    $StatusLabel.Text = "Processor Status: Running (PID: $($script:processorJob.Id))"
                }
            }
            else {
                if ($script:processorJob) {
                    Write-Host "Stopping process ID: $($script:processorJob.Id)"
                    Stop-Process -Id $script:processorJob.Id -Force -ErrorAction SilentlyContinue
                    $script:processorJob = $null
                }
                $script:isProcessing = $false
                $ProcessorButton.Text = "Start Document Processor"
                $ProcessorButton.BackColor = $script:BUTTON_BLUE
                $StatusLabel.Text = "Processor Status: Not Running"
            }
        }
        catch {
            Write-Host "Error occurred: $_"
            Show-ErrorMessage -Message "Error managing processor: $_"
            $script:isProcessing = $false
            $ProcessorButton.Text = "Start Document Processor"
            $ProcessorButton.BackColor = $script:BUTTON_BLUE
            $StatusLabel.Text = "Processor Status: Error"
        }
    })
}
function Add-DropPanelHandlers {
    param($DropPanel, $StatusLabel)
    
    Write-Host "Setting up drag and drop handlers..."
    
    $DropPanel.AllowDrop = $true  # Make sure this is set
    
    $DropPanel.Add_DragEnter({
        param($mysender, $e)
        Write-Host "DragEnter event triggered"
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
            $mysender.BackColor = [System.Drawing.Color]::FromArgb(235, 245, 251)
            Write-Host "Drag effect set to Copy"
        }
    })
    
    $DropPanel.Add_DragLeave({
        param($mysender, $e)
        $mysender.BackColor = $script:BACKGROUND_WHITE
        Write-Host "DragLeave event triggered"
    })
    
    $DropPanel.Add_DragDrop({
        param($mysender, $e)
        Write-Host "DragDrop event triggered"
        $mysender.BackColor = $script:BACKGROUND_WHITE
        $files = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        Write-Host "Received files: $($files -join ', ')"
        
        foreach ($file in $files) {
            Start-ProcessDroppedFile -File $file -StatusLabel $StatusLabel
        }
    })
    
    Write-Host "Drag and drop handlers set up successfully"
}

function Add-BrowseButtonHandler {
    param($BrowseButton, $StatusLabel)
    
    $BrowseButton.Add_Click({
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Multiselect = $true
        $openFileDialog.Filter = "All Supported Files|*" + ($global:KBConfig.FileProcessing.SupportedTypes -join ";*")
        
        if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            foreach ($file in $openFileDialog.FileNames) {
                Start-ProcessDroppedFile -File $file -StatusLabel $StatusLabel
            }
        }
    })
}

function Add-ProcessorButtonHandler {
    param(
        [System.Windows.Forms.Button]$ProcessorButton,
        [System.Windows.Forms.Label]$StatusLabel
    )
    
    # Store the button reference
    $script:processorButton = $ProcessorButton
    $script:statusLabel = $StatusLabel
    
    $ProcessorButton.Add_Click({
        try {
            if (-not $script:isProcessing) {
                $processPath = Join-Path $PSScriptRoot "DocumentProcessor.ps1"
                $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                $startInfo.FileName = "powershell.exe"
                $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$processPath`""
                $startInfo.UseShellExecute = $true
                $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
                
                Write-Host "Starting processor with path: $processPath"
                $script:processorJob = [System.Diagnostics.Process]::Start($startInfo)
                
                if ($script:processorJob) {
                    # Open the input folder for the user
                    if (Test-Path $global:KBConfig.Paths.Input) {
                        Start-Process "explorer.exe" -ArgumentList $global:KBConfig.Paths.Input
                    }
                    $script:isProcessing = $true
                    $script:processorButton.Text = "Stop Document Processor"
                    $script:processorButton.BackColor = $script:BUTTON_RED
                    $script:statusLabel.Text = "Processor Status: Running (PID: $($script:processorJob.Id))"
                }
            }
            else {
                if ($script:processorJob) {
                    Stop-Process -Id $script:processorJob.Id -Force -ErrorAction SilentlyContinue
                    $script:processorJob = $null
                }
                $script:isProcessing = $false
                $script:processorButton.Text = "Start Document Processor"
                $script:processorButton.BackColor = $script:BUTTON_BLUE
                $script:statusLabel.Text = "Processor Status: Not Running"
            }
        }
        catch {
            Write-Host "Error occurred: $_"
            Show-ErrorMessage -Message "Error starting processor: $_"
            $script:isProcessing = $false
            $script:processorButton.Text = "Start Document Processor"
            $script:processorButton.BackColor = $script:BUTTON_BLUE
            $script:statusLabel.Text = "Processor Status: Error"
        }
    })
}

# Helper function to make updating status more reliable
function Update-Status {
    param(
        [string]$Message,
        [System.Windows.Forms.Label]$StatusLabel
    )
    
    if ($StatusLabel) {
        $StatusLabel.Text = $Message
    }
}

function Start-ProcessDroppedFile {
    param($File, $StatusLabel)
    
    $extension = [System.IO.Path]::GetExtension($File)
    if ($extension -in $global:KBConfig.FileProcessing.SupportedTypes) {
        try {
            $destinationPath = Join-Path $global:KBConfig.Paths.Input (Split-Path $File -Leaf)
            Copy-Item -Path $File -Destination $destinationPath -Force
            Update-Status -Message "File added: $(Split-Path $File -Leaf)" -StatusLabel $StatusLabel
        }
        catch {
            Show-ErrorMessage -Message "Error copying file: $_"
        }
    }
    else {
        Show-ErrorMessage -Message "Unsupported file type: $extension`nSupported types: $($global:KBConfig.FileProcessing.SupportedTypes -join ', ')" -IsWarning $true
    }
}

function Start-DocumentProcessor {
    param($Button, $StatusLabel)
    
    try {
        $processPath = Join-Path $PSScriptRoot "DocumentProcessor.ps1"
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = "cmd"
        #$startInfo.Arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -File `"$processPath`""
        $startInfo.Arguments = "/k powershell.exe -File `"$processPath`""
        #$startInfo.UseShellExecute = $false
        #$startInfo.CreateNoWindow = $true
        Write-Host "Starting processor with arguments: $($startInfo.Arguments)"
        $script:processorJob = [System.Diagnostics.Process]::Start($startInfo)
        write-host "Processor started with PID: $($script:processorJob.Id)"
        $script:isProcessing = $true
        $Button.Text = "Stop Processing"
        $Button.BackColor = $script:BUTTON_RED
        Update-Status -Message "Processor Status: Running" -StatusLabel $StatusLabel
    }
    catch {
        Show-ErrorMessage -Message "Error starting processor: $_"
    }
}

function Stop-DocumentProcessor {
    param($Button, $StatusLabel)
    
    try {
        if ($script:processorJob) {
            Stop-Process -Id $script:processorJob.Id -Force
            $script:processorJob = $null
        }
        $script:isProcessing = $false
        $Button.Text = "Start Processing"
        $Button.BackColor = $script:BUTTON_BLUE
        Update-Status -Message "Processor Status: Stopped" -StatusLabel $StatusLabel
    }
    catch {
        Show-ErrorMessage -Message "Error stopping processor: $_"
    }
}


function Show-ErrorMessage {
    param(
        [string]$Message,
        [bool]$IsWarning = $false
    )
    
    Write-Host "Showing error message: $Message"
    $icon = if ($IsWarning) { 
        [System.Windows.Forms.MessageBoxIcon]::Warning 
    } else { 
        [System.Windows.Forms.MessageBoxIcon]::Error 
    }
    
    $title = if ($IsWarning) { "Warning" } else { "Error" }
    
    [System.Windows.Forms.MessageBox]::Show($Message, $title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}