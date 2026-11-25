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
$port = if ($settings['POSTGRES_PORT']) { $settings['POSTGRES_PORT'] } else { '5432' }
$password = $settings['POSTGRES_LOCAL_PASSWORD']
if (-not $password -or $password -like 'change_me*') {
    throw 'Set a strong POSTGRES_LOCAL_PASSWORD in the git-ignored .env file.'
}

$existing = docker ps -a --filter "name=^$name$" --format '{{.Status}}'
if (-not $existing) {
    docker run -d --name $name -p "${port}:5432" `
        -e "POSTGRES_PASSWORD=$password" `
        -e "POSTGRES_DB=$database" `
        -v "${root}:/prison" `
        -v "${name}-data:/var/lib/postgresql/data" `
        postgres:17-alpine | Out-Null
} elseif ($existing -notmatch '^Up') {
    docker start $name | Out-Null
}

for ($i = 0; $i -lt 60; $i++) {
    docker exec $name pg_isready -U postgres -d $database 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "PostgreSQL is ready in container '$name' on port $port." -ForegroundColor Green
        return
    }
    Start-Sleep -Seconds 2
}
throw "PostgreSQL did not become ready. Check: docker logs $name"
