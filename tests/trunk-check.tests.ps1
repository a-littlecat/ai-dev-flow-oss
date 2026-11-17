param([string]$Script = (Join-Path $PSScriptRoot '../skills/ai-dev-flow/scripts/trunk-check.ps1'), [switch]$Keep, [switch]$Q85Only)
# trunk-check.ps1 的检查：在系统临时目录建项目和清单，用真实 git/worktree ，
# 断言本地调度、锁、快检让路、本机环境。退出码 0 才算通过。
#   pwsh -NoProfile -File tests/trunk-check.tests.ps1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = Join-Path ([IO.Path]::GetTempPath()) ("trunk-check-fixture-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $root
$fail = 0
$notRun = [Collections.Generic.List[string]]::new()
function Check($name, $cond) { if ($cond) { "ok   $name" } else { "FAIL $name"; $script:fail++ } }
function G { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main @args; if ($LASTEXITCODE) { throw "git $args" } }

$PwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$inProcPwshDef = @'
# Run 在同一个进程的 runspace 里执行；忙进程夹具模拟另一个会话，而非这个宿主的子进程。
function Get-CimInstance {
    if ($env:Q85_FALLBACK_BUSY -and (Test-Path $env:Q85_FALLBACK_BUSY)) {
        [pscustomobject]@{ ProcessId=900001; ParentProcessId=0; CommandLine="pwsh $env:AI_DEV_FLOW_BUSY_MARK" }
        return
    }
    $items = @(CimCmdlets\Get-CimInstance @args)
    foreach ($item in $items) {
        if ($item.CimClass.CimClassName -eq 'Win32_Process' -and $env:AI_DEV_FLOW_BUSY_MARK -and "$($item.CommandLine)".Contains($env:AI_DEV_FLOW_BUSY_MARK)) {
            [pscustomobject]@{ ProcessId=$item.ProcessId; ParentProcessId=0; CommandLine=$item.CommandLine }
        } else { $item }
    }
}
function pwsh {
    $piped = @($input)
    if ($piped.Count) { $piped | & $script:PwshExeInner @args; return }
    $i = 0
    while ($i -lt $args.Count -and "$($args[$i])" -in '-NoProfile', '-NonInteractive') { $i++ }
    $mode = "$($args[$i])"
    if ($mode -notin '-File', '-Command') { & $script:PwshExeInner @args; return }
    $ps = [PowerShell]::Create()
    $tmpCmd = $null
    try {
        $null = $ps.AddScript($script:InProcBootstrap)
        $null = $ps.Invoke()
        $ps.Commands.Clear()
        $cwd = (Get-Location).ProviderPath
        if ($mode -eq '-File') {
            $file = $args[$i + 1]
            $rest = @($args | Select-Object -Skip ($i + 2))
            $params = (Get-Command -Name $file -CommandType ExternalScript).Parameters
            $named = @{}; $pos = [Collections.Generic.List[object]]::new()
            for ($k = 0; $k -lt $rest.Count; $k++) {
                $tok = $rest[$k]
                $m = if ($tok -is [string]) { [regex]::Match($tok, '^-([A-Za-z]\w*)(?::(.*))?$') }
                $hit = if ($m -and $m.Success) { @($params.Keys | Where-Object { $_ -like "$($m.Groups[1].Value)*" }) }
                if ($hit.Count -eq 1 -or ($hit -contains $m.Groups[1].Value)) {
                    $name = if ($hit -contains $m.Groups[1].Value) { $m.Groups[1].Value } else { $hit[0] }
                    if ($params[$name].SwitchParameter) { $named[$name] = if ($m.Groups[2].Success) { $m.Groups[2].Value -notin '$false', 'false', '0' } else { $true } }
                    elseif ($m.Groups[2].Success) { $named[$name] = $m.Groups[2].Value }
                    else { $k++; $named[$name] = $rest[$k] }
                } else { $pos.Add($tok) }
            }
            $posArr = $pos.ToArray()
            $null = $ps.AddScript("param(`$f,`$n,`$p,`$d,`$b,`$e) `$script:InProcBootstrap=`$b; `$script:PwshExeInner=`$e; Set-Location -LiteralPath `$d; `$global:LASTEXITCODE=0; & `$f @n @p; `$global:LASTEXITCODE").AddArgument($file).AddArgument($named).AddArgument($posArr).AddArgument($cwd).AddArgument($script:InProcBootstrap).AddArgument($script:PwshExeInner)
        } else {
            $cmdText = ($args | Select-Object -Skip ($i + 1)) -join ' '
            $tmpCmd = Join-Path ([IO.Path]::GetTempPath()) ("pwsh-cmd-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
            [IO.File]::WriteAllText($tmpCmd, $cmdText, [Text.UTF8Encoding]::new($false))
            $null = $ps.AddScript("param(`$f,`$d,`$b,`$e) `$script:InProcBootstrap=`$b; `$script:PwshExeInner=`$e; Set-Location -LiteralPath `$d; `$global:LASTEXITCODE=0; & `$f; `$global:LASTEXITCODE").AddArgument($tmpCmd).AddArgument($cwd).AddArgument($script:InProcBootstrap).AddArgument($script:PwshExeInner)
        }
        $prevDir = [Environment]::CurrentDirectory
        [Environment]::CurrentDirectory = $cwd
        try {
            $res = $ps.Invoke()
        } finally {
            [Environment]::CurrentDirectory = $prevDir
        }
        foreach ($warning85 in $ps.Streams.Warning) { "$warning85" }
        $code = 0
        if ($ps.HadErrors -and $ps.Streams.Error.Count) {
            foreach ($er in $ps.Streams.Error) { "$er" }
            $code = 1
        }
        $arr = @($res)
        if ($arr.Count -gt 0 -and $arr[-1] -is [int]) {
            $code = [int]$arr[-1]
            if ($arr.Count -gt 1) { $arr[0..($arr.Count - 2)] | ForEach-Object { "$_" } }
        } else {
            $arr | ForEach-Object { "$_" }
        }
        $global:LASTEXITCODE = $code
    } finally {
        if ($tmpCmd) { Remove-Item -LiteralPath $tmpCmd -Force -ErrorAction SilentlyContinue }
        $ps.Dispose()
    }
}
'@

function Run([string[]]$more) {
    if (-not $script:q85Mode) {
        $c85 = Get-Content $cfg -Raw | ConvertFrom-Json -AsHashtable
        $c85.trunkIdleMinutes = 0
        $c85 | ConvertTo-Json -Depth 12 | Set-Content $cfg -Encoding utf8NoBOM
        $env:AI_DEV_FLOW_TRUNK_NOW = (Get-Date).Date.AddHours(12).ToString('o')
    }
    $ps = [PowerShell]::Create()
    try {
        $null = $ps.AddScript("param(`$b,`$e) `$script:InProcBootstrap=`$b; `$script:PwshExeInner=`$e; . ([scriptblock]::Create(`$b))").AddArgument($inProcPwshDef).AddArgument($PwshExe)
        $null = $ps.Invoke()
        $ps.Commands.Clear()
        $allArgs = [Collections.Generic.List[string]]@('-NoProfile', '-File', $Script, '-Config', $cfg, '-Lock', $lock, '-NotifyDryRun')
        if ($more) { foreach ($m in $more) { if ($null -ne $m) { $allArgs.Add($m) } } }
        $null = $ps.AddScript("param(`$a) `$o = @(pwsh @a 2>&1 | ForEach-Object { `"`$_`" }); `$o; `$global:LASTEXITCODE").AddArgument($allArgs.ToArray())
        $res = @($ps.Invoke())
        $code = if ($res.Count -gt 0 -and $res[-1] -is [int]) { [int]$res[-1] } else { 0 }
        $lines = if ($res.Count -gt 1) { @($res[0..($res.Count - 2)] | ForEach-Object { "$_" }) } else { @() }
        if ($ps.Streams.Error.Count) {
            $lines += @($ps.Streams.Error | ForEach-Object { "$_" })
            if ($code -eq 0) { $code = 1 }
        }
        [pscustomobject]@{ Out = $lines; Text = ($lines -join "`n"); Code = $code }
    } finally { $ps.Dispose() }
}

# #79：从实际脚本 AST 载入函数，不执行调度入口；变异只写临时新目录。
$source79 = Get-Content -LiteralPath $Script -Raw
$tokens79 = $null; $errors79 = $null
$ast79 = [Management.Automation.Language.Parser]::ParseInput($source79, [ref]$tokens79, [ref]$errors79)
Check 'Q79 script parses' (-not $errors79.Count)
foreach ($name79 in @('Normalize-TrunkCommand', 'Get-TrunkCpuBusy', 'Find-TrunkProcesses', 'Get-TrunkEntries', 'Get-DocumentGreen', 'Invoke-LocalVerify', 'Test-TimeoutOnly')) {
    $node79 = $ast79.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name79 }, $true)
    . ([scriptblock]::Create($node79.Extent.Text))
}
$proof79 = Join-Path $root 'q79-mutations'
$null = New-Item -ItemType Directory -Path $proof79
$oldMark79 = $env:AI_DEV_FLOW_BUSY_MARK
$env:AI_DEV_FLOW_BUSY_MARK = ''
function Q79-Prove([string]$Name, [scriptblock]$Assertion, [string]$Target, [string]$BadBody) {
    Check $Name (& $Assertion)
    $mutant = Join-Path $proof79 (([guid]::NewGuid().ToString('N')) + '.ps1')
    Set-Content -LiteralPath $mutant -Encoding utf8NoBOM -Value "function $Target { $BadBody }"
    . $mutant
    Check "$Name mutation caught" (-not (& $Assertion))
}
$cases79 = @(
    @{ Name='R3 assertion containing timeout text'; Code=1; Lines=@('FAILED test_a.py::test_msg - AssertionError: expected - subprocess.TimeoutExpired: cmd','=== 1 failed in 0.2s ==='); Where='本机'; Want=$false },
    @{ Name='R3 later collection error'; Code=1; Lines=@('FAILED a.py::x - subprocess.TimeoutExpired: cmd','=== 1 failed in 0.2s ===','ERROR collecting test_b.py','=== 1 error in 0.2s ==='); Where='本机'; Want=$false },
    @{ Name='R3 passed batch then timeout batch'; Code=1; Lines=@('=== 5 passed in 0.2s ===','FAILED a.py::x - subprocess.TimeoutExpired: cmd','=== 1 failed in 0.2s ==='); Where='本机'; Want=$true },
    @{ Name='R3 dotnet failure before budget'; Code=124; Lines=@('  Failed Name [50 ms]','__TRUNK_LOCAL_BUDGET_TIMEOUT__=1'); Where='主干后台 本机（预算超时）'; Want=$false },
    @{ Name='R3 qualified chained exception'; Code=1; Lines=@('ERROR: test_x (test.X)','----------------------------------------------------------------------','json.decoder.JSONDecodeError: bad','subprocess.TimeoutExpired: cmd','----------------------------------------------------------------------','Ran 1 test in 1.0s','FAILED (errors=1)'); Where='本机'; Want=$false },
    @{ Name='local own budget'; Code=124; Lines=@('__TRUNK_LOCAL_BUDGET_TIMEOUT__=1'); Where='主干后台 本机（预算超时）'; Want=$true },
    @{ Name='local budget with real failure'; Code=124; Lines=@('FAIL: step','__TRUNK_LOCAL_BUDGET_TIMEOUT__=1'); Where='主干后台 本机（预算超时）'; Want=$false },
    @{ Name='unittest timeout'; Code=1; Lines=@('ERROR: test_x (test.X)','----------------------------------------------------------------------','Traceback (most recent call last):','subprocess.TimeoutExpired: command','----------------------------------------------------------------------','Ran 1 test in 1.0s','FAILED (errors=1)'); Where='本机'; Want=$true },
    @{ Name='unittest mixed failure'; Code=1; Lines=@('ERROR: test_x (test.X)','----------------------------------------------------------------------','subprocess.TimeoutExpired: command','FAILED (failures=1, errors=1)'); Where='本机'; Want=$false },

    @{ Name='timeout only'; Code=1; Lines=@('FAILED test.py::x - subprocess.TimeoutExpired: command', '=== 1 failed in 2.0s ==='); Where='本机'; Want=$true },
    @{ Name='mixed true failure'; Code=1; Lines=@('FAILED test.py::x - subprocess.TimeoutExpired: command','FAILED test.py::y - AssertionError: bad', '=== 2 failed in 2.0s ==='); Where='本机'; Want=$false },
    @{ Name='timeout keyword not evidence'; Code=1; Lines=@('TimeoutExpired','FAIL bad'); Where='本机'; Want=$false },
    @{ Name='wrong exit'; Code=2; Lines=@('FAILED test.py::x - subprocess.TimeoutExpired: command','=== 1 failed in 2.0s ==='); Where='本机'; Want=$false }
)
foreach ($c79 in $cases79) {
    $got79 = Test-TimeoutOnly $c79.Code $c79.Lines $c79.Where
    Check "Q79 $($c79.Name)" ($got79 -eq $c79.Want)
    # 独立新文件中的反转变异必须使同一个断言失败。
    $mut79 = Join-Path $proof79 (([guid]::NewGuid().ToString('N')) + '.ps1')
    Set-Content -LiteralPath $mut79 -Encoding utf8NoBOM -Value ('function Test-TimeoutOnly([int]$Code,$Lines,[string]$Where) { ' + $(if ($c79.Want) { '$false' } else { '$true' }) + ' }')
    . $mut79
    Check "Q79 mutation caught: $($c79.Name)" ((Test-TimeoutOnly $c79.Code $c79.Lines $c79.Where) -ne $c79.Want)
    $restore79 = $ast79.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-TimeoutOnly' }, $true)
    . ([scriptblock]::Create($restore79.Extent.Text))
}
$ps79 = @(
    [pscustomobject]@{ ProcessId=10; ParentProcessId=0; CommandLine='pwsh -NoProfile -File scripts/verify.ps1' },
    [pscustomobject]@{ ProcessId=11; ParentProcessId=10; CommandLine='pwsh -NoProfile -File scripts/verify.ps1' },
    [pscustomobject]@{ ProcessId=12; ParentProcessId=0; CommandLine='pwsh -NoProfile -File ".\scripts\verify.ps1"' }
)
$hits79 = @(Find-TrunkProcesses $ps79 @('pwsh -NoProfile -File scripts/verify.ps1') 10)
Q79-Prove 'Q79 direct candidate verifier matches; self and descendants excluded' { $h = @(Find-TrunkProcesses $ps79 @('pwsh -NoProfile -File scripts/verify.ps1') 10); $h.Count -eq 1 -and $h[0] -match '进程 12：' } 'Find-TrunkProcesses' '$null'
Q79-Prove 'Q79 CPU uses average not instantaneous spike' { -not (Get-TrunkCpuBusy @(0,0,100) 75) } 'Get-TrunkCpuBusy' "'busy'"
Q79-Prove 'Q79 CPU threshold configurable' { [bool](Get-TrunkCpuBusy @(80,80,80) 75) -and -not (Get-TrunkCpuBusy @(80,80,80) 90) } 'Get-TrunkCpuBusy' "`$null"
$env:AI_DEV_FLOW_BUSY_MARK = $oldMark79

