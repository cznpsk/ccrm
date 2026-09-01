# ccrm — จัดการ sessions ของ Claude Code + Codex + Kimi + Gemini แบบ interactive (fzf) สำหรับ Windows PowerShell
# ใช้: ccrm       -> Claude (project ปัจจุบัน) + Codex/Kimi/Gemini ทั้งหมด
#      ccrm -All  -> Claude ทุก project + Codex/Kimi/Gemini ทั้งหมด
# คีย์: Enter=resume, Tab=เลือกจะลบ, กด Tab อีกครั้งบนบรรทัดเดิม=ยืนยันลบ, Esc=ยกเลิก
# หมายเหตุ gemini: --resume ของตัว CLI เองรับแค่ "latest"/index ผูกกับ project ปัจจุบัน
#   ไม่มี resume-by-id ตรงๆ เลยใช้ --session-file แทน (ต้อง cd เข้า project เดิมก่อนเสมอ)
param(
  [switch]$All,
  [switch]$ListOnly,
  [switch]$PreviewLine,
  [string]$Line,
  [switch]$TabTransform,
  [string]$Sel,
  [string]$Cur,
  [switch]$DeletePath,
  [string]$Target
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# กันกรณี ccrm.cmd เวอร์ชันเก่าส่ง "update" ทะลุมาเป็น positional arg
if ($Line -eq 'update') {
  $u = 'https://raw.githubusercontent.com/cznpsk/ccrm/main/install.ps1?ts=' + [DateTimeOffset]::Now.ToUnixTimeSeconds()
  Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri $u).Content
  exit 0
}

if ($DeletePath) {
  if ($Target) { Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue }
  exit 0
}

if ($TabTransform) {
  $cnt = 0
  [void][int]::TryParse($env:FZF_SELECT_COUNT, [ref]$cnt)
  $ps = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
  $allFlag = if ($All) { ' -All' } else { '' }
  if ($cnt -gt 0 -and $Sel -eq $Cur) {
    Write-Output ('execute-silent(' + $ps + ' -DeletePath -Target {1})+reload(' + $ps + ' -ListOnly' + $allFlag + ')+clear-selection')
  } else {
    Write-Output 'clear-selection+toggle'
  }
  exit 0
}

# อ่านไฟล์ผ่าน .NET ตรงๆ — เลี่ยง Get-Content -Encoding ที่เป็น dynamic param แล้วพังบนบางเครื่อง (PS 5.1)
function Read-FileLines([string]$p, [int]$max = 0) {
  try {
    if ($max -gt 0) { return @([System.IO.File]::ReadLines($p) | Select-Object -First $max) }
    return @([System.IO.File]::ReadAllLines($p))
  } catch { return @() }
}

function Read-FileRaw([string]$p) {
  try { return [System.IO.File]::ReadAllText($p) } catch { return $null }
}

function Format-Size([long]$bytes) {
  if ($bytes -ge 1GB) { return ("{0:N1}G" -f ($bytes / 1GB)) }
  elseif ($bytes -ge 1MB) { return ("{0:N1}M" -f ($bytes / 1MB)) }
  elseif ($bytes -ge 1KB) { return ("{0:N1}K" -f ($bytes / 1KB)) }
  else { return "$bytes" }
}

