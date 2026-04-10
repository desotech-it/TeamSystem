# Credenziali cifrate (single-domain)

`Scopo`: genera e salva, in formato XML protetto (Export-Clixml), **una sola** credenziale (`cred_runas.xml`) per eseguire gli script.

Il file risultante può essere decifrato **solo** dallo stesso account Windows che lo ha creato, sullo stesso computer (DPAPI).

---

## Come creare la credenziale (una tantum)

1. Apri **PowerShell** con “Esegui come un altro utente” (o fai log-on) usando l’account che lancerà gli script.
2. Posizionati nella cartella degli script.
3. Esegui:

```powershell
# Scegli un account che abbia i permessi necessari (AD + share/NTFS)
Get-Credential -UserName 'file\administrator' |
  Export-Clixml '.\creds\cred_runas.xml'
```

4. Nel `config.psd1` imposta:
   - `UseStoredCredentials = $true`
   - `CredFiles.RunAs = 'creds\cred_runas.xml'`

---

## Quando rigenerarla

- È stata cambiata/scaduta la password dell’account usato.
- Il pacchetto di script viene spostato su un altro server/workstation.
- Cambia l’utente Windows che esegue gli script (DPAPI è legato al SID).
- Vuoi modificare il percorso di output del file `.xml`.

---

## Riepilogo

Viene creato **un solo** file:

```text
┌───────────────┬───────────────────────────────────────────────┐
│ File XML       │ Scopo                                         │
├───────────────┼───────────────────────────────────────────────┤
│ cred_runas.xml │ Credenziale unica (AD + share/NTFS)          │
└───────────────┴───────────────────────────────────────────────┘
```

Percorso consigliato (relativo alla cartella script):
- `.\creds\cred_runas.xml`
