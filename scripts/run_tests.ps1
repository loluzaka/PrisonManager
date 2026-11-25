# =============================================================================
# run_tests.ps1 - runs the complete automated test suite on the LOCAL container
# Feature : F34 (test suite)
# Usage   : .\scripts\run_tests.ps1
# Steps   : 1) re-seed the database so every run starts from the same data (04_seed_data.sql)
#           2) role tests as each of the 5 demo users (tests/31_test_roles.sql)
#           3) main suite as PRISON_OWNER (tests/30_test_suite.sql)
#           4) two-session concurrency test (scripts/concurrency_demo.ps1)
# Output  : printed, and saved to Documentation/Test_Results/latest_test_run.log
# =============================================================================
. "$PSScriptRoot\common.ps1"
Initialize-Env
$owner = Get-Setting 'PRISON_OWNER_PASSWORD'
$demo  = Get-Setting 'PRISON_DEMO_PASSWORD'
$name  = Get-Setting 'PRISON_CONTAINER' 'prison-oracle'
$out   = Join-Path $script:Root 'Documentation\Test_Results'
New-Item -ItemType Directory -Force $out | Out-Null
$log   = Join-Path $out 'latest_test_run.log'

function Run-Container([string]$User, [string]$Pass, [string]$FileInContainer) {
    $service = Get-Setting 'PRISON_DB_SERVICE' 'FREEPDB1'
    docker exec -i $name bash -c "cd /prison/tests && sqlplus -L -S `"$User/$Pass@//localhost:1521/$service`" @$FileInContainer"
}

$result = New-Object System.Collections.Generic.List[string]
$result.Add("Test run started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")

Write-Host '== Re-seeding ==' -ForegroundColor Cyan
Invoke-LocalSql -User prison_owner -Password $owner -Script '04_seed_data.sql' | Out-Null

Write-Host '== Role tests (F25 / F26 / F31) ==' -ForegroundColor Cyan
foreach ($u in 'PRISON_U_FRONTDESK','PRISON_U_AUDITOR','PRISON_U_WARDEN','PRISON_U_WARDEN2','PRISON_U_ADMIN') {
    $lines = Run-Container $u $demo '31_test_roles.sql'
    $lines | ForEach-Object { $result.Add($_) }
}

Write-Host '== Re-seeding again (role tests book a visit) ==' -ForegroundColor Cyan
Invoke-LocalSql -User prison_owner -Password $owner -Script '04_seed_data.sql' | Out-Null

Write-Host '== Main suite ==' -ForegroundColor Cyan
Run-Container 'prison_owner' $owner '30_test_suite.sql' | ForEach-Object { $result.Add($_) }

Write-Host '== Concurrency (F24) ==' -ForegroundColor Cyan
& "$PSScriptRoot\concurrency_demo.ps1" -Quiet | ForEach-Object { $result.Add($_) }

$tests   = $result | Where-Object { $_ -like 'TEST|*' -or $_ -like 'CONCURRENCY|*' }
$failed  = $tests  | Where-Object { $_ -like '*|FAIL' }
$result.Add(("SUMMARY|passed={0}|failed={1}|total={2}" -f ($tests.Count - $failed.Count), $failed.Count, $tests.Count))
$result | Set-Content -Path $log -Encoding utf8
$result | Where-Object { $_ -like 'TEST|*' -or $_ -like 'SUMMARY|*' -or $_ -like 'CONCURRENCY|*' } | ForEach-Object {
    if ($_ -like '*|FAIL') { Write-Host $_ -ForegroundColor Red } else { Write-Host $_ }
}
Write-Host ''
Write-Host ("Total checks: {0}   Failed: {1}   (log: {2})" -f $tests.Count, $failed.Count, $log) `
    -ForegroundColor $(if ($failed.Count -eq 0) { 'Green' } else { 'Red' })
if ($failed.Count -gt 0) { exit 1 }
