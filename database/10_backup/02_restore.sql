/* ============================================================
   File    : database/10_backup/02_restore.sql
   Purpose : Restore Full -> Diff -> Log 1 -> Log 2 dừng TRƯỚC dấu XoaNham (point-in-time). CHẠY TAY.
   Lưu ý   : Chạy ngay sau 01_backup.sql, KHÔNG dùng -d FilmLabDB, đóng các tab SSMS đang nối FilmLabDB.
   ============================================================ */
USE master;
GO
DECLARE @path NVARCHAR(260) = N'C:\SQLBackup\';
DECLARE @full NVARCHAR(260) = @path + N'FilmLabDB_full.bak';
DECLARE @diff NVARCHAR(260) = @path + N'FilmLabDB_diff.bak';
DECLARE @log1 NVARCHAR(260) = @path + N'FilmLabDB_log1.trn';
DECLARE @log2 NVARCHAR(260) = @path + N'FilmLabDB_log2.trn';

ALTER DATABASE FilmLabDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE FilmLabDB FROM DISK = @full WITH NORECOVERY, REPLACE;
RESTORE DATABASE FilmLabDB FROM DISK = @diff WITH NORECOVERY;
RESTORE LOG      FilmLabDB FROM DISK = @log1 WITH NORECOVERY;
RESTORE LOG      FilmLabDB FROM DISK = @log2 WITH STOPBEFOREMARK = N'XoaNham', RECOVERY;
ALTER DATABASE FilmLabDB SET MULTI_USER;

SELECT COUNT(*) AS RowsAfterRestore FROM FilmLabDB.dbo.BackupDemo;  -- 5 (A1 A2 A3 B1 B2)
GO
-- Dọn demo sau khi kiểm tra xong:
-- DROP TABLE FilmLabDB.dbo.BackupDemo;