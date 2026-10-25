/* ============================================================
   File    : database/03_indexes/ord_feedback.sql
   Module  : ord_feedback - M6 Review & Complaint
   Purpose : Index của M6 Review & Complaint (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord (ord.sql chạy trước)
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Complaints_OpenPerCategory
    ON ord.Complaints (OrderId, Category)
    WHERE Status IN ('Open','InReview') AND IsDeleted = 0;
GO

CREATE NONCLUSTERED INDEX IX_Reviews_Lab
    ON ord.Reviews (LabId, IsVisible)
    INCLUDE (RatingOverall);
GO

CREATE NONCLUSTERED INDEX IX_Complaints_Status
    ON ord.Complaints (Status, CreatedAt);
GO
