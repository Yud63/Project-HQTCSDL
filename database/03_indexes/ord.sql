/* ============================================================
   File    : database/03_indexes/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : Index của M3 Order, Processing, Payment, Fee (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Payments_OrderPaid
    ON ord.Payments (OrderId)
    WHERE Status = 'Succeeded';
GO

CREATE NONCLUSTERED INDEX IX_Orders_Customer
    ON ord.Orders (CustomerId, CreatedAt DESC);
GO

CREATE NONCLUSTERED INDEX IX_Orders_Lab_Stage
    ON ord.Orders (LabId, StageId);
GO

CREATE NONCLUSTERED INDEX IX_OrderItems_Order
    ON ord.OrderItems (OrderId);
GO

CREATE NONCLUSTERED INDEX IX_OrderStageLog_Order
    ON ord.OrderStageLog (OrderId, ChangedAt);
GO
