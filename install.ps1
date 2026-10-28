# ccrm installer for Windows PowerShell - kept ASCII-only on purpose:
# `irm | iex` in Windows PowerShell 5.1 decodes the script as Latin-1, so a UTF-8 BOM and
# Thai text turn into garbage. This stub saves install-core.ps1 to a file and runs it with
# -File, which reads UTF-8 (with BOM) correctly. No `exit` here: under iex it would close the shell.
$ProgressPreference = 'SilentlyContinue'
$here = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $null }
if ($here -and (Test-Path -LiteralPath (Join-Path $here 'install-core.ps1'))) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'install-core.ps1')
} else {
  $tmp = Join-Path $env:TEMP ('ccrm-install-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $core = Join-Path $tmp 'install-core.ps1'
  try {
    Invoke-WebRequest -UseBasicParsing -OutFile $core -Uri ('https://github.com/cznpsk/ccrm/releases/latest/download/install-core.ps1?ts=' + [DateTimeOffset]::Now.ToUnixTimeSeconds())
    & powershell -NoProfile -ExecutionPolicy Bypass -File $core
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}
