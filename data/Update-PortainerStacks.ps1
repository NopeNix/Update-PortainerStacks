. ($PSScriptRoot + "/functions.ps1")

# Check if all needed variabels are set:


# Sanatize Vars
$env:PortainerBaseAddress= $env:PortainerBaseAddress.TrimEnd("/")
$PortainerBaseDomain = ([System.Uri]::new($env:PortainerBaseAddress)).Host

# Get Bearer Token
Write-Host ("Getting Bearer token from '$env:PortainerBaseAddress' with User '$env:PortainerUsername'...") -ForegroundColor Blue
try {
    $Bearer = Get-BearerToken
    Write-Host (" -> OK") -ForegroundColor Green
}
catch {
    Write-Host (" -> Error! " + $_.Exception.Message) -ForegroundColor Red
    Exit 1
}

# Get All Stacks
Write-Host ("Getting all Stacks...") -ForegroundColor Blue
try {
    $Stacks = Get-Stacks
    Write-Host (" -> Got " + $Stacks.count + " ") -ForegroundColor Green
}
catch {
    Write-Host (" -> Error! " + $_.Exception.Message) -ForegroundColor Red
    Exit 1
}

# Get All Stack Status and strigger according action
Write-Host ("Looking for Outdated Stacks on '$PortainerBaseDomain'`n (Default update Policy is '$AutoUpdateDefaultMode')...") -ForegroundColor Blue

$Stacks | ForEach-Object {
    $CurrentObj = $_
    if ($null -eq $_.UpdatePolicy) {
        $_ | Add-Member -NotePropertyName "UpdatePolicy"  -NotePropertyValue $env:AutoUpdateDefaultMode-Force
    }
    if ($_.UpdatePolicy -eq "AutoUpdate" -or $_.UpdatePolicy -eq "OnlyNTFY") {
        try {
            $Status = Get-StackUpdateStatus -Stack $CurrentObj
    
            switch ($Status.Status) {
                "skipped" { 
                    if ($CurrentObj.Status -eq 1) {
                        Write-Host (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (but Active, maybe update already in progress?) " + $Status.Message) -ForegroundColor Red
                    } elseif ($CurrentObj.Status -eq 2) {
                        Write-Host (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (because Inactive) " + $Status.Message) -ForegroundColor Gray
                    } else {
                        Write-Host (" -> [ SKIPPED  ] : " + $CurrentObj.Name + " (unhandled) " + $Status.Message) -ForegroundColor Red
                    }
                }
                "outdated" { 
                    $_ | Add-Member -NotePropertyName "LastSuccessfullUpdate" -NotePropertyValue (Get-Date)
                    Write-Host (" -> [ OUTDATED ] : " + $CurrentObj.Name + $Status.Message + " triggering Update...") -ForegroundColor Yellow
                    if ($_.UpdatePolicy -eq "AutoUpdate") {
                        try {
                            Update-Stack -Stack $CurrentObj -ErrorAction Stop
                            Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' is outdated, update has been triggered!")
                            Write-Host ("  -> Update has been triggered successfully!") -ForegroundColor Green
                        }
                        catch {
                            Write-Host ("  -> Error: " + $_.Exception.Message) -ForegroundColor Red
                        }
                    } elseif ($_.UpdatePolicy -eq "AutoUpdate" -and $env:NTFYEnabled-eq $true) {
                        Send-NTFYMessage -Message ("'" + $CurrentObj.name + "' is outdated, NO update has been triggered!")
                        Write-Host ("  -> Notification has been sent") -ForegroundColor Green
                    } elseif ($_.UpdatePolicy -eq "AutoUpdate" -and $env:NTFYEnabled-eq $false) {
                        Write-Host ("WARNING: You have set this Stack to send NTFY but NTFY is not enabled yet, please check you configuration (environment Variables)")
                        Write-Host ("  -> Notification has not been sent") -ForegroundColor Red
                    }
                }
                "updated" { 
                    $_ | Add-Member -NotePropertyName "LastSuccessfullUpdate" -NotePropertyValue (Get-Date)
                    Write-Host (" -> [ UP2DATE  ] : " + $CurrentObj.Name + ": Up to Date " + $Status.Message) -ForegroundColor Green
                }
                Default {
                    Write-Host (" -> [  ERROR   ] : " + $CurrentObj.Name + ": Not Defined " + $Status.Message) -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Host (" -> [  ERROR   ] : Stack '" + $CurrentObj.name + "'! " + $_.Exception.Message) -ForegroundColor Red
        }
    } elseif ($_.UpdatePolicy -eq "DoNotUpdate") {
        Write-Host (" -> [   DONT   ] : " + $CurrentObj.Name + " (has 'DoNotUpdate' Policy) " + $Status.Message) -ForegroundColor Gray
    }
} 

Disconnect-Token