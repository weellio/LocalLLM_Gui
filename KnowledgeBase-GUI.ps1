# Initialize configuration
$global:KBConfig = $null
$global:DocumentProcessorJob = $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

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

function Initialize-Configuration {
    $configPath = "F:\KnowledgeBase\config\settings.json"
    try {
        $rawConfig = Get-Content $configPath | ConvertFrom-Json
        Write-Host "Raw config loaded, converting to hashtable..."
        $global:KBConfig = ConvertTo-Hashtable $rawConfig
        Write-Host "Config loaded successfully. Base path: $($global:KBConfig.Paths.Base)"
        Write-Host "Logs path: $($global:KBConfig.Paths.Logs)"
        
        # Verify the hashtable conversion worked
        Write-Host "Config structure:"
        $global:KBConfig.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value)"
        }
        
        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error loading configuration: $_",
            "Configuration Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }
}


# Initialize configuration first
if (-not (Initialize-Configuration)) {
    exit
}

# Load module files
$documentsTabPath = Join-Path $PSScriptRoot "DocumentsTab.ps1"
$chatTabPath = Join-Path $PSScriptRoot "ChatTab.ps1"

. $documentsTabPath
. $chatTabPath

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Knowledge Base Assistant"
$form.Size = New-Object System.Drawing.Size(1024,768)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false

# Create tab control
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(0,0)
$tabControl.Size = New-Object System.Drawing.Size(1000,700)

# Create tabs
$tabChat = New-Object System.Windows.Forms.TabPage
$tabChat.Text = "Chat"

$tabDocs = New-Object System.Windows.Forms.TabPage
$tabDocs.Text = "Documents"

$tabHelp = New-Object System.Windows.Forms.TabPage
$tabHelp.Text = "Help"

$tabChat.AutoScroll = $true
$tabDocs.AutoScroll = $true
$tabHelp.AutoScroll = $true

# Initialize tabs
if ($global:KBConfig) {
    # Initialize Chat tab
    Initialize-ChatTab -TabPage $tabChat -Configuration $global:KBConfig
    
    # Initialize Documents tab
    Initialize-DocumentsTab -TabPage $tabDocs -Configuration $global:KBConfig
} else {
    [System.Windows.Forms.MessageBox]::Show(
        "Configuration not available for tab initialization",
        "Configuration Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

# Add tabs to control
$tabControl.Controls.AddRange(@($tabChat, $tabDocs))


# Add tab control to form
$form.Controls.Add($tabControl)

# Add form closing handler
$form.Add_FormClosing({
    param($mysender, $e)
    Start-CleanupDocumentsTab
})

# Set custom icon if exists
$iconPath = Join-Path $PSScriptRoot "logo.ico"
if (Test-Path $iconPath) {
    $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
}

# Show the form
$form.ShowDialog()