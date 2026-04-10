# Legge i file migra-*.txt e li processa in ordine di arrivo.

$Cfg       = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
$BaseDir   = if ($Cfg.BaseDir) { $Cfg.BaseDir } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Incoming  = Join-Path $BaseDir $Cfg.IncomingSubDir
if (-not (Test-Path $Incoming)) { New-Item -ItemType Directory -Path $Incoming | Out-Null }

# Prepara la cartella e il file di log.
$LogDir  = Join-Path $BaseDir 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir ("dispatcher_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function WLog ([string]$Msg,[ValidateSet('INFO','WARN','ERROR')]$Lvl='INFO') {
    '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date),$Lvl,$Msg |
        Out-File $LogFile -Append -Encoding utf8
    switch ($Lvl) {
        'ERROR' { Write-Error   $Msg }
        'WARN'  { Write-Warning $Msg }
        default { Write-Host    $Msg }
    }
}

WLog '=== dispatcher started ==='

while ($true) {
    $queue = Get-ChildItem $Incoming -Filter 'migra-*.txt' | Sort-Object LastWriteTime
    if (-not $queue) { break }

    foreach ($f in $queue) {
        $work = "$($f.FullName).work"
        Rename-Item $f.FullName $work -ErrorAction Stop

        try {
            $parts = (Get-Content $work -Raw).Trim() -split '\|'
            if ($parts.Count -lt 3) { throw "invalid format" }

            $user,$src,$dst = $parts
            WLog "processing $user  ($src -> $dst)"

            $esito = (& "$BaseDir\migrazione.ps1" `
                        -User $user -Source $src -Destination $dst |
                      Select-Object -Last 1)
            $esito = [int]$esito
            $suffix = if ($esito -eq 1) { 'done' } else { 'fail' }
        }
        catch {
            WLog "dispatcher error: $_" 'ERROR'
            $suffix = 'fail'
        }

        Rename-Item $work "$($f.BaseName).$suffix"
        WLog "file renamed to .$suffix"
    }
}

WLog '=== dispatcher finished ==='
