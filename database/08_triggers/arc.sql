/* ============================================================
   File    : database/08_triggers/arc.sql
   Module  : arc - M5 Digital Archive
   Purpose : Trigger: trg_ScanFiles_Notify, trg_ScanFiles_CheckOwner, trg_AlbumPhotos_CheckOwner. Dùng templates/trigger_template.sql.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER TRIGGER arc.trg_ScanFiles_CheckOwner
ON arc.ScanFiles
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;
    IF NOT (UPDATE(OwnerUserId) OR UPDATE(OrderId)) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN ord.Orders o ON o.OrderId = i.OrderId
               WHERE i.OwnerUserId <> o.CustomerId)
        THROW 50505, N'Chủ sở hữu file scan phải là khách hàng của đơn.', 1;
END
GO

CREATE OR ALTER TRIGGER arc.trg_ScanFiles_Notify
ON arc.ScanFiles
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    -- Chỉ báo khi đây là lần upload đầu của đơn (toàn bộ file của đơn đều nằm trong lô vừa chèn)
    DECLARE @Pending TABLE (OrderId INT, UserId INT, OrderCode NVARCHAR(20));
    INSERT INTO @Pending (OrderId, UserId, OrderCode)
    SELECT i.OrderId, MIN(i.OwnerUserId), o.OrderCode
    FROM inserted i
    JOIN ord.Orders o ON o.OrderId = i.OrderId
    GROUP BY i.OrderId, o.OrderCode
    HAVING COUNT(*) = (SELECT COUNT(*) FROM arc.ScanFiles s WHERE s.OrderId = i.OrderId);

    DECLARE @OrderId INT, @UserId INT, @OrderCode NVARCHAR(20), @Body NVARCHAR(500);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT OrderId, UserId, OrderCode FROM @Pending;
    OPEN c;
    FETCH NEXT FROM c INTO @OrderId, @UserId, @OrderCode;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Body = N'Đơn ' + @OrderCode + N' đã có ảnh scan trong Digital Film Archive của bạn.';
        EXEC arc.sp_CreateNotification @UserId, N'ScanReady', N'Ảnh scan đã sẵn sàng', @Body, @OrderId;
        FETCH NEXT FROM c INTO @OrderId, @UserId, @OrderCode;
    END
    CLOSE c;
    DEALLOCATE c;
END
GO

CREATE OR ALTER TRIGGER arc.trg_AlbumPhotos_CheckOwner
ON arc.AlbumPhotos
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN arc.Albums a ON a.AlbumId = i.AlbumId
               JOIN arc.ScanFiles s ON s.ScanFileId = i.ScanFileId
               WHERE a.OwnerUserId <> s.OwnerUserId)
        THROW 50503, N'Ảnh trong album phải thuộc cùng chủ sở hữu với album.', 1;
END
GO