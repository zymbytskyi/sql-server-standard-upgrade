# SQL Server Standard Edition Upgrade — v0.1.0-preview1

Local SQL Server 2017 Standard to **2022 or 2025 Standard**, using an interactive Setup Wizard with a pinned CU-branch update. This separate preview does not change the Express package. **Not yet qualified for production: licensed Standard media and visible Wizard qualification are still required. Developer engine rehearsals are documented separately.**

## Install and open the menu

Sign in to the SQL server itself with a Windows account that is a local administrator and SQL sysadmin. Open **64-bit Windows PowerShell as administrator** and run:

```powershell
$ErrorActionPreference = 'Stop'
$networkSettings = [Net.ServicePointManager]
$networkSettings::SecurityProtocol = 'Tls12'
$installer = Join-Path $env:TEMP 'Install-SqlServerStandardEditionUpgrade-preview1.ps1'
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/zymbytskyi/sql-server-standard-upgrade/v0.1.0-preview1/Bootstrap.ps1' -OutFile $installer
Unblock-File -LiteralPath $installer
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
& $installer
```

The bootstrap downloads the exact versioned release ZIP and checks its pinned SHA-256 before extraction. Installation opens the local menu; it does not upgrade SQL. Repeating installation reuses identical files and preserves different existing files. For an offline transfer, extract the verified release ZIP and run `Install.ps1` from that directory. Use `-NoLaunch` to install without opening the menu.

