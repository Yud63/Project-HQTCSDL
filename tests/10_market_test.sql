USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @seller INT, @buyer INT, @cat INT, @l INT, @t INT, @t2 INT, @e INT;
DECLARE @r DECIMAL(5,4), @fx DECIMAL(18,0), @n0 INT, @n1 INT, @code1 NVARCHAR(20), @code2 NVARCHAR(20);

SET @seller = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
SET @buyer = (SELECT TOP 1 UserId FROM iam.Users WHERE IsDeleted = 0 AND IsActive = 1 AND UserId <> @seller ORDER BY UserId);
SET @cat = (SELECT TOP 1 CategoryId FROM mkt.ListingCategories WHERE IsActive = 1 ORDER BY CategoryId);

DECLARE @img2 NVARCHAR(MAX) = N'[{"url":"https://img.example.com/a.jpg"},{"url":"https://img.example.com/b.jpg"}]';
DECLARE @imgPrim NVARCHAR(MAX) = N'[{"url":"https://img.example.com/a.jpg","isPrimary":false},{"url":"https://img.example.com/b.jpg","isPrimary":true}]';
DECLARE @imgTwoPrim NVARCHAR(MAX) = N'[{"url":"a","isPrimary":true},{"url":"b","isPrimary":true}]';
DECLARE @img8 NVARCHAR(MAX) = N'[{"url":"u1"},{"url":"u2"},{"url":"u3"},{"url":"u4"},{"url":"u5"},{"url":"u6"},{"url":"u7"},{"url":"u8"}]';
DECLARE @img9 NVARCHAR(MAX) = N'[{"url":"u1"},{"url":"u2"},{"url":"u3"},{"url":"u4"},{"url":"u5"},{"url":"u6"},{"url":"u7"},{"url":"u8"},{"url":"u9"}]';

-- 1-3. Function
SELECT TOP 1 @r = Rate, @fx = FixedAmount
FROM ord.FeeConfigs
WHERE FeeType = N'MarketplaceFee' AND ScopeLabId IS NULL AND EffectiveFrom <= CAST(SYSUTCDATETIME() AS DATE)
  AND (EffectiveTo IS NULL OR EffectiveTo >= CAST(SYSUTCDATETIME() AS DATE))
ORDER BY EffectiveFrom DESC, FeeConfigId DESC;
IF @r IS NULL AND @fx IS NULL SET @r = 0.05;

IF mkt.fn_CalcMarketplaceFee(1000000, CAST(SYSUTCDATETIME() AS DATE)) = ROUND(1000000 * ISNULL(@r, 0), 0) + ISNULL(@fx, 0)
    PRINT N'PASS: fn_CalcMarketplaceFee theo cấu hình hiệu lực (mặc định 5%)';
ELSE PRINT N'FAIL: fn_CalcMarketplaceFee';

IF mkt.fn_CalcMarketplaceFee(0, CAST(SYSUTCDATETIME() AS DATE)) = 0
   AND mkt.fn_CalcMarketplaceFee(100, CAST(SYSUTCDATETIME() AS DATE)) <= 100
    PRINT N'PASS: fn_CalcMarketplaceFee không vượt số tiền';
ELSE PRINT N'FAIL: fn_CalcMarketplaceFee giới hạn';

IF ISNULL(mkt.fn_SellerRating(@seller), -1) =
   ISNULL((SELECT CAST(AVG(CAST(BuyerRating AS DECIMAL(5,2))) AS DECIMAL(3,2)) FROM mkt.MarketTransactions
           WHERE SellerId = @seller AND BuyerRating IS NOT NULL), -1)
    PRINT N'PASS: fn_SellerRating khớp AVG(BuyerRating)';
ELSE PRINT N'FAIL: fn_SellerRating';

