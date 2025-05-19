Import-Module Pode

Start-PodeServer -Verbose {
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http
    
    # Stacks
    Add-PodeRoute -Method Get -Path "/" -ScriptBlock {
        Write-PodeHtmlResponse (Get-Content ($PSScriptRoot + "/html/stacks.html") -Raw)
    }
    Add-PodeRoute -Method Get -Path "/stacks.html" -ScriptBlock {
        Write-PodeHtmlResponse (Get-Content ($PSScriptRoot + "/html/stacks.html") -Raw)
    }
    
    # Logs
    Add-PodeRoute -Method Get -Path "/logs.html" -ScriptBlock {
        Write-PodeHtmlResponse (Get-Content ($PSScriptRoot + "/html/logs.html") -Raw)
    }
    
    # Stacks API
    Add-PodeRoute -Method Get -Path "/api/stacks" -ScriptBlock {
        . ($PSScriptRoot + "/../functions.ps1")
        try {
            $Bearer = Get-BearerToken
            $stats = Get-Stacks
            Disconnect-Token
            Write-PodeJsonResponse -Value @{
                success = $true
                data = $stats
            }
        }
        catch {
            Write-PodeJsonResponse -Value @{
                success = $false
                error = ("<pre align='left'>" + ( $_.Exception | ConvertTo-Json -Depth 1) + "</pre>")
            } -StatusCode 500
        }
    }
    
    # StackUpdateStatus API
    Add-PodeRoute -Method Post -Path "/api/stack-update-status" -ScriptBlock {
        . ($PSScriptRoot + "/../functions.ps1")
        try {
            $Bearer = Get-BearerToken
            $StackUpdateStatus = Get-StackUpdateStatus -StackID $WebEvent.Data.StackID
            Disconnect-Token
            Write-PodeJsonResponse -Value @{
                success = $true
                data = $StackUpdateStatus
            }
        }
        catch {
            Write-PodeJsonResponse -Value @{
                success = $false
                error = $_.Exception.Message
                requested_id = $WebEvent.Data.StackID
            } -StatusCode 500
        }
    }

    # Fake log API
    Add-PodeRoute -Method Get -Path "/api/logs" -ScriptBlock {
        $logs = @(
            @{ timestamp = "2025-04-05 10:00:00"; message = "System started" },
            @{ timestamp = "2025-04-05 10:15:00"; message = "Low RAM" },
            @{ timestamp = "2025-04-05 10:20:00"; message = "Disk full" },
            @{ timestamp = "2025-04-05 10:25:00"; message = "Restart triggered" }
        )
        Write-PodeJsonResponse -Value $logs
    }
}