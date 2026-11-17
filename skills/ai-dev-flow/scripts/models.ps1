[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Role,
    [string]$Writer,
    [string]$Table,
    [string]$Config,
    [string]$Today,
    [switch]$Json
)
# 只读模型设置表，按角色依次选取未停用且不同于写方厂商的候选。
# -Table <models.json> 或 -Config <projects.json>（读取同目录 models.json）。
# -Today yyyy-MM-dd 仅供测试；退出码 0 成功，2 参数或表格式错误，3 无可用候选。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function Fail([string]$m) { Write-Error "models.ps1: $m" -ErrorAction Continue; exit 2 }
function Parse-Date([string]$raw, [string]$label) {
    $dt = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($raw, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)) {
        Fail "$label 日期格式必须为 yyyy-MM-dd：$raw"
    }
    $dt
}
function Get-Vendor([string]$model) {
    if ($explicitVendors.ContainsKey($model)) { return $explicitVendors[$model] }
    switch -Regex ($model) {
        '^(gpt-|o)' { return 'openai' }
        '^gemini-' { return 'google' }
        '^claude-' { return 'anthropic' }
        '^(dsh|deepseek)' { return 'deepseek' }
    }
    Fail "无法推断模型 $model 的 vendor，请显式填写 vendor"
}
function Test-Text($value) { $value -is [string] -and -not [string]::IsNullOrWhiteSpace($value) }