-- A. Luồng đúng: tạo tin + ảnh, view, đặt 2 lần, Reserved, rồi đặt lần ba -> 50602
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 Nikon F3', @Condition = N'Good', @Price = 3500000,
         @Quantity = 3, @City = N'Hồ Chí Minh', @ImagesJson = @img2, @NewListingId = @l OUTPUT;

    IF EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND SellerId = @seller AND Status = N'Active'
               AND Quantity = 3 AND ExpiresAt > SYSUTCDATETIME())
       AND (SELECT COUNT(*) FROM mkt.ListingImages WHERE ListingId = @l) = 2
       AND (SELECT COUNT(*) FROM mkt.ListingImages WHERE ListingId = @l AND IsPrimary = 1) = 1
       AND EXISTS (SELECT 1 FROM mkt.ListingImages WHERE ListingId = @l AND IsPrimary = 1 AND SortOrder = 0)
        PRINT N'PASS: sp_CreateListing tạo tin + 2 ảnh (ảnh đầu là ảnh chính)';
    ELSE PRINT N'FAIL: sp_CreateListing hợp lệ';

    IF EXISTS (SELECT 1 FROM mkt.vw_MarketActive WHERE ListingId = @l AND PrimaryImageUrl IS NOT NULL AND SellerName IS NOT NULL)
        PRINT N'PASS: vw_MarketActive hiển thị tin Active';
    ELSE PRINT N'FAIL: vw_MarketActive hiển thị';

    SET @n0 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @seller AND Type = N'Market');

    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 2, N'Test10 đơn 1', @NewTransactionId = @t OUTPUT;
    SET @code1 = (SELECT TransactionCode FROM mkt.MarketTransactions WHERE TransactionId = @t);
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND ListingId = @l AND SellerId = @seller
               AND BuyerId = @buyer AND Quantity = 2 AND UnitPrice = 3500000 AND TotalAmount = 7000000
               AND PlatformFee = mkt.fn_CalcMarketplaceFee(7000000, CAST(SYSUTCDATETIME() AS DATE))
               AND Status = N'Pending' AND TransactionCode LIKE N'MK-%')
       AND EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Quantity = 1 AND Status = N'Active')
        PRINT N'PASS: sp_PlaceMarketOrder tạo giao dịch Pending, trừ số lượng, chốt phí';
    ELSE PRINT N'FAIL: sp_PlaceMarketOrder đơn 1';

    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t2 OUTPUT;
    SET @code2 = (SELECT TransactionCode FROM mkt.MarketTransactions WHERE TransactionId = @t2);
    IF EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Quantity = 0 AND Status = N'Reserved')
       AND CAST(RIGHT(@code2, 6) AS INT) = CAST(RIGHT(@code1, 6) AS INT) + 1
        PRINT N'PASS: đặt hết số lượng -> Reserved, mã giao dịch tăng theo sequence';
    ELSE PRINT N'FAIL: Reserved/sequence, mã ' + @code1 + N' -> ' + @code2;

    IF NOT EXISTS (SELECT 1 FROM mkt.vw_MarketActive WHERE ListingId = @l)
        PRINT N'PASS: vw_MarketActive ẩn tin Reserved';
    ELSE PRINT N'FAIL: vw_MarketActive ẩn Reserved';

    SET @n1 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @seller AND Type = N'Market');
    IF @n1 = @n0 + 2 PRINT N'PASS: người bán nhận 2 thông báo Market';
    ELSE PRINT N'FAIL: thông báo Market, trước ' + CAST(@n0 AS NVARCHAR(10)) + N' sau ' + CAST(@n1 AS NVARCHAR(10));

    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50602 PRINT N'PASS: đặt mua tin Reserved -> 50602'; ELSE PRINT N'FAIL: đặt tin Reserved, nhận ' + CAST(@e AS NVARCHAR(10));

-- B. Ảnh chính theo isPrimary
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 Canon AE-1', @Condition = N'Good', @Price = 2000000,
         @City = N'Hà Nội', @ImagesJson = @imgPrim, @NewListingId = @l OUTPUT;
    IF EXISTS (SELECT 1 FROM mkt.ListingImages WHERE ListingId = @l AND IsPrimary = 1 AND SortOrder = 1 AND ImageUrl LIKE N'%b.jpg')
       AND (SELECT COUNT(*) FROM mkt.ListingImages WHERE ListingId = @l AND IsPrimary = 1) = 1
        PRINT N'PASS: ảnh chính theo isPrimary';
    ELSE PRINT N'FAIL: ảnh chính theo isPrimary';
END TRY
BEGIN CATCH PRINT N'FAIL: ảnh chính theo isPrimary, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- C. Tin Exchange: đặt mua có UnitPrice = 0, phí 0
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Exchange', N'Test10 đổi lens', @Condition = N'Good',
         @ExchangeWanted = N'Lens 85mm', @City = N'Đà Nẵng', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND UnitPrice = 0 AND TotalAmount = 0 AND PlatformFee = 0)
        PRINT N'PASS: tin Exchange đặt mua -> UnitPrice 0, phí 0';
    ELSE PRINT N'FAIL: tin Exchange';
