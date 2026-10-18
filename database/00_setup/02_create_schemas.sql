/* ============================================================
   File    : database/00_setup/02_create_schemas.sql
   Purpose : Tạo 9 schema, mỗi schema = 1 module
   Lưu ý   : KHÔNG dùng tên "sys" (schema hệ thống của SQL Server) -> module M10 dùng "audit"
   ============================================================ */
USE FilmLabDB;
GO

IF SCHEMA_ID(N'iam')   IS NULL EXEC(N'CREATE SCHEMA iam   AUTHORIZATION dbo;');  -- M1  Identity & Access
IF SCHEMA_ID(N'lab')   IS NULL EXEC(N'CREATE SCHEMA lab   AUTHORIZATION dbo;');  -- M2  Lab & Catalog
IF SCHEMA_ID(N'ord')   IS NULL EXEC(N'CREATE SCHEMA ord   AUTHORIZATION dbo;');  -- M3+M6 Order, Payment, Review, Complaint
IF SCHEMA_ID(N'dlv')   IS NULL EXEC(N'CREATE SCHEMA dlv   AUTHORIZATION dbo;');  -- M4  Delivery
IF SCHEMA_ID(N'arc')   IS NULL EXEC(N'CREATE SCHEMA arc   AUTHORIZATION dbo;');  -- M5  Digital Archive
IF SCHEMA_ID(N'mkt')   IS NULL EXEC(N'CREATE SCHEMA mkt   AUTHORIZATION dbo;');  -- M7  Marketplace
IF SCHEMA_ID(N'com')   IS NULL EXEC(N'CREATE SCHEMA com   AUTHORIZATION dbo;');  -- M8  Community
IF SCHEMA_ID(N'ai')    IS NULL EXEC(N'CREATE SCHEMA ai    AUTHORIZATION dbo;');  -- M9  AI Support
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit AUTHORIZATION dbo;');  -- M10 System / Audit
GO