# JsonDocument 保留对象的原始属性，先递归检查再交给 ConvertFrom-Json。
function Test-JsonKeys($element, [string]$path) {
    if ($element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) { Fail "JSON 重复键：$path.$($property.Name)" }
            Test-JsonKeys $property.Value "$path.$($property.Name)"
        }
    } elseif ($element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $i = 0
        foreach ($entry in $element.EnumerateArray()) {
            Test-JsonKeys $entry "$path[$i]"
            $i++
        }
    }
}
if (-not (Test-Text $Role)) { Fail '需要 -Role' }
if ([bool]$Table -eq [bool]$Config) { Fail '需要且只能指定一个 -Table 或 -Config' }
try {
    if ($Config) {
        if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) { Fail "找不到配置文件：$Config" }
        $Table = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Config))) 'models.json'
    }
    if (-not (Test-Path -LiteralPath $Table -PathType Leaf)) { Fail "找不到模型设置表：$Table" }
    $raw = Get-Content -LiteralPath $Table -Raw -Encoding UTF8
    $document = [System.Text.Json.JsonDocument]::Parse([string]$raw)
    try { Test-JsonKeys $document.RootElement '$' } finally { $document.Dispose() }
    $data = $raw | ConvertFrom-Json -AsHashtable
} catch { Fail "读取模型设置表失败：$($_.Exception.Message)" }
$todayDate = if ($Today) { Parse-Date $Today '-Today' } else { (Get-Date).Date }
if ($data -isnot [Collections.IDictionary] -or $data.roles -isnot [Collections.IDictionary]) { Fail '表缺少 roles 对象' }
if ($data.version -ne 1) { Fail '表 version 必须为 1' }
if ($data.Contains('sameVendorFallback')) {
    if ($data.sameVendorFallback -isnot [array]) { Fail 'sameVendorFallback 必须是字符串数组' }
    foreach ($fallbackRole in $data.sameVendorFallback) {
        if ($fallbackRole -isnot [string]) { Fail 'sameVendorFallback 必须是字符串数组' }
        if (-not @($data.roles.Keys | Where-Object { [string]::Equals($_, $fallbackRole, [StringComparison]::OrdinalIgnoreCase) }).Count) {
            Fail "sameVendorFallback 未知角色：$fallbackRole"
        }
    }
}
$explicitVendors = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
# 先校验整张表，不能因为首选可用而漏掉后续格式错误。
foreach ($key in $data.roles.Keys) {
    $candidates = $data.roles[$key]
    if ($candidates -isnot [array]) { Fail "roles.$key 必须是候选数组" }
    foreach ($c in $candidates) {
        if ($c -isnot [Collections.IDictionary]) { Fail "roles.$key 候选必须是对象" }
        foreach ($field in 'provider', 'model', 'effort') {
            if (-not (Test-Text $c[$field])) { Fail "roles.$key 候选缺少有效 $field" }
        }
        if ($c.Contains('vendor')) {
            if (-not (Test-Text $c.vendor)) { Fail "roles.$key 候选 vendor 必须为非空字符串" }
            if ($explicitVendors.ContainsKey($c.model) -and $explicitVendors[$c.model] -ne $c.vendor) {
                Fail "模型 $($c.model) 声明了冲突的 vendor"
            }
            $explicitVendors[$c.model] = $c.vendor
        }
    }
}
# 第二遍才解析厂商，保证角色顺序和候选是否写 vendor 都不影响结果。
foreach ($key in $data.roles.Keys) {
    foreach ($c in $data.roles[$key]) { $c.vendor = Get-Vendor $c.model }
}
$disabled = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
if ($data.Contains('disabled')) {
    if ($data.disabled -isnot [Collections.IDictionary]) { Fail 'disabled 必须是对象' }
    foreach ($model in $data.disabled.Keys) {
        $entry = $data.disabled[$model]
        if ($entry -isnot [Collections.IDictionary]) { Fail "disabled.$model 必须是对象" }
        $until = $null
        if ($entry.Contains('until')) {
            if (-not (Test-Text $entry.until)) { Fail "disabled.$model.until 必须为日期字符串" }
            $until = Parse-Date $entry.until "disabled.$model.until"
        }
        $disabled[$model] = @{ Until = $until; Reason = $entry.reason }
    }
}
$roleKey = @($data.roles.Keys | Where-Object { [string]::Equals($_, $Role, [StringComparison]::OrdinalIgnoreCase) })
if (-not $roleKey.Count) { Fail "未知角色：$Role" }
$writerVendor = if ($Writer) {
    Get-Vendor $Writer
} else { $null }
$skipped = [Collections.Generic.List[object]]::new()
$selected = $null
foreach ($c in $data.roles[$roleKey[0]]) {
    $reasons = [Collections.Generic.List[string]]::new()
    if ($disabled.ContainsKey($c.model)) {
        $d = $disabled[$c.model]
        if ($null -eq $d.Until -or $todayDate -le $d.Until) {
            $reasons.Add("停用$(if ($d.Until) { '至 ' + $d.Until.ToString('yyyy-MM-dd') } else { '（无限期）' })$(if ($d.Reason) { '：' + $d.Reason })")
        }
    }
    if ($Writer -and [string]::Equals($c.model, $Writer, [StringComparison]::OrdinalIgnoreCase)) {
        $reasons.Add("与写方相同模型：$Writer")
    }
    if ($writerVendor -and $c.vendor -eq $writerVendor) { $reasons.Add("与写方同厂商：$writerVendor") }
    if ($reasons.Count) {
        $skipped.Add([pscustomobject]@{ Model = $c.model; Reason = $reasons -join '；' })
        continue
    }
    $selected = $c
    break
}
$sameVendorFallback = $false
if ($null -eq $selected -and $Writer -and $data.sameVendorFallback -contains $Role) {
    foreach ($c in $data.roles[$roleKey[0]]) {
        if ($disabled.ContainsKey($c.model)) {
            $d = $disabled[$c.model]
            if ($null -eq $d.Until -or $todayDate -le $d.Until) { continue }
        }
        $selected = $c
        $sameVendorFallback = $true
        break
    }
}
if ($null -eq $selected) {
    $details = @($skipped | ForEach-Object { "skipped: $($_.Model) $($_.Reason)" })
    Write-Error ("models.ps1: 角色 $Role 无可用候选" + $(if ($details.Count) { "`n" + ($details -join "`n") } else { '（候选列表为空）' })) -ErrorAction Continue
    exit 3
}
$option = switch ($selected.provider) {
    'codex' { 'reasoningEffort' }
    'antigravity' { 'thinking_level' }
    'claudeAgent' { 'effort' }
    default { '' }
}
if ($Json) {
    [ordered]@{ Role = $Role; Provider = $selected.provider; Model = $selected.model; Vendor = $selected.vendor; Effort = $selected.effort; EffortOption = $option; SameVendorFallback = $sameVendorFallback; Skipped = @($skipped.ToArray()) } | ConvertTo-Json -Depth 6
} else {
    "$($selected.provider) $($selected.model) $($selected.effort)"
    if ($sameVendorFallback) { 'fallback: same vendor' }
    foreach ($s in $skipped) { "skipped: $($s.Model) $($s.Reason)" }
}
exit 0
