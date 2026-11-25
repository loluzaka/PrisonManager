# =============================================================================
# common.ps1 - shared helpers for the local Docker deployment scripts (dot-source this file)
# Feature : F29 / F32 (credentials come from .env or the environment, never from the repo)
# Usage   : . "$PSScriptRoot\common.ps1"
# =============================================================================
$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)   # no BOM when piping SQL text to SQL*Plus
$script:Root = Split-Path -Parent $PSScriptRoot
$script:EnvFile = Join-Path $script:Root '.env'

function New-RandomPassword {
    # letter first (Oracle rule), then random letters/digits; no special characters so it is safe in connect strings
    $chars = (48..57) + (65..90) + (97..122) | ForEach-Object { [char]$_ }
    'Pm' + (-join (1..14 | ForEach-Object { $chars | Get-Random })) + '9x'
}

function Initialize-Env {
    # Create .env with random passwords on first run, then load every KEY=VALUE into the process environment.
    if (-not (Test-Path $script:EnvFile)) {
        $content = @"
PRISON_CONTAINER=prison-oracle
PRISON_DB_PORT=1521
PRISON_DB_SERVICE=FREEPDB1
PRISON_SYS_PASSWORD=$(New-RandomPassword)
PRISON_OWNER_PASSWORD=$(New-RandomPassword)
PRISON_DEMO_PASSWORD=$(New-RandomPassword)
"@
        Set-Content -Path $script:EnvFile -Value $content -Encoding ascii
        Write-Host "Created $script:EnvFile with random passwords (git-ignored)." -ForegroundColor Yellow
    }
    Get-Content $script:EnvFile | ForEach-Object {
        if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
}

function Get-Setting([string]$Name, [string]$Default = '') {
    $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrEmpty($v)) { $Default } else { $v }
}

function Invoke-LocalSql {
    <#
      Runs a script (relative to /prison/sql inside the container) or an inline SQL string with SQL*Plus.
        Invoke-LocalSql -User prison_owner -Password $pw -Script '04_seed_data.sql' -ScriptArgs 'a','b'
        Invoke-LocalSql -User prison_owner -Password $pw -Inline "SELECT 1 FROM dual;"
    #>
    param(
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password,
        [string]$Script,
        [string[]]$ScriptArgs = @(),
        [string]$Inline,
        [string]$WorkDir = '/prison/sql',
        [switch]$AsSysdba
    )
    $container = Get-Setting 'PRISON_CONTAINER' 'prison-oracle'
    $service   = Get-Setting 'PRISON_DB_SERVICE' 'FREEPDB1'
    $connect   = "$User/$Password@//localhost:1521/$service"
    if ($AsSysdba) { $connect += ' as sysdba' }
    if ($Script) {
        $argText = ($ScriptArgs | ForEach-Object { "`"$_`"" }) -join ' '
        $cmd = "cd $WorkDir && sqlplus -L -S `"$connect`" @$Script $argText"
        docker exec -i $container bash -c $cmd
    } else {
        # send the SQL as base64 so no byte-order mark or console code page can corrupt the first line
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Inline))
        docker exec $container bash -c "echo $b64 | base64 -d | sqlplus -L -S '$connect'"

    }
    if ($LASTEXITCODE -ne 0) { throw "SQL*Plus exited with code $LASTEXITCODE" }
}
