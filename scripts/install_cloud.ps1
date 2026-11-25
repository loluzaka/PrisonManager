# =============================================================================
# install_cloud.ps1 - deploys the project to an Oracle Autonomous Database (mTLS wallet connection)
# Features: F29 (cloud deployment), F32 (secure cloud access)
# STATUS  : prepared but NOT YET RUN - it needs a real Autonomous Database and its wallet.
# Usage   : .\scripts\install_cloud.ps1 [-Fresh]
# Needs   : Docker running (the local Oracle container is reused only as a SQL*Plus client),
#           .env containing TNS_ADMIN (unzipped wallet folder), PRISON_CLOUD_TNS (service alias from
#           tnsnames.ora, e.g. prisondb_high) and the three PRISON_CLOUD_*_PASSWORD values.
# Nothing secret is written into the repository: the wallet folder and .env are git-ignored.
# =============================================================================
param([switch]$Fresh)
. "$PSScriptRoot\common.ps1"
Initialize-Env
$name   = Get-Setting 'PRISON_CONTAINER' 'prison-oracle'
$wallet = Get-Setting 'TNS_ADMIN'
$tns    = Get-Setting 'PRISON_CLOUD_TNS'
$admin  = Get-Setting 'PRISON_CLOUD_ADMIN_PASSWORD'
$owner  = Get-Setting 'PRISON_CLOUD_OWNER_PASSWORD'
$demo   = Get-Setting 'PRISON_CLOUD_DEMO_PASSWORD'
foreach ($p in 'TNS_ADMIN','PRISON_CLOUD_TNS','PRISON_CLOUD_ADMIN_PASSWORD','PRISON_CLOUD_OWNER_PASSWORD','PRISON_CLOUD_DEMO_PASSWORD') {
    if (-not (Get-Setting $p) -or (Get-Setting $p) -like 'change_me*' -or (Get-Setting $p) -like 'C:\path*') {
        throw "Set $p in .env first (see .env.example and Documentation/Cloud_Setup.md)."
    }
}
if (-not (Test-Path (Join-Path $wallet 'tnsnames.ora'))) { throw "No tnsnames.ora in $wallet - unzip the wallet there." }

Write-Host 'Copying the wallet into the client container (/tmp/wallet) ...'
docker exec $name rm -rf /tmp/wallet | Out-Null
docker cp $wallet "${name}:/tmp/wallet" | Out-Null
docker exec $name bash -c "sed -i 's#?/network/admin#/tmp/wallet#g' /tmp/wallet/sqlnet.ora" | Out-Null

function Invoke-CloudSql([string]$User, [string]$Pass, [string]$Script, [string[]]$Args = @()) {
    $argText = ($Args | ForEach-Object { "`"$_`"" }) -join ' '
    docker exec -i -e TNS_ADMIN=/tmp/wallet $name bash -c "cd /prison/sql && sqlplus -L -S `"$User/$Pass@$tns`" @$Script $argText"
    if ($LASTEXITCODE -ne 0) { throw "SQL*Plus failed for $Script" }
}

Write-Host '== 1/3 Schema owner and demo users (as ADMIN) ==' -ForegroundColor Cyan
Invoke-CloudSql 'ADMIN' $admin '00_admin_setup.sql' @($owner, $demo)
if ($Fresh) { Invoke-CloudSql 'PRISON_OWNER' $owner '99_drop_all.sql' }
Write-Host '== 2/3 Build (run_all.sql as PRISON_OWNER) ==' -ForegroundColor Cyan
Invoke-CloudSql 'PRISON_OWNER' $owner 'run_all.sql'
Write-Host '== 3/3 Connection check ==' -ForegroundColor Cyan
docker exec -i -e TNS_ADMIN=/tmp/wallet $name bash -c "cd /prison/cloud && sqlplus -L -S `"PRISON_OWNER/$owner@$tns`" @connection_check.sql"
Write-Host 'Cloud install finished.' -ForegroundColor Green
