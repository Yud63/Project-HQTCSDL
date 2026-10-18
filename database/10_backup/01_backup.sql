/* ============================================================
   File    : database/10_backup/01_backup.sql
   Purpose : Mẫu Full / Differential / Log backup. CHẠY TAY, không nằm trong 99_run_all.sql
   Lưu ý   : Sửa đường dẫn @path cho đúng máy (thư mục SQL Server có quyền ghi).
   ============================================================ */
USE master;
GO

-- DECLARE @path NVARCHAR(260) = N'C:\SQLBackup\';
-- BACKUP DATABASE FilmLabDB TO DISK = @path + N'FilmLabDB_full.bak' WITH INIT, COMPRESSION, CHECKSUM;
-- BACKUP DATABASE FilmLabDB TO DISK = @path + N'FilmLabDB_diff.bak' WITH DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM;
-- BACKUP LOG      FilmLabDB TO DISK = @path + N'FilmLabDB_log.trn'  WITH INIT, COMPRESSION, CHECKSUM;
-- TODO: hoàn thiện + kịch bản demo (xoá thử dữ liệu rồi restore)
