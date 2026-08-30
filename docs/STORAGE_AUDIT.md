# SQL Server Storage Audit

Audit date: 2026-07-31

Server: `DESKTOP-HBA9S76\SQLEXPRESS01`

## Active F-Drive Layout

- Final Japan target: `japan_cohort_cdm_500k_final`
- Final target data file: 153,600 MB on `F:\database\data`
- Final target log file: 51,200 MB on `F:\database\log`
- `tempdb` data: `F:\database\data\tempdb.mdf`, initial size 10,240 MB
- `tempdb` log: `F:\database\log\templog.ldf`, initial size 5,120 MB

The Japan and Korea runners default new target files to those F-drive
directories with a 4,096 MB growth increment. They validate environment or CLI
paths before connecting and verify actual target paths through
`sys.master_files`.

F: had approximately 802.2 GB free before the final Japan cost load. This is a
historical checkpoint, not a substitute for checking current free space before
another large run.

## Remaining C-Drive Exposure

- The SQL Server instance default data and log directories are still on C:.
  Explicit runner paths prevent new packaged targets from silently using those
  defaults.
- Korea RAW database `nhisnsc2013original` remains on C: at approximately
  40,840 MB data and 1,352 MB log. Reading it during Korea ETL can still
  compete with normal desktop work.
- Old physical `tempdb` files may remain on C: after the move. They are not
  active SQL Server files once `sys.master_files` points to F:, but removal
  should be a separately reviewed administrator action.
- Small historical databases on C: are outside the final package workflow.

## Operating Rule

Do not run two large ETL stages, a large ETL stage and full QA, or two full QA
scans at the same time. Check SQL Server activity and disk queue before each
large stage. The storage guards prevent target misplacement; they cannot
eliminate read I/O against the Korea RAW database on C:.

Moving the Korea RAW database or deleting inactive historical files is a
separate SQL Server administration task and is not performed automatically by
the ETL package.