$lock = Join-Path $root 'trunk-check.lock'
$env:AI_DEV_FLOW_BUSY_MARK = 'trunk-check-test-busy-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
try {
    $proj = Join-Path $root 'proj'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $proj 'docs')
    G init -q $proj
    Set-Content -LiteralPath (Join-Path $proj '.gitignore') -Encoding utf8NoBOM -Value '.agents/'
    Set-Content -LiteralPath (Join-Path $proj 'docs/queue.md') -Encoding utf8NoBOM -Value "| # | 目标 | 依赖 | 状态 |`n|---|---|---|---|`n| 1 | x | 无 | 待做 |"
    G -C $proj add -A; G -C $proj commit -q -m one
    $count = Join-Path $root 'runs.txt'
    $runs = { if (Test-Path -LiteralPath $count) { @(Get-Content -LiteralPath $count).Count } else { 0 } }
    $verify = "Add-Content -LiteralPath '$count' -Value (Get-Location).Path; if (Test-Path fail.txt) { exit 1 } else { exit 0 }"
    $cfg = Join-Path $root 'projects.json'
    $writeCfg = { param($v, $s) @{ projects = @(@{ name = '项目'; path = $proj; status = '推进中'; trunkVerify = $v; trunkSetup = $s; trunkRemote = @{ host = 'ignored.invalid'; verify = 'exit 99' } }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfg -Encoding utf8NoBOM }

    # Q85：真实调度多轮、时间注入，独立计数后清掉夹具账本回到旧用例。
    $script:q85Mode = $true
    & $writeCfg $verify
    $env:AI_DEV_FLOW_TRUNK_NOW = '2026-11-17T12:00:00'
    $null = New-Item -ItemType Directory -Force (Join-Path $proj '.agents')
    @{ $proj = '2026-11-17T11:00:00' } | ConvertTo-Json | Set-Content (Join-Path $root 'trunk-check-local.json')
    $r = Run
    Check 'Q85 first observation starts idle clock' ($r.Code -eq 0 -and (& $runs) -eq 0 -and $r.Text -match '0/30')
    foreach ($n85 in 1..2) { Set-Content (Join-Path $proj 'latest.txt') $n85; G -C $proj add -A; G -C $proj commit -q -m latest }
    $env:AI_DEV_FLOW_TRUNK_NOW = '2026-11-17T12:12:00'
    $r = Run
    Check 'Q85 latest tree still waits at 12 minutes' ((& $runs) -eq 0 -and $r.Text -match '12/30')
    $r = Run
    $pending85 = @(Get-Content (Join-Path $proj '.agents/trunk-check.log') | Where-Object { $_ -like '待跑：*' })
    Check 'Q85 same tree and reason logs once' ($pending85.Count -eq 2)
    $state85 = Get-Content (Join-Path $root 'trunk-check-idle.json') -Raw
    $env:AI_DEV_FLOW_TRUNK_NOW = '2026-11-17T12:31:00'
    $r = Run @('-DryRun')
    Check 'Q85 DryRun explains and does not write state' ($r.Text -match '会跑' -and (Get-Content (Join-Path $root 'trunk-check-idle.json') -Raw) -eq $state85 -and (& $runs) -eq 0)
    $r = Run
    $entry85 = Get-Content (Join-Path $proj '.agents/verify-ledger.jsonl') | ConvertFrom-Json
    Check 'Q85 runs only latest tree after idle threshold' ($r.Code -eq 0 -and (& $runs) -eq 1 -and @($entry85).Count -eq 1 -and $entry85.tree -eq (git -C $proj rev-parse 'HEAD^{tree}'))
    Set-Content (Join-Path $proj 'latest.txt') 3; G -C $proj add -A; G -C $proj commit -q -m latest
    $env:AI_DEV_FLOW_TRUNK_NOW = '2026-11-17T12:32:00'
    Set-Content (Join-Path $root 'trunk-check-idle.json') 'broken'
    $r = Run @('-Rerun','项目')
    Check 'Q85 manual rerun bypasses idle' ($r.Code -eq 0 -and (& $runs) -eq 2)
    $env85 = Join-Path $root 'env85.json'
    $verify85 = "@{ priority=(Get-Process -Id `$PID).PriorityClass.ToString(); trunk=`$env:AI_DEV_FLOW_TRUNK; parallel=`$env:AI_DEV_FLOW_TRUNK_PARALLEL; busy=`$env:AI_DEV_FLOW_MACHINE_BUSY } | ConvertTo-Json | Set-Content '$env85'"
    & $writeCfg $verify85
    $busy85 = Start-Process -FilePath $PwshExe -ArgumentList "-NoProfile -Command `"Start-Sleep 3600 # $env:AI_DEV_FLOW_BUSY_MARK`"" -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 500
        $r = Run
        Check 'Q85 busy blocks daytime' ($r.Text -match '本机忙' -and -not (Test-Path $env85))
        $env:AI_DEV_FLOW_TRUNK_NOW = '2026-11-18T03:00:00'
        $r = Run
        $e85 = Get-Content $env85 -Raw | ConvertFrom-Json
        Check 'Q85 night runs while busy with priority and environment' ($r.Code -eq 0 -and $e85.priority -eq 'BelowNormal' -and $e85.trunk -eq '1' -and [int]$e85.parallel -ge 1 -and $e85.busy -eq '1')
    } finally { Stop-Process -Id $busy85.Id -Force }
    & $writeCfg ($verify85 + '; echo aged')
    $env:AI_DEV_FLOW_TRUNK_NOW = '2026-11-20T12:00:00'
    $r = Run
    Check 'Q85 aged pending runs in one idle observation' ($r.Code -eq 0 -and $r.Text -match '：green')
    & $writeCfg ($verify85 + '; echo invalid')
    $c85 = Get-Content $cfg -Raw | ConvertFrom-Json -AsHashtable
    $c85.trunkIdleMinutes = -1; $c85.trunkNightWindow = 'bad'; $c85.trunkParallel = 0; $c85.trunkMaxAgeHours = 'bad'
    $c85 | ConvertTo-Json -Depth 5 | Set-Content $cfg
    $r = Run @('-DryRun')
    Check 'Q85 invalid configuration warns and continues' ($r.Code -eq 0 -and $r.Text -match 'trunkIdleMinutes' -and $r.Text -match 'trunkNightWindow' -and $r.Text -match 'trunkParallel' -and $r.Text -match 'trunkMaxAgeHours')
    # R85：采样中断、setup 不受全量预算限制。
    & $writeCfg ($verify85 + '; echo gap')
    $env:AI_DEV_FLOW_TRUNK_NOW = '2026-11-20T16:00:00'
    @{ $proj='2026-11-20T11:00:00' } | ConvertTo-Json | Set-Content (Join-Path $root 'trunk-check-local.json')
    @{ observed='2026-11-20T12:00:00'; idleSince='2026-11-20T12:00:00'; busy=$false } | ConvertTo-Json | Set-Content (Join-Path $root 'trunk-check-idle.json')
    $r = Run @('-DryRun')
    Check 'R85-1 sampling gap restarts idle observation' ($r.Code -eq 0 -and $r.Text -match '0/30' -and $r.Text -notmatch '会跑')
    & $writeCfg 'Write-Output setup-budget-verification' 'Start-Sleep -Seconds 6; Write-Output setup-done'
    $c85=Get-Content $cfg -Raw | ConvertFrom-Json -AsHashtable
    $c85.projects[0].trunkTimeoutSeconds=5; $c85.trunkIdleMinutes=0
    $c85 | ConvertTo-Json -Depth 8 | Set-Content $cfg
    # setup 预算用真实外部入口，避免进程内 pwsh 替身影响退出码和计时。
    $setupResult85 = @(& $PwshExe -NoProfile -File $Script -Config $cfg -Lock $lock -NotifyDryRun 2>&1)
    $setupExit85 = $LASTEXITCODE
    $setupEntry85 = Get-Content (Join-Path $proj '.agents/verify-ledger.jsonl') -Tail 1 | ConvertFrom-Json
    Check 'R85-3 setup may exceed verification-only budget' ($setupExit85 -eq 0 -and $setupEntry85.command -eq 'Write-Output setup-budget-verification' -and $setupEntry85.result -eq 'green' -and (Get-Content (Join-Path $proj '.agents/trunk-check.log') -Raw) -match '(?m)^setup-done\r?$')
    if ($Q85Only) { if ($fail) { exit 1 }; exit 0 }
    Remove-Item (Join-Path $proj '.agents') -Recurse -Force
    Remove-Item $count -Force
    $script:q85Mode = $false

    & $writeCfg $null
    $r = Run
    Check 'no trunkVerify: nothing to run' ($r.Code -eq 0 -and $r.Text -match '没有要跑的' -and (& $runs) -eq 0)

    & $writeCfg $verify
    $r = Run
    $ledger = Join-Path $proj '.agents/verify-ledger.jsonl'
    Check 'trunk not in the ledger: runs once in a clean worktree, records green, removes the worktree' ($r.Code -eq 0 -and (& $runs) -eq 1 -and $r.Text -match '：green' -and (Get-Content -LiteralPath $count -Raw) -match 'trunk-check' -and -not (Test-Path -LiteralPath (Join-Path $proj '.agents/trunk-check')) -and (Test-Path -LiteralPath $ledger))
    $last = Join-Path $proj '.agents/verify-last.json'
    $vl = try { Get-Content -LiteralPath $last -Raw | ConvertFrom-Json } catch { $null }
    Check 'green: the time goes into .agents/verify-last.json for the status page' ($vl -and $vl.source -eq 'trunk-check' -and $vl.head -eq (git -C $proj rev-parse HEAD) -and $null -ne $vl.seconds -and $vl.date -eq (Get-Date).ToString('yyyy-MM-dd'))
    $r = Run
    Check 'trunk unchanged: not run again' ($r.Text -match '没有要跑的' -and (& $runs) -eq 1)

    # 文档沿用的树比较使用独立仓库，避免改变旧测试的运行次数。
    $doc79 = Join-Path $root 'docs79'
    G init -q $doc79
    Set-Content (Join-Path $doc79 '.gitignore') '.agents/'
    Set-Content (Join-Path $doc79 'a.ps1') 'echo ok'
    Set-Content (Join-Path $doc79 'a.md') 'one'
    G -C $doc79 add -A; G -C $doc79 commit -q -m base
    $base79 = git -C $doc79 rev-parse HEAD
    $tree79 = git -C $doc79 rev-parse 'HEAD^{tree}'
    Q79-Prove 'Q79 first run has no green' { -not (Get-DocumentGreen $doc79 $tree79 'verify') } 'Get-DocumentGreen' "[pscustomobject]@{tree='bad';commit='bad'}"
    $null = New-Item -ItemType Directory (Join-Path $doc79 '.agents')
    $ledger79 = Join-Path $doc79 '.agents/verify-ledger.jsonl'
    @{tree=$tree79;commit=$base79;command='verify';result='red'} | ConvertTo-Json -Compress | Set-Content $ledger79
    Q79-Prove 'Q79 red-only ledger runs' { -not (Get-DocumentGreen $doc79 $tree79 'verify') } 'Get-DocumentGreen' "[pscustomobject]@{tree='bad';commit='bad'}"
    @{tree=$tree79;commit=$base79;command='verify';result='green'} | ConvertTo-Json -Compress | Add-Content $ledger79
    $ledgerSave79 = Get-Content $ledger79 -Raw
    @{tree=('f' * 40);commit=$base79;command='verify';result='green'} | ConvertTo-Json -Compress | Add-Content $ledger79
    Q79-Prove 'Q79 missing previous green tree runs full' { -not (Get-DocumentGreen $doc79 $tree79 'verify') } 'Get-DocumentGreen' "[pscustomobject]@{tree='bad';commit='bad'}"
    Set-Content $ledger79 $ledgerSave79
    Set-Content (Join-Path $doc79 'a.md') 'two'
    G -C $doc79 add -A; G -C $doc79 commit -q -m doc
    $newTree79 = git -C $doc79 rev-parse 'HEAD^{tree}'
    Q79-Prove 'Q79 markdown inherits source tree and commit' { (Get-DocumentGreen $doc79 $newTree79 'verify').commit -eq $base79 } 'Get-DocumentGreen' "`$null"
    $savedR2 = Get-Content $ledger79 -Raw
    @{tree=$tree79;commit=$base79;command='verify';result='red'} | ConvertTo-Json -Compress | Add-Content $ledger79
    Check 'R2 same tree latest red cannot inherit' (-not (Get-DocumentGreen $doc79 $newTree79 'verify'))
    Set-Content $ledger79 $savedR2
    @{tree=$newTree79;command='verify';result='red'} | ConvertTo-Json -Compress | Add-Content $ledger79
    Check 'R2 document red barrier cannot inherit' (-not (Get-DocumentGreen $doc79 $newTree79 'verify'))
    Set-Content $ledger79 $savedR2
    Q79-Prove 'Q79 command change does not inherit' { -not (Get-DocumentGreen $doc79 $newTree79 'verify changed') } 'Get-DocumentGreen' "[pscustomobject]@{tree='bad';commit='bad'}"
    G -C $doc79 commit -q --amend -m amended
    Q79-Prove 'Q79 amend compares trees' { (Get-DocumentGreen $doc79 $newTree79 'verify').tree -eq $tree79 } 'Get-DocumentGreen' "`$null"
    Move-Item (Join-Path $doc79 'a.md') (Join-Path $doc79 'a.txt')
    G -C $doc79 add -A; G -C $doc79 commit -q -m rename
    $badTree79 = git -C $doc79 rev-parse 'HEAD^{tree}'
    Q79-Prove 'Q79 md to txt requires full run' { -not (Get-DocumentGreen $doc79 $badTree79 'verify') } 'Get-DocumentGreen' "[pscustomobject]@{tree='bad';commit='bad'}"
    @{tree=$badTree79;command='verify';result='red'} | ConvertTo-Json -Compress | Add-Content $ledger79
    Set-Content (Join-Path $doc79 'b.markdown') 'doc after red'
    G -C $doc79 add -A; G -C $doc79 commit -q -m afterRed
    $badTree79 = git -C $doc79 rev-parse 'HEAD^{tree}'
    Q79-Prove 'Q79 intervening red does not hide code difference' { -not (Get-DocumentGreen $doc79 $badTree79 'verify') } 'Get-DocumentGreen' "[pscustomobject]@{tree='bad';commit='bad'}"
    Remove-Item (Join-Path $doc79 'a.ps1')
    G -C $doc79 add -A; G -C $doc79 commit -q -m deleteScript
    $badTree79 = git -C $doc79 rev-parse 'HEAD^{tree}'
    Q79-Prove 'Q79 deleted script requires full run' { -not (Get-DocumentGreen $doc79 $badTree79 'verify') } 'Get-DocumentGreen' "[pscustomobject]@{tree='bad';commit='bad'}"
    Q79-Prove 'Q79 local process budget kills child and emits own marker' { $lines = [Collections.Generic.List[string]]::new(); $code = Invoke-LocalVerify 'Start-Sleep 30' 1 $lines; $code -eq 124 -and $lines.Contains('__TRUNK_LOCAL_BUDGET_TIMEOUT__=1') } 'Invoke-LocalVerify' '0'
    # #91：原生子进程直接写 UTF-8 字节，不依赖 Python。
    $q91Function = $ast79.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-LocalVerify' }, $true)
    . ([scriptblock]::Create($q91Function.Extent.Text))
    $q91Native = '[Console]::OpenStandardOutput().Write([Text.Encoding]::UTF8.GetBytes("实验/源码.cs")); [Console]::OpenStandardError().Write([Text.Encoding]::UTF8.GetBytes("错误：实验"))'
    $q91Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($q91Native))
    $q91Command = @'
