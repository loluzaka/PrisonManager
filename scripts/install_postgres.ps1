param(
    [switch]$Cloud,
    [switch]$Fresh
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { throw 'Copy .env.example to .env and configure PostgreSQL first.' }

$settings = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$') { $settings[$Matches[1]] = $Matches[2] }
}
$name = if ($settings['POSTGRES_CONTAINER']) { $settings['POSTGRES_CONTAINER'] } else { 'prison-postgres' }
$database = if ($settings['POSTGRES_DB']) { $settings['POSTGRES_DB'] } else { 'prison_db' }
$demoPassword = $settings['POSTGRES_DEMO_PASSWORD']
if (-not $demoPassword -or $demoPassword -like 'change_me*') {
    throw 'Set a strong POSTGRES_DEMO_PASSWORD in the git-ignored .env file.'
}

docker inspect $name 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Start the PostgreSQL container first: .\scripts\start_postgres.ps1" }

if ($Cloud) {
    $connectionUrl = $settings['POSTGRES_ADMIN_URL']
    if (-not $connectionUrl -or $connectionUrl -notmatch '^postgres(ql)?://') {
        throw 'Set POSTGRES_ADMIN_URL to your provider owner connection URL in .env.'
    }
    $connectArgs = @('--dbname', $connectionUrl)
} else {
    $connectArgs = @('-U', 'postgres', '-d', $database)
}

if ($Fresh) {
    Write-Warning 'Fresh mode DROPS every object in the target public schema.'
    docker exec -i $name psql @connectArgs -v ON_ERROR_STOP=1 -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'
    if ($LASTEXITCODE -ne 0) { throw 'Could not recreate the public schema.' }
}

docker exec -i $name psql @connectArgs -v ON_ERROR_STOP=1 -v "demo_password=$demoPassword" -f /prison/postgres/install.sql
if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL installation failed; see the SQL error above.' }
Write-Host 'PostgreSQL schema, roles, and seed data installed.' -ForegroundColor Green
