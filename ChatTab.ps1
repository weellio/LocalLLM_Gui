# ChatTab.ps1
# Module for Chat tab functionality in Knowledge Base GUI


# Style constants
$script:BUTTON_BLUE = [System.Drawing.Color]::FromArgb(52, 152, 219)
$script:BACKGROUND_WHITE = [System.Drawing.Color]::White

# State management
$script:Messages = [System.Collections.ArrayList]::new()
$script:ChatStartTime = Get-Date
$script:statusLabel = $null
$script:progressBar = $null
$script:chatBrowser = $null
$script:QueryCache = @{}
# Import required modules
. .\VectorUtils.ps1

# Message class
class ChatMessage {
    [string]$MessageType
    [string]$Content
    [string]$Time
}

function Update-ChatDisplay {
    Write-Host "Updating chat display..."
    $script:chatBrowser.DocumentText = New-ChatHTML -Messages $script:Messages
    $script:chatBrowser.DocumentText | Out-File "$script:ChatLogPath.html"
}
function New-ChatTabControls {
    # Create a main container panel first
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill

    # Create status label at the top
    $script:statusLabel = New-Object System.Windows.Forms.Label
    $script:statusLabel.Text = "System Status: Ready"
    $script:statusLabel.Dock = [System.Windows.Forms.DockStyle]::Top
    $script:statusLabel.Height = 20

    # Create progress bar
    $script:progressBar = New-Object System.Windows.Forms.ProgressBar
    $script:progressBar.Dock = [System.Windows.Forms.DockStyle]::Top
    $script:progressBar.Height = 15
    $script:progressBar.Visible = $false

    # Create chat browser
    $script:chatBrowser = New-Object System.Windows.Forms.WebBrowser
    $script:chatBrowser.Dock = [System.Windows.Forms.DockStyle]::Fill
    $script:chatBrowser.BackColor = [System.Drawing.Color]::Black
    $script:chatBrowser.DocumentText = New-ChatHTML -Messages $script:Messages

    # Create input panel at the bottom
    $inputPanel = New-Object System.Windows.Forms.Panel
    $inputPanel.Height = 50
    $inputPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $inputPanel.BackColor = $script:BACKGROUND_WHITE

    # Calculate dimensions for input controls
    $padding = 10
    $controlHeight = 23
    $totalWidth = 1000 - (2 * $padding)  # Set a default width
     # Calculate vertical positioning to center in panel
    $verticalPadding = ($inputPanel.Height - $controlHeight) / 2

    # Calculate widths for proper distribution
    $inputBoxWidth = [Math]::Floor($totalWidth * 0.6)  # 60% for input
    $buttonWidth = [Math]::Floor($totalWidth * 0.15)   # 15% for button
    $comboBoxWidth = 200

    # Create input box
    $inputBox = New-Object System.Windows.Forms.TextBox
    $inputBox.Size = New-Object System.Drawing.Size($inputBoxWidth, $controlHeight)
    $inputBox.Location = New-Object System.Drawing.Point($padding, $verticalPadding)


    # Create ask button
    $askButton = New-Object System.Windows.Forms.Button
    $askButton.Text = "Ask"
    $askButton.Size = New-Object System.Drawing.Size($buttonWidth, $controlHeight)
    $askButton.Location = New-Object System.Drawing.Point(($inputBox.Right + $padding), $verticalPadding)
    $askButton.BackColor = $script:BUTTON_BLUE
    $askButton.ForeColor = [System.Drawing.Color]::White

    # Create model selection combo box
    $modelComboBox = New-Object System.Windows.Forms.ComboBox
    $modelComboBox.Size = New-Object System.Drawing.Size($comboBoxWidth, $controlHeight)
    $modelComboBox.Location = New-Object System.Drawing.Point(($askButton.Right + $padding), $verticalPadding)
    $modelComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $modelComboBox.Items.AddRange(@(
        "Query Embedded Data",
        "Query DeepSeek for Reasoning"
    ))
    $modelComboBox.SelectedIndex = 0

    # Add click handler for the Ask button
    $clickScript = [ScriptBlock]::Create({
        param($sender, $e)
        Write-Host "DEBUG: Click handler triggered"
        $parentControl = $sender.Parent
        Write-Host "DEBUG: Parent control type: $($parentControl.GetType().Name)"
        $textBox = $parentControl.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }
        $comboBox = $parentControl.Controls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] }
        
        if ($textBox -and $textBox.Text.Length -gt 0) {
            try {
                $question = $textBox.Text
                $textBox.Clear()
                
                $script:progressBar.Visible = $true
                $script:progressBar.Value = 20
                $script:statusLabel.Text = "Processing query..."
                
                Add-UserMessage $question
                
                if ($comboBox.SelectedItem -eq "Query Embedded Data") {
                    # Existing embedded data flow
                    $queryEmbedding = Get-QueryEmbedding -Query $question
                    $script:progressBar.Value = 40
                    $script:statusLabel.Text = "Searching knowledge base..."
                    
                    $similarContent = Find-SimilarContent -QueryEmbedding $queryEmbedding
                    $script:progressBar.Value = 60
                    $script:statusLabel.Text = "Generating answer..."
                    
                    $answer = Get-Answer -Query $question -RelevantChunks $similarContent
                    $formattedAnswer = Format-Response $answer
                }
                else {
                    # DeepSeek query flow
                    $script:statusLabel.Text = "Querying DeepSeek..."
                    $answer = Get-DeepSeekAnswer -Query $question
                    $formattedAnswer = Format-DeepSeekResponse $answer
                }
                
                Add-AssistantMessage $formattedAnswer
                
                $script:progressBar.Value = 100
                $script:statusLabel.Text = "Ready"
                
            } catch {
                Write-Host "Error processing question: $_"
                Add-AssistantMessage "Sorry, there was an error processing your question. Please try again."
            } finally {
                $script:progressBar.Visible = $false
            }
        }
    })

    $askButton.Add_Click($clickScript)

       # Add enter key handler for input box
    $inputBox.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $button = $sender.Parent.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] }
            if ($button) {
                $button.PerformClick()
                $e.SuppressKeyPress = $true
            }
        }
    })

    # Add controls to panels in the correct order
    $mainPanel.Controls.AddRange(@(
        $script:statusLabel,
        $script:progressBar,
        $script:chatBrowser
    ))

    # Add input controls to the input panel
    $inputPanel.Controls.AddRange(@($inputBox, $askButton, $modelComboBox))

    # Add input panel to main panel last
    $mainPanel.Controls.Add($inputPanel)