function Get-DirSize([string]$dir) {
  $sum = (Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  if (-not $sum) { $sum = 0 }
  return [long]$sum
}

function Get-ClaudeLabel([string]$sPath) {
  # customTitle มาจาก /rename — โดน append ท้ายไฟล์ ต้อง scan ทั้งไฟล์ เอาอันล่าสุด
  $m = Select-String -LiteralPath $sPath -Pattern '"customTitle":"([^"]*)"' -ErrorAction SilentlyContinue | Select-Object -Last 1
  if ($m) {
    $val = $m.Matches[0].Groups[1].Value
    if ($val) { return $val.Substring(0, [Math]::Min(70, $val.Length)) }
  }
  $lines = Read-FileLines $sPath 200
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $obj = $null
    try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    if ($obj.type -eq 'user' -and -not $obj.isMeta) {
      $content = $obj.message.content
      $text = $null
      if ($content -is [string]) {
        $text = $content
      } elseif ($content) {
        $parts = @()
        foreach ($p in $content) { if ($p.type -eq 'text') { $parts += $p.text } }
        $text = ($parts -join ' ')
      }
      if ($text -and -not $text.StartsWith('<')) {
        return $text.Substring(0, [Math]::Min(70, $text.Length))
      }
    }
  }
  return '(ว่าง)'
}

function Get-CodexLabel([string]$sPath) {
  $fname = [System.IO.Path]::GetFileNameWithoutExtension($sPath)
  if ($fname -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
    $id = $matches[1]
    $idx = Join-Path $HOME '.codex\session_index.jsonl'
    $m = Select-String -LiteralPath $idx -Pattern ('"' + $id + '"') -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($m) {
      try {
        $name = ($m.Line | ConvertFrom-Json).thread_name
        if ($name) { return $name.Substring(0, [Math]::Min(70, $name.Length)) }
      } catch {}
    }
  }
  $lines = Read-FileLines $sPath 200
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $obj = $null
    try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    if ($obj.type -eq 'response_item' -and $obj.payload.role -eq 'user') {
      foreach ($c in $obj.payload.content) {
        if ($c.type -eq 'input_text' -and $c.text -and -not $c.text.StartsWith('<')) {
          return $c.text.Substring(0, [Math]::Min(70, $c.text.Length))
        }
      }
    }
  }
  return '(ว่าง)'
}

function Get-KimiLabel([string]$sessionDir) {
  $statePath = Join-Path $sessionDir 'state.json'
  $title = $null
  try {
    $state = Read-FileRaw $statePath | ConvertFrom-Json
    if ($state.title -and $state.title -ne 'New Session') { $title = $state.title }
  } catch {}
  if (-not $title) {
    $wirePath = Join-Path $sessionDir 'agents\main\wire.jsonl'
    $lines = Read-FileLines $wirePath
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $obj = $null
      try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      if ($obj.type -eq 'turn.prompt' -and $obj.origin.kind -eq 'user') {
        foreach ($p in $obj.input) {
          if ($p.type -eq 'text' -and $p.text) { $title = $p.text; break }
        }
      }
      if ($title) { break }
    }
  }
  if (-not $title) { return '(ว่าง)' }
  return $title.Substring(0, [Math]::Min(70, $title.Length))
}

function Get-GeminiLabel([string]$sPath) {
  try {
    $data = Read-FileRaw $sPath | ConvertFrom-Json
  } catch { return '(ว่าง)' }
  foreach ($m in $data.messages) {
    if ($m.type -eq 'user') {
      foreach ($c in $m.content) {
        if ($c.text) { return $c.text.Substring(0, [Math]::Min(70, $c.text.Length)) }
      }
    }
  }
  return '(ว่าง)'
}

# หา customTitle เฉพาะช่วง byte ที่งอกใหม่ (jsonl append-only) — ไม่อ่านไฟล์ใหญ่ซ้ำทั้งไฟล์
function Get-TailTitle([string]$p, [long]$from) {
  try {
    $fs = [System.IO.File]::OpenRead($p)
    [void]$fs.Seek($from, [System.IO.SeekOrigin]::Begin)
    $sr = New-Object System.IO.StreamReader($fs)
    $txt = $sr.ReadToEnd()
    $sr.Close()
    $ms = [regex]::Matches($txt, '"customTitle":"([^"]*)"')
    if ($ms.Count -gt 0) {
      $v = $ms[$ms.Count - 1].Groups[1].Value
      if ($v) { return $v.Substring(0, [Math]::Min(70, $v.Length)) }
    }
  } catch {}
  return $null
}

