. ($PSScriptRoot + "/functions.ps1")

# Check if all needed variabels are set:


# Sanatize Vars
$env:PortainerBaseAddress = $env:PortainerBaseAddress.TrimEnd("/")
$PortainerBaseDomain = ([System.Uri]::new($env:PortainerBaseAddress)).Host

# Get All Stacks
Write-Host ("Getting all Stacks...") -ForegroundColor Blue
try {
    $Stacks = Get-PortainerStacks
    Write-Host (" -> Got " + $Stacks.count + " ") -ForegroundColor Green
}
catch {
    Write-Host (" -> Error! " + $_.Exception.Message) -ForegroundColor Red
    Exit 1
}

# Get All Stack Status and strigger according action
Write-Host ("Looking for Outdated Stacks on '$PortainerBaseDomain'`n (Default update Policy is '$env:AutoUpdateDefaultMode')") -ForegroundColor Blue

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
                        Write-Host (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (but Active, maybe update already in progress?) " + $Status.Message) -ForegroundColor Red
                    }
                    elseif ($CurrentObj.Status -eq 2) {
                        Write-Host (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (because Inactive) " + $Status.Message) -ForegroundColor Gray
                    }
                    else {
                        Write-Host (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (unhandled) " + $Status.Message) -ForegroundColor Red
                    }
                }
                "outdated" { 
                    #$_ | Add-Member -NotePropertyName "LastSuccessfullUpdate" -NotePropertyValue (Get-Date)
                    Write-Host (" -> [ OUTDATED ] : " + $CurrentObj.Name + "(" + $CurrentObj.UpdatePolicy + ")" + $Status.Message) -ForegroundColor Yellow
                    if ($CurrentObj.UpdatePolicy -eq "AutoUpdate") {
                        try {
                            Update-Stack -Stack $CurrentObj -ErrorAction Stop
                            Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' is outdated, update has been triggered!")
                            Write-Host ("  -> Update has been triggered successfully!") -ForegroundColor Green
                        }
                        catch {
                            Write-Host ("  -> Error: " + $_.Exception.Message) -ForegroundColor Red
                        }
                    }
                    elseif ($CurrentObj.UpdatePolicy -eq "NTFYOnly" -and $env:NTFYEnabled -eq $true) {   
                        Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' is outdated, a manual update is required")
                        Write-Host ("  -> Notification has been sent") -ForegroundColor DarkGreen
                    }
                    elseif ($CurrentObj.UpdatePolicy -eq "NTFYOnly" -and $env:NTFYEnabled -eq $false) {
                        Write-Host ("  -> WARNING: You have set this Stack to send NTFY but NTFY is not enabled yet, please check you configuration (environment Variables)")
                        Write-Host ("  -> Notification has not been sent") -ForegroundColor Red
                    }
                    elseif ($CurrentObj.UpdatePolicy -eq "DoNotUpdate") {
                        Write-Host ("  -> Stack has 'DoNotUpdate' Policy. Doing nothing.") -ForegroundColor Red
                    }
                }
                "updated" { 
                    $_ | Add-Member -NotePropertyName "LastSuccessfullUpdate" -NotePropertyValue (Get-Date)
                    Write-Host (" -> [ UP2DATE  ] : " + $CurrentObj.Name + $Status.Message) -ForegroundColor Green
                }
                Default {
                    Write-Host (" -> [  ERROR   ] : " + $CurrentObj.Name + ": Not Defined " + $Status.Message) -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Host (" -> [  ERROR   ] : Stack '" + $CurrentObj.name + "'! " + $_.Exception.Message) -ForegroundColor Red
        }
    }
    elseif ($CurrentObj.UpdatePolicy -eq "DoNotUpdate") {
        Write-Host (" -> [   DONT   ] : " + $CurrentObj.Name + " (has 'DoNotUpdate' Policy) " + $Status.Message) -ForegroundColor Gray
    }
} 