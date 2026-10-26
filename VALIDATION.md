# Validation — v0.1.0-preview1

Status: public preview, not production-qualified. No Standard instance was upgraded, restarted or restored during this implementation.

## Completed

- Windows PowerShell 5.1 isolated fixture suite: target mapping, OS gates, local instance names, Standard scope, CU-branch catalog ordering, cross-version/RTM rejection, exact build acceptance, Agent metadata checks, backup manifest isolation/cache, changed media and update hashes, and mixed UpdateSource rejection.
- Read-only live Microsoft servicing catalog resolution on 2026-10-26: SQL 2022 CU27+GDR KB5126934 / 16.0.4305.5; SQL 2025 CU10 KB5125471 / 17.0.5035.5. These are observations, not hardcoded production targets.
- The previous Express engine rehearsal is design evidence only; it does not qualify Standard or SQL 2025.

Run the fixture suite without SQL or media:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SqlServerUpgrade.ps1
```

- Installer smoke test: first installation and identical repeat succeeded; a modified destination was rejected without overwriting it. Menu/SQL was not launched.
- Repository validation: 22 PASS, 0 FAIL, one existing dirty-working-tree warning.

## Required before release qualification

1. Supply licensed English Standard 2022 and 2025 ISO files. Validate media layout, mount ownership/cleanup and actual target licensing behavior.
2. On isolated SQL 2017 Standard copies, exercise actual Prepare, backups, permissions, restore rehearsal and final readiness for each target. Include named/default instances and representative Agent jobs/proxies/schedules.
3. Complete the visible Wizard using pinned CU/CU-security updates. Confirm Product Updates, exact resulting engine build, restart and application acceptance. Test both supported target years independently.
4. Restore the external full-server recovery point, run Verify-Recovery and validate domain trust and application functionality. Record evidence outside Git.
5. Test interrupted download/Setup, insufficient space, unavailable backup storage and pending restart on the real lab environment.

Current recovery integration records a provider runbook and verifies recovery. It does not automate Hyper-V restoration or prove an external recovery point is usable.


## Developer lab findings — 2026-10-26

The existing SQLEXPRESS17 VM runs Windows Server 2022 (20348). A separate DEV2017 Developer instance was installed alongside the preserved Express instance. No new VM was created. SQLEXPRESS01 was initially inspected/staged but reverted to its initial checkpoint because its Windows Server 2025 OS is unsuitable for this SQL 2017 source profile; the OS guard was not weakened.

SQL 2017 Developer 14.0.1000.169 to SQL 2022 Developer 16.0.4305.5 (KB5126934): real preparation, COPY_ONLY/CHECKSUM/VERIFYONLY backups, scratch restore/CHECKDB, final readiness, one Setup invocation with UpdateSource, restart, actual package verification, synthetic reads/writes and all-database CHECKDB passed. Setup returned 3010. The Express instance remained 14.0.1000.169; domain trust passed. Full-VM checkpoint rollback restored Developer 14.0.1000.169 and the pre-upgrade row count; the generated recovery verifier and domain trust passed.

The engine rehearsal used package-generated arguments with `/UIMODE=Normal` replaced by `/Q` and license acceptance for the isolated lab. It does not qualify the visible Wizard click-through. SQL Setup changed the built-in `syspolicy_purge_history` steps; the custom job step hash was unchanged. Verification correctly blocked until a specific lab review was recorded. New regression tests bind approvals to exact step hashes and ensure all other Agent checks remain strict.

The guest update download initially showed no transferred bytes but eventually completed successfully. Microsoft signature and the published SHA-256 matched. A library import variable collision found in the host validation harness was fixed and regression-tested.

Evidence is outside Git under `C:\AI\Data\sqlserver-alwayson-lab\Hyper-V\StandardUpgradeLabAcceptance\2022`. This is Developer workflow evidence, not Standard license/edition qualification. SQL 2025 engine results are below.

SQL 2017 Developer 14.0.1000.169 to SQL 2025 Enterprise Developer 17.0.5035.5 (KB5125471): actual ISO preparation, pre-fetched Microsoft-signed CU validation, backups, scratch restore/CHECKDB, final readiness, one integrated Setup invocation, restart, actual package verification and synthetic reads/writes passed. Setup returned 3010. All-database CHECKDB, preserved Express 14.0.1000.169 and domain trust passed. Only the built-in policy job steps required explicit lab review; the synthetic job remained unchanged. Evidence is in the corresponding `StandardUpgradeLabAcceptance\2025` directory outside Git.

The 2025 full-VM rollback also passed the generated recovery verifier, all-database CHECKDB, restored single-row baseline and domain trust. Final VM state is SQL 2017 Developer and SQL 2017 Express, both 14.0.1000.169. The common SQL2017Developer-Ready-20261026 checkpoint and the original Express-only Before-StandardDeveloperLab-20261026 point remain; the intermediate 2022 point was retired. Temporary Hyper-V file-copy integration was restored to disabled. The laboratory remains subject to the Standard-media, visible-Wizard and representative application/workload qualification requirements above; the small synthetic database is not a large-database performance test.
