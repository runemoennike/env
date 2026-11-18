[CmdletBinding()]
param(
    [string]$Path = (Join-Path $HOME ".local/share/opencode/permission-audit.jsonl"),
    [Nullable[datetime]]$Since
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Audit log not found: $Path"
}

function Get-CommandPrefix {
    param(
        [string]$Tool,
        [AllowNull()][string]$ArgsSummary
    )

    if ($Tool -ne "bash") {
        return "(non-bash)"
    }

    if ([string]::IsNullOrWhiteSpace($ArgsSummary)) {
        return "(unknown)"
    }

    $trimmed = $ArgsSummary.Trim()
    if ($trimmed.Length -eq 0) {
        return "(unknown)"
    }

    $tokens = [regex]::Matches($trimmed, '\S+') | ForEach-Object { $_.Value }
    if (-not $tokens -or $tokens.Count -eq 0) {
        return "(unknown)"
    }

    if ($tokens.Count -eq 1) {
        return $tokens[0]
    }

    return "$($tokens[0]) $($tokens[1])"
}

function New-CallRecord {
    param(
        [string]$SessionID,
        [string]$CallID
    )

    [pscustomobject]@{
        SessionID      = $SessionID
        CallID         = $CallID
        Agent          = $null
        Tool           = $null
        ArgsSummary    = $null
        HasBefore      = $false
        HasAfter       = $false
        Asked          = $false
        Replies        = New-Object System.Collections.Generic.List[string]
        FirstTimestamp = $null
        LastTimestamp  = $null
    }
}

function Resolve-Outcome {
    param(
        $Call,
        [datetimeoffset]$SessionLastTimestamp,
        [datetimeoffset]$LogLastTimestamp
    )

    if ($Call.HasAfter) {
        if ($Call.Asked -and $Call.Replies -contains "reject") {
            return "PromptRejected"
        }

        if ($Call.Asked) {
            return "PromptApproved"
        }

        return "AutoAllowed"
    }

    if ($Call.Asked) {
        if ($Call.Replies -contains "reject") {
            return "PromptRejected"
        }

        if (($Call.Replies | Where-Object { $_ -eq "once" -or $_ -eq "always" }).Count -gt 0) {
            return "PromptApproved"
        }

        if ($null -eq $Call.LastTimestamp -or $null -eq $LogLastTimestamp) {
            return "Unresolved"
        }

        return "Unresolved"
    }

    if (-not $Call.HasBefore) {
        return "Unresolved"
    }

    if ($null -eq $Call.LastTimestamp -or $null -eq $SessionLastTimestamp) {
        return "Unresolved"
    }

    if ($Call.LastTimestamp -eq $SessionLastTimestamp) {
        return "Unresolved"
    }

    if ($null -eq $LogLastTimestamp) {
        return "Unresolved"
    }

    $age2 = $LogLastTimestamp - $Call.LastTimestamp
    if ($age2.TotalMinutes -lt 10) {
        return "Unresolved"
    }

    return "HardDenied"
}

$callsByKey = @{}
$requestToCallKey = @{}
$sessionLastTimestamp = @{}
$globalLastTimestamp = $null

$lines = Get-Content -LiteralPath $Path -ErrorAction Stop

foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    try {
        $entry = $line | ConvertFrom-Json -Depth 50
    }
    catch {
        continue
    }

    if ($null -eq $entry.ts -or $null -eq $entry.kind) {
        continue
    }

    try {
        if ($entry.ts -is [datetimeoffset]) {
            [datetimeoffset]$ts = $entry.ts
        }
        elseif ($entry.ts -is [datetime]) {
            [datetimeoffset]$ts = [datetimeoffset]$entry.ts
        }
        else {
            [datetimeoffset]$ts = [datetimeoffset]::Parse([string]$entry.ts, [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }
    catch {
        continue
    }

    if ($null -eq $globalLastTimestamp -or $ts -gt $globalLastTimestamp) {
        $globalLastTimestamp = $ts
    }

    $sessionID = if ([string]::IsNullOrWhiteSpace([string]$entry.sessionID)) { $null } else { [string]$entry.sessionID }
    if (-not $sessionID) {
        continue
    }

    if (-not $sessionLastTimestamp.ContainsKey($sessionID) -or $ts -gt $sessionLastTimestamp[$sessionID]) {
        $sessionLastTimestamp[$sessionID] = $ts
    }

    $callID = if ([string]::IsNullOrWhiteSpace([string]$entry.callID)) { $null } else { [string]$entry.callID }
    $kind = [string]$entry.kind

    if ($kind -eq "permission.replied") {
        $requestID = if ([string]::IsNullOrWhiteSpace([string]$entry.requestID)) { $null } else { [string]$entry.requestID }
        if ($requestID) {
            $reqKey = "$sessionID`::$requestID"
            if ($requestToCallKey.ContainsKey($reqKey)) {
                $mapped = [string]$requestToCallKey[$reqKey]
                $parts = $mapped.Split("::", 2)
                if ($parts.Count -eq 2) {
                    $callID = $parts[1]
                }
            }
        }
    }

    if (-not $callID) {
        continue
    }

    $callKey = "$sessionID`::$callID"
    if (-not $callsByKey.ContainsKey($callKey)) {
        $callsByKey[$callKey] = New-CallRecord -SessionID $sessionID -CallID $callID
    }

    $call = $callsByKey[$callKey]

    if ($null -eq $call.FirstTimestamp -or $ts -lt $call.FirstTimestamp) {
        $call.FirstTimestamp = $ts
    }
    if ($null -eq $call.LastTimestamp -or $ts -gt $call.LastTimestamp) {
        $call.LastTimestamp = $ts
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$entry.agent)) {
        $call.Agent = [string]$entry.agent
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$entry.tool)) {
        $call.Tool = [string]$entry.tool
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$entry.argsSummary)) {
        $call.ArgsSummary = [string]$entry.argsSummary
    }

    switch ($kind) {
        "tool.before" {
            $call.HasBefore = $true
        }
        "tool.after" {
            $call.HasAfter = $true
        }
        "permission.asked" {
            $call.Asked = $true
            $requestID = if ([string]::IsNullOrWhiteSpace([string]$entry.requestID)) { $null } else { [string]$entry.requestID }
            if ($requestID) {
                $requestToCallKey["$sessionID`::$requestID"] = $callKey
            }
        }
        "permission.replied" {
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.reply)) {
                [void]$call.Replies.Add(([string]$entry.reply).ToLowerInvariant())
            }
        }
    }
}

