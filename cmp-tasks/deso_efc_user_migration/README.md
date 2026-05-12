# deso_efc_user_migration

## Scopo

Prepara e avvia la migrazione dati utente per istanze DANEA EFC, creando un file dichiarativo nella coda del dispatcher e aggiornando lo stato migrazione su Morpheus.

## Script

- `deso_efc_user_migration.ps1`

## Contesto di esecuzione

- Piattaforma: Morpheus
- Target: Resource
- Shell elevata: si
- Output: none
- Visibilita: Public

## Parametri Morpheus usati

- `customOptions.MigrateData`
- `customOptions.fromUser`
- `customOptions.fromServer`
- `instance.containers[0].server.internalIp`
- `instance.name`
- `instance.id`
- `morpheus.applianceUrl`
- `morpheus.apiAccessToken`

## Segreti Cypher richiesti

- `secret/EFC-TS_MIG_DANEA-USR`: username per la connessione al dispatcher
- `secret/EFC-TS_MIG_DANEA_SSH`: chiave privata SSH, preferibilmente codificata Base64

La chiave SSH puo essere generata in formato Base64 con:

```bash
base64 -i chiave | tr -d '\n'
```

## Logica

Se `MigrateData` non vale `true`, lo script termina senza eseguire la migrazione.

Quando la migrazione e richiesta:

- valida credenziali e parametri obbligatori
- prepara temporaneamente la chiave SSH
- registra la host key del dispatcher
- apre una sessione PowerShell remota via SSH
- crea il file di coda per il dispatcher
- monitora lo stato della migrazione tramite file remoti
- aggiorna `MigrationStatus` su Morpheus con `running`, `completed` o `failed`

## Dispatcher

- IP dispatcher: `10.182.1.11`
- Coda remota: `D:\tools\migration-tool-st\incoming`

## Esito

Lo script scrive log operativi su standard output e termina con codice `0` in caso di completamento corretto. In caso di errore aggiorna, quando possibile, `MigrationStatus` a `failed` ed esce con codice `1`.
