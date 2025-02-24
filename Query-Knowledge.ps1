# Query-Knowledge.ps1
# System for querying embedded knowledge base

# Import required modules
. .\VectorUtils.ps1
function Get-ElapsedTime {
    param (
        [DateTime]$StartTime,
        [string]$Operation
    )
    $elapsed = (Get-Date) - $StartTime
    Write-Host "Time for $Operation : $($elapsed.TotalSeconds) seconds" -ForegroundColor Yellow
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
Write-Host "Loading query system..."
$script:QueryCache = @{}

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
"@

        $body = @{
            model = "llama2:13b"
            prompt = "[INST] <<SYS>>$systemPrompt<</SYS>>$finalPrompt [/INST]"
            stream = $false
            keep_alive = 1h
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
        $embeddingsPath = Join-Path $config.Paths.Embeddings "embeddings.json"
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

function Start-QueryMode {
    Write-Host "`nKnowledge Base Query System"
    Write-Host "Enter your question (or 'exit' to quit)"
    
    while ($true) {
        Write-Host "`n> " -NoNewline
        $query = Read-Host
        
        if ($query -eq 'exit') { break }
        
        $totalStartTime = Get-Date
        
        # Generate embedding for query
        $embeddingStartTime = Get-Date
        $queryEmbedding = Get-QueryEmbedding -Query $query
        if (-not $queryEmbedding) { continue }
        Get-ElapsedTime -StartTime $embeddingStartTime -Operation "Query Embedding"
        
        # Find similar content
        $searchStartTime = Get-Date
        $similarContent = Find-SimilarContent -QueryEmbedding $queryEmbedding
        if (-not $similarContent) { 
            Write-Host "No relevant information found"
            continue
        }
        Get-ElapsedTime -StartTime $searchStartTime -Operation "Similarity Search"
        
        # Generate answer
        $answerStartTime = Get-Date
        $answer = Get-Answer -Query $query -RelevantChunks $similarContent
        Get-ElapsedTime -StartTime $answerStartTime -Operation "Answer Generation"
        
        # Display results
        Write-Host "`nAnswer:" -ForegroundColor Green
        Write-Host $answer
        
        Write-Host "`nSources:" -ForegroundColor Cyan
        $similarContent | ForEach-Object {
            Write-Host "- From: $($_.Metadata.SourceFile) (Similarity: $([math]::Round($_.Similarity, 2)))"
        }
        
        Get-ElapsedTime -StartTime $totalStartTime -Operation "Total Response"
        Write-Host "`n--------------------------------------"
        Write-Host "Ready for next question (or type 'exit' to quit)" -ForegroundColor Cyan
    }
}
# Start query system
Start-QueryMode