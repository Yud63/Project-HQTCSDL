/* ============================================================
   File    : database/00_setup/01_create_database.sql
   Purpose : Tạo database FilmLabDB (SQL Server 2022, compat level 160)
   Param   : $(REBUILD) = 1 -> DROP rồi tạo lại từ đầu (dùng khi dev / CI)
                         = 0 -> giữ nguyên nếu đã tồn tại
   Chạy qua: database/99_run_all.sql (cần SQLCMD mode)
   ============================================================ */
USE master;
GO

IF '$(REBUILD)' = '1' AND DB_ID(N'FilmLabDB') IS NOT NULL
BEGIN
    ALTER DATABASE FilmLabDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE FilmLabDB;
END
GO

IF DB_ID(N'FilmLabDB') IS NULL
    CREATE DATABASE FilmLabDB COLLATE Vietnamese_100_CI_AS;
GO

ALTER DATABASE FilmLabDB SET COMPATIBILITY_LEVEL = 160;  -- SQL Server 2022
ALTER DATABASE FilmLabDB SET RECOVERY FULL;              -- cho phép backup log (10_backup)
GO
