<#
.SYNOPSIS
    Enable the OCI VCN Security List ingress rule for the public Kanban proxy
    port (TCP 3484) from YOUR WORKSTATION, using your already-configured local
    OCI CLI (~/.oci/config with an API key / user auth).

.DESCRIPTION
    This replaces the previous approach that installed the OCI CLI on the Oracle
    instance and used instance-principal auth (which needed a tenancy-level
    dynamic-group + policy). Running it locally with your own credentials avoids
    all of that: you already have permission in the OCI Console, so the CLI you
    already use has it too.

    The rule added is idempotent (a no-op if the port is already open):
      Stateless: No | Source: 0.0.0.0/0 | Protocol: TCP | Dest port: 3484

    Provide exactly ONE target: -InstanceId, -SubnetId, or -SecurityListId.

.PARAMETER InstanceId
    OCID of the Oracle Compute instance. Its primary VNIC -> subnet -> security
    list are resolved automatically.

.PARAMETER SubnetId
    OCID of the subnet. Its first security list is used.

.PARAMETER SecurityListId
    OCID of the security list to update directly.

.PARAMETER Port
    TCP port to open. Default: 3484.

.PARAMETER Source
    Source CIDR for the rule. Default: 0.0.0.0/0.

.PARAMETER Profile
    OCI CLI config profile to use. Default: DEFAULT.

.EXAMPLE
    ./deploy/enable-oci-ingress.ps1 -InstanceId ocid1.instance.oc1..aaaa

.EXAMPLE
    ./deploy/enable-oci-ingress.ps1 -SecurityListId ocid1.securitylist.oc1..bbbb -Port 3484

.NOTES
    Requires: oci (OCI CLI) on PATH. Uses PowerShell's built-in JSON support
    (no python3 needed on Windows).
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)][string]$InstanceId,
    [Parameter(Mandatory=$false)][string]$SubnetId,
    [Parameter(Mandatory=$false)][string]$SecurityListId,
    [Parameter(Mandatory=$false)][int]$Port = 3484,
    [Parameter(Mandatory=$false)][string]$Source = "0.0.0.0/0",
    [Parameter(Mandatory=$false)][string]$Profile
)

$ErrorActionPreference = "Stop"

# The OCI CLI is a Python program that can emit a harmless SyntaxWarning to
# stderr at import time. Under $ErrorActionPreference='Stop', that native-command
# stderr write is otherwise promoted to a terminating error. Suppress it.
if (-not $env:PYTHONWARNINGS) { $env:PYTHONWARNINGS = "ignore" }

function Invoke-Oci {
    # Runs the OCI CLI with the optional profile and returns raw stdout.
    param([Parameter(Mandatory=$true)][string[]]$OciArgs)
    $allArgs = @()
    if ($Profile) { $allArgs += @("--profile", $Profile) }
    $allArgs += $OciArgs
    # Localize the error-action preference so any stray stderr from the native
    # CLI (e.g. a Python warning) does not become a terminating error before the
    # redirection can capture it. We still check $LASTEXITCODE below.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $errFile = Join-Path ([System.IO.Path]::GetTempPath()) ("oci-stderr-" + [System.Guid]::NewGuid().ToString() + ".txt")
    try {
        $out = & oci @allArgs 2>$errFile
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($LASTEXITCODE -ne 0) {
        $errText = ""
        if (Test-Path $errFile) { $errText = (Get-Content -Path $errFile -Raw) }
        Remove-Item -Path $errFile -ErrorAction SilentlyContinue
        throw "oci $($allArgs -join ' ') failed with exit code $LASTEXITCODE`n$errText"
    }
    Remove-Item -Path $errFile -ErrorAction SilentlyContinue
    return $out
}

# --- Preconditions ----------------------------------------------------------
if (-not (Get-Command oci -ErrorAction SilentlyContinue)) {
    Write-Error "The OCI CLI ('oci') is not on PATH. Install it and run 'oci setup config' first: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
    exit 1
}

# Provide exactly one target.
$targets = @($InstanceId, $SubnetId, $SecurityListId | Where-Object { $_ })
if ($targets.Count -ne 1) {
    Write-Error "Provide exactly one of -InstanceId / -SubnetId / -SecurityListId."
    exit 1
}

Write-Host "=== Enabling OCI VCN ingress for TCP $Port (source $Source) ==="

# --- Resolve instance -> subnet ---------------------------------------------
if ($InstanceId) {
    Write-Host "Resolving primary VNIC / subnet for instance $InstanceId..."
    # NOTE: We fetch full JSON and parse it in PowerShell rather than using OCI's
    # --query, because PowerShell strips the embedded double quotes from native-
    # command arguments. That mangles any JMESPath expression that must quote a
    # kebab-case key (e.g. data."compartment-id" arrives as data.compartment-id,
    # which fails with a JMESPath LexerError).
    $instJson = Invoke-Oci @("compute", "instance", "get", "--instance-id", $InstanceId, "--output", "json") | ConvertFrom-Json
    $compartmentId = $instJson.data.'compartment-id'
    if (-not $compartmentId) {
        Write-Error "Could not read the instance (check the OCID, profile, and permissions)."
        exit 1
    }
    $vnicsJson = Invoke-Oci @("compute", "instance", "list-vnics", "--instance-id", $InstanceId, "--compartment-id", $compartmentId, "--output", "json") | ConvertFrom-Json
    $SubnetId = $vnicsJson.data[0].'subnet-id'
    if (-not $SubnetId) {
        Write-Error "Could not resolve the instance's subnet."
        exit 1
    }
    Write-Host "Subnet: $SubnetId"
}

# --- Resolve subnet -> security list ----------------------------------------
if ($SubnetId -and -not $SecurityListId) {
    $subnetJson = Invoke-Oci @("network", "subnet", "get", "--subnet-id", $SubnetId, "--output", "json") | ConvertFrom-Json
    $SecurityListId = $subnetJson.data.'security-list-ids'[0]
    if (-not $SecurityListId) {
        Write-Error "Could not resolve the subnet's security list."
        exit 1
    }
}
Write-Host "Target security list: $SecurityListId"

# --- Fetch current ingress rules --------------------------------------------
$slJson = Invoke-Oci @("network", "security-list", "get", "--security-list-id", $SecurityListId, "--output", "json") | ConvertFrom-Json
if (-not $slJson) {
    Write-Error "Could not read current ingress rules for $SecurityListId."
    exit 1
}

# The CLI returns kebab-case JSON; the update command expects camelCase.
$curRules = @($slJson.data.'ingress-security-rules')

function ConvertTo-CamelKey([string]$s) {
    $parts = $s.Split('-')
    $out = $parts[0]
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $p = $parts[$i]
        if ($p.Length -gt 0) { $out += $p.Substring(0,1).ToUpper() + $p.Substring(1) }
    }
    return $out
}

