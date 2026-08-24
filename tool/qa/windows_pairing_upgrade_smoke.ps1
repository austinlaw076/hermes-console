param(
    [string]$PairScript = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) "scripts/hermes-pair.ps1")
)

$ErrorActionPreference = "Stop"
$testHome = Join-Path ([IO.Path]::GetTempPath()) ("hermes-pair-upgrade-" + [Guid]::NewGuid().ToString("N"))
$previousHome = $env:HERMES_HOME
$previousRaw = $env:HERMES_REPO_RAW

function global:Invoke-RestMethod {
    param(
        [string]$Method,
        [string]$Uri,
        [int]$TimeoutSec,
        [hashtable]$Headers
    )
    if ($Uri -notlike "*/hermes-mobile-setup.ps1") {
        throw "Unexpected network request in pairing upgrade smoke test: $Uri"
    }
    return @'
# Hermes Console - native Windows setup (PowerShell 5.1+).
$ServicesDir = Join-Path $env:HERMES_HOME "console-services"
$PairingFile = Join-Path $ServicesDir "pairing.json"
function Get-PairingConfiguration { return $null }
$services = Join-Path $env:HERMES_HOME "console-services"
New-Item -ItemType Directory -Force -Path $services | Out-Null
$pairing = '{"schema":1,"host":"192.168.1.20","scheme":"http","port":8642,"gateway":"http://192.168.1.20:8642","dashboard":"http://192.168.1.20:9119","bridge":"http://192.168.1.20:9131","kind":"lan"}'
[IO.File]::WriteAllText((Join-Path $services "pairing.json"), $pairing)
[IO.File]::WriteAllText((Join-Path $env:HERMES_HOME "repair-ran"), "ok")
'@
}

try {
    New-Item -ItemType Directory -Force -Path $testHome | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $testHome ".env"),
        "API_SERVER_KEY=0123456789abcdef0123456789abcdef" + [Environment]::NewLine
    )
    $env:HERMES_HOME = $testHome
    $env:HERMES_REPO_RAW = "https://example.invalid/hermes-setup"

    . $PairScript

    if (-not (Test-Path -LiteralPath (Join-Path $testHome "repair-ran"))) {
        throw "The legacy-install repair path did not execute."
    }
    $pairingFile = Join-Path $testHome "console-services/pairing.json"
    if (-not (Test-Path -LiteralPath $pairingFile)) {
        throw "The repair path did not create pairing metadata."
    }
    $pairing = Get-Content -LiteralPath $pairingFile -Raw | ConvertFrom-Json
    if ($pairing.schema -ne 1) {
        throw "The repaired pairing metadata has the wrong schema."
    }
    Write-Host "windows pairing upgrade smoke: OK"
} finally {
    Remove-Item -LiteralPath Function:\Invoke-RestMethod -Force -ErrorAction SilentlyContinue
    if ($null -eq $previousHome) {
        Remove-Item Env:\HERMES_HOME -ErrorAction SilentlyContinue
    } else {
        $env:HERMES_HOME = $previousHome
    }
    if ($null -eq $previousRaw) {
        Remove-Item Env:\HERMES_REPO_RAW -ErrorAction SilentlyContinue
    } else {
        $env:HERMES_REPO_RAW = $previousRaw
    }
    Remove-Item -LiteralPath $testHome -Recurse -Force -ErrorAction SilentlyContinue
}
