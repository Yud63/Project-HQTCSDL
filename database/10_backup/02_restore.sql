/* ============================================================
   File    : database/10_backup/02_restore.sql
   Purpose : Mẫu Restore (Full -> Diff -> Log, point-in-time). CHẠY TAY.
   ============================================================ */
USE master;
GO

-- ALTER DATABASE FilmLabDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
-- RESTORE DATABASE FilmLabDB FROM DISK = N'C:\SQLBackup\FilmLabDB_full.bak' WITH NORECOVERY, REPLACE;
-- RESTORE DATABASE FilmLabDB FROM DISK = N'C:\SQLBackup\FilmLabDB_diff.bak' WITH NORECOVERY;
-- RESTORE LOG      FilmLabDB FROM DISK = N'C:\SQLBackup\FilmLabDB_log.trn'  WITH RECOVERY;
-- ALTER DATABASE FilmLabDB SET MULTI_USER;
-- TODO: hoàn thiện
