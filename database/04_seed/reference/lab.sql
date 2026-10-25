/* ============================================================
   File    : database/04_seed/reference/lab.sql
   Module  : lab - M2 Lab & Catalog
   Purpose : Dữ liệu danh mục cố định: FilmFormats (5), ServiceTypes (4), FilmStocks (khoảng 12).
   Owner   : B (xem docs/Phan-cong.md)
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

-- Định dạng phim
INSERT INTO lab.FilmFormats (FormatId, FormatCode, FormatName) VALUES
    (1, N'35mm', N'Phim 35mm (135)'),
    (2, N'120', N'Phim cuộn 120 (medium format)'),
    (3, N'4x5', N'Phim tấm 4x5 inch'),
    (4, N'110', N'Phim cartridge 110'),
    (5, N'APS', N'Phim APS');
GO

-- Dịch vụ
INSERT INTO lab.ServiceTypes (ServiceTypeId, ServiceCode, ServiceName, Category, Description) VALUES
    (1, N'DEV', N'Tráng phim', N'Develop', N'Tráng hóa chất (C-41, E-6, B&W, ECN-2)'),
    (2, N'SCAN', N'Scan phim', N'Scan', N'Scan thành file số'),
    (3, N'PRINT', N'In ảnh', N'Print', N'In ảnh từ phim hoặc file scan'),
    (4, N'EXTRA', N'Dịch vụ phụ trợ', N'Other', N'Cắt phim, sleeve, hộp lưu trữ...');
GO

-- Loại phim phổ biến
INSERT INTO lab.FilmStocks (StockId, Brand, StockName, Iso, FilmType, ProcessCode) VALUES
    (1, N'Kodak', N'Portra 160', 160, N'ColorNegative', N'C-41'),
    (2, N'Kodak', N'Portra 400', 400, N'ColorNegative', N'C-41'),
    (3, N'Kodak', N'Portra 800', 800, N'ColorNegative', N'C-41'),
    (4, N'Kodak', N'Gold 200', 200, N'ColorNegative', N'C-41'),
    (5, N'Kodak', N'Ultramax 400', 400, N'ColorNegative', N'C-41'),
    (6, N'Kodak', N'Ektar 100', 100, N'ColorNegative', N'C-41'),
    (7, N'Fujifilm', N'Superia X-tra 400', 400, N'ColorNegative', N'C-41'),
    (8, N'Kodak', N'Tri-X 400', 400, N'BlackWhite', N'BW'),
    (9, N'Kodak', N'T-Max 100', 100, N'BlackWhite', N'BW'),
    (10, N'Ilford', N'HP5 Plus 400', 400, N'BlackWhite', N'BW'),
    (11, N'Ilford', N'FP4 Plus 125', 125, N'BlackWhite', N'BW'),
    (12, N'Ilford', N'Delta 3200', 3200, N'BlackWhite', N'BW'),
    (13, N'Kodak', N'Ektachrome E100', 100, N'ColorSlide', N'E-6'),
    (14, N'Fujifilm', N'Velvia 50', 50, N'ColorSlide', N'E-6'),
    (15, N'Kodak', N'Vision3 500T', 500, N'ColorNegative', N'ECN-2');
GO