function Convert-Keys($obj) {
    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
        return @($obj | ForEach-Object { Convert-Keys $_ })
    }
    if ($obj -is [psobject] -and $obj.PSObject.Properties.Count -gt 0 -and $null -eq ($obj -as [ValueType])) {
        $h = [ordered]@{}
        foreach ($prop in $obj.PSObject.Properties) {
            $h[(ConvertTo-CamelKey $prop.Name)] = Convert-Keys $prop.Value
        }
        return [pscustomobject]$h
    }
    return $obj
}

$camelRules = @(Convert-Keys $curRules)

function Test-Covers($r) {
    if ($r.source -ne $Source) { return $false }
    $proto = [string]$r.protocol
    if ($proto -eq "all") { return $true }
    if ($proto -ne "6") { return $false }   # 6 = TCP
    $tcp = $r.tcpOptions
    if (-not $tcp -or -not $tcp.destinationPortRange) { return $true }  # all TCP ports
    $dpr = $tcp.destinationPortRange
    $min = if ($null -ne $dpr.min) { [int]$dpr.min } else { 1 }
    $max = if ($null -ne $dpr.max) { [int]$dpr.max } else { 65535 }
    return ($min -le $Port -and $Port -le $max)
}

$alreadyOpen = $false
foreach ($r in $camelRules) {
    if (Test-Covers $r) { $alreadyOpen = $true; break }
}

if ($alreadyOpen) {
    Write-Host "[OK] OCI ingress for TCP $Port (source $Source) already present - nothing to do."
    exit 0
}

# --- Append the new rule and write the full set to a temp file --------------
$newRule = [pscustomobject]@{
    source      = $Source
    sourceType  = "CIDR_BLOCK"
    protocol    = "6"
    isStateless = $false
    tcpOptions  = [pscustomobject]@{
        destinationPortRange = [pscustomobject]@{ min = $Port; max = $Port }
    }
}
$updated = @($camelRules + $newRule)

$rulesFile = Join-Path ([System.IO.Path]::GetTempPath()) ("oci-ingress-rules-" + [System.Guid]::NewGuid().ToString() + ".json")
try {
    # -Depth ensures nested tcpOptions/destinationPortRange are serialized fully.
    # Write UTF-8 WITHOUT a BOM: Windows PowerShell 5.1's `Set-Content -Encoding
    # utf8` prepends a BOM (EF BB BF), and the OCI CLI reads the file with the
    # system default codec (e.g. cp949 on a Korean-locale box), which then fails
    # with "UnicodeDecodeError ... 0xbf". A BOM-less UTF-8 file avoids that.
    $json = ($updated | ConvertTo-Json -Depth 10)
    [System.IO.File]::WriteAllText($rulesFile, $json, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "Adding ingress rule for TCP $Port..."
    Invoke-Oci @("network", "security-list", "update", "--security-list-id", $SecurityListId, "--ingress-security-rules", "file://$rulesFile", "--force") | Out-Null
    Write-Host "[OK] Added OCI ingress rule for TCP $Port (source $Source)."
}
catch {
    Write-Error "Failed to update the security list: $($_.Exception.Message)"
    exit 1
}
finally {
    Remove-Item -Path $rulesFile -ErrorAction SilentlyContinue
}
