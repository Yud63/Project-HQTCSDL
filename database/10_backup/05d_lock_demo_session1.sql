/* ============================================================
   Purpose : Phần 3a, cửa sổ 1. Giữ khóa UPDLOCK/HOLDLOCK trên tin demo
             $(Delay) giây rồi đặt mua THẬT qua mkt.sp_PlaceMarketOrder
             (Buyer 1 mua 1) trong cùng transaction, rồi COMMIT.
             Tham số sqlcmd: Delay.
   ============================================================ */
USE FilmLabDB;
GO
DECLARE @ListingId INT, @Buyer1 INT, @q INT, @NewId INT;
SELECT @ListingId = ListingId, @Buyer1 = Buyer1Id FROM dbo.LockDemoCtx;

BEGIN TRAN;
SELECT @q = Quantity
FROM mkt.Listings WITH (UPDLOCK, HOLDLOCK)
WHERE ListingId = @ListingId;
PRINT 'S1: dang giu khoa tren tin ' + CAST(@ListingId AS VARCHAR(10)) + ', Quantity = ' + CAST(@q AS VARCHAR(10));

WAITFOR DELAY '00:00:$(Delay)';

EXEC mkt.sp_PlaceMarketOrder @ListingId = @ListingId, @BuyerId = @Buyer1, @Quantity = 1,
                             @NewTransactionId = @NewId OUTPUT;
PRINT 'S1: Buyer 1 dat mua 1 thanh cong, TransactionId = ' + CAST(@NewId AS VARCHAR(10));
COMMIT;
PRINT 'S1: da COMMIT, nha khoa';
GO