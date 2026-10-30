/* ============================================================
   File    : database/04_seed/reference/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : Dữ liệu danh mục cố định: ProcessingStages (13 dòng, StageId 1-13), FeeConfigs (3 dòng: PlatformCommission 10%, DeliveryBase 25000, MarketplaceFee 5%).
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- 13 giai đoạn xử lý đơn (docs/Requirements.md mục C.2)
INSERT INTO ord.ProcessingStages (StageId, StageCode, StageName, SortOrder, IsTerminal) VALUES
    (1, N'Pending', N'Chờ lab xác nhận', 10, 0),
    (2, N'Confirmed', N'Lab đã xác nhận', 20, 0),
    (3, N'AwaitingFilm', N'Chờ nhận phim', 30, 0),
    (4, N'FilmReceived', N'Đã nhận phim tại lab', 40, 0),
    (5, N'Developing', N'Tráng hóa chất', 50, 0),
    (6, N'Washing', N'Rửa', 60, 0),
    (7, N'Drying', N'Sấy', 70, 0),
    (8, N'Scanning', N'Scan', 80, 0),
    (9, N'ImagePrep', N'Chuẩn bị ảnh', 90, 0),
    (10, N'QualityCheck', N'Kiểm tra chất lượng', 100, 0),
    (11, N'ReadyToReturn', N'Sẵn sàng trả phim/ảnh', 110, 0),
    (12, N'Completed', N'Hoàn tất', 120, 1),
    (13, N'Cancelled', N'Đã hủy', 255, 1);
GO
