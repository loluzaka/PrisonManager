param([switch]$Cloud)

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
    throw 'Set POSTGRES_DEMO_PASSWORD in the git-ignored .env file.'
}
if ($Cloud) {
    $connectionUrl = $settings['POSTGRES_URL']
    $adminUrl = $settings['POSTGRES_ADMIN_URL']
    if (-not $adminUrl -or $adminUrl -notmatch '^postgres(ql)?://') {
        throw 'Set POSTGRES_ADMIN_URL to your provider owner connection URL in .env.'
    }
    if (-not $connectionUrl -or $connectionUrl -notmatch '^postgres(ql)?://') {
        throw 'Set POSTGRES_URL to your provider endpoint URL in .env.'
    }
    $adminArgs = @('--dbname', $adminUrl)
} else {
    $adminArgs = @('-U', 'postgres', '-d', $database)
}

docker exec -i $name psql @adminArgs -v ON_ERROR_STOP=1 -f /prison/postgres/tests.sql
if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL tests failed; see the TEST rows above.' }

foreach ($role in 'prison_u_admin', 'prison_u_warden', 'prison_u_warden2', 'prison_u_frontdesk', 'prison_u_auditor') {
    if ($Cloud) {
        $roleArgs = @('--dbname', $connectionUrl, '--username', $role)
    } else {
        $roleArgs = @('--username', $role, '--dbname', $database)
    }
    docker exec -i -e "PGPASSWORD=$demoPassword" $name psql @roleArgs -v ON_ERROR_STOP=1 -f /prison/postgres/tests_roles.sql
    if ($LASTEXITCODE -ne 0) { throw "Role tests failed for $role." }
}
