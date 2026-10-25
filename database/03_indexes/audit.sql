/* ============================================================
   File    : database/03_indexes/audit.sql
   Module  : audit - M10 System / Audit
   Purpose : Index của M10 System / Audit (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (không FK)
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE NONCLUSTERED INDEX IX_Audit_Record
    ON audit.AuditLogs (TableSchema, TableName, PrimaryKeyValue, ChangedAt DESC);
GO

CREATE NONCLUSTERED INDEX IX_Audit_User
    ON audit.AuditLogs (ChangedBy, ChangedAt DESC);
GO
