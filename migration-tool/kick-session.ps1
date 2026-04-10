[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$User,
    [Parameter(Mandatory)][string]$Source,
    [switch]$Force,
    [int]$LogoffTimeoutSec = 20
)

# Config e log (stile migrazione/dispatcher)
$Cfg     = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
$BaseDir = if ($Cfg.BaseDir) { $Cfg.BaseDir } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$LogDir  = Join-Path $BaseDir 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir ("kick_{0}_{1}_{2:yyyyMMdd_HHmmss}.log" -f $User,$Source,(Get-Date))

function WLog ($m,[ValidateSet('INFO','WARN','ERROR')]$l='INFO') {
    '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date),$l,$m |
        Out-File $LogFile -Append -Encoding utf8
    switch ($l) {
        'ERROR' { Write-Error   $m }
        'WARN'  { Write-Warning $m }
        default { Write-Host    $m }
    }
}

# Normalizza username (accetta anche domain\user o user@domain)
$userShort = $User
if ($userShort -match '\\') { $userShort = ($userShort -split '\\')[-1] }
if ($userShort -match '@')  { $userShort = ($userShort -split '@')[0] }

# Carica una credenziale opzionale (stesso meccanismo della migrazione)
$credRunAs = $null
if ($Cfg.UseStoredCredentials) {
    try {
        $credRunAs = Import-Clixml (Join-Path $BaseDir $Cfg.CredFiles.RunAs)
        WLog "credenziale RunAs caricata da '$($Cfg.CredFiles.RunAs)'"
    } catch {
        WLog "impossibile caricare la credenziale RunAs: $_" 'ERROR'
        return 0
    }
} else {
    WLog "UseStoredCredentials=$($Cfg.UseStoredCredentials): uso le credenziali dell'utente corrente"
}

function Get-SessionsFromQuser {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$UserName
    )

    $res = @()
    foreach ($line in $Lines) {
        if (-not $line) { continue }
        if ($line -match '^\s*USERNAME\s+') { continue } # header

        $tokens = ($line -split '\s+') | Where-Object { $_ }
        if ($tokens.Count -lt 2) { continue }

        $u = $tokens[0].TrimStart('>')
        if ($u -ieq $UserName) {
            $sid = $null
            $state = $null

            for ($i = 0; $i -lt $tokens.Count; $i++) {
                if ($tokens[$i] -match '^[0-9]+$') {
                    $sid = [int]$tokens[$i]
                    if (($i + 1) -lt $tokens.Count) { $state = $tokens[$i + 1] }
                    break
                }
            }

            if ($null -ne $sid) {
                $res += [pscustomobject]@{
                    SessionId = $sid
                    State     = $state
                    Line      = $line
                }
            }
        }
    }

    $res | Sort-Object SessionId -Unique
}

function Invoke-WinRM {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter()][object[]]$ArgumentList
    )

    if ($null -ne $credRunAs) {
        Invoke-Command -ComputerName $Source -Credential $credRunAs -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    } else {
        Invoke-Command -ComputerName $Source -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    }
}

function Invoke-ServerLogoffWithTimeout {
    param(
        [Parameter(Mandatory)][int]$SessionId,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$LogoffExe,
        [Parameter(Mandatory)][string]$RwinstaExe,
        [int]$TimeoutSec = 20,
        [switch]$Force
    )

    # Esegue logoff in un job per poterlo interrompere se resta appeso
    $job = Start-Job -ScriptBlock {
        param($sid,$src,$logoffPath)
        & $logoffPath $sid "/server:$src" "/V" 2>&1
    } -ArgumentList @($SessionId,$Source,$LogoffExe)

    if (Wait-Job -Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force | Out-Null
        return ,@($out)
    }

    # Timeout: stop job e, se richiesto, fallback a rwinsta
    Stop-Job -Job $job | Out-Null
    Remove-Job -Job $job -Force | Out-Null

    if ($Force.IsPresent) {
        $out2 = & $RwinstaExe $SessionId "/server:$Source" 2>&1
        return ,@($out2)
    }

    return @("__TIMEOUT__")
}

