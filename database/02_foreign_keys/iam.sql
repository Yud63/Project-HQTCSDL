/* ============================================================
   File    : database/02_foreign_keys/iam.sql
   Module  : iam - M1 Identity & Access
   Purpose : Không có FK liên module cho M1 Identity & Access.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (gốc)
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- (không có FK liên module)
