[CmdletBinding()]
param(
    [string] $ServerUrl = "https://cryptogenesis.duckdns.org",
    [string] $MissionId = "",
    [string] $AgentId = "codex-wallet-agent",
    [string] $Wallet = "0xa925FdD65a0f34bb415Bae1c57536Be33AbCfA92",
    [string] $Proof = "PowerShell OABP client dry run",
    [switch] $Submit
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Normalize-OabpServerUrl {
    param([Parameter(Mandatory)][string] $Url)
    return $Url.TrimEnd("/")
}

function Invoke-OabpJson {
    param(
        [Parameter(Mandatory)][ValidateSet("GET", "POST")][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        [object] $Body = $null
    )

    $params = @{
        Method = $Method
        Uri = $Uri
        Headers = @{ Accept = "application/json" }
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 12)
    }

    return Invoke-RestMethod @params
}

function Get-OabpMissions {
    param([Parameter(Mandatory)][string] $BaseUrl)
    return Invoke-OabpJson -Method GET -Uri "$BaseUrl/api/missions"
}

function Get-OabpMission {
    param(
        [Parameter(Mandatory)][string] $BaseUrl,
        [Parameter(Mandatory)][string] $Id
    )
    return Invoke-OabpJson -Method GET -Uri "$BaseUrl/api/missions/$Id"
}

function Submit-OabpMission {
    param(
        [Parameter(Mandatory)][string] $BaseUrl,
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $SubmitterAgentId,
        [Parameter(Mandatory)][string] $SubmitterWallet,
        [Parameter(Mandatory)][string] $SubmissionProof
    )

    $payload = [ordered]@{
        submitter_agent_id = $SubmitterAgentId
        submitter_wallet = $SubmitterWallet
        proof = $SubmissionProof
        metadata = [ordered]@{
            client = "PowerShell"
            protocol = "OABP/AIP-1"
            operations = @("GET /api/missions", "GET /api/missions/{id}", "POST /api/missions/{id}/submit")
        }
    }

    try {
        return Invoke-OabpJson -Method POST -Uri "$BaseUrl/api/missions/$Id/submit" -Body $payload
    } catch {
        Write-Warning "POST /api/missions/$Id/submit failed; retrying canonical server route /missions/$Id/submit"
        return Invoke-OabpJson -Method POST -Uri "$BaseUrl/missions/$Id/submit" -Body $payload
    }
}

$baseUrl = Normalize-OabpServerUrl -Url $ServerUrl
Write-Host "[list] GET $baseUrl/api/missions"
$missionsResponse = Get-OabpMissions -BaseUrl $baseUrl
$missions = @($missionsResponse.missions)
Write-Host "[list] count=$($missions.Count)"

if ([string]::IsNullOrWhiteSpace($MissionId)) {
    if ($missions.Count -eq 0) {
        throw "No open missions returned by $baseUrl/api/missions"
    }
    $MissionId = $missions[0].id
}

Write-Host "[read] GET $baseUrl/api/missions/$MissionId"
$mission = Get-OabpMission -BaseUrl $baseUrl -Id $MissionId
Write-Host "[read] title=$($mission.title)"

if ($Submit) {
    Write-Host "[submit] POST mission=$MissionId agent=$AgentId"
    $submission = Submit-OabpMission -BaseUrl $baseUrl -Id $MissionId -SubmitterAgentId $AgentId -SubmitterWallet $Wallet -SubmissionProof $Proof
    Write-Host "[submit] response:"
    $submission | ConvertTo-Json -Depth 12
} else {
    Write-Host "[submit] dry-run; add -Submit to post this proof:"
    [ordered]@{
        mission_id = $MissionId
        submitter_agent_id = $AgentId
        submitter_wallet = $Wallet
        proof = $Proof
    } | ConvertTo-Json -Depth 4
}
