/* ============================================================
   Purpose : Phần 3b, cửa sổ 2. Sau $(Pre) giây, gọi thủ tục thật
             mkt.sp_PlaceMarketOrder cho Buyer 2 mua 2. Kỳ vọng bị block
             tới khi cửa sổ 1 COMMIT, rồi nhận lỗi 50606 (không đủ số lượng).
             Tham số sqlcmd: Pre.
   ============================================================ */
USE FilmLabDB;
GO
WAITFOR DELAY '00:00:$(Pre)';
GO
DECLARE @ListingId INT, @Buyer2 INT, @NewId INT, @t0 DATETIME2 = SYSDATETIME();
SELECT @ListingId = ListingId, @Buyer2 = Buyer2Id FROM dbo.LockDemoCtx;

PRINT 'S2: bat dau goi sp_PlaceMarketOrder (Buyer 2 mua 2)';
BEGIN TRY
    EXEC mkt.sp_PlaceMarketOrder @ListingId = @ListingId, @BuyerId = @Buyer2, @Quantity = 2,
                                 @NewTransactionId = @NewId OUTPUT;
    PRINT 'S2: DAT MUA THANH CONG (khong mong doi), TransactionId = ' + CAST(@NewId AS VARCHAR(10));
END TRY
BEGIN CATCH
    PRINT 'S2: LOI ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' sau '
          + CAST(DATEDIFF(SECOND, @t0, SYSDATETIME()) AS VARCHAR(10)) + ' giay cho khoa';
END CATCH
GO