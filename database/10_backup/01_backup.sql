/* ============================================================
   File    : database/10_backup/01_backup.sql
   Purpose : Demo Full / Differential / Log backup + xóa nhầm có MARK. CHẠY TAY, không nằm trong 99_run_all.sql
   Lưu ý   : Sửa @path nếu cần (thư mục SQL Server có quyền ghi). Chạy xong chạy tiếp 02_restore.sql.
   ============================================================ */
USE master;
GO
DECLARE @path NVARCHAR(260) = N'C:\SQLBackup\';
DECLARE @full NVARCHAR(260) = @path + N'FilmLabDB_full.bak';
DECLARE @diff NVARCHAR(260) = @path + N'FilmLabDB_diff.bak';
DECLARE @log1 NVARCHAR(260) = @path + N'FilmLabDB_log1.trn';
DECLARE @log2 NVARCHAR(260) = @path + N'FilmLabDB_log2.trn';

EXEC master.dbo.xp_create_subdir @path;
ALTER DATABASE FilmLabDB SET RECOVERY FULL;   -- cần để backup log

-- 1. FULL
BACKUP DATABASE FilmLabDB TO DISK = @full WITH INIT, COMPRESSION, CHECKSUM;
RESTORE VERIFYONLY FROM DISK = @full WITH CHECKSUM;

-- 2. Bảng demo + 3 dòng A
DROP TABLE IF EXISTS FilmLabDB.dbo.BackupDemo;
CREATE TABLE FilmLabDB.dbo.BackupDemo (Id INT IDENTITY PRIMARY KEY, Note NVARCHAR(50) NOT NULL);
INSERT FilmLabDB.dbo.BackupDemo (Note) VALUES (N'A1'), (N'A2'), (N'A3');

-- 3. DIFFERENTIAL
BACKUP DATABASE FilmLabDB TO DISK = @diff WITH DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM;

-- 4. Thêm 2 dòng B rồi LOG 1
INSERT FilmLabDB.dbo.BackupDemo (Note) VALUES (N'B1'), (N'B2');
BACKUP LOG FilmLabDB TO DISK = @log1 WITH INIT, COMPRESSION, CHECKSUM;

-- 5. "Xóa nhầm" có đánh dấu để restore dừng ngay trước nó
BEGIN TRAN XoaNham WITH MARK N'Xoa nham BackupDemo';
    DELETE FROM FilmLabDB.dbo.BackupDemo;
COMMIT;

-- 6. LOG 2 (chứa dấu XoaNham)
BACKUP LOG FilmLabDB TO DISK = @log2 WITH INIT, COMPRESSION, CHECKSUM;

SELECT COUNT(*) AS RowsAfterDelete FROM FilmLabDB.dbo.BackupDemo;   -- 0
GO