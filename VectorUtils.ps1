# VectorUtils.ps1
# Helper functions for vector operations and embedding handling

function Get-CosineSimilarity {
    param (
        [float[]]$vector1,
        [float[]]$vector2
    )
    
    # Ensure vectors are same length
    if ($vector1.Length -ne $vector2.Length) {
        throw "Vectors must be same length"
    }
    
    try {
        $dotProduct = 0.0
        $norm1 = 0.0
        $norm2 = 0.0
        
        # Calculate dot product and norms
        $i = 0
        while ($i -lt $vector1.Length) {
            $dotProduct += $vector1[$i] * $vector2[$i]
            $norm1 += $vector1[$i] * $vector1[$i]
            $norm2 += $vector2[$i] * $vector2[$i]
            $i++
        }
        
        # Calculate final similarity
        $similarity = $dotProduct / ([Math]::Sqrt($norm1) * [Math]::Sqrt($norm2))
        return $similarity
    }
    catch {
        Write-Error "Error calculating similarity: $_"
        return 0
    }
}

function Get-TextEmbedding {
    param (
        [string]$Text,
        [string]$ModelPath = "ollama"
    )
    
    try {
        # Call Ollama for embedding
        $result = & $ModelPath run nomic-embed-text $Text --format json
        
        # Parse the result
        $embedding = $result | ConvertFrom-Json
        
        return $embedding
    }
    catch {
        Write-Error "Failed to generate embedding: $_"
        return $null
    }
}