END TRY
BEGIN CATCH PRINT N'FAIL: tin Exchange, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- D. Tin Wanted: tạo được không cần giá/tình trạng; đặt mua -> 50605
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Wanted', N'Test10 cần mua Canon AE-1', @City = N'Hà Nội', @NewListingId = @l OUTPUT;
    IF EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND ListingType = N'Wanted' AND Price IS NULL AND Condition IS NULL)
        PRINT N'PASS: tin Wanted tạo được không cần giá/tình trạng';
    ELSE PRINT N'FAIL: tin Wanted';
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: đặt mua tin Wanted -> 50605'; ELSE PRINT N'FAIL: đặt mua Wanted, nhận ' + CAST(@e AS NVARCHAR(10));

-- E. Kiểm tra dữ liệu sp_CreateListing
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_CreateListing @seller, @cat, N'Exchange', N'Test10 x', @Condition = N'Good', @City = N'HN', @NewListingId = @l OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: Exchange thiếu ExchangeWanted -> 50605'; ELSE PRINT N'FAIL: Exchange thiếu ExchangeWanted, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @City = N'HN', @NewListingId = @l OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: Sell thiếu Price -> 50605'; ELSE PRINT N'FAIL: Sell thiếu Price, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: Sell thiếu Condition -> 50605'; ELSE PRINT N'FAIL: Sell thiếu Condition, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_CreateListing @seller, @cat, N'Auction', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: ListingType lạ -> 50605'; ELSE PRINT N'FAIL: ListingType lạ, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @ImagesJson = @img9, @NewListingId = @l OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: 9 ảnh -> 50605'; ELSE PRINT N'FAIL: 9 ảnh, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @ImagesJson = @imgTwoPrim, @NewListingId = @l OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: hai ảnh chính -> 50605'; ELSE PRINT N'FAIL: hai ảnh chính, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_CreateListing @seller, -1, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50601 PRINT N'PASS: danh mục không tồn tại -> 50601'; ELSE PRINT N'FAIL: danh mục, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    UPDATE iam.Users SET IsActive = 0 WHERE UserId = @seller;
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50603 PRINT N'PASS: người đăng bị khóa -> 50603'; ELSE PRINT N'FAIL: người đăng bị khóa, nhận ' + CAST(@e AS NVARCHAR(10));

-- F. Kiểm tra sp_PlaceMarketOrder
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @Quantity = 3, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 5, NULL, @NewTransactionId = @t OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50606 PRINT N'PASS: đặt quá số lượng -> 50606'; ELSE PRINT N'FAIL: đặt quá số lượng, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @seller, 1, NULL, @NewTransactionId = @t OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50603 PRINT N'PASS: người mua là người bán -> 50603'; ELSE PRINT N'FAIL: người mua là người bán, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_PlaceMarketOrder -1, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50601 PRINT N'PASS: tin không tồn tại -> 50601'; ELSE PRINT N'FAIL: tin không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 0, NULL, @NewTransactionId = @t OUTPUT;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: Quantity = 0 -> 50605'; ELSE PRINT N'FAIL: Quantity = 0, nhận ' + CAST(@e AS NVARCHAR(10));

-- G. Trigger
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    UPDATE mkt.Listings SET Status = N'Sold' WHERE ListingId = @l;
    UPDATE mkt.Listings SET Status = N'Active' WHERE ListingId = @l;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50602 PRINT N'PASS: trigger Guard chặn Sold -> Active (50602)'; ELSE PRINT N'FAIL: Guard Sold -> Active, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    UPDATE mkt.Listings SET Quantity = 0 WHERE ListingId = @l;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: trigger Guard chặn Active với Quantity 0 (50605)'; ELSE PRINT N'FAIL: Guard Active Quantity 0, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    UPDATE mkt.Listings SET Status = N'Removed', ModerationReason = N'Test10' WHERE ListingId = @l;
    UPDATE mkt.Listings SET Quantity = 7 WHERE ListingId = @l;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: trigger Guard chặn đổi Quantity tin Removed (50605)'; ELSE PRINT N'FAIL: Guard Quantity tin Removed, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test10 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @ImagesJson = @img8, @NewListingId = @l OUTPUT;
    INSERT INTO mkt.ListingImages (ListingId, ImageUrl) VALUES (@l, N'u9');
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: trigger ListingImages_Limit chặn ảnh thứ 9 (50605)'; ELSE PRINT N'FAIL: ListingImages_Limit, nhận ' + CAST(@e AS NVARCHAR(10));
GO