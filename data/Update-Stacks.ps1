. ($PSScriptRoot + "/functions.ps1")

# Prep
if ($null -ne $env:PortainerBaseAddress -or $env:PortainerBaseAddress -eq "") {
    $env:PortainerBaseAddress = $env:PortainerBaseAddress.TrimEnd("/")
}

# Portainer Updates
if ($null -ne $env:PortainerBaseAddress -and $env:PortainerBaseAddress.Trim(" ") -ne "") {
    # Sanatize Vars
    $env:PortainerBaseAddress = $env:PortainerBaseAddress.TrimEnd("/")
    $PortainerBaseDomain = ([System.Uri]::new($env:PortainerBaseAddress)).Host

    # Get All Stacks
    Write-Host -Message ("Getting all Portainer Stacks...") -ForegroundColor Blue
    try {
        $Stacks = Get-PortainerStacks
        Write-Host -Message (" -> Got " + $Stacks.count + " ") -ForegroundColor Green
    }
    catch {
        Write-Host -Message (" -> Error! " + $_.Exception.Message) -ForegroundColor Red
        Exit 1
    }

    # Get All Stack Status and strigger according action
    Write-Host -Message ("Looking for outdated Portainer Stacks on '$PortainerBaseDomain'`n (Default update Policy is '$env:AutoUpdateDefaultMode')") -ForegroundColor Blue

    $NotifiedStacks = Get-NotifiedStacks

    $Stacks | ForEach-Object {
        if ($null -eq $_.UpdatePolicy) {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue $env:AutoUpdateDefaultMode -Force
        }
        $CurrentObj = $_
        if ($_.UpdatePolicy -eq "AutoUpdate" -or $_.UpdatePolicy -eq "NTFYOnly") {
            try {
                $Status = Get-PortainerStacksUpdateStatus -Stack $CurrentObj
    
                switch ($Status.Status) {
                    "skipped" { 
                        if ($CurrentObj.Status -eq 1) {
                            Write-Host -Message (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (but Active, maybe update already in progress?) " + $Status.Message) -ForegroundColor Red
                        }
                        elseif ($CurrentObj.Status -eq 2) {
                            Write-Host -Message (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (because Inactive) " + $Status.Message) -ForegroundColor Gray
                        }
                        else {
                            Write-Host -Message (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (unhandled) " + $Status.Message) -ForegroundColor Red
                        }
                    }
                    "outdated" { 
                        Write-Host -Message (" -> [ OUTDATED ] : " + $CurrentObj.Name + "(" + $CurrentObj.UpdatePolicy + ")" + $Status.Message) -ForegroundColor Yellow
                        if ($CurrentObj.UpdatePolicy -eq "AutoUpdate") {
                            try {
                                Update-PortainerStack -Stack $CurrentObj -ErrorAction Stop
                                Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' is outdated, update has been triggered!")
                                Write-Host -Message ("  -> Update has been triggered successfully!") -ForegroundColor Green
                            }
                            catch {
                                Write-Host -Message ("  -> Error: " + $_.Exception.Message) -ForegroundColor Red
                            }
                        }
                        elseif ($CurrentObj.UpdatePolicy -eq "NTFYOnly" -and $env:NTFYEnabled -eq $true) {   
                            if ($NotifiedStacks -contains $CurrentObj.name) {
                                Write-Host -Message ("  -> Notification has already been sent")
                            }
                            else {
                                Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' is outdated, a manual update is required")
                                Add-NotifiedStacks $CurrentObj.name
                                Write-Host -Message ("  -> Notification has been sent") -ForegroundColor DarkGreen
                            }
                        }
                        elseif ($CurrentObj.UpdatePolicy -eq "NTFYOnly" -and $env:NTFYEnabled -eq $false) {
                            Write-Host -Message ("  -> WARNING: You have set this Stack to send NTFY but NTFY is not enabled yet, please check you configuration (environment Variables)")
                            Write-Host -Message ("  -> Notification has not been sent") -ForegroundColor Red
                        }
                        elseif ($CurrentObj.UpdatePolicy -eq "DoNotUpdate") {
                            Write-Host -Message ("  -> Stack has 'DoNotUpdate' Policy. Doing nothing.") -ForegroundColor Red
                        }
                    }
                    "updated" { 
                        $_ | Add-Member -NotePropertyName "LastSuccessfullUpdate" -NotePropertyValue (Get-Date)
                        Write-Host -Message (" -> [ UP2DATE  ] : " + $CurrentObj.Name + $Status.Message) -ForegroundColor Green
                        if ($NotifiedStacks -contains $CurrentObj.Name) {
                            Remove-NotifiedStacks -Names $CurrentObj.Name
                            Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' has been updated to latest version")

                        }
                    }
                    Default {
                        Write-Host -Message (" -> [  ERROR   ] : " + $CurrentObj.Name + ": Not Defined " + $Status.Message) -ForegroundColor Red
                    }
                }
            }
            catch {
                Write-Host -Message (" -> [  ERROR   ] : Stack '" + $CurrentObj.name + "'! " + $_.Exception.Message) -ForegroundColor Red
            }
        }
        elseif ($CurrentObj.UpdatePolicy -eq "DoNotUpdate") {
            Write-Host -Message (" -> [   DONT   ] : " + $CurrentObj.Name + " (has 'DoNotUpdate' Policy) " + $Status.Message) -ForegroundColor Gray
        }
    } 
}

# Docker Compose Updates
if ($true) {
    # Get All Stacks
    Write-Host -Message ("Getting all Docker Compose Stacks...") -ForegroundColor Blue
    try {
        $Stacks = Get-DockerComposeStacks
        Write-Host -Message (" -> Got " + $Stacks.count + " ") -ForegroundColor Green
    }
    catch {
        Write-Host -Message (" -> Error! " + $_.Exception.Message) -ForegroundColor Red
        Exit 1
    }

    # Get Stack Update Status
    Write-Host -Message ("Getting all Docker Compose Stacks Update Status...") -ForegroundColor Blue
    try {
        $StacksUpdatestatus = (bash /data/dockcheck.sh | ConvertFrom-Json).stacks
        Write-Host -Message (" -> Got " + $Stacks.count + " ") -ForegroundColor Green
    }
    catch {
        Write-Host -Message (" -> Error! " + $_.Exception.Message) -ForegroundColor Red
        Exit 1
    }

    # Get All Stack Status and strigger according action
    Write-Host -Message ("Looking for outdated Docker Compose Stacks on '/var/run/docker.sock'`n (Default update Policy is '$env:AutoUpdateDefaultMode')") -ForegroundColor Blue

    $NotifiedStacks = Get-NotifiedStacks

    $Stacks | ForEach-Object {
        if ($null -eq $_.UpdatePolicy -or $_.UpdatePolicy  -eq "") {
            $_ | Add-Member -NotePropertyName "UpdatePolicy" -NotePropertyValue $env:AutoUpdateDefaultMode -Force
        }
        $CurrentObj = $_

        if ($CurrentObj.UpdatePolicy -eq "AutoUpdate" -or $CurrentObj.UpdatePolicy -eq "NTFYOnly") {
            try {
                if ("" -eq ($StacksUpdatestatus | Where-Object {$_.name -eq $CurrentObj.name}).outdated) {
                    $Status = @{ status = "updated" }
                } else {
                    $Status = @{ status = "outdated" }
                }
    
                switch ($Status.Status) {
                    "outdated" { 
                        Write-Host -Message (" -> [ OUTDATED ] : " + $CurrentObj.Name + "(" + $CurrentObj.UpdatePolicy + ")" + $Status.Message) -ForegroundColor Yellow
                        if ($CurrentObj.UpdatePolicy -eq "AutoUpdate") {
                            try {
                                Update-DockerComposeStack -Stack $CurrentObj -ErrorAction Stop
                                Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' is outdated, update has been triggered!")
                                Write-Host -Message ("  -> Update has been triggered successfully!") -ForegroundColor Green
                            }
                            catch {
                                Write-Host -Message ("  -> Error: " + $_.Exception.Message) -ForegroundColor Red
                            }
                        }
                        elseif ($CurrentObj.UpdatePolicy -eq "NTFYOnly" -and $env:NTFYEnabled -eq $true) {   
                            if ($NotifiedStacks -contains $CurrentObj.name) {
                                Write-Host -Message ("  -> Notification has already been sent")
                            }
                            else {
                                Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' is outdated, a manual update is required")
                                Add-NotifiedStacks $CurrentObj.name
                                Write-Host -Message ("  -> Notification has been sent") -ForegroundColor DarkGreen
                            }
                        }
                        elseif ($CurrentObj.UpdatePolicy -eq "NTFYOnly" -and $env:NTFYEnabled -eq $false) {
                            Write-Host ("  -> WARNING: You have set this Stack to send NTFY but NTFY is not enabled yet, please check you configuration (environment Variables)")
                            Write-Host -Message ("  -> Notification has not been sent") -ForegroundColor Red
                        }
                        elseif ($CurrentObj.UpdatePolicy -eq "DoNotUpdate") {
                            Write-Host -Message ("  -> Stack has 'DoNotUpdate' Policy. Doing nothing.") -ForegroundColor Red
                        }
                    }
                    "updated" { 
                        $_ | Add-Member -NotePropertyName "LastSuccessfullUpdate" -NotePropertyValue (Get-Date)
                        Write-Host -Message (" -> [ UP2DATE  ] : " + $CurrentObj.Name + $Status.Message) -ForegroundColor Green
                        if ($NotifiedStacks -contains $CurrentObj.Name) {
                            Remove-NotifiedStacks -Names $CurrentObj.Name
                            Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' has been updated to latest version")
                        }
                    }
                    Default {
                        Write-Host -Message (" -> [  ERROR   ] : " + $CurrentObj.Name + ": Not Defined " + $Status.Message) -ForegroundColor Red
                    }
                }
            }
            catch {
                Write-Host -Message (" -> [  ERROR   ] : Stack '" + $CurrentObj.name + "'! " + $_.Exception.Message) -ForegroundColor Red
            }
        }
        elseif ($CurrentObj.UpdatePolicy -eq "DoNotUpdate") {
            Write-Host -Message (" -> [   DONT   ] : " + $CurrentObj.Name + " (has 'DoNotUpdate' Policy) " + $Status.Message) -ForegroundColor Gray
        }
    } 
}