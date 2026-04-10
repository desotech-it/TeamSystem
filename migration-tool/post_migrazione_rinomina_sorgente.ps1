[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$User,
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination,

    # Parametri opzionali (per compatibilità con la chiamata da migrazione.ps1).
    [Parameter()][string]$SrcDriveLetter,
    [Parameter()][string]$DstDriveLetter,
    [Parameter()][pscredential]$Credential,
    [Parameter()][string]$LogFile
)

# --- Config / Log ---
$Cfg     = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
$BaseDir = if ($Cfg.BaseDir) { $Cfg.BaseDir } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$LogDir  = Join-Path $BaseDir 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# Se non viene passato un LogFile "di sessione", ne creo uno dedicato a questo step.
if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $LogFile = Join-Path $LogDir ("post_migra_{0}_{1:yyyyMMdd_HHmmss}.log" -f $User,(Get-Date))
}

function WLog ([string]$Msg,[ValidateSet('INFO','WARN','ERROR')]$Lvl='INFO') {
    '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date),$Lvl,$Msg |
        Out-File $LogFile -Append -Encoding utf8
    if($Lvl -eq 'ERROR'){Write-Host $Msg -ForegroundColor Red}else{Write-Host $Msg}
}

# Log storico (sempre lo stesso file, append).
$HistoryFile = Join-Path $LogDir 'storico_migrazioni.log'

function Resolve-IPv4([string]$HostOrIp) {
    try {
        $ip = [System.Net.Dns]::GetHostAddresses($HostOrIp) |
              Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
              Select-Object -First 1
        if ($ip) { return $ip.IPAddressToString }
    } catch { }
    return $HostOrIp
}

function Append-History([string]$Outcome) {
    $srcIP = Resolve-IPv4 $Source
    $dstIP = Resolve-IPv4 $Destination
    $line  = '{0:yyyy-MM-dd HH:mm:ss};{1};{2};{3};{4}' -f (Get-Date),$User,$srcIP,$dstIP,$Outcome
    $line | Out-File $HistoryFile -Append -Encoding utf8
}

# --- Helper: mappa drive se mancano ---
function Ensure-Drive {
    param(
        [Parameter(Mandatory)][string]$Letter,
        [Parameter(Mandatory)][string]$UncRoot,
        [Parameter()][pscredential]$Cred
    )

    if (Get-PSDrive $Letter -ErrorAction SilentlyContinue) { return }

    if ($null -ne $Cred) {
        New-PSDrive -Name $Letter -PSProvider FileSystem -Root $UncRoot -Credential $Cred -Persist -Scope Global -ErrorAction Stop | Out-Null
    } else {
        New-PSDrive -Name $Letter -PSProvider FileSystem -Root $UncRoot -Persist -Scope Global -ErrorAction Stop | Out-Null
    }
}

# Valori default drive da config, se non passati.
if ([string]::IsNullOrWhiteSpace($SrcDriveLetter)) { $SrcDriveLetter = $Cfg.SrcDriveLetter }
if ([string]::IsNullOrWhiteSpace($DstDriveLetter)) { $DstDriveLetter = $Cfg.DstDriveLetter }

$Outcome = 'ERROR'

WLog "=== post-migrazione: rinomina cartella sorgente avviata ==="
WLog "parametri: User=$User Source=$Source Destination=$Destination SrcDrive=$SrcDriveLetter DstDrive=$DstDriveLetter"

try {
    # Assicura che i drive esistano (in migrazione.ps1 dovrebbero già esserci).
    Ensure-Drive -Letter $SrcDriveLetter -UncRoot "\\$Source\d$" -Cred $Credential
    Ensure-Drive -Letter $DstDriveLetter -UncRoot "\\$Destination\c$" -Cred $Credential

    $srcPath = "${SrcDriveLetter}:\users\$User"
    $dstPath = "${DstDriveLetter}:\Danea"
    $newName = "${User}_migrated"
    $srcUsersRoot = "${SrcDriveLetter}:\users"
    $targetPath = Join-Path $srcUsersRoot $newName

    # Check 1: destinazione esiste.
    if (-not (Test-Path $dstPath)) {
        throw "check fallito: cartella destinazione non trovata: $dstPath"
    }

    # Check 2: sorgente esiste oppure è già stata rinominata.
    if (-not (Test-Path $srcPath)) {
        if (Test-Path $targetPath) {
            WLog "sorgente già rinominata: $targetPath"
            $Outcome = 'SUCCESS'
            Append-History $Outcome
            WLog "=== post-migrazione: completato (già rinominata) ==="
            return 1
        }
        throw "check fallito: cartella sorgente non trovata: $srcPath"
    }

    # Check 3 (quick): se sorgente ha contenuti top-level, anche destinazione deve averne.
    $srcTopCount = (Get-ChildItem $srcPath -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    $dstTopCount = (Get-ChildItem $dstPath -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    WLog "check contenuti top-level: src=$srcTopCount dst=$dstTopCount"
    if ($srcTopCount -gt 0 -and $dstTopCount -eq 0) {
        throw "check fallito: sorgente non vuota ma destinazione vuota (top-level)."
    }

    # Check 4: collisione nome target.
    if (Test-Path $targetPath) {
        throw "collisione: esiste già la cartella target: $targetPath"
    }

    # Rinomina.
    WLog "rinomina sorgente: '$srcPath' -> '$newName'"
    Rename-Item -Path $srcPath -NewName $newName -ErrorAction Stop

    # Verifica post-rinomina.
    if (-not (Test-Path $targetPath)) {
        throw "verifica fallita: dopo rinomina non trovo $targetPath"
    }

    WLog "rinomina completata: $targetPath"
    $Outcome = 'SUCCESS'
    Append-History $Outcome
    WLog "=== post-migrazione: completato con successo ==="
    return 1
}
catch {
    WLog "post-migrazione: ERRORE: $_" 'ERROR'
    $Outcome = 'ERROR'
    Append-History $Outcome
    return 0
}