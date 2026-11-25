# =============================================================================
# concurrency_demo.ps1 - two database sessions fight for the LAST place in a visit slot
# Feature : F24 (transactions and concurrency control)
# Usage   : .\scripts\concurrency_demo.ps1 [-Quiet]
# Runs sql/20_concurrency_setup.sql, then sql/21_concurrency_session.sql in TWO parallel
# SQL*Plus processes, twice:
#   NAIVE mode  - check-then-insert without locks   => expect BOTH to succeed (rule broken)
#   SAFE  mode  - sp_schedule_visit with row locks  => expect exactly ONE to succeed
# Prints  CONCURRENCY|<id>|<purpose>|<expected>|<actual>|PASS/FAIL  lines for the test log.
# =============================================================================
param([switch]$Quiet)
. "$PSScriptRoot\common.ps1"
Initialize-Env
$owner = Get-Setting 'PRISON_OWNER_PASSWORD'
$name  = Get-Setting 'PRISON_CONTAINER' 'prison-oracle'
$service = Get-Setting 'PRISON_DB_SERVICE' 'FREEPDB1'

function Say($t) { if (-not $Quiet) { Write-Host $t } }

function Start-Session([string]$Mode, [string]$Label, [int]$Inmate, [int]$Visitor, [int]$Delay, [int]$Hold) {
    $cmd = "cd /prison/sql && sqlplus -L -S 'prison_owner/$owner@//localhost:1521/$service' @21_concurrency_session.sql $Mode $Label $Inmate $Visitor $Delay $Hold"
    # a background job = an independent PowerShell process-like worker, so both sessions really run in parallel
    Start-Job -ArgumentList $name, $cmd -ScriptBlock { param($c, $x) docker exec -i $c bash -c $x }
}

function Run-Scenario([string]$Mode) {
    Say "---- $Mode scenario: clerk A starts now, clerk B starts 2 s later; A holds for 6 s"
    Invoke-LocalSql -User prison_owner -Password $owner -Script '20_concurrency_setup.sql' -ScriptArgs 'SETUP' | ForEach-Object { Say "   $_" }
    $a = Start-Session $Mode 'ClerkA' 6 25 0 6
    $b = Start-Session $Mode 'ClerkB' 7 26 2 0
    $a, $b | Wait-Job | Out-Null
    foreach ($j in @($a, $b)) {
        Receive-Job $j | Where-Object { $_ -match '\S' } | ForEach-Object { Say "   $_" }
        Remove-Job $j
    }
    $check = Invoke-LocalSql -User prison_owner -Password $owner -Script '20_concurrency_setup.sql' -ScriptArgs 'CHECK'
    $check | Where-Object { $_ -match '\S' } | ForEach-Object { Say "   $_" }
    $count = [int]([regex]::Match(($check -join ' '), 'holds (\d+) visits').Groups[1].Value)
    Invoke-LocalSql -User prison_owner -Password $owner -Script '20_concurrency_setup.sql' -ScriptArgs 'CLEANUP' | Out-Null
    return $count
}

$naive = Run-Scenario 'NAIVE'
$safe  = Run-Scenario 'SAFE'

$r1 = if ($naive -eq 6) { 'PASS' } else { 'FAIL' }
$r2 = if ($safe  -eq 5) { 'PASS' } else { 'FAIL' }
"CONCURRENCY|X01|without locking two clerks overbook the last place (demonstrates the problem)|6 visits in a 5-place slot|$naive visits|$r1"
"CONCURRENCY|X02|sp_schedule_visit row locks keep the slot at its capacity|5 visits in a 5-place slot|$safe visits|$r2"
