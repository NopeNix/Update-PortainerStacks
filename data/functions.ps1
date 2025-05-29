function Send-NTFYMessage {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $Message
    )
    
    Add-UpdateLogEntry -Message $Message

    if ($env:NTFYEnabled -eq $false) {
        Break
    }

    if ($null -eq $env:NTFYTopicURL -or $env:NTFYTopicURL.trim() -eq "") {
        Write-Error ("Topic URL is missing!")
    }

    try {
        if ($null -eq $env:NTFYToken -or $env:NTFYToken.trim() -eq "") {
            $Result = Invoke-WebRequest $env:NTFYTopicURL -Body $Message -Method Post -ErrorAction Stop
        }
        else {
            $Result = Invoke-WebRequest $env:NTFYTopicURL -Body $Message -Method Post -AllowUnencryptedAuthentication -Authentication Bearer -Token ($env:NTFYToken | ConvertTo-SecureString -AsPlainText) -ErrorAction Stop
        }
        if ($Result.StatusDescription -ne "OK") {
            Write-Error $Result
        }
        Start-Sleep -Milliseconds 200
    }
    catch {
        Write-Error ("Error Sending Notification to '$env:NTFYTopicURL': " + $_.Exception.Message)
    }
}

function Update-PortainerStack {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]
        $Stack
    )
    
    # Update Stack
    $Body = @{
        env              = $Stack.Env 
        prune            = $true
        pullImage        = $true
        stackFileContent = $Stack.StackFileContent
    }
    $Body = $Body | ConvertTo-Json -Depth 10
    
    try {
        $Headers = @{
            "X-API-KEY" = $env:PortainerAPIToken
            "Content-Type" = "application/json"
        }
        
        $Uri = ($env:PortainerBaseAddress + "/api/stacks/" + $stack.id + "?endpointId=" + $Stack.EndpointId)
        
        Invoke-RestMethod $Uri `
            -Method Put `
            -SkipCertificateCheck `
            -Body $Body `
            -Headers $Headers `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error ("Update not possible: " + ($env:PortainerBaseAddress + "/api/stacks/" + $stack.id + "?endpointId=" + $Stack.EndpointId) + " " + $_)
    }
}

function Update-DockerComposeStack {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]
        $Stack
    )
    
    # Pull Images
    $Pull = docker compose -f ("/mnt/rootfs" + $Stack.ConfigFiles) pull > /dev/null 2>&1
    if ($? -eq $false ) {
        Write-Error ("Was not able to pull stack Images " + $Pull)
    }

    # Up Images
    $UpImage = docker compose -f ("/mnt/rootfs" + $Stack.ConfigFiles) up -d  > /dev/null 2>&1
    if ($? -eq $false ) {
        Write-Error ("Was not able to bring Stack back online! " + $UpImage)
    }
}

function Get-PortainerStacks {
    $Stacks = Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/stacks") -AllowUnencryptedAuthentication -Body @{"X-API-KEY" = $env:PortainerAPIToken } -Method Get -ErrorAction Stop
    $Stacks = $Stacks | ForEach-Object {
        $StackFileContent = (Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/stacks/" + $_.id + "/file") -AllowUnencryptedAuthentication -Body @{"X-API-KEY" = $env:PortainerAPIToken } -Method get -ErrorAction stop -ContentType "application/json").StackFileContent
        $_ | Add-Member -NotePropertyName "StackFileContent" -NotePropertyValue $StackFileContent -Force
            
        if ($StackFileContent -imatch "#UpdatePolicy=AutoUpdate") {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "AutoUpdate" -Force
        }
        elseif ($StackFileContent -imatch "#UpdatePolicy=DoNotUpdate") {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "DoNotUpdate" -Force
        }
        elseif ($StackFileContent -imatch "#UpdatePolicy=NTFYOnly") {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "NTFYOnly" -Force
        }
        else {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue $env:AutoUpdateDefaultMode -Force
        }
    
        $_
    }

    Return $Stacks
}

function Get-DockerComposeStacks {
    $Stacks = (docker compose ls --format json | convertfrom-json)
    $Stacks = $Stacks | ForEach-Object {
        if ((Test-Path "/mnt/rootfs/")) {
            try {
                $ComposeFile = (Get-Content ("/mnt/rootfs/" + $_.ConfigFiles) -ErrorAction Stop -Raw)

                if ($ComposeFile -imatch "#UpdatePolicy=AutoUpdate") {
                    $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "AutoUpdate" -Force
                }
                elseif ($ComposeFile -imatch "#UpdatePolicy=DoNotUpdate") {
                    $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "DoNotUpdate" -Force
                }
                elseif ($ComposeFile -imatch "#UpdatePolicy=NTFYOnly") {
                    $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "NTFYOnly" -Force
                }
                else {
                    $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue $env:AutoUpdateDefaultMode -Force
                }
            }
            catch {
                Write-Host ("Error: unaböe tp read stack file '" + $_.ConfigFiles + "' because " + $_.Exception.Message)
            }
        }
        else {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "NTFYOnly" -Force
        }
        
        $_
        
    }
    
    Return $Stacks
}

function Get-PortainerStacksUpdateStatus {
    param (
        [Parameter(ParameterSetName = 'Stack', Mandatory = $true)]
        [PSCustomObject]
        $Stack,

        [Parameter(ParameterSetName = 'StackID', Mandatory = $true)]
        [int]
        $StackID
    )

    switch ($PSCmdlet.ParameterSetName) {
        'Stack' {
            $Status = Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/stacks/" + $Stack.Id + "/images_status?refresh=1") -AllowUnencryptedAuthentication -Body @{"X-API-KEY" = $env:PortainerAPIToken } -Method Get -ErrorAction Stop
        }
        'StackID' {
            $Status = Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/stacks/" + $StackID + "/images_status?refresh=1") -AllowUnencryptedAuthentication -Body @{"X-API-KEY" = $env:PortainerAPIToken } -Method Get -ErrorAction Stop
        }
        default {
            Write-Error 'No valid parameter provided. Must specify either -Stack or -ID.'
        }
    }

    Return $Status
}

function Get-NotifiedStacks {
    <#
    .SYNOPSIS
        Retrieves the list of names from the NotifiedStacks file.
    .DESCRIPTION
        Reads the content of the NotifiedStacks.txt file and returns the list of names.
    .EXAMPLE
        Get-NotifiedStacks
    .OUTPUTS
        Array of strings representing the names in the list.
    #>
    # Check if the file exists
    if ((Test-Path "/data/db/NotifiedStacks.db") -eq $false) {
        New-Item -Path "/data/db/NotifiedStacks.db" -ItemType File -Force
    } 
    # Read the content of the file and return it
    $stacks = Get-Content -Path "/data/db/NotifiedStacks.db" -ErrorAction SilentlyContinue
    if ($stacks) {
        return $stacks
    }
    else {
        Write-Output "No names found in the list."
        return @()
    }
   
}

function Add-NotifiedStacks {
    <#
    .SYNOPSIS
        Adds one or more names to the NotifiedStacks list.
    .DESCRIPTION
        Appends the provided names to the NotifiedStacks.txt file if they don't already exist.
    .PARAMETER Names
        One or more names to add to the list.
    .EXAMPLE
        Add-NotifiedStacks -Names "John", "Jane"
    #>
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Names
    )
    # Get the current list of names
    $currentStacks = Get-NotifiedStacks
    $addedCount = 0
    
    foreach ($name in $Names) {
        # Check if the name already exists in the list (case-insensitive)
        if ($currentStacks -notcontains $name) {
            # Append the name to the file
            Add-Content -Path "/data/db/NotifiedStacks.db" -Value $name -ErrorAction Stop
            Write-Output "Added '$name' to the list."
            $addedCount++
        }
        else {
            Write-Output "'$name' is already in the list. Skipping."
        }
    }
    
    if ($addedCount -eq 0) {
        Write-Output "No new names were added."
    }
}

function Remove-NotifiedStacks {
    <#
    .SYNOPSIS
        Removes one or more names from the NotifiedStacks list.
    .DESCRIPTION
        Removes the specified names from the NotifiedStacks.txt file if they exist.
    .PARAMETER Names
        One or more names to remove from the list.
    .EXAMPLE
        Remove-NotifiedStacks -Names "John", "Jane"
    #>
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Names
    )
    # Get the current list of names
    $currentStacks = Get-NotifiedStacks
    $removedCount = 0
    
    if ($currentStacks.Count -eq 0) {
        Write-Output "The list is already empty. Nothing to remove."
        return
    }
    
    foreach ($name in $Names) {
        # Check if the name exists in the list
        if ($currentStacks -contains $name) {
            # Filter out the name to remove and update the file
            $updatedStacks = $currentStacks | Where-Object { $_ -ne $name }
            Set-Content -Path "/data/db/NotifiedStacks.db" -Value $updatedStacks -ErrorAction Stop
            Write-Output "Removed '$name' from the list."
            $removedCount++
        }
        else {
            Write-Output "'$name' is not in the list. Skipping."
        }
    }
    
    if ($removedCount -eq 0) {
        Write-Output "No names were removed."
    }
}

function Add-UpdateLogEntry {
    param (
        [Parameter()]
        [String]
        $Message,

        [Parameter()]
        [switch]
        $PrintToConsole,

        [Parameter()]
        [System.ConsoleColor]
        $ForegroundColor = [System.ConsoleColor]::White
    )
    if ($PrintToConsole) {
        Write-Host $Message -ForegroundColor $ForegroundColor
    }
    Add-Content -Path "/data/db/updatelog.log" -Value "$(Get-Date -Format '[yyyy-MM-dd HH:mm]') : $Message"
}

function Get-UpdateLog {
    Return (Get-Content "/data/db/updatelog.log" -Raw)
}

function Get-EscapedJsonString {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$InputString,

        # Forces escaping of { and } even though they're technically legal in JSON strings
        [switch]$EscapeCurlyBraces
    )

    process {
        # Start with built-in escaping (handles quotes, backslashes, etc.)
        $escaped = $InputString -replace '\\', '\\' `
            -replace '"', '\"' `
            -replace "`n", '\n' `
            -replace "`r", '\r' `
            -replace "`t", '\t'

        # Optionally murder curly braces if requested
        if ($EscapeCurlyBraces) {
            $escaped = $escaped -replace '{', '\{' -replace '}', '\}'
        }

        $escaped
    }
}