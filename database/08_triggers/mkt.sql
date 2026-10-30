/* ============================================================
   File    : database/08_triggers/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : Trigger: trg_Listings_Guard, trg_ListingImages_Limit, trg_MarketTransactions_Guard, trg_Messages_CheckParties, trg_Listings_Audit, trg_MarketTransactions_Audit. Dùng templates/trigger_template.sql.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER TRIGGER mkt.trg_Listings_Guard
ON mkt.Listings
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT (UPDATE(Status) OR UPDATE(Quantity)) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN deleted d ON d.ListingId = i.ListingId
               WHERE i.Status <> d.Status
                 AND NOT ((d.Status = N'Active'   AND i.Status IN (N'Reserved', N'Sold', N'Closed', N'Removed'))
                       OR (d.Status = N'Reserved' AND i.Status IN (N'Active', N'Sold', N'Closed', N'Removed'))))
        THROW 50602, N'Chuyển trạng thái tin không hợp lệ.', 1;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN deleted d ON d.ListingId = i.ListingId
               WHERE i.Quantity <> d.Quantity AND d.Status IN (N'Sold', N'Closed', N'Removed'))
        THROW 50605, N'Không được đổi số lượng của tin đã Sold/Closed/Removed.', 1;

    IF EXISTS (SELECT 1 FROM inserted i WHERE i.Status = N'Active' AND i.Quantity = 0)
        THROW 50605, N'Tin Active phải còn số lượng lớn hơn 0.', 1;
END
GO

CREATE OR ALTER TRIGGER mkt.trg_ListingImages_Limit
ON mkt.ListingImages
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    IF EXISTS (SELECT 1
               FROM mkt.ListingImages li
               WHERE li.ListingId IN (SELECT ListingId FROM inserted)
               GROUP BY li.ListingId
               HAVING COUNT(*) > 8)
        THROW 50605, N'Mỗi tin tối đa 8 ảnh.', 1;
END
GO

CREATE OR ALTER TRIGGER mkt.trg_MarketTransactions_Guard
ON mkt.MarketTransactions
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN deleted d ON d.TransactionId = i.TransactionId
               WHERE i.ListingId <> d.ListingId OR i.SellerId <> d.SellerId OR i.BuyerId <> d.BuyerId
                  OR i.Quantity <> d.Quantity OR i.UnitPrice <> d.UnitPrice OR i.PlatformFee <> d.PlatformFee)
        THROW 50605, N'Không được sửa thông tin đã chốt của giao dịch.', 1;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN deleted d ON d.TransactionId = i.TransactionId
               WHERE i.Status <> d.Status
                 AND NOT ((d.Status = N'Pending'   AND i.Status IN (N'Confirmed', N'Cancelled'))
                       OR (d.Status = N'Confirmed' AND i.Status IN (N'Shipped', N'Cancelled'))
                       OR (d.Status = N'Shipped'   AND i.Status IN (N'Completed', N'Disputed'))
                       OR (d.Status = N'Disputed'  AND i.Status IN (N'Completed', N'Cancelled'))))
        THROW 50602, N'Chuyển trạng thái giao dịch không hợp lệ.', 1;
END
GO

CREATE OR ALTER TRIGGER mkt.trg_Messages_CheckParties
ON mkt.Messages
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN mkt.Listings l ON l.ListingId = i.ListingId
               WHERE i.SenderId <> l.SellerId AND i.ReceiverId <> l.SellerId)
        THROW 50603, N'Một trong hai bên của tin nhắn phải là người bán của tin đăng.', 1;
END
GO

CREATE OR ALTER TRIGGER mkt.trg_Listings_Audit
ON mkt.Listings
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @By INT = TRY_CAST(SESSION_CONTEXT(N'UserId') AS INT);
    DECLARE @Pk NVARCHAR(100), @Old NVARCHAR(MAX), @New NVARCHAR(MAX);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT CAST(i.ListingId AS NVARCHAR(100)),
               (SELECT d.Status, d.Quantity, d.Price, d.ModerationReason FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER),
               (SELECT i.Status, i.Quantity, i.Price, i.ModerationReason FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER)
        FROM inserted i
        JOIN deleted d ON d.ListingId = i.ListingId
        WHERE i.Status <> d.Status OR i.Quantity <> d.Quantity
           OR ISNULL(i.Price, -1) <> ISNULL(d.Price, -1)
           OR ISNULL(i.ModerationReason, N'') <> ISNULL(d.ModerationReason, N'');

    OPEN c;
    FETCH NEXT FROM c INTO @Pk, @Old, @New;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC audit.sp_WriteAudit N'mkt', N'Listings', @Pk, N'UPDATE', @Old, @New, @By;
        FETCH NEXT FROM c INTO @Pk, @Old, @New;
    END
    CLOSE c;
    DEALLOCATE c;
END
GO

CREATE OR ALTER TRIGGER mkt.trg_MarketTransactions_Audit
ON mkt.MarketTransactions
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @By INT = TRY_CAST(SESSION_CONTEXT(N'UserId') AS INT);
    DECLARE @Pk NVARCHAR(100), @Old NVARCHAR(MAX), @New NVARCHAR(MAX);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT CAST(i.TransactionId AS NVARCHAR(100)),
               (SELECT d.Status, d.BuyerRating, d.ResolvedBy FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER),
               (SELECT i.Status, i.BuyerRating, i.ResolvedBy FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER)
        FROM inserted i
        JOIN deleted d ON d.TransactionId = i.TransactionId
        WHERE i.Status <> d.Status
           OR ISNULL(i.BuyerRating, 0) <> ISNULL(d.BuyerRating, 0)
           OR ISNULL(i.ResolvedBy, 0) <> ISNULL(d.ResolvedBy, 0);

    OPEN c;
    FETCH NEXT FROM c INTO @Pk, @Old, @New;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC audit.sp_WriteAudit N'mkt', N'MarketTransactions', @Pk, N'UPDATE', @Old, @New, @By;
        FETCH NEXT FROM c INTO @Pk, @Old, @New;
    END
    CLOSE c;
    DEALLOCATE c;
END
GO