foreach ($e in @([Console]::OutputEncoding, [Console]::InputEncoding, $OutputEncoding)) {
    if ($e.CodePage -ne 65001 -or $e.GetPreamble().Length) { exit 31 }
}
if ($env:PYTHONUTF8 -ne '1' -or $env:PYTHONIOENCODING -ne 'utf-8') { exit 32 }
$text = pwsh -NoProfile -EncodedCommand ENCODED 2>&1 | Out-String
Write-Output $text
if ($text -notlike '*实验/源码.cs*' -or $text -notlike '*错误：实验*') { exit 33 }
exit 7
'@
    $q91Command = $q91Command.Replace('ENCODED', $q91Encoded)
    $q91SavedCfg = Get-Content $cfg -Raw
    $q91Env = @{}
    foreach ($key in @('PYTHONUTF8', 'PYTHONIOENCODING')) {
        $q91Env[$key] = [Environment]::GetEnvironmentVariable($key)
        Remove-Item "Env:$key" -ErrorAction SilentlyContinue
    }
    try {
        @{projects=@(@{name='编码项目';path=$doc79;trunk='main';trunkVerify=$q91Command})} | ConvertTo-Json -Depth 4 | Set-Content $cfg
        $q91Result = Run
        $q91Log = Get-Content (Join-Path $doc79 '.agents/trunk-check.log') -Raw -Encoding utf8
        $q91Lines = [Collections.Generic.List[string]]::new()
        $q91Code = Invoke-LocalVerify $q91Command 30 $q91Lines
        Check 'Q91 no-console UTF8 native output, environment, log and exit code' ($q91Code -eq 7 -and $q91Result.Text -match '：red' -and $q91Log.Contains('实验/源码.cs') -and $q91Log.Contains('错误：实验'))
        $env:PYTHONUTF8 = '0'; $env:PYTHONIOENCODING = 'ascii'
        $q91Lines.Clear()
        $q91Code = Invoke-LocalVerify 'if ($env:PYTHONUTF8 -ne "0" -or $env:PYTHONIOENCODING -ne "ascii") { exit 34 }; [Console]::OutputEncoding = [Text.Encoding]::ASCII; if ([Console]::OutputEncoding.CodePage -ne 20127) { exit 35 }; "quoted;value"; cmd /c exit 0 && "chain"' 30 $q91Lines
        Check 'Q91 preserves environment, encoding override and command syntax' ($q91Code -eq 0 -and $q91Lines.Contains('quoted;value') -and $q91Lines.Contains('chain'))
    } finally {
        Set-Content $cfg $q91SavedCfg -Encoding utf8NoBOM
        foreach ($key in $q91Env.Keys) { [Environment]::SetEnvironmentVariable($key, $q91Env[$key]) }
    }
    $cfgSave79 = Get-Content $cfg -Raw
    $timeoutCmd79 = "Write-Output 'FAILED test.py::x - subprocess.TimeoutExpired: command'; Write-Output '=== 1 failed in 2.0s ==='; exit 1"
    @{projects=@(@{name='超时项目';path=$doc79;trunk='main';trunkVerify=$timeoutCmd79})} | ConvertTo-Json -Depth 4 | Set-Content $cfg
    $r79a = Run; $r79b = Run; $r79c = Run
    Check 'Q79 timeout retries same tree twice without red; third records red and notifies' ($r79a.Text -match '仅超时（1/3）' -and $r79b.Text -match '仅超时（2/3）' -and $r79a.Text -notmatch '主干全量红了' -and $r79b.Text -notmatch '主干全量红了' -and $r79c.Text -match '：red' -and $r79c.Text -match '主干全量红了')
    Set-Content $cfg $cfgSave79 -Encoding utf8NoBOM

    $docCfgSave = Get-Content $cfg -Raw
    $docCmd = 'exit 1'
    $docHead = git -C $doc79 rev-parse HEAD
    $docTree = git -C $doc79 rev-parse 'HEAD^{tree}'
    @{tree=$docTree;commit=$docHead;command=$docCmd;result='green';seconds=900} | ConvertTo-Json -Compress | Add-Content $ledger79
    $docLast = Join-Path $doc79 '.agents/verify-last.json'
    Set-Content $docLast '{"seconds":900,"source":"real-run"}'
    $docLastSaved = Get-Content $docLast -Raw
    Set-Content (Join-Path $doc79 'c.md') 'doc'
    G -C $doc79 add -A; G -C $doc79 commit -q -m inherit
    @{projects=@(@{name='文档项目';path=$doc79;trunk='main';trunkVerify=$docCmd})} | ConvertTo-Json -Depth 4 | Set-Content $cfg
    $rDoc = Run
    $entryDoc = Get-Content $ledger79 | Select-Object -Last 1 | ConvertFrom-Json
    Check 'R1 inheritance keeps measured 900 seconds and marks source' ($rDoc.Text -match '：green' -and (Get-Content $docLast -Raw) -ceq $docLastSaved -and $entryDoc.seconds -eq 900 -and $entryDoc.where -match '沿用')
    $headDoc = git -C $doc79 rev-parse HEAD
    $null = pwsh -NoProfile -File (Join-Path (Split-Path $Script) 'verify-ledger.ps1') -Repo $doc79 -Record -Rev $headDoc -Result red -For $docCmd -Where test
    Set-Content (Join-Path $doc79 '.agents/trunk-red.json') '{}'
    $rDoc = Run @('-Rerun','文档项目')
    Check 'R2 rerun executes failing command and keeps red marker' ($rDoc.Text -match '：red' -and (Test-Path (Join-Path $doc79 '.agents/trunk-red.json')))
    Set-Content $cfg $docCfgSave

    Set-Content -LiteralPath (Join-Path $proj 'fail.txt') -Encoding utf8NoBOM -Value 'x'
    G -C $proj add -A; G -C $proj commit -q -m 'break it'
    $r = Run
    Check 'trunk changed and red: recorded red, notifies once' ($r.Code -eq 0 -and (& $runs) -eq 2 -and $r.Text -match '：red' -and $r.Text -match 'title: .*项目 主干全量红了' -and $r.Text -match 'bark: yes')
    $r = Run
    Check 'red tree: not rerun, no second notice' ((& $runs) -eq 2 -and $r.Text -notmatch '主干全量红了')
    Check 'red: verify-last.json keeps the last green' ((Get-Content -LiteralPath $last -Raw | ConvertFrom-Json).head -eq $vl.head)
    $redMark = Join-Path $proj '.agents/trunk-red.json'
    $rm = try { Get-Content -LiteralPath $redMark -Raw | ConvertFrom-Json } catch { $null }
    Check 'red: .agents/trunk-red.json tells the project session the head and how to rerun' ($rm -and $rm.head -eq (git -C $proj rev-parse HEAD) -and $rm.project -eq '项目' -and $rm.config -and (Test-Path -LiteralPath $rm.config))

    $st = pwsh -NoProfile -File (Join-Path (Split-Path $Script) 'status.ps1') -Config $cfg -All -Json | ConvertFrom-Json
    Check 'status: trunk red is flagged for /next' ($st.Projects[0].TrunkRed -and [bool](@($st.Projects[0].Problems) -match '^主干全量红了'))

    Remove-Item -LiteralPath (Join-Path $proj 'fail.txt')
    Set-Content -LiteralPath (Join-Path $proj 'b.txt') -Encoding utf8NoBOM -Value 'new'
    G -C $proj add -A; G -C $proj commit -q -m 'fix it'
    Set-Content -LiteralPath $lock -Value "$PID|$((Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks)" -NoNewline
    $r = Run
    Check 'lock held by a live process: skipped' ($r.Text -match '跳过：另一轮' -and (& $runs) -eq 2)
    Set-Content -LiteralPath $lock -Value 999999 -NoNewline
    $busy = Start-Process -FilePath $PwshExe -ArgumentList "-NoProfile -Command ""Start-Sleep 3600 # $env:AI_DEV_FLOW_BUSY_MARK""" -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 1500
        $busyCfgSave = Get-Content $cfg -Raw
        & $writeCfg $null
        $rEmpty = Run
        Check 'R4 no pending work stays nothing while busy' ($rEmpty.Text -match '没有要跑的' -and $rEmpty.Text -notmatch '本机忙')
        Set-Content $cfg $busyCfgSave
        $r = Run
        Check 'a session is running a check through the ledger: waits for the next round' ($r.Text -match '跳过：本机忙：进程 \d+：' -and (& $runs) -eq 2)
    } finally { Stop-Process -Id $busy.Id -Force -ErrorAction SilentlyContinue }
    $r = Run
    Check 'stale lock and nobody busy: runs, green again, the red record is gone' ((& $runs) -eq 3 -and $r.Text -match '：green' -and -not (Test-Path -LiteralPath $lock) -and -not (Test-Path -LiteralPath $redMark))
    $null = pwsh -NoProfile -File (Join-Path (Split-Path $Script) 'verify-ledger.ps1') -Repo $proj -Record -Rev HEAD -Result red -For 'one test' -Where 会话
    $st = pwsh -NoProfile -File (Join-Path (Split-Path $Script) 'status.ps1') -Config $cfg -All -Json | ConvertFrom-Json
    Check 'status: another command red on the trunk tree is not trunk red' (-not $st.Projects[0].TrunkRed -and -not (@($st.Projects[0].Problems) -match '^主干全量红了'))
    $commit = { param($name) Set-Content -LiteralPath (Join-Path $proj $name) -Encoding utf8NoBOM -Value $name; G -C $proj add -A; G -C $proj commit -q -m $name }

    & $commit 'c.txt'
    Set-Content -LiteralPath $lock -Value "$PID|123" -NoNewline
    $r = Run
    Check 'lock PID reused by another process (start time differs): stale, runs' ((& $runs) -eq 4 -and $r.Text -match '：green' -and -not (Test-Path -LiteralPath $lock))

    & $commit 'd.txt'
    $setupStart = Join-Path $root 'setup-start.txt'
    $verifyEnd = Join-Path $root 'verify-end.txt'
    $timedVerify = "try { $verify } finally { [IO.File]::WriteAllText('$verifyEnd', [string][datetime]::UtcNow.Ticks) }"
    & $writeCfg $timedVerify "[IO.File]::WriteAllText('$setupStart', [string][datetime]::UtcNow.Ticks); Start-Sleep -Seconds 6; Set-Content copied.dat x"
    $r = Run
    $r2 = Run
    Check 'trunkSetup copies a file into the worktree: still recorded, not rerun' ((& $runs) -eq 5 -and $r.Text -match '：green' -and $r2.Text -match '没有要跑的' -and $r2.Text -match '账上是 green')
    $timing = Get-Content -LiteralPath $last -Raw | ConvertFrom-Json
    $entry = Get-Content -LiteralPath $ledger -Tail 1 | ConvertFrom-Json
    $elapsed = ([long](Get-Content -LiteralPath $verifyEnd -Raw) - [long](Get-Content -LiteralPath $setupStart -Raw)) / [timespan]::TicksPerSecond
    Check 'trunkSetup: ledger and verify-last seconds exclude setup sleep' ($timing.seconds -lt ($elapsed - 3) -and $entry.seconds -ge 0 -and $entry.seconds -eq $timing.seconds)
    & $writeCfg $verify

    Set-Content -LiteralPath (Join-Path $proj 'fail.txt') -Encoding utf8NoBOM -Value 'x'
    & $commit 'e.txt'
    $null = Run
    $r = Run @('-Rerun', '项目')
    $r2 = Run
    Check '-Rerun: a red tree runs once more, then waits again' ((& $runs) -eq 7 -and $r.Text -match '：red' -and $r2.Text -match '账上是 red')
    $r = Run @('-Rerun', '项目')
    Remove-Item -LiteralPath (Join-Path $proj 'fail.txt')
    & $commit 'f.txt'
    $null = Run
    $r = Run @('-Rerun', '项目')
    Check '-Rerun: a green tree is not rerun' ((& $runs) -eq 9 -and $r.Text -match '账上是 green')

    & $commit 'g.txt'
    Move-Item -LiteralPath $ledger -Destination "$ledger.bak"
    $null = New-Item -ItemType Directory -Path $ledger
    $r = Run
    $r2 = Run
    Check 'ledger cannot be written: notifies once, the tree is not rerun' ((& $runs) -eq 10 -and $r.Text -match '记不进账' -and $r.Text -match 'title: .*主干全量记不进账' -and $r2.Text -match '上次跑完记不进账' -and (& $runs) -eq 10)
    Remove-Item -LiteralPath $ledger -Recurse
    Move-Item -LiteralPath "$ledger.bak" -Destination $ledger

    $m = Join-Path $root 'm'
    $null = New-Item -ItemType Directory -Force -Path $m
    git -c init.defaultBranch=master init -q $m
    Set-Content -LiteralPath (Join-Path $m '.gitignore') -Encoding utf8NoBOM -Value '.agents/'
    G -C $m add -A; G -C $m commit -q -m one
    $cfgMain = $cfg; $cfg = Join-Path $root 'm.json'
    @{ projects = @(@{ name = 'M'; path = $m; status = '推进中'; trunkVerify = $verify }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfg -Encoding utf8NoBOM
    $r = Run
    Check 'no trunk written, the checkout is on master: runs master' ((& $runs) -eq 11 -and $r.Text -match '：green')
    Set-Content -LiteralPath (Join-Path $m '.gitignore') -Encoding utf8NoBOM -Value 'x'
    G -C $m add -A; G -C $m commit -q -m 'stop ignoring'
    $r = Run
    $st = pwsh -NoProfile -File (Join-Path (Split-Path $Script) 'status.ps1') -Config $cfg -All -Json | ConvertFrom-Json
    Check '.agents/ not ignored: skipped with the reason, status says so' ((& $runs) -eq 11 -and $r.Text -match '没被 Git 忽略' -and [bool](@($st.Projects[0].Problems) -match '合并后全量'))
    $cfg = $cfgMain

}
finally {
    Remove-Item Env:AI_DEV_FLOW_TRUNK_NOW -ErrorAction SilentlyContinue
    Remove-Item Env:AI_DEV_FLOW_BUSY_MARK -ErrorAction SilentlyContinue
    if ($Keep) { "fixture kept: $root" } else { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($notRun.Count) { "not run: $($notRun -join '; ')" }
if ($fail) { "$fail check(s) failed"; exit 1 }
'all checks passed'