Reopen the installed menu, including after restarting Windows:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
& 'C:\Tools\SqlServerStandardEditionUpgrade-v0.1.0-preview1\Start-SqlServerUpgrade.ps1'
```

The script discovers local running SQL 2017 Standard instances. With more than one, choose the intended instance. There is no Hyper-V VM name or remote SQL server prompt. For a separate campaign/instance use a separate runtime:

```powershell
& 'C:\Tools\SqlServerStandardEditionUpgrade-v0.1.0-preview1\Start-SqlServerUpgrade.ps1' -InstanceName 'APPDATA' -WorkRoot 'D:\SqlUpgradeCampaign-APPDATA'
```

Keep that same `-WorkRoot` on every subsequent invocation. Do not use an Express runtime directory.

## Before downtime

1. **Menu 1 — Prepare.** Choose 2022 or 2025 and supply a local/UNC path to the licensed target Standard ISO. Confirm entitlement and media edition. The ISO may be RTM: the tool copies it locally, obtains the newest CU-branch build from Microsoft's catalog, and asks you to approve the update after reviewing its known issues and application support. If automatic URL resolution fails, supply the exact Microsoft package URL. Internet access is needed during preparation.
2. Preparation validates Microsoft signatures, records SHA-256 hashes, and pins the update/build. The media and update remain separate directories; Setup uses `/UpdateEnabled=True /UpdateSource=...` to integrate the update. The tool does not silently fall back to RTM or choose a different update on upgrade day. Read the generated `UPGRADE-PLAN.txt` and `ROLLBACK-PLAN.txt` in the runtime directory.
3. **Menu 2 — Backups.** Choose the recommended local drive/folder or another local path. Recommendations use available space and estimated database allocation. Allow time for COPY_ONLY/CHECKSUM backups, hashes and VERIFYONLY. Copy recovery files off-server; the tool does not perform that copy.
4. **Menu 6 — Recovery.** Record an existing tested full-server recovery point, provider and exact restore procedure/operator. For Hyper-V, the recovery action belongs on the host/provider console, not inside this local SQL tool. Recording a reference does not create or test a VM backup. Retain the package, campaign files and original SQL 2017 backups off-server.
5. Optional **menu 7** restores user databases into scratch databases and runs CHECKDB. This needs additional storage and I/O. VERIFYONLY alone is not a restore rehearsal. Failed scratch databases remain for investigation.

The copied ISO can contain a licensed target PID. The runtime is restricted to administrators/SYSTEM; protect off-server copies too. The tool never extracts the old SQL 2017 key. Software Assurance entitlement does not make a 2017 key a target-version key. Obtain the licensed target media through your licensing channel; if Setup requests a target key, enter it there, never in a script or log.

## Upgrade window

1. Stop application writers and coordinate scheduled SQL Agent jobs. Capture the agreed recovery point and final **menu 2** backups; copy them off-server.
2. Resolve any pending Windows restart, reopen the same menu/runtime, then choose **3 — Final readiness**. Read `FINAL-READINESS.txt`: backup time/age/paths, update/build and failure reason. The check validates media, backup availability, OS, disk space, source identity and Agent metadata. Capacity thresholds are minimum guards, not a workload-specific sizing guarantee. Technical readiness is not application-owner approval.
3. Choose **4 — Upgrade Wizard**. Confirm the selected local instance. On Product Key/edition, confirm **Standard** and your licensed target media. On Product Updates, confirm the pinned KB is included; keep updates selected. Review feature/rule checks and Ready to Upgrade, then click **Upgrade**. Cancel if edition, instance or update differs. No unattended upgrade runs.
4. Review Complete and Setup logs under `%ProgramFiles%\Microsoft SQL Server\160\Setup Bootstrap\Log` (2022) or `170` (2025). Close Setup and restart Windows in the agreed window.
5. Reopen the menu using the command above; choose **5 — Verify**. It requires a real restart, the exact approved engine build, Standard edition, databases online, original user compatibility levels and matching Agent metadata/service account/start mode (or an explicit approval for exact reviewed step changes). Read `COMPLETION.txt`. Test application logins, reads/writes, jobs and performance before restoring traffic.

If Setup fails or is cancelled, preserve logs and inspect actual engine state before retrying. The tool does not automatically repair failed Setup or roll back a server. Do not erase campaign files to bypass a failed check. Preparation cannot replace media after Wizard launch; use a new campaign only after establishing a known source baseline.

## Rollback

Read the generated instance-specific `ROLLBACK-PLAN.txt`. Keep writers stopped, agree the data-loss point, preserve logs and later writes externally, and use the recorded provider procedure to restore the entire pre-upgrade server. There is no in-place engine downgrade; target-version database backups cannot be restored to SQL 2017.

After restoring the original server and making its original campaign available, run:

```powershell
& 'C:\Tools\SqlServerStandardEditionUpgrade-v0.1.0-preview1\Verify-Recovery.ps1' -WorkRoot 'C:\SqlServerUpgradeData'
```

This script **verifies** the original build, edition, databases and Agent metadata and runs CHECKDB. It does not restore a VM/database. Check domain trust and application behavior separately before reopening traffic.

## Initial supported scope and validation

- English x64 SQL 2017 Standard, standalone, Database Engine and SQL Agent, Windows authentication.
- Source Windows Server 2016/2019/2022; target 2025 requires Server 2019/2022. Member server or standalone host; no domain controller.
- AG/FCI, TDE, replication, database snapshots and installed Full-Text are blocked. SSIS/SSRS/SSAS, linked-server/provider migration and application compatibility are not qualified by this package.
- [Validation record](VALIDATION.md) distinguishes fixture checks from live SQL qualification.

Microsoft references: [servicing catalog](https://support.microsoft.com/en-us/servicing/sql/kb321185-download-and-install-latest-updates), [2025 upgrade paths](https://learn.microsoft.com/en-us/sql/database-engine/install-windows/supported-version-and-edition-upgrades-2025), [2025 OS requirements](https://learn.microsoft.com/en-us/sql/sql-server/install/hardware-and-software-requirements-for-installing-sql-server-2025), [SQL licensing guidance](https://www.microsoft.com/licensing/guidance/SQL).

## Developer laboratory mode

Use `-LabDeveloper` explicitly with both Start-SqlServerUpgrade.ps1 and Verify-Recovery.ps1, and a separate `-WorkRoot`. This mode accepts Developer only, records the mode in the campaign and refuses to reopen it in production mode. The default still accepts Standard only. Developer 2017 uses Developer 2022 or Enterprise Developer 2025 target media. A Developer test validates the workflow, not Standard licensing or edition-specific behavior. No new VM is required.

```powershell
& .\Start-SqlServerUpgrade.ps1 -LabDeveloper -InstanceName DEV2017 -WorkRoot C:\SqlStandardLab2022
```


## SQL Agent step review after an upgrade

SQL Setup can change the built-in `syspolicy_purge_history` job. Menu 5 blocks on changed steps rather than silently ignoring them. If this happens, use **menu 9**: it displays job names, step IDs and before/after hashes. In SSMS, inspect **SQL Server Agent > Jobs > Properties > Steps** and compare with the original definition or the original `msdb` backup. Explain why the changes are expected and type `APPROVE-STEPS` only after review. Run menu 5 again.

The approval records the campaign, approved target build and exact before/after step hashes in `agent-step-review.json`. A further change invalidates it. Job identities/owners/enabled states, schedules, operators, proxies, credentials and service checks remain strict. Recovery verification always compares against the original baseline without this exception.

## Prepared local lab

The reused VM is **SQLEXPRESS17**, Windows Server 2022. Its **DEV2017** instance is SQL 2017 Developer; the separate **SQLEXPRESS** instance remains SQL 2017 Express. No additional VM is required. On that VM, open Windows PowerShell as administrator and choose a prepared target:

```powershell
# Rehearse 2017 -> 2022 Developer
& 'C:\StandardUpgradeLab\Package\Start-SqlServerUpgrade.ps1' -LabDeveloper -WorkRoot 'C:\SqlStandardLab2022'

# Alternatively, rehearse 2017 -> 2025 Enterprise Developer
& 'C:\StandardUpgradeLab\Package\Start-SqlServerUpgrade.ps1' -LabDeveloper -WorkRoot 'C:\SqlStandardLab2025'
```

Run only one target before restoring the common checkpoint **SQL2017Developer-Ready-20261026** on the Hyper-V host. Never upgrade the already-upgraded instance with the other prepared SQL 2017 campaign. Both recovery plans refer to that common source checkpoint. **Before-StandardDeveloperLab-20261026** preserves the original Express-only VM state. Older pre-existing Express checkpoints were retained. The intermediate 2022 checkpoint was retired after the tested recovery; its historical evidence is retained on the host.
