# =============================================================================
# install.ps1 - builds the whole schema on the LOCAL Oracle container
# Feature : F29 (deployment), F4 (repeatable setup)
# Usage   : .\scripts\install.ps1 [-Fresh] [-WithDemos]
#             -Fresh      drops every project object first (99_drop_all.sql) for a clean rebuild
#             -WithDemos  also runs the demo/report scripts (12-16, 19) and prints their output
# Steps   : 1) 00_admin_setup.sql as SYSTEM  2) run_all.sql as PRISON_OWNER  3) optional demos
# =============================================================================
param([switch]$Fresh, [switch]$WithDemos)
. "$PSScriptRoot\common.ps1"
Initialize-Env
$sys   = Get-Setting 'PRISON_SYS_PASSWORD'
$owner = Get-Setting 'PRISON_OWNER_PASSWORD'
$demo  = Get-Setting 'PRISON_DEMO_PASSWORD'

Write-Host '== 1/3 Creating schema owner and demo users (as SYSTEM) ==' -ForegroundColor Cyan
Invoke-LocalSql -User system -Password $sys -Script '00_admin_setup.sql' -ScriptArgs $owner, $demo

if ($Fresh) {
    Write-Host '== Dropping existing objects ==' -ForegroundColor Cyan
    Invoke-LocalSql -User prison_owner -Password $owner -Script '99_drop_all.sql'
}

Write-Host '== 2/3 Building schema, data, rules, procedures, views, roles, jobs ==' -ForegroundColor Cyan
Invoke-LocalSql -User prison_owner -Password $owner -Script 'run_all.sql'

if ($WithDemos) {
    Write-Host '== 3/3 Demo and report scripts ==' -ForegroundColor Cyan
    foreach ($s in '12_dml_demo.sql','13_queries_select_aggregate.sql','14_queries_joins.sql',
                   '15_queries_nested_window.sql','16_reports.sql','19_transactions_demo.sql') {
        Write-Host "---- $s" -ForegroundColor DarkCyan
        Invoke-LocalSql -User prison_owner -Password $owner -Script $s
    }
}
Write-Host 'Install finished.' -ForegroundColor Green
