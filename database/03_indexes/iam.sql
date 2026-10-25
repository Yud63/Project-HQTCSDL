/* ============================================================
   File    : database/03_indexes/iam.sql
   Module  : iam - M1 Identity & Access
   Purpose : Index của M1 Identity & Access (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
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

CREATE UNIQUE NONCLUSTERED INDEX UX_Users_Email
    ON iam.Users (Email)
    WHERE IsDeleted = 0;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Addresses_Default
    ON iam.Addresses (UserId)
    WHERE IsDefault = 1 AND IsDeleted = 0;
GO
