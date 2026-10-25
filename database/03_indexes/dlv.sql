/* ============================================================
   File    : database/03_indexes/dlv.sql
   Module  : dlv - M4 Delivery
   Purpose : Index của M4 Delivery (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : iam, ord
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_Delivery_ActiveLeg
    ON dlv.DeliveryRequests (OrderId, Direction)
    WHERE Status IN ('Requested','Assigned','PickedUp','Delivered') AND IsDeleted = 0;
GO

CREATE NONCLUSTERED INDEX IX_Delivery_Partner_Status
    ON dlv.DeliveryRequests (DeliveryPartnerId, Status)
    INCLUDE (OrderId, Direction);
GO

CREATE NONCLUSTERED INDEX IX_DeliveryLog_Request
    ON dlv.DeliveryStatusLog (DeliveryRequestId, ChangedAt);
GO
