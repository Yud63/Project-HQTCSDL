/* ============================================================
   File    : database/04_seed/reference/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : Dữ liệu danh mục cố định: ListingCategories (6 dòng).
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Danh mục loại hàng Marketplace
INSERT INTO mkt.ListingCategories (CategoryId, CategoryCode, CategoryName) VALUES
    (1, N'CAMERA', N'Máy ảnh'),
    (2, N'LENS', N'Ống kính'),
    (3, N'FILM', N'Phim'),
    (4, N'FLASH', N'Đèn flash'),
    (5, N'ACCESSORY', N'Phụ kiện'),
    (6, N'OTHER', N'Khác');
GO