function Get-SessionRows([bool]$includeAll) {
  $base = Join-Path $HOME '.claude\projects'
  $claudeFiles = @()
  if ($includeAll) {
    if (Test-Path $base) {
      $claudeFiles = @(Get-ChildItem -Path (Join-Path $base '*\*.jsonl') -File -ErrorAction SilentlyContinue)
    }
  } else {
    $proj = ($PWD.Path -replace '[\\/:.]', '-')
    $projDir = Join-Path $base $proj
    if (Test-Path $projDir) {
      $claudeFiles = @(Get-ChildItem -Path $projDir -Filter *.jsonl -File -ErrorAction SilentlyContinue)
    }
  }

  $codexDirs = @((Join-Path $HOME '.codex\sessions'), (Join-Path $HOME '.codex\archived_sessions')) | Where-Object { Test-Path $_ }
  $codexFiles = @()
  if ($codexDirs) {
    $codexFiles = @(Get-ChildItem -Path $codexDirs -Filter *.jsonl -File -Recurse -ErrorAction SilentlyContinue)
  }

  $kimiBase = Join-Path $HOME '.kimi-code\sessions'
  $kimiStateFiles = @()
  if (Test-Path $kimiBase) {
    $kimiStateFiles = @(Get-ChildItem -Path (Join-Path $kimiBase '*\*\state.json') -File -ErrorAction SilentlyContinue)
  }

  $geminiBase = Join-Path $HOME '.gemini\tmp'
  $geminiFiles = @()
  if (Test-Path $geminiBase) {
    $geminiFiles = @(Get-ChildItem -Path (Join-Path $geminiBase '*\chats\*.json') -File -ErrorAction SilentlyContinue)
  }

  $items = @()
  foreach ($f in $claudeFiles) { $items += [PSCustomObject]@{ Path = $f.FullName; RefPath = $f.FullName; Tag = 'claude'; Time = $f.LastWriteTime; Bytes = $f.Length } }
  foreach ($f in $codexFiles)  { $items += [PSCustomObject]@{ Path = $f.FullName; RefPath = $f.FullName; Tag = 'codex';  Time = $f.LastWriteTime; Bytes = $f.Length } }
  foreach ($f in $kimiStateFiles) {
    $dir = $f.Directory.FullName
    $items += [PSCustomObject]@{ Path = $dir; RefPath = $f.FullName; Tag = 'kimi'; Time = $f.LastWriteTime; Bytes = (Get-DirSize $dir) }
  }
  foreach ($f in $geminiFiles) { $items += [PSCustomObject]@{ Path = $f.FullName; RefPath = $f.FullName; Tag = 'gemini'; Time = $f.LastWriteTime; Bytes = $f.Length } }

  $items = @($items | Sort-Object Time -Descending)

  # cache ชื่อ session ตาม path+mtime — ไฟล์ใหญ่หลักร้อย MB สแกนหา customTitle ครั้งเดียวพอ
  $cacheFile = Join-Path $env:LOCALAPPDATA 'ccrm-labels.tsv'
  $cache = @{}
  $byPath = @{}   # entry ล่าสุดต่อ path — ไว้ทำ incremental scan ของ claude
  foreach ($ln in (Read-FileLines $cacheFile)) {
    $parts = $ln -split "`t", 3
    if ($parts.Count -eq 3) {
      $cache[$parts[0] + '|' + $parts[1]] = $parts[2]
      $n = 0L
      if ([long]::TryParse($parts[1], [ref]$n)) { $byPath[$parts[0]] = @{ Size = $n; Label = $parts[2] } }
    }
  }
  # codex rename เขียนแค่ session_index.jsonl ไม่แตะไฟล์ session — ผูก key กับ mtime ของ index ด้วย
  $codexIdx = Join-Path $HOME '.codex\session_index.jsonl'
  $codexIdxEp = if (Test-Path $codexIdx) { (Get-Item $codexIdx).LastWriteTime.Ticks } else { 0 }
  $newLines = New-Object System.Text.StringBuilder

  $rows = @()
  foreach ($item in $items) {
    $sz = Format-Size $item.Bytes
    $dt = $item.Time.ToString('dd/MM HH:mm')
    $ck = "$($item.Time.Ticks)"
    if ($item.Tag -eq 'codex') { $ck = "$ck-$codexIdxEp" }
    if ($item.Tag -eq 'claude') { $ck = "$($item.Bytes)" }   # jsonl append-only — key ตาม size
    $key = $item.RefPath + '|' + $ck
    if ($cache.ContainsKey($key)) {
      $label = $cache[$key]
    } else {
      $label = $null
      if ($item.Tag -eq 'claude' -and $byPath.ContainsKey($item.RefPath)) {
        $prev = $byPath[$item.RefPath]
        if ($prev.Size -lt $item.Bytes) {
          $nt = Get-TailTitle $item.RefPath $prev.Size
          $label = if ($nt) { $nt } else { $prev.Label }
        }
      }
      if (-not $label) {
        switch ($item.Tag) {
          'codex'  { $label = Get-CodexLabel $item.RefPath }
          'kimi'   { $label = Get-KimiLabel $item.Path }
          'gemini' { $label = Get-GeminiLabel $item.RefPath }
          default  { $label = Get-ClaudeLabel $item.RefPath }
        }
      }
      $label = $label -replace "[`t`r`n]", ' '
      [void]$newLines.AppendLine($item.RefPath + "`t" + $ck + "`t" + $label)
    }
    $rows += ($item.Path + "`t" + $item.Tag + "`t" + $dt + "`t" + $sz + "`t" + $label)
  }
  if ($newLines.Length -gt 0) {
    try {
      [System.IO.File]::AppendAllText($cacheFile, $newLines.ToString())
      $all = Read-FileLines $cacheFile
      if ($all.Count -gt 5000) { [System.IO.File]::WriteAllLines($cacheFile, $all[-2000..-1]) }
    } catch {}
  }
  return $rows
}

