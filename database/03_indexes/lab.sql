/* ============================================================
   File    : database/03_indexes/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : Index của M2 Lab & Catalog (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE NONCLUSTERED INDEX IX_FilmLabs_Approval_City
    ON lab.FilmLabs (ApprovalStatus, City)
    INCLUDE (AvgRating);
GO

CREATE NONCLUSTERED INDEX IX_LabServices_Search
    ON lab.LabServices (LabId, ServiceTypeId, FormatId)
    INCLUDE (UnitPrice, TurnaroundDays);
GO

CREATE SPATIAL INDEX SIX_FilmLabs_Location
    ON lab.FilmLabs (Location)
    USING GEOGRAPHY_AUTO_GRID;
GO