WLog "kick start: user='$userShort' source='$Source' force=$($Force.IsPresent)"

# 1) Query sessioni (prefer WinRM; fallback /server)
$useWinRM = $true
$qOut = $null

try {
    $qOut = Invoke-WinRM -ScriptBlock { quser.exe 2>&1 } -ArgumentList @()
    WLog "query sessioni via WinRM: OK"
} catch {
    $useWinRM = $false
    WLog "Invoke-Command fallito ($_). Fallback su 'quser /server:'" 'WARN'
    $qOut = & "$env:SystemRoot\System32\quser.exe" "/server:$Source" 2>&1
}

$sessions = Get-SessionsFromQuser -Lines $qOut -UserName $userShort

if (-not $sessions -or $sessions.Count -eq 0) {
    WLog "nessuna sessione trovata per '$userShort' su '$Source' (OK)"
    return 1
}

WLog ("sessioni trovate: {0}" -f (($sessions | ForEach-Object { "$($_.SessionId):$($_.State)" }) -join ', '))

# 2) Termina sessioni
$logoffExe = "$env:SystemRoot\System32\logoff.exe"
$rwinstaExe = "$env:SystemRoot\System32\rwinsta.exe"

foreach ($s in $sessions) {
    $sid = $s.SessionId
    WLog "termino sessione id=$sid (logoff) ..."

    if ($useWinRM) {
        try {
            $out1 = Invoke-WinRM -ScriptBlock {
                param($id)
                & "$env:SystemRoot\System32\logoff.exe" $id /V 2>&1
            } -ArgumentList @($sid)
            foreach ($l in $out1) { if ($l) { WLog "    $l" } }
        } catch {
            WLog "logoff via WinRM fallito per id=${sid}: $_" 'WARN'
        }

        if ($Force.IsPresent) {
            WLog "force=ON: reset sessione id=$sid (rwinsta) ..."
            try {
                $out2 = Invoke-WinRM -ScriptBlock {
                    param($id)
                    & "$env:SystemRoot\System32\rwinsta.exe" $id 2>&1
                } -ArgumentList @($sid)
                foreach ($l in $out2) { if ($l) { WLog "    $l" } }
            } catch {
                WLog "rwinsta via WinRM fallito per id=${sid}: $_" 'WARN'
            }
        }
    }
    else {
        $out1 = Invoke-ServerLogoffWithTimeout `
            -SessionId $sid `
            -Source $Source `
            -LogoffExe $logoffExe `
            -RwinstaExe $rwinstaExe `
            -TimeoutSec $LogoffTimeoutSec `
            -Force:$Force

        if ($out1.Count -eq 1 -and $out1[0] -eq "__TIMEOUT__") {
            WLog "logoff id=$sid si è bloccato oltre ${LogoffTimeoutSec}s (Force=$($Force.IsPresent))" 'WARN'
        } else {
            foreach ($l in $out1) { if ($l) { WLog "    $l" } }
        }
    }
}

# 3) Verifica residui
Start-Sleep -Seconds 2

try {
    if ($useWinRM) {
        $qOut2 = Invoke-WinRM -ScriptBlock { quser.exe 2>&1 } -ArgumentList @()
    } else {
        $qOut2 = & "$env:SystemRoot\System32\quser.exe" "/server:$Source" 2>&1
    }
} catch {
    WLog "verifica finale fallita: $_" 'WARN'
    # se non posso verificare, considero comunque fallimento "prudente"
    return 0
}

$left = Get-SessionsFromQuser -Lines $qOut2 -UserName $userShort
if ($left -and $left.Count -gt 0) {
    WLog ("sessioni residue dopo kill: {0}" -f (($left | ForEach-Object { "$($_.SessionId):$($_.State)" }) -join ', ')) 'ERROR'
    return 0
}

WLog "tutte le sessioni terminate (OK)"
return 1