if ($ListOnly) {
  Get-SessionRows -includeAll:$All | Write-Output
  exit 0
}

if ($PreviewLine) {
  $fields = $Line -split "`t"
  $sPath = $fields[0]
  $tag = $fields[1]
  if ($tag -eq 'kimi') {
    $wirePath = Join-Path $sPath 'agents\main\wire.jsonl'
    $lines = Read-FileLines $wirePath
    foreach ($ln in $lines) {
      if ([string]::IsNullOrWhiteSpace($ln)) { continue }
      $o = $null
      try { $o = $ln | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      if ($o.type -eq 'turn.prompt' -and $o.origin.kind -eq 'user') {
        foreach ($p in $o.input) { if ($p.type -eq 'text') { $p.text } }
      }
    }
  } elseif ($tag -eq 'gemini') {
    try {
      $data = Read-FileRaw $sPath | ConvertFrom-Json
      foreach ($m in $data.messages) {
        if ($m.type -eq 'user') { foreach ($c in $m.content) { if ($c.text) { $c.text } } }
      }
    } catch {}
  } else {
    $lines = Read-FileLines $sPath 2000
    foreach ($ln in $lines) {
      if ([string]::IsNullOrWhiteSpace($ln)) { continue }
      $o = $null
      try { $o = $ln | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      if ($tag -eq 'codex') {
        if ($o.type -eq 'response_item' -and $o.payload.role -eq 'user') {
          foreach ($c in $o.payload.content) {
            if ($c.type -eq 'input_text' -and $c.text -and -not $c.text.StartsWith('<')) { $c.text }
          }
        }
      } else {
        if ($o.type -eq 'user' -and -not $o.isMeta) {
          $c = $o.message.content
          if ($c -is [string]) { $c }
          elseif ($c) { foreach ($p in $c) { if ($p.type -eq 'text') { $p.text } } }
        }
      }
    }
  }
  exit 0
}

$rows = @(Get-SessionRows -includeAll:$All)
if ($rows.Count -eq 0) {
  Write-Host 'ไม่พบ session'
  exit 0
}

$fzf = Get-Command fzf -ErrorAction SilentlyContinue
if (-not $fzf) {
  Write-Host 'ไม่พบ fzf ติดตั้งก่อน: winget install -e --id junegunn.fzf'
  exit 1
}

$ver = 16
$verCache = Join-Path $env:LOCALAPPDATA 'ccrm-latest'
# เช็คเวอร์ชันใหม่แบบ background ไม่บล็อกการใช้งาน — ผลไปโผล่ครั้งถัดไป
Start-Process -WindowStyle Hidden powershell -ArgumentList '-NoProfile', '-Command', "try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 ('https://raw.githubusercontent.com/cznpsk/ccrm/main/VERSION?ts=' + [DateTimeOffset]::Now.ToUnixTimeSeconds())).Content.Trim() | Set-Content -LiteralPath '$verCache' } catch {}" -ErrorAction SilentlyContinue
$updateNote = ''
if (Test-Path $verCache) {
  $latest = Read-FileRaw $verCache
  if ($latest) { $latest = $latest.Trim() }
  if ($latest -and $latest -ne "$ver") { $updateNote = "  |  v$latest มาแล้ว — พิมพ์: ccrm update" }
}

$scriptPath = $PSCommandPath
$psBase = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
$header = "รวม $($rows.Count) sessions  |  Enter=resume  Tab=เลือกลบ (กด Tab อีกครั้งยืนยัน)  Ctrl-A=ทุกโปรเจกต์  Esc=ยกเลิก$updateNote"
$previewCmd = $psBase + ' -PreviewLine -Line "{r}"'
$allFlag = if ($All) { ' -All' } else { '' }
$tabBind = 'tab:transform:' + $psBase + ' -TabTransform -Sel {+1} -Cur {1}' + $allFlag

$allBind = 'ctrl-a:reload(' + $psBase + ' -ListOnly -All)+change-header(รวมทุกโปรเจกต์  |  Enter=resume  Tab=เลือกลบ  Esc=ยกเลิก)'
$picked = $rows | fzf --multi --delimiter "`t" --with-nth 2.. --header $header --preview $previewCmd --preview-window right:50%:wrap --bind $tabBind --bind $allBind

if (-not $picked) { exit 0 }

$fields = $picked -split "`t"
$spath = $fields[0]
$tag = $fields[1].Trim()

switch ($tag) {
  'codex' {
    $fname = [System.IO.Path]::GetFileNameWithoutExtension($spath)
    if ($fname -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
      $id = $matches[1]
    } else {
      Write-Host 'หา session id ไม่เจอ'
      exit 1
    }
    & codex resume $id --yolo
  }
  'kimi' {
    $id = Split-Path -Leaf $spath
    try {
      $state = Read-FileRaw (Join-Path $spath 'state.json') | ConvertFrom-Json
      $wd = if ($state.cwd) { $state.cwd } elseif ($state.workDir) { $state.workDir } else { $null }
      if ($wd) { Set-Location -LiteralPath $wd }
    } catch {}
    & kimi -r $id --yolo
  }
  'gemini' {
    $projDir = Split-Path -Parent (Split-Path -Parent $spath)
    $rootFile = Join-Path $projDir '.project_root'
    if (Test-Path $rootFile) {
      $root = Read-FileRaw $rootFile
      if ($root) { $root = $root.Trim() }
      if ($root) { Set-Location -LiteralPath $root }
    }
    & gemini --session-file $spath -y
  }
  default {
    $id = [System.IO.Path]::GetFileNameWithoutExtension($spath)
    & claude --resume $id --dangerously-skip-permissions
  }
}