$classified = foreach ($kvp in $callsByKey.GetEnumerator()) {
    $call = $kvp.Value

    if ($Since.HasValue) {
        $sinceUtc = $Since.Value.ToUniversalTime()
        if ($null -eq $call.FirstTimestamp -or $call.FirstTimestamp.UtcDateTime -lt $sinceUtc) {
            continue
        }
    }

    $tool = if ([string]::IsNullOrWhiteSpace($call.Tool)) { "(unknown)" } else { $call.Tool }
    $agent = if ([string]::IsNullOrWhiteSpace($call.Agent)) { "(unknown)" } else { $call.Agent }
    $prefix = Get-CommandPrefix -Tool $tool -ArgsSummary $call.ArgsSummary
    $sessionTail = if ($sessionLastTimestamp.ContainsKey($call.SessionID)) { $sessionLastTimestamp[$call.SessionID] } else { $globalLastTimestamp }

    [pscustomobject]@{
        Outcome       = Resolve-Outcome -Call $call -SessionLastTimestamp $sessionTail -LogLastTimestamp $globalLastTimestamp
        Agent         = $agent
        Tool          = $tool
        CommandPrefix = $prefix
        SessionID     = $call.SessionID
        CallID        = $call.CallID
    }
}

if (-not $classified -or $classified.Count -eq 0) {
    "No correlated tool calls found in $Path"
    exit 0
}

"`nOutcome totals"
$classified |
    Group-Object Outcome |
    Sort-Object Count -Descending |
    Select-Object Count, Name |
    Format-Table -AutoSize

"`nOutcome x Agent"
$classified |
    Group-Object Outcome, Agent |
    Sort-Object Count -Descending |
    ForEach-Object {
        [pscustomobject]@{
            Count   = $_.Count
            Outcome = $_.Group[0].Outcome
            Agent   = $_.Group[0].Agent
        }
    } |
    Format-Table -AutoSize

"`nOutcome x Tool"
$classified |
    Group-Object Outcome, Tool |
    Sort-Object Count -Descending |
    ForEach-Object {
        [pscustomobject]@{
            Count   = $_.Count
            Outcome = $_.Group[0].Outcome
            Tool    = $_.Group[0].Tool
        }
    } |
    Format-Table -AutoSize

"`nOutcome x CommandPrefix"
$classified |
    Group-Object Outcome, CommandPrefix |
    Sort-Object Count -Descending |
    ForEach-Object {
        [pscustomobject]@{
            Count         = $_.Count
            Outcome       = $_.Group[0].Outcome
            CommandPrefix = $_.Group[0].CommandPrefix
        }
    } |
    Format-Table -AutoSize

$promptApprovedPrefixes =
    $classified |
    Where-Object { $_.Outcome -eq "PromptApproved" -and $_.Tool -eq "bash" } |
    Group-Object CommandPrefix |
    Sort-Object Count -Descending |
    ForEach-Object {
        [pscustomobject]@{
            Count         = $_.Count
            CommandPrefix = $_.Name
            Note          = "candidate for allow rules"
        }
    }

if ($promptApprovedPrefixes -and $promptApprovedPrefixes.Count -gt 0) {
    "`nPromptApproved bash prefixes (candidates for allow rules)"
    $promptApprovedPrefixes | Format-Table -AutoSize
}
