@{
    # Impostazioni dominio e controller.
    Domain             = 'ad.easyfattincloud.it'
    DC                 = 'EFC-ADDC-01.ad.easyfattincloud.it'

    # Cartella base (vuota = cartella dello script).
    BaseDir            = ''

    SourceRootTmpl     = '\\{0}\d$\users\{1}'
    TargetRootTmpl     = '\\{0}\c$\Danea'

    # Argomenti comuni per Robocopy.
    RoboArgs = @(
    '/MIR',
    '/MT:32',          # multi-thread (va testato con 16/32/64 a seconda della macchina per performance)
    '/XJ',             # NON seguire junction (risolve i loop Application Data)
    '/R:1','/W:1',     # meno attese su errori/lock
    '/COPY:DATS',       # niente ACL dal sorgente
    '/DCOPY:DA',
    '/NP',             # meno overhead di progress
    '/XD',
    'Y:\users\{0}\Desktop',
    'Y:\users\{0}\Downloads',
    'Y:\users\{0}\Danea Easyfatt'
    )

    # Gestione credenziali.
    UseStoredCredentials = $false
    CredFiles = @{
        RunAs = 'creds\cred_runas.xml'
    }

    # Lettere dei drive.
    SrcDriveLetter     = 'Y'
    DstDriveLetter     = 'Z'

    # Dominio per assegnare le ACL.
    AclIdentityDomain   = 'ad.easyfattincloud.it'

    # Cartella di input per la coda.
    IncomingSubDir      = 'incoming'

    # Flag modalità single-domain.
    SingleDomainMode    = $true
}
