# deso_efc_update_metadata

## Scopo

Aggiorna i metadati dell'istanza Morpheus valorizzando le `customOptions` relative a hostname, IP, FQDN e dominio.

## Script

- `deso_efc_update_metadata.py`

## Contesto di esecuzione

- Piattaforma: Morpheus
- Target: Resource
- Shell elevata: no
- Output: JSON
- Visibilita: Private

## Logica

Lo script legge i dati dell'istanza dal contesto `morpheus`, calcola un suffisso breve in Base62 a partire dall'MD5 del nome istanza e lo aggiunge all'hostname originale.

Aggiorna quindi le seguenti `customOptions`:

- `instance-hostname`
- `instance-ip`
- `instance-fqdn`
- `instance-domain`

Il dominio impostato e `easyfattincloud.it`.

## Dipendenze

- Python 3
- Libreria `requests`
- Token API Morpheus disponibile nel contesto di esecuzione

## Esito

In caso di successo stampa un JSON con:

- `hostname`
- `domain`
- `url`
- `ipv4`

In caso di errore stampa un JSON con stato `error` ed esce con codice `1`.