# Add this to the New-ChatTabControls function in ChatTab.ps1

    return @($mainPanel)
}

function Initialize-ChatTab {
    param (
        [Parameter(Mandatory=$true)]
        [System.Windows.Forms.TabPage]$TabPage,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Configuration
    )
    
    Write-Host "ChatTab: Initializing..."
    
    # Store configuration
    $global:KBConfig = $Configuration
    
    # Initialize chat log path
    $script:ChatLogPath = Join-Path $global:KBConfig.Paths.Logs "Chat_$($script:ChatStartTime.ToString('yyyy-MM-dd_HH-mm-ss'))"
    
    # Clear messages and controls
    $script:Messages.Clear()
    $TabPage.Controls.Clear()
    
    try {
       
        # Create and add controls
        $controls = New-ChatTabControls
        $TabPage.Controls.AddRange($controls)
        
        # Add welcome message
        Add-AssistantMessage "Ready to answer your questions! How can I help you?"
        
        Write-Host "Chat tab initialized successfully"
        return $true
    }
    catch {
        Write-Host "Error initializing Chat tab: $_"
        return $false
    }
}

function New-ChatHTML {
    param([System.Collections.ArrayList]$Messages)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body {
            font-family: 'Segoe UI', sans-serif;
            background-color: #000000;
            margin: 0;
            padding: 5px;
        }
        .chat-container {
            max-width: 100%;
            margin: 0;
        }
        .message {
            margin: 5px 0;
            max-width: 95%;
            clear: both;
        }
        .user-message {
            float: right;
            background-color: #9de69d;
            color: #000;
            border-radius: 20px 20px 5px 20px;
            padding: 10px 15px;
            margin-left: 5%;
        }
        .assistant-message {
            float: left;
            background-color: #2980b9;
            color: #fff;
            border-radius: 20px 20px 20px 5px;
            padding: 15px 20px;
            margin-right: 5%;
        }
        .timestamp {
            font-size: 0.8em;
            color: #888;
            margin: 5px 10px;
            clear: both;
        }
        .user-timestamp {
            float: right;
        }
        .assistant-timestamp {
            float: left;
        }
    </style>
</head>
<body>
    <div class="chat-container">
"@

    foreach ($msg in $Messages) {
        if ($msg.MessageType -eq "User") {
            $html += @"
        <div class="message">
            <div class="user-message">$($msg.Content)</div>
            <div class="timestamp user-timestamp">$($msg.Time)</div>
        </div>
"@
        } else {
            $html += @"
        <div class="message">
            <div class="assistant-message">$($msg.Content)</div>
            <div class="timestamp assistant-timestamp">$($msg.Time)</div>
        </div>
"@
        }
    }

    $html += @"
    </div>
</body>
</html>
"@

    return $html
}

