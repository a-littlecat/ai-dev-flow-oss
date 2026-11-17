[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Config,
    [int]$StaleMinutes = 60,
    [int]$IdleHours = 12,
    [int]$GoalHours = 24,
    [string]$State,
    [switch]$DryRun,
    [switch]$NoTrunkCheck
)
# 只拉起后台全量；旧的通知阈值和状态参数接受但忽略。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$here = $PSScriptRoot
if ($DryRun) {
    if ($NoTrunkCheck) { '不会拉起 trunk-check.ps1：-NoTrunkCheck' }
    else { '会拉起 trunk-check.ps1（DryRun 不启动进程）' }
    exit 0
}
# 合并后的全量：另起一个隐藏的低优先级进程跑 trunk-check.ps1，不等它；它自己管不叠跑。
if (-not $DryRun -and -not $NoTrunkCheck) {
    $tcArgs = @('-NoProfile', '-File', (Join-Path $here 'trunk-check.ps1'))
    if ($Config) { $tcArgs += '-Config', $Config }
    try { $null = Start-Process -FilePath (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source -ArgumentList (($tcArgs | ForEach-Object { '"' + $_ + '"' }) -join ' ') -WindowStyle Hidden -PassThru } catch { [Console]::Error.WriteLine("watch.ps1 could not start trunk-check: $($_.Exception.Message)") }
}
exit 0
