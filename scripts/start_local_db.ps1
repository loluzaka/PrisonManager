# =============================================================================
# start_local_db.ps1 - starts (or creates) the local Oracle Database Free container
# Feature : F29 (local stand-in for the cloud database; same Oracle SQL / PL/SQL)
# Usage   : .\scripts\start_local_db.ps1
# Needs   : Docker Desktop running. Image gvenzl/oracle-free:slim-faststart (Oracle 23ai Free).
# The project folder is mounted into the container at /prison so SQL*Plus can read the scripts.
# =============================================================================
. "$PSScriptRoot\common.ps1"
Initialize-Env
$name = Get-Setting 'PRISON_CONTAINER' 'prison-oracle'
$port = Get-Setting 'PRISON_DB_PORT' '1521'

$existing = docker ps -a --filter "name=^$name$" --format '{{.Status}}'
if (-not $existing) {
    Write-Host "Creating container $name ..."
    docker run -d --name $name -p "${port}:1521" `
        -e ORACLE_PASSWORD=$(Get-Setting 'PRISON_SYS_PASSWORD') `
        -v "${script:Root}:/prison" `
        gvenzl/oracle-free:slim-faststart | Out-Null
} elseif ($existing -notmatch '^Up') {
    Write-Host "Starting existing container $name ..."
    docker start $name | Out-Null
} else {
    Write-Host "Container $name is already running."
}

Write-Host 'Waiting for the database to accept connections (first start can take a few minutes) ...'
for ($i = 0; $i -lt 90; $i++) {
    docker exec $name healthcheck.sh 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host 'Database is ready.' -ForegroundColor Green; return }
    Start-Sleep -Seconds 5
}
throw 'Database did not become ready in time. Check: docker logs ' + $name
