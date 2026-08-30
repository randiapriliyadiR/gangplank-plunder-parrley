<#
.SYNOPSIS
  Compile Gangplank Plunder Parrrley and run headless MT5 Strategy Tester.
#>
param(
  [string]$Symbol = "XAUUSD_ExnessPro",
  [string]$Period = "D1",
  [string]$FromDate = "2021.01.01",
  [string]$ToDate = "2025.07.31",
  [int]$Deposit = 100000,
  [int]$Model = 4,
  [int]$Leverage = 500,
  [int]$TimeoutSec = 7200,
  [string]$ReportName = "GPP_XAUUSD_ExnessPro_D1_100k",
  [string]$IniFile = "",
  [string]$Label = "v1.10 D1 quality | box breakout | lock=flat | major TP | Ladder=3",
  [switch]$SkipCompile
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$TerminalData = "C:\Users\randi\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$Mql5 = Join-Path $TerminalData "MQL5"
$TerminalExe = "C:\Program Files\MetaTrader 5\terminal64.exe"
$MetaEditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$EaMq5 = Join-Path $ProjectRoot "Gangplank Plunder Parrrley.mq5"
if ([string]::IsNullOrWhiteSpace($IniFile)) {
  $IniFile = "_run_GPP_D1_100k.ini"
}
$IniRun = Join-Path $PSScriptRoot $IniFile
$SummaryOut = Join-Path $PSScriptRoot ("last_summary_{0}.txt" -f $ReportName)

if (-not (Test-Path $TerminalExe)) { throw "terminal64.exe not found: $TerminalExe" }
if (-not (Test-Path $EaMq5)) { throw "EA source not found: $EaMq5" }
if (-not (Test-Path $IniRun)) { throw "INI not found: $IniRun" }

if (-not $SkipCompile) {
  Write-Host "== Compile EA =="
  $compileLog = Join-Path $PSScriptRoot "gpp_compile.log"
  $compileArgs = @("/compile:`"$EaMq5`"", "/include:`"$Mql5`"", "/log:`"$compileLog`"")
  Start-Process -FilePath $MetaEditor -ArgumentList $compileArgs -Wait -PassThru | Out-Null
  Start-Sleep -Seconds 2
  $logText = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($compileLog))
  $compileResult = ($logText -split "`r?`n" | Where-Object { $_ -match "Result:" } | Select-Object -Last 1)
  Write-Host $compileResult
  if ($compileResult -notmatch "0 errors") {
    throw "Compile failed. See $compileLog"
  }
} else {
  Write-Host "== Skip compile =="
}

$ini = Get-Content $IniRun -Raw
$ini = $ini -replace "(?m)^Symbol=.*$", "Symbol=$Symbol"
$ini = $ini -replace "(?m)^Period=.*$", "Period=$Period"
$ini = $ini -replace "(?m)^FromDate=.*$", "FromDate=$FromDate"
$ini = $ini -replace "(?m)^ToDate=.*$", "ToDate=$ToDate"
$ini = $ini -replace "(?m)^Deposit=.*$", "Deposit=$Deposit"
$ini = $ini -replace "(?m)^Model=.*$", "Model=$Model"
$ini = $ini -replace "(?m)^Leverage=.*$", "Leverage=$Leverage"
$ini = $ini -replace "(?m)^Report=.*$", "Report=$ReportName"
Set-Content -Path $IniRun -Value $ini -Encoding ASCII

$candidates = @(
  (Join-Path $TerminalData "$ReportName.htm"),
  (Join-Path $TerminalData "$ReportName.html"),
  (Join-Path $TerminalData "Tester\$ReportName.htm"),
  (Join-Path $Mql5 "Files\$ReportName.htm")
)
foreach ($c in $candidates) {
  if (Test-Path $c) { Remove-Item $c -Force }
}

Get-Process terminal64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "== Launch Strategy Tester (headless) =="
Write-Host "Config: $IniRun"
Write-Host "Range: $FromDate -> $ToDate | Deposit=$Deposit | Model=$Model | $Period $Symbol"
$before = Get-Date
$p = Start-Process -FilePath $TerminalExe -ArgumentList "/config:`"$IniRun`"" -PassThru

function Test-ReportReady([string]$path) {
  if (-not (Test-Path $path)) { return $false }
  $len1 = (Get-Item $path).Length
  if ($len1 -lt 1500) { return $false }
  Start-Sleep -Seconds 2
  $len2 = (Get-Item $path).Length
  if ($len1 -ne $len2) { return $false }
  $raw = Get-Content $path -Raw -Encoding UTF8
  if ($raw -match 'Total Net Profit') { return $true }
  if ($raw -match 'Bars:</td>\s*<td[^>]*>\s*(?:<b>)?([1-9][0-9,]*)') { return $true }
  return $false
}

$reportPath = $null
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$exitGraceUntil = $null
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 10
  foreach ($c in $candidates) {
    if (Test-ReportReady $c) {
      $reportPath = $c
      break
    }
  }
  if ($reportPath) { break }
  if ($p.HasExited) {
    if ($null -eq $exitGraceUntil) {
      $exitGraceUntil = (Get-Date).AddSeconds(90)
      Write-Host "  tester exited; grace wait for report..."
    }
    if ((Get-Date) -ge $exitGraceUntil) { break }
  }
  Write-Host ("  waiting... {0}s pid={1} exited={2}" -f [int]((Get-Date) - $before).TotalSeconds, $p.Id, $p.HasExited)
}

if (-not $reportPath) {
  throw "No report HTML found within ${TimeoutSec}s."
}

Write-Host "Report: $reportPath"
$html = Get-Content $reportPath -Raw -Encoding UTF8

function Get-Stat([string]$label) {
  $pat = [regex]::Escape($label) + ':</td>\s*<td[^>]*>\s*(?:<b>)?([^<]+)'
  if ($html -match $pat) { return $Matches[1].Trim() }
  return "n/a"
}

$lines = @(
  "Report: $reportPath",
  "Symbol=$Symbol Period=$Period Deposit=$Deposit Model=$Model",
  "From=$FromDate To=$ToDate",
  $Label,
  "Total Net Profit: $(Get-Stat 'Total Net Profit')",
  "Gross Profit: $(Get-Stat 'Gross Profit')",
  "Gross Loss: $(Get-Stat 'Gross Loss')",
  "Profit Factor: $(Get-Stat 'Profit Factor')",
  "Expected Payoff: $(Get-Stat 'Expected Payoff')",
  "Equity DD Maximal: $(Get-Stat 'Equity Drawdown Maximal')",
  "Balance DD Maximal: $(Get-Stat 'Balance Drawdown Maximal')",
  "Total Trades: $(Get-Stat 'Total Trades')",
  "Profit Trades: $(Get-Stat 'Profit Trades (% of total)')",
  "Bars: $(Get-Stat 'Bars')"
)
$lines | Tee-Object -FilePath $SummaryOut
Write-Host "Summary saved: $SummaryOut"
