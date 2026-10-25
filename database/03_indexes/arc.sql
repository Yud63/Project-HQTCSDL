/* ============================================================
   File    : database/03_indexes/arc.sql
   Module  : arc - M5 Digital Archive
   Purpose : Index của M5 Digital Archive (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Albums_Owner_Title
    ON arc.Albums (OwnerUserId, Title)
    WHERE IsDeleted = 0;
GO

CREATE NONCLUSTERED INDEX IX_ScanFiles_Owner
    ON arc.ScanFiles (OwnerUserId, UploadedAt DESC);
GO

CREATE NONCLUSTERED INDEX IX_ScanFiles_Order
    ON arc.ScanFiles (OrderId);
GO

CREATE NONCLUSTERED INDEX IX_PhotoMetadata_Stock
    ON arc.PhotoMetadata (FilmStockId);
GO

CREATE NONCLUSTERED INDEX IX_AlbumPhotos_ScanFile
    ON arc.AlbumPhotos (ScanFileId);
GO

CREATE NONCLUSTERED INDEX IX_Notifications_User
    ON arc.Notifications (UserId, IsRead, CreatedAt DESC);
GO
