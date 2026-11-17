param(
    [string]$ModelsScript = (Join-Path $PSScriptRoot '../skills/ai-dev-flow/scripts/models.ps1'),
    [switch]$Keep
)
# 在系统临时目录创建模型表，检查返回值、边界与只读保证。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ModelsScript = [IO.Path]::GetFullPath($ModelsScript)
$root = Join-Path ([IO.Path]::GetTempPath()) ("models-fixture-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $root
$pwsh = (Get-Process -Id $PID).Path
$fail = 0
function Check($name, $cond) { if ($cond) { "ok   $name" } else { "FAIL $name"; $script:fail++ } }
function Save($data) { $data | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $table -Encoding utf8NoBOM }
function Run([string[]]$Extra = @()) {
    $callArgs = @{ Role='review'; Table=$table; Today='2026-11-20' }
    for ($i=0; $i -lt $Extra.Count; $i++) {
        $key=$Extra[$i].TrimStart('-')
        if ($key -eq 'Json') { $callArgs[$key]=$true } else { $callArgs[$key]=$Extra[++$i] }
    }
    $out = & $pwsh -NoProfile -File $ModelsScript @callArgs 2>&1
    $script:code = $LASTEXITCODE
    $script:output = $out -join "`n"
    if ($code -eq 0 -and $Extra -contains '-Json') { $script:result = $output | ConvertFrom-Json }
}
function Fresh {
    @{ version = 1; roles = @{ review = @(
        @{ provider = 'codex'; model = 'gpt-6.1-sol'; effort = 'high' },
        @{ provider = 'antigravity'; model = 'gemini-4-argon'; effort = 'high' }
    ) }; disabled = @{} }
}
$table = Join-Path $root 'models.json'
try {
    $d = Fresh; Save $d
    Run @('-Json')
    Check 'preferred and JSON fields' ($code -eq 0 -and $result.Role -eq 'review' -and $result.Provider -eq 'codex' -and $result.Model -eq 'gpt-6.1-sol' -and $result.Vendor -eq 'openai' -and $result.Effort -eq 'high' -and $result.EffortOption -eq 'reasoningEffort' -and $result.Skipped -is [array] -and $result.Skipped.Count -eq 0)
    $d.disabled['gpt-6.1-sol'] = @{ until = '2026-11-20'; reason = '维护' }; Save $d
    Run @('-Json')
    Check 'until inclusive selects fallback' ($code -eq 0 -and $result.Model -eq 'gemini-4-argon' -and $result.EffortOption -eq 'thinking_level' -and $result.Skipped[0].Model -eq 'gpt-6.1-sol' -and $result.Skipped[0].Reason -match '停用')
    Run @('-Today', '2026-11-21', '-Json')
    Check 'next day restored' ($code -eq 0 -and $result.Model -eq 'gpt-6.1-sol')
    $d.disabled['gpt-6.1-sol'] = @{}; Save $d
    Run @('-Today', '2030-01-01', '-Json')
    Check 'no until disabled forever' ($code -eq 0 -and $result.Model -eq 'gemini-4-argon')
    $d = Fresh; Save $d
    Run @('-Writer', 'gpt-6.1-sol', '-Json')
    Check 'writer same vendor skipped' ($code -eq 0 -and $result.Model -eq 'gemini-4-argon' -and $result.Skipped[0].Reason -match '同厂商')
    Run @('-Writer', 'o-unlisted', '-Json')
    Check 'unlisted writer prefix inferred' ($code -eq 0 -and $result.Model -eq 'gemini-4-argon')
    $d.roles.review[0] = @{ provider = 'antigravity'; model = 'claude-opus-5-5'; effort = 'high' }; Save $d
    Run @('-Json')
    Check 'vendor follows model not provider' ($code -eq 0 -and $result.Vendor -eq 'anthropic')
    Run @('-Writer', 'claude-unlisted', '-Json')
    Check 'antigravity claude same vendor skipped' ($code -eq 0 -and $result.Model -eq 'gemini-4-argon')
    foreach ($pair in @(@('claudeAgent','claude-test','effort'), @('dsh','dsh',''), @('custom','deepseek-test',''))) {
        $d.roles.review = @(@{ provider=$pair[0]; model=$pair[1]; effort='default' }); Save $d
        Run @('-Json')
        Check "effort mapping $($pair[0])" ($code -eq 0 -and $result.EffortOption -ceq $pair[2])
    }
    $d.roles.review = @(@{ provider='custom'; model='custom-model'; effort='high'; vendor='custom-vendor' }); Save $d
    Run @('-Json')
    Check 'explicit vendor accepted' ($code -eq 0 -and $result.Vendor -eq 'custom-vendor')
    $d = Fresh; $d.disabled['gemini-4-argon'] = @{}; Save $d
    Run @('-Writer', 'gpt-6.1-sol')
    Check 'all unavailable lists every reason' ($code -eq 3 -and $output -match 'gpt-6.1-sol.*同厂商' -and $output -match 'gemini-4-argon.*停用')
    $d.roles.review = @(); Save $d; Run
    Check 'empty candidates exits 3' ($code -eq 3 -and $output -match '候选列表为空')
    $d = Fresh; $d.sameVendorFallback = @('REVIEW'); Save $d
    Run @('-Writer', 'gpt-6.1-sol', '-Json')
    Check 'cross vendor preferred over allowed fallback' ($code -eq 0 -and $result.Model -eq 'gemini-4-argon' -and $result.SameVendorFallback -ceq $false)
    $d.disabled['gemini-4-argon'] = @{}; Save $d
    Run @('-Writer', 'gpt-6.1-sol', '-Json')
    Check 'allowed fallback preserves first pass reasons' ($code -eq 0 -and $result.Model -eq 'gpt-6.1-sol' -and $result.SameVendorFallback -ceq $true -and $result.Skipped.Count -eq 2 -and $result.Skipped[0].Reason -match '相同模型' -and $result.Skipped[1].Reason -match '停用')
    Run @('-Writer', 'gpt-6.1-sol')
    Check 'fallback text follows first line' ($code -eq 0 -and $output -match '^codex gpt-6.1-sol high\nfallback: same vendor\nskipped:')
    $d.sameVendorFallback = @(); Save $d
    Run @('-Writer', 'gpt-6.1-sol')
    Check 'unlisted role still exits 3' ($code -eq 3)
    $d.sameVendorFallback = @('review'); $d.disabled['gpt-6.1-sol'] = @{ until='2026-11-20' }; Save $d
    Run @('-Writer', 'gpt-6.1-sol')
    Check 'fallback never revives disabled candidates' ($code -eq 3)
    foreach ($invalid in @('review', 42, @('review', 42), @('missing-role'))) {
        $d = Fresh; $d.sameVendorFallback = $invalid; Save $d; Run
        Check 'invalid fallback configuration exits 2' ($code -eq 2 -and $output -match 'sameVendorFallback')
    }
    $d = Fresh; $d.roles.other = $d.roles.review; Save $d; Run @('-Json')
    Check 'model shared across roles allowed' ($code -eq 0)
    Run @('-Role', 'unknown'); Check 'unknown role' ($code -eq 2 -and $output -match '未知角色')
    foreach ($field in 'provider','model','effort') {
        $d = Fresh; $d.roles.review[1].Remove($field); Save $d; Run
        Check "missing $field even in fallback" ($code -eq 2 -and $output -match $field)
    }
    $d = Fresh; $d.roles.review[1].model = 'unknown-model'; Save $d; Run
    Check 'cannot infer vendor' ($code -eq 2 -and $output -match 'vendor')
    $d = Fresh; $d.disabled['unused-model'] = @{ until='2026-02-30' }; Save $d; Run
    Check 'invalid until anywhere rejects table' ($code -eq 2 -and $output -match 'until')
    # 写方可在别的角色中声明 vendor，优先于模型名前缀。
    $d = Fresh
    $d.roles.review = @($d.roles.review[1], $d.roles.review[0])
    $d.roles.build = @(@{ provider='custom'; model='o-router-alias'; effort='high'; vendor='google' })
    Save $d; Run @('-Writer', 'o-router-alias', '-Json')
    Check 'writer explicit vendor overrides prefix across roles' ($code -eq 0 -and $result.Model -eq 'gpt-6.1-sol' -and $result.Skipped[0].Model -eq 'gemini-4-argon' -and $result.Skipped[0].Reason -match 'google')
    $d.roles.build = @(@{ provider='custom'; model='custom-model'; effort='high'; vendor='openai' })
    $d.roles.review = @($d.roles.review[1], $d.roles.review[0])
    Save $d; Run @('-Writer', 'custom-model', '-Json')
    Check 'writer explicit vendor works without known prefix' ($code -eq 0 -and $result.Model -eq 'gemini-4-argon' -and $result.Skipped[0].Reason -match 'openai')
    $d.roles.other = @(@{ provider='custom'; model='custom-model'; effort='high'; vendor='google' })
    Save $d; Run
    Check 'conflicting explicit vendors rejected across roles' ($code -eq 2 -and $output -match 'custom-model.*冲突.*vendor')
    $d.roles.other[0].vendor = 'openai'
    Save $d; Run @('-Writer', 'custom-model', '-Json')
    Check 'same explicit vendor repeated across roles allowed' ($code -eq 0 -and $result.Model -eq 'gemini-4-argon')
    $raw = (Fresh | ConvertTo-Json -Depth 12).Replace('"disabled": {}', '"disabled": {"gpt-6.1-sol":{"until":"2026-12-31"},"gpt-6.1-sol":{"until":"2026-01-01"}}')
    Set-Content -LiteralPath $table -Value $raw -Encoding utf8NoBOM
    Run
    Check 'duplicate disabled model rejected before overwrite' ($code -eq 2 -and $output -match '重复键.*disabled.gpt-6.1-sol')
    $raw = '{"version":1,"roles":{"review":[]},"roles":{"review":[{"provider":"codex","model":"gpt-6.1-sol","effort":"high"}]}}'
    Set-Content -LiteralPath $table -Value $raw -Encoding utf8NoBOM
    Run
    Check 'duplicate roles key rejected' ($code -eq 2 -and $output -match '重复键.*roles')
    # 同一个 model 的显式声明必须同时作用于写方和所有候选。
    $d = Fresh
    $d.roles.build = @(@{ provider='custom'; model='o-router-alias'; effort='high'; vendor='google' })
    $d.roles.review = @(@{ provider='custom'; model='O-ROUTER-ALIAS'; effort='high' }, $d.roles.review[0])
    Save $d; Run @('-Writer', 'o-router-alias', '-Json')
    Check 'same model cannot review itself across case variants' ($code -eq 0 -and $result.Model -eq 'gpt-6.1-sol' -and $result.Skipped[0].Reason -match '相同模型')
    Run @('-Writer', 'gemini-writer', '-Json')
    Check 'candidate shares explicit vendor across roles and case' ($code -eq 0 -and $result.Model -eq 'gpt-6.1-sol' -and $result.Skipped[0].Reason -match '同厂商')
    Run @('-Json')
    Check 'candidate output uses global explicit vendor' ($code -eq 0 -and $result.Model -eq 'O-ROUTER-ALIAS' -and $result.Vendor -eq 'google')
    # 未知前缀候选可从别的角色取得显式厂商，先后顺序不影响解析。
    $raw = '{"version":1,"roles":{"review":[{"provider":"custom","model":"CUSTOM-MODEL","effort":"high"},{"provider":"codex","model":"gpt-6.1-sol","effort":"high"}],"build":[{"provider":"custom","model":"custom-model","effort":"high","vendor":"google"}]}}'
    Set-Content -LiteralPath $table -Value $raw -Encoding utf8NoBOM
    Run @('-Writer', 'gemini-writer', '-Json')
    Check 'unknown prefix candidate resolves later explicit declaration' ($code -eq 0 -and $result.Model -eq 'gpt-6.1-sol')
    $d = Fresh
    $d.roles.build = @(@{ provider='custom'; model='GPT-6.1-SOL'; effort='high'; vendor='google' })
    $d.roles.review[0].vendor = 'openai'
    Save $d; Run
    Check 'vendor conflict model comparison ignores case' ($code -eq 2 -and $output -match '冲突.*vendor')
    $d = Fresh; $d.disabled['GEMINI-4-ARGON'] = @{}
    Save $d; Run @('-Writer', 'gpt-6.1-sol')
    Check 'disabled model match ignores case' ($code -eq 3 -and $output -match 'gemini-4-argon.*停用')
    foreach ($raw in @(
        '{"version":1,"roles":{"review":[]},"disabled":{"gemini-4-argon":{"until":"2026-12-31"},"GEMINI-4-ARGON":{"until":"2026-01-01"}}}',
        '{"version":1,"roles":{"review":[],"Review":[]}}'
    )) {
        Set-Content -LiteralPath $table -Value $raw -Encoding utf8NoBOM
        Run
        Check 'case variant duplicate keys rejected' ($code -eq 2 -and $output -match '重复键')
    }
    Save (Fresh); Run @('-Role', 'REVIEW', '-Json')
    Check 'role lookup ignores case consistently' ($code -eq 0 -and $result.Model -eq 'gpt-6.1-sol')
    Save @{ version=1 }; Run; Check 'missing roles' ($code -eq 2 -and $output -match 'roles')
    Set-Content -LiteralPath $table -Value '{broken'; Run; Check 'bad JSON' ($code -eq 2 -and $output -match '读取模型设置表失败')
    Run @('-Table', (Join-Path $root 'missing.json')); Check 'missing table' ($code -eq 2 -and $output -match '找不到模型设置表')
    $null = & $pwsh -NoProfile -File $ModelsScript -Role review 2>&1
    Check 'no table or config' ($LASTEXITCODE -eq 2)
    Save (Fresh)
    $cfg = Join-Path $root 'projects.json'
    Set-Content -LiteralPath $cfg -Value '{}'
    $before = @(Get-ChildItem $root -Recurse -File | ForEach-Object { $_.FullName + ':' + (Get-FileHash $_.FullName).Hash })
    $out = & $pwsh -NoProfile -File $ModelsScript -Role review -Config $cfg -Json
    $r = ($out -join "`n") | ConvertFrom-Json
    Check 'config reads sibling models' ($LASTEXITCODE -eq 0 -and $r.Model -eq 'gpt-6.1-sol')
    Run
    Check 'text output first line' ($code -eq 0 -and $output -eq 'codex gpt-6.1-sol high')
    $d = Fresh; $d.disabled['gpt-6.1-sol'] = @{}; Save $d
    Run
    Check 'text skipped line' ($code -eq 0 -and $output -match "high`nskipped: gpt-6.1-sol")
    Save (Fresh)
    $after = @(Get-ChildItem $root -Recurse -File | ForEach-Object { $_.FullName + ':' + (Get-FileHash $_.FullName).Hash })
    Check 'read only no files changed or added' (@(Compare-Object $before $after).Count -eq 0)
} finally {
    if ($Keep) { "fixtures: $root" } else { Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($fail) { "$fail checks failed"; exit 1 }
'all models checks passed'
exit 0
