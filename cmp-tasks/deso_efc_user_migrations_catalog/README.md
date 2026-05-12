# deso_efc_user_migrations_catalog

## Scopo

Aggiorna le `customOptions` Morpheus legate alla migrazione dati utente partendo dai valori ricevuti dal Catalog Item.

## Script

- `deso_efc_user_migrations_catalog.ps1`

## Contesto di esecuzione

- Piattaforma: Morpheus
- Target: Resource
- Shell elevata: si
- Output: none
- Visibilita: Public

## Parametri Morpheus usati

- `instance.id`
- `instance.name`
- `instance.containers[0].server.internalIp`
- `instance.config.customOptions.MigrateData`
- `instance.config.customOptions.fromUser`
- `instance.config.customOptions.fromServer`
- `instance.config.customOptions.MigrationStatus`
- `customOptions.MigrateData`
- `customOptions.fromUser`
- `customOptions.fromServer`
- `customOptions.toServer`
- `morpheus.applianceUrl`
- `morpheus.apiAccessToken`

## Logica

Lo script stampa una diagnostica dei valori correnti presenti sull'istanza e dei valori ricevuti dal Catalog Item, poi aggiorna Morpheus impostando:

- `MigrateData` a `true`
- `fromUser` dal Catalog Item
- `fromServer` dal Catalog Item
- `MigrationStatus` a `null`

Il valore `toServer` non viene incluso nel body di update e quindi non viene modificato.

## Esito

In caso di update riuscito stampa un riepilogo delle `customOptions` aggiornate. Se l'update verso Morpheus fallisce, stampa un warning ma lo script completa comunque il flusso diagnostico.
