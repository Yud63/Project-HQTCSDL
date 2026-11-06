/* ============================================================
   Purpose : Phần 2b. Mua hàng KHÔNG khóa (READ COMMITTED, không hint):
             đọc Stock, chờ $(Delay) giây (để cửa sổ kia kịp đọc), rồi
             trừ nếu thấy đủ. Chạy ở hai cửa sổ cmd cách nhau vài giây.
             Tham số sqlcmd: Buyer, Qty, Delay.
   ============================================================ */
USE FilmLabDB;
GO
DECLARE @stock INT;
BEGIN TRAN;
SELECT @stock = Stock FROM dbo.LockDemoStock WHERE Id = 1;
PRINT 'Buyer $(Buyer) doc Stock = ' + CAST(@stock AS VARCHAR(10)) + ', muon mua $(Qty)';
WAITFOR DELAY '00:00:$(Delay)';
IF @stock >= $(Qty)
BEGIN
    UPDATE dbo.LockDemoStock SET Stock = Stock - $(Qty) WHERE Id = 1;
    INSERT dbo.LockDemoSold (BuyerId, Qty) VALUES ($(Buyer), $(Qty));
    PRINT 'Buyer $(Buyer): DAT MUA THANH CONG';
END
ELSE
    PRINT 'Buyer $(Buyer): khong du so luong';
COMMIT;
GO