function Add-UserMessage {
    param([string]$message)
    
    $msg = [ChatMessage]::new()
    $msg.MessageType = "User"
    $msg.Content = $message
    $msg.Time = Get-Date -Format "h:mm tt"
    [void]$script:Messages.Add($msg)
    
    Update-ChatDisplay
}

function Add-AssistantMessage {
    param([string]$message)
    
    $msg = [ChatMessage]::new()
    $msg.MessageType = "Assistant"
    $msg.Content = $message
    $msg.Time = Get-Date -Format "h:mm tt"
    [void]$script:Messages.Add($msg)
    
    Update-ChatDisplay
}


function Add-ChatEventHandlers {
    param(
        [System.Windows.Forms.TextBox]$InputBox,
        [System.Windows.Forms.Button]$AskButton
    )
    Write-Host "Event handlers are now managed in the main control creation"
}


function Get-QueryEmbedding {
    param (
        [string]$Query,
        [string]$Model = "nomic-embed-text"
    )
    
    try {
        # Prepare request body
        $body = @{
            model = $Model
            prompt = $Query
        } | ConvertTo-Json
        
        # Make API call
        $response = Invoke-WebRequest -Method Post `
                                    -Uri "http://localhost:11434/api/embeddings" `
                                    -Body $body `
                                    -ContentType "application/json"
        
        if ($response.StatusCode -eq 200) {
            $result = $response.Content | ConvertFrom-Json
            return $result.embedding
        }
        
        Write-Error "Failed to generate query embedding"
        return $null
    }
    catch {
        Write-Error "Query embedding error: $_"
        return $null
    }
}

function Get-Answer {
    param(
        [string]$Query,
        [array]$RelevantChunks
    )
    
    # Generate cache key from query and chunks
    $cacheKey = "$Query|$([string]::Join('|', ($RelevantChunks.Content)))"
    
    # Check cache first
    if ($script:QueryCache.ContainsKey($cacheKey)) {
        Write-Host "Using cached response" -ForegroundColor Gray
        return $script:QueryCache[$cacheKey]
    }


    try {
        $systemPrompt = @"
You are a helpful assistant answering questions based on the provided information.
Only use the information provided to answer the question.
If you cannot answer the question with the provided information, say so.
Format your response with clear paragraphs and structure.
Keep your response concise and to the point.
"@

        # Format context with clear delineation
        $context = $RelevantChunks | ForEach-Object {
            "Reference (${$_.Metadata.SourceFile}):
            $($_.Content)
            ---"
        }

        $finalPrompt = @"
Information:
$($context -join "`n")

Question: $Query

Provide a clear, structured answer.
use html formatting to emphasize the answer
"@

        $body = @{
            model = "llama2:13b"
            prompt = "[INST] <<SYS>>$systemPrompt<</SYS>>$finalPrompt [/INST]"
            stream = $false
            options = @{
                stop = @("[INST]", "[/INST]", "Question:", "Information:")
                temperature = 0.7
                top_p = 0.9
            }
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-WebRequest -Method Post `
                                    -Uri "http://localhost:11434/api/generate" `
                                    -Body $body `
                                    -ContentType "application/json"
        
        if ($response.StatusCode -eq 200) {
            $result = $response.Content | ConvertFrom-Json
            # Cache the response
            $script:QueryCache[$cacheKey] = $result.response
            return $result.response
        }
        
        Write-Error "Failed to generate answer"
        return $null
    }
    catch {
        Write-Error "Answer generation error: $_"
        return $null
    }
}

# Find similar content using cosine similarity
function Find-SimilarContent {
    param(
        [array]$QueryEmbedding,
        [int]$MaxResults = 3
    )
    
    try {
        # Load stored embeddings
        $embeddingsPath = Join-Path $global:KBConfig.Paths.Embeddings "embeddings.json"
        $storedEmbeddings = Get-Content $embeddingsPath | ConvertFrom-Json
        
        # Calculate similarities
        #$jobs = @()
        $results = @()
        
        # Process in batches
        $batchSize = 10
        for ($i = 0; $i -lt $storedEmbeddings.Count; $i += $batchSize) {
            $batch = $storedEmbeddings[$i..([Math]::Min($i + $batchSize - 1, $storedEmbeddings.Count - 1))]
            
            foreach ($embedding in $batch) {
                $similarity = Get-CosineSimilarity $QueryEmbedding $embedding.Embedding
                $results += @{
                    Content = $embedding.Content
                    Metadata = $embedding.Metadata
                    Similarity = $similarity
                }
            }
        }
        
        # Return top results
        return $results | Sort-Object Similarity -Descending | Select-Object -First $MaxResults
    }
    catch {
        Write-Error "Similarity search error: $_"
        return @()
    }
}

function Get-ElapsedTime {
    param (
        [DateTime]$StartTime,
        [string]$Operation
    )
    $elapsed = (Get-Date) - $StartTime
    Write-Host "Time for $Operation : $($elapsed.TotalSeconds) seconds" -ForegroundColor Yellow
}


function Format-Response {
    param([string]$text)
    
    # Split into sections based on common patterns
    $text = $text -replace "(\d+)\. ", "<br><strong>$1.</strong> "  # Numbered lists
    $text = $text -replace "([IVX]+)\. ", "<br><strong>$1.</strong> "  # Roman numerals
    $text = $text -replace "â€¢ ", "<br>• "  # Fix bullet points
    
    # Format hierarchy items
    $text = $text -replace "(Team \d+)", "<br><strong>$1</strong>"
    $text = $text -replace "(CEO|COO|CTO|CFO)", "<strong>$1</strong>"
    
    # Add proper spacing and structure
    $text = @"
<div style='line-height: 1.6em; padding: 5px;'>
    <div style='margin-bottom: 10px;'>$text</div>
</div>
"@
    
    return $text
}

function Get-DeepSeekAnswer {
    param([string]$Query)
    
    try {
        $body = @{
            model = "deepseek-r1:8b"
            messages = @(
                @{
                    role = "user"
                    content = $Query
                }
            )
            stream = $false
            options = @{
                temperature = 0.7
                top_p = 0.9
            }
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-WebRequest -Method Post `
                                    -Uri "http://localhost:11434/api/chat" `
                                    -Body $body `
                                    -ContentType "application/json"
        
        if ($response.StatusCode -eq 200) {
            $result = $response.Content | ConvertFrom-Json
            return $result.message.content
        }
        
        Write-Error "Failed to generate DeepSeek answer"
        return $null
    }
    catch {
        Write-Error "DeepSeek answer generation error: $_"
        return $null
    }
}

# Add function for formatting DeepSeek responses with different styling
function Format-DeepSeekResponse {
    param([string]$text)
    
    # Similar formatting to existing responses but with different colors
    $text = $text -replace "(\d+)\. ", "<br><strong>$1.</strong> "
    $text = $text -replace "([IVX]+)\. ", "<br><strong>$1.</strong> "
    $text = $text -replace "â€¢ ", "<br>• "
    
    $text = @"
<div style='line-height: 1.6em; padding: 5px; background-color: #34495e; border-radius: 15px;'>
    <div style='margin-bottom: 10px; color: #ecf0f1;'>$text</div>
</div>
"@
    
    return $text
}