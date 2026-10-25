/* ============================================================
   File    : database/02_foreign_keys/audit.sql
   Module  : audit - M10 System / Audit
   Purpose : Không có FK liên module cho M10 System / Audit.
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

-- (không có FK liên module)
