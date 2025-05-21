function Send-NTFYMessage {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $Message
    )
    
    if ($env:NTFYEnabled -eq $false) {
        Break
    }

    if ($null -eq $env:NTFYTopicURL -or $NTFYTopicURL.trim() -eq "") {
        Write-Error ("Topic URL is missing!")
    }

    try {
        if ($null -eq $env:NTFYToken -or $NTFYToken.trim() -eq "") {
            $Result = Invoke-WebRequest $env:NTFYTopicURL-Body $Message -Method Post -ErrorAction Stop
        }
        else {
            $Result = Invoke-WebRequest $env:NTFYTopicURL-Body $Message -Method Post -AllowUnencryptedAuthentication -Authentication Bearer -Token ($env:NTFYToken | ConvertTo-SecureString -AsPlainText) -ErrorAction Stop
        }
        if ($Result.StatusDescription -ne "OK") {
            Write-Error $Result
        }
    }
    catch {
        Write-Error ("Error Sending Notification to '$NTFYTopicURL': " + $_.Exception.Message)
    }
}

function Update-Stack {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]
        $Stack
    )
    
    # Update Stack
    $Body = @{
        env              = ($Stack.Env | ConvertTo-Json)
        prune            = $true
        pullImage        = $true
        stackFileContent = $Stack.StackFileContent
    }
    $Body = $Body | ConvertTo-Json

    try {
        Invoke-RestMethod ($env:PortainerBaseAddress + "/api/portainer/stacks/" + $stack.id + "?endpointId=" + $Stack.EndpointId) -AllowUnencryptedAuthentication -Authentication Bearer -Token ($Bearer | ConvertTo-SecureString -AsPlainText) -Body $Body -Method Put -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error ("Update not possible: " + $_.Exception.Message)
    }
}

function Get-PortainerStacks {
    $Stacks = Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/stacks") -AllowUnencryptedAuthentication -Authentication Bearer -Token ($Bearer | ConvertTo-SecureString -AsPlainText) -Method Get -ErrorAction Stop
    $Stacks = $Stacks | ForEach-Object {
        $StackFileContent = (Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/stacks/" + $_.id + "/file") -AllowUnencryptedAuthentication -Authentication Bearer -Token ($Bearer | ConvertTo-SecureString -AsPlainText) -Method get -ErrorAction stop -ContentType "application/json").StackFileContent
        $_ | Add-Member -NotePropertyName "StackFileContent" -NotePropertyValue $StackFileContent -Force
            
        if ($StackFileContent -imatch "#UpdatePolicy=AutoUpdate") {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "AutoUpdate" -Force
        }
        elseif ($StackFileContent -imatch "#UpdatePolicy=DoNotUpdate") {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "DoNotUpdate" -Force
        }
        elseif ($StackFileContent -imatch "#UpdatePolicy=OnlyNTFY") {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "OnlyNTFY" -Force
        }
        else {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue $env:AutoUpdateDefaultMode -Force
        }
    
        $_
    }

    Return $Stacks
}

function Get-DockerStacks {
    $Stacks = (docker compose ls --format json | convertfrom-json)
    $Stacks = $Stacks | ForEach-Object {
        try {
            $ComposeFile = (Get-Content $_.ConfigFiles -Raw)

            if ($ComposeFile -imatch "#UpdatePolicy=AutoUpdate") {
                $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "AutoUpdate" -Force
            }
            elseif ($ComposeFile -imatch "#UpdatePolicy=DoNotUpdate") {
                $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "DoNotUpdate" -Force
            }
            elseif ($ComposeFile -imatch "#UpdatePolicy=OnlyNTFY") {
                $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue "OnlyNTFY" -Force
            }
            else {
                $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue $env:AutoUpdateDefaultMode -Force
            }
        }
        catch {}
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
            $Status = Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/stacks/" + $Stack.Id + "/images_status?refresh=1") -AllowUnencryptedAuthentication -Authentication Bearer -Token ($Bearer | ConvertTo-SecureString -AsPlainText) -Method Get -ErrorAction Stop
        }
        'StackID' {
            $Status = Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/stacks/" + $StackID + "/images_status?refresh=1") -AllowUnencryptedAuthentication -Authentication Bearer -Token ($Bearer | ConvertTo-SecureString -AsPlainText) -Method Get -ErrorAction Stop
        }
        default {
            Write-Error 'No valid parameter provided. Must specify either -Stack or -ID.'
        }
    }

    Return $Status
}

function Get-BearerToken {
    $Body = @{
        username = $env:PortainerUsername
        password = $env:PortainerPassword
    }
    $Body = $Body | ConvertTo-Json

    $Bearer = (Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/auth") -Body $Body -Method Post -ErrorAction Stop).jwt

    Return $Bearer
}

function Disconnect-Token {
    Invoke-RestMethod -SkipCertificateCheck ($env:PortainerBaseAddress + "/api/auth/logout") -AllowUnencryptedAuthentication -Authentication Bearer -Token ($Bearer | ConvertTo-SecureString -AsPlainText) -Method Post -ErrorAction Stop | Out-Null
}