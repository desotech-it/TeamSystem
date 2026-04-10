[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$User,
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
)

# Config e log.
$Cfg     = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
$BaseDir = if ($Cfg.BaseDir) { $Cfg.BaseDir } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$LogDir  = Join-Path $BaseDir 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogFile = Join-Path $LogDir ("migra_{0}_{1:yyyyMMdd_HHmmss}.log" -f $User,(Get-Date))

function WLog ($m,[ValidateSet('INFO','WARN','ERROR')]$l='INFO') {
    '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date),$l,$m |
        Out-File $LogFile -Append -Encoding utf8
    if($l -eq 'ERROR'){Write-Host $m -ForegroundColor Red}else{Write-Host $m}
}

Import-Module ActiveDirectory -EA Stop

# Carica una credenziale opzionale, altrimenti usa l'utente corrente.
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

# Esegue uno scriptblock passando le credenziali se disponibili.
function Invoke-WithOptionalCredential {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter()][pscredential]$Credential
    )
    if ($null -ne $Credential) { & $ScriptBlock $Credential } else { & $ScriptBlock $null }
}

# Imposta lettere di drive e percorsi di rete.
$Y = $Cfg.SrcDriveLetter
$Z = $Cfg.DstDriveLetter
$SrcUNC = "\\$Source\d$"
$DstUNC = "\\$Destination\c$"
$SrcHomeUNC = [string]::Format($Cfg.SourceRootTmpl, $Source, $User)
$DstHomeUNC = [string]::Format($Cfg.TargetRootTmpl, $Destination, $User)

# Cerca l'utente in Active Directory.
try {
    $adUser = Invoke-WithOptionalCredential -Credential $credRunAs -ScriptBlock {
        param($c)
        if ($null -ne $c) {
            Get-ADUser -Server $Cfg.DC -Credential $c -Identity $User -EA Stop
        } else {
            Get-ADUser -Server $Cfg.DC -Identity $User -EA Stop
        }
    }
    WLog "utente AD trovato: $($adUser.SamAccountName)"
} catch {
    WLog "utente '$User' non trovato in AD (single-domain). Interrompo." 'ERROR'
    #return 0
}

# Mappa i drive di origine e destinazione.
function Map-Drive {
    param(
        [Parameter(Mandatory)][string]$letter,
        [Parameter(Mandatory)][string]$unc,
        [Parameter()][pscredential]$cred
    )

    if (Get-PSDrive $letter -EA SilentlyContinue) { Remove-PSDrive $letter -EA SilentlyContinue }

    if ($null -ne $cred) {
        New-PSDrive -Name $letter -PSProvider FileSystem -Root $unc -Credential $cred -Persist -Scope Global -EA Stop | Out-Null
    } else {
        New-PSDrive -Name $letter -PSProvider FileSystem -Root $unc -Persist -Scope Global -EA Stop | Out-Null
    }

    WLog "drive ${letter}: mapped -> $unc"
}

# Prima di mappare i drive, tenta di "kickare" eventuali sessioni attive dell'utente sulla macchina sorgente.
try {
    $KickScript = Join-Path $BaseDir 'kick-session.ps1'
    $kickRc = (& $KickScript -User $User -Source $Source -Force | Select-Object -Last 1)
    $kickRc = [int]$kickRc

    if ($kickRc -ne 1) { throw "kick-session rc=$kickRc" }
    WLog "kick session OK per $User su $Source"
} catch {
    WLog "kick session fallito per $User su ${Source}: $_" 'ERROR'
    return 0
}

try   { Map-Drive $Y $SrcUNC $credRunAs }
catch { WLog "map $Y fallita: $_" 'ERROR'; return 0 }

try   { Map-Drive $Z $DstUNC $credRunAs }
catch {
    Remove-PSDrive $Y -EA SilentlyContinue
    WLog "map $Z fallita: $_" 'ERROR'
    return 0
}

$retry = 0
while (-not (Test-Path "${Z}:\" ) -and $retry -lt 5) { Start-Sleep 1; $retry++ }
if (-not (Test-Path "${Z}:\")) {
    WLog "drive ${Z} non accessibile dopo il mapping" 'ERROR'
    Remove-PSDrive $Y -EA SilentlyContinue
    return 0
}

# Esegue la copia con Robocopy.
$RoboExe = "$env:SystemRoot\System32\robocopy.exe"
$RoboLog = Join-Path $LogDir ("robocopy_${User}_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

# Sostituisce {0} con il nome utente nei percorsi esclusi.
$roboArgsFinal = $Cfg.RoboArgs | ForEach-Object {
    if ($_ -like '*{0}*') { $_ -f $User } else { $_ }
}

$RoboArgs = @(
    "${Y}:\users\$User\Documents",
    "${Z}:\Danea"
) + $roboArgsFinal + "/LOG+:$RoboLog"

WLog "run: $RoboExe $($RoboArgs -join ' ')"
$LASTEXITCODE = 0
& $RoboExe @RoboArgs
$rc = $LASTEXITCODE

# Stato step post-migrazione (rinomina cartella sorgente).
$postOk = $true

# Imposta i permessi NTFS per l'utente.
if ($rc -le 2) {
    $aclDom = if ($Cfg.ContainsKey('AclIdentityDomain') -and $Cfg.AclIdentityDomain) { $Cfg.AclIdentityDomain } else { $env:USERDOMAIN }
    $aclCmd = "icacls `"${Z}:\Danea`" /inheritance:r /grant `"${aclDom}\\${User}:(OI)(CI)F`" /T"
    WLog "set ACL: $aclCmd"
    cmd.exe /c $aclCmd | Out-Null
    WLog "permessi NTFS assegnati"

    # Step post-migrazione: rinomina cartella sorgente aggiungendo _migrated.
    $postScript = Join-Path $PSScriptRoot 'post_migrazione_rinomina_sorgente.ps1'
    WLog "post-migrazione: avvio step rinomina cartella sorgente (aggiunta _migrated)"
    try {
        if (-not (Test-Path $postScript)) { throw "script non trovato: $postScript" }
        $postRc = & $postScript -User $User -Source $Source -Destination $Destination -SrcDriveLetter $Y -DstDriveLetter $Z -Credential $credRunAs -LogFile $LogFile
        if ($postRc -ne 1) { throw "rc=$postRc" }
        WLog "post-migrazione: step rinomina completato"
    } catch {
        $postOk = $false
        WLog "post-migrazione: step rinomina FALLITO: $_" 'ERROR'
    }
}

# Smonta i drive e chiude con il risultato.
Remove-PSDrive $Y,$Z -EA SilentlyContinue
WLog "drive $Y e $Z rimossi"

if ($rc -gt 2) { WLog "robocopy error rc=$rc" 'ERROR'; return 0 }
if (-not $postOk) { WLog "post-migrazione fallita: migrazione considerata non completata" 'ERROR'; return 0 }
WLog "copy completed rc=$rc"
return 1