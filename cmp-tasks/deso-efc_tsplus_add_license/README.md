# deso-efc_tsplus_add_license

## Scopo

Configura la licenza TSPlus per gli utenti sui server DANEA EFC.

## Script

- `deso-efc_tsplus_add_license.ps1`

## Contesto di esecuzione

- Piattaforma: Morpheus
- Target: Resource
- Shell elevata: si
- Output: none
- Visibilita: Public

## Parametri Morpheus usati

- `instance.name`
- `customOptions.licenseUsers`

## Logica

Lo script legge il nome della VM e il numero utenti richiesto da `licenseUsers`.

Se `licenseUsers` e valorizzato con un numero intero, usa quel valore. In caso contrario usa il default di `5` utenti.

## Nota operativa

Il comando effettivo di attivazione TSPlus e presente nello script ma attualmente commentato:

```powershell
& "C:\Program Files (x86)\TSplus\UserDesktop\files\AdminTool.exe" /vl /activate ... /users $users /edition Enterprise /supportyears 0 /comments $nomevm
```

Per rendere effettiva l'attivazione, verificare chiave licenza e parametri, poi decommentare il comando.

## Esito

Lo script stampa i dettagli della configurazione e un messaggio di successo.
