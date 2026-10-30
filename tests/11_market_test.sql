USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DROP TABLE IF EXISTS #res11;
SELECT * INTO #res11 FROM mkt.vw_MarketActive WHERE 1 = 0;
ALTER TABLE #res11 ADD TotalRows INT;

DECLARE @seller INT, @buyer INT, @third INT, @admin INT, @cat INT;
DECLARE @l INT, @l2 INT, @l3 INT, @l4 INT, @t INT, @m INT, @e INT, @n0 INT, @n1 INT, @c INT, @a INT, @rows INT, @tot INT, @p DECIMAL(18,0);

SET @seller = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
SET @admin = (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn');
SET @buyer = (SELECT TOP 1 u.UserId FROM iam.Users u
              WHERE u.IsDeleted = 0 AND u.IsActive = 1 AND u.UserId <> @seller
                AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                                WHERE ur.UserId = u.UserId AND r.RoleCode = N'Admin')
              ORDER BY u.UserId);
SET @third = (SELECT TOP 1 u.UserId FROM iam.Users u
              WHERE u.IsDeleted = 0 AND u.IsActive = 1 AND u.UserId NOT IN (@seller, @buyer)
                AND NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                                WHERE ur.UserId = u.UserId AND r.RoleCode = N'Admin')
              ORDER BY u.UserId);
SET @cat = (SELECT TOP 1 CategoryId FROM mkt.ListingCategories WHERE IsActive = 1 ORDER BY CategoryId);

-- ===== S. sp_SearchListings =====
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 máy A', @Condition = N'Good', @Price = 100000, @City = N'Test11City', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 máy B', @Condition = N'Good', @Price = 300000, @City = N'Test11City', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11Unique máy C', @Condition = N'Good', @Price = 200000, @City = N'Test11City', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_CreateListing @seller, @cat, N'Exchange', N'Test11 máy D', @Condition = N'Good', @ExchangeWanted = N'Lens', @City = N'Test11City', @NewListingId = @l OUTPUT;

    DELETE FROM #res11;
    INSERT INTO #res11 EXEC mkt.sp_SearchListings @City = N'Test11City';
    IF (SELECT COUNT(*) FROM #res11) = 4 AND (SELECT MAX(TotalRows) FROM #res11) = 4
        PRINT N'PASS: SearchListings lọc City, TotalRows đúng';
    ELSE PRINT N'FAIL: SearchListings lọc City';

    DELETE FROM #res11;
    INSERT INTO #res11 EXEC mkt.sp_SearchListings @City = N'Test11City', @ListingType = N'Sell';
    IF (SELECT COUNT(*) FROM #res11) = 3 PRINT N'PASS: SearchListings lọc ListingType';
    ELSE PRINT N'FAIL: SearchListings lọc ListingType';

    DELETE FROM #res11;
    INSERT INTO #res11 EXEC mkt.sp_SearchListings @City = N'Test11City', @MinPrice = 150000, @MaxPrice = 250000;
    IF (SELECT COUNT(*) FROM #res11) = 1 AND (SELECT MIN(Price) FROM #res11) = 200000
        PRINT N'PASS: SearchListings lọc khoảng giá';
    ELSE PRINT N'FAIL: SearchListings lọc khoảng giá';

    DELETE FROM #res11;
    INSERT INTO #res11 EXEC mkt.sp_SearchListings @City = N'Test11City', @SortBy = N'PriceAsc', @PageSize = 1;
    SET @p = (SELECT TOP 1 Price FROM #res11);
    IF @p = 100000 PRINT N'PASS: SortBy PriceAsc';
    ELSE PRINT N'FAIL: SortBy PriceAsc';

    DELETE FROM #res11;
    INSERT INTO #res11 EXEC mkt.sp_SearchListings @City = N'Test11City', @SortBy = N'PriceDesc', @PageSize = 1;
    SET @p = (SELECT TOP 1 Price FROM #res11);
    IF @p = 300000 PRINT N'PASS: SortBy PriceDesc';
    ELSE PRINT N'FAIL: SortBy PriceDesc';

    DELETE FROM #res11;
    INSERT INTO #res11 EXEC mkt.sp_SearchListings @City = N'Test11City', @PageNo = 2, @PageSize = 3;
    IF (SELECT COUNT(*) FROM #res11) = 1 AND (SELECT MAX(TotalRows) FROM #res11) = 4
        PRINT N'PASS: SearchListings phân trang';
    ELSE PRINT N'FAIL: SearchListings phân trang';

    DELETE FROM #res11;
    INSERT INTO #res11 EXEC mkt.sp_SearchListings @Keyword = N'Test11Unique';
    IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'mkt.Listings'))
        PRINT N'PASS: SearchListings từ khóa (Full-Text bật, chỉ kiểm tra chạy không lỗi)';
    ELSE IF (SELECT COUNT(*) FROM #res11) = 1 AND EXISTS (SELECT 1 FROM #res11 WHERE Title LIKE N'Test11Unique%')
        PRINT N'PASS: SearchListings từ khóa (LIKE)';
    ELSE PRINT N'FAIL: SearchListings từ khóa';
END TRY
BEGIN CATCH PRINT N'FAIL: SearchListings, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

SET @e = 0; BEGIN TRY EXEC mkt.sp_SearchListings @SortBy = N'Random'; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50605 PRINT N'PASS: SortBy lạ -> 50605'; ELSE PRINT N'FAIL: SortBy lạ, nhận ' + CAST(@e AS NVARCHAR(10));
SET @e = 0; BEGIN TRY EXEC mkt.sp_SearchListings @PageNo = 0; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50605 PRINT N'PASS: PageNo = 0 -> 50605'; ELSE PRINT N'FAIL: PageNo = 0, nhận ' + CAST(@e AS NVARCHAR(10));
SET @e = 0; BEGIN TRY EXEC mkt.sp_SearchListings @PageSize = 101; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50605 PRINT N'PASS: PageSize = 101 -> 50605'; ELSE PRINT N'FAIL: PageSize = 101, nhận ' + CAST(@e AS NVARCHAR(10));
SET @e = 0; BEGIN TRY EXEC mkt.sp_SearchListings @MinPrice = 500, @MaxPrice = 100; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50605 PRINT N'PASS: MinPrice > MaxPrice -> 50605'; ELSE PRINT N'FAIL: MinPrice > MaxPrice, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== F1. Luồng đầy đủ: Confirm -> Ship -> Complete (Sold) -> Rate -> Stats; rate lần 2 -> 50604 =====
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 flow', @Condition = N'Good', @Price = 1000000, @Quantity = 2, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 2, NULL, @NewTransactionId = @t OUTPUT;

    SET @n0 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @buyer AND Type = N'Market');
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Confirmed';
    SET @n1 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @buyer AND Type = N'Market');
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND Status = N'Confirmed' AND ConfirmedAt IS NOT NULL) AND @n1 = @n0 + 1
        PRINT N'PASS: người bán Confirmed + thông báo cho người mua';
    ELSE PRINT N'FAIL: Confirmed';

    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Shipped';
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND Status = N'Shipped' AND ShippedAt IS NOT NULL)
        PRINT N'PASS: người bán Shipped';
    ELSE PRINT N'FAIL: Shipped';

    EXEC mkt.sp_UpdateMarketTransaction @t, @buyer, N'Completed';
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND Status = N'Completed' AND CompletedAt IS NOT NULL)
       AND EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Status = N'Sold' AND Quantity = 0)
        PRINT N'PASS: người mua Completed -> tin chuyển Sold';
    ELSE PRINT N'FAIL: Completed/Sold';

    EXEC mkt.sp_RateSeller @t, @buyer, 5, N'Người bán tốt';
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND BuyerRating = 5 AND RatedAt IS NOT NULL)
       AND mkt.fn_SellerRating(@seller) IS NOT NULL
        PRINT N'PASS: sp_RateSeller ghi đánh giá';
    ELSE PRINT N'FAIL: sp_RateSeller';

    IF EXISTS (SELECT 1 FROM mkt.vw_SellerStats WHERE SellerId = @seller AND TotalTransactions >= 1
               AND CompletedTransactions >= 1 AND CompletedRevenue >= 2000000 AND RatingCount >= 1)
        PRINT N'PASS: vw_SellerStats';
    ELSE PRINT N'FAIL: vw_SellerStats';

    EXEC mkt.sp_RateSeller @t, @buyer, 4;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50604 PRINT N'PASS: đánh giá lần hai -> 50604'; ELSE PRINT N'FAIL: đánh giá lần hai, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== F2. Hủy một phần: cộng lại số lượng =====
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 cancel', @Condition = N'Good', @Price = 1000000, @Quantity = 3, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Cancelled', N'Hết hàng thật';
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND Status = N'Cancelled' AND CancelReason = N'Hết hàng thật')
       AND EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Quantity = 3 AND Status = N'Active')
        PRINT N'PASS: hủy giao dịch -> cộng lại số lượng';
    ELSE PRINT N'FAIL: hủy giao dịch';
END TRY
BEGIN CATCH PRINT N'FAIL: hủy giao dịch, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- ===== F3. Hủy khi tin Reserved (người mua hủy) -> tin về Active =====
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 reserved', @Condition = N'Good', @Price = 1000000, @Quantity = 2, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 2, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @buyer, N'Cancelled', N'Đổi ý';
    IF EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Quantity = 2 AND Status = N'Active')
        PRINT N'PASS: hủy khi tin Reserved -> tin về Active';
    ELSE PRINT N'FAIL: hủy khi Reserved';
END TRY
BEGIN CATCH PRINT N'FAIL: hủy khi Reserved, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- ===== F4. Khiếu nại -> Admin giải quyết Completed =====
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 dispute', @Condition = N'Good', @Price = 1000000, @Quantity = 1, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Confirmed';
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Shipped';
    EXEC mkt.sp_UpdateMarketTransaction @t, @buyer, N'Disputed', N'Hàng không đúng mô tả';
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND Status = N'Disputed'
               AND DisputeReason = N'Hàng không đúng mô tả' AND DisputedAt IS NOT NULL)
        PRINT N'PASS: người mua khiếu nại Disputed';
    ELSE PRINT N'FAIL: Disputed';

    EXEC mkt.sp_ResolveDispute @t, @admin, N'Completed', N'Hàng đúng mô tả, hoàn tất giao dịch';
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND Status = N'Completed'
               AND ResolvedBy = @admin AND ResolvedAt IS NOT NULL AND CompletedAt IS NOT NULL AND DisputeResolution IS NOT NULL)
       AND EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Status = N'Sold')
        PRINT N'PASS: Admin giải quyết tranh chấp -> Completed (+ Sold)';
    ELSE PRINT N'FAIL: ResolveDispute Completed';
END TRY
BEGIN CATCH PRINT N'FAIL: luồng khiếu nại, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- ===== F5. Admin giải quyết Cancelled -> hoàn số lượng =====
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 dispute2', @Condition = N'Good', @Price = 1000000, @Quantity = 1, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Confirmed';
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Shipped';
    EXEC mkt.sp_UpdateMarketTransaction @t, @buyer, N'Disputed', N'Hàng hỏng';
    EXEC mkt.sp_ResolveDispute @t, @admin, N'Cancelled', N'Hoàn hàng, hủy giao dịch';
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND Status = N'Cancelled' AND CancelReason IS NOT NULL)
       AND EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Status = N'Active' AND Quantity = 1)
        PRINT N'PASS: Admin giải quyết -> Cancelled, hoàn số lượng';
    ELSE PRINT N'FAIL: ResolveDispute Cancelled';
END TRY
BEGIN CATCH PRINT N'FAIL: ResolveDispute Cancelled, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- ===== E1. Lỗi sp_UpdateMarketTransaction =====
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Shipped';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50602 PRINT N'PASS: Pending -> Shipped -> 50602'; ELSE PRINT N'FAIL: Pending -> Shipped, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @buyer, N'Confirmed';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50603 PRINT N'PASS: người mua Confirmed -> 50603'; ELSE PRINT N'FAIL: người mua Confirmed, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Cancelled';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: hủy không lý do -> 50605'; ELSE PRINT N'FAIL: hủy không lý do, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_UpdateMarketTransaction -1, @seller, N'Confirmed'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50601 PRINT N'PASS: giao dịch không tồn tại -> 50601'; ELSE PRINT N'FAIL: giao dịch không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_UpdateMarketTransaction 1, @seller, N'Foo'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: trạng thái mới lạ -> 50605'; ELSE PRINT N'FAIL: trạng thái lạ, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Confirmed';
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Shipped';
    EXEC mkt.sp_UpdateMarketTransaction @t, @buyer, N'Disputed';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: khiếu nại không lý do -> 50605'; ELSE PRINT N'FAIL: khiếu nại không lý do, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== G. trg_MarketTransactions_Guard =====
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    UPDATE mkt.MarketTransactions SET Status = N'Completed' WHERE TransactionId = @t;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50602 PRINT N'PASS: trigger Guard chặn Pending -> Completed (50602)'; ELSE PRINT N'FAIL: Guard Pending -> Completed, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    UPDATE mkt.MarketTransactions SET Quantity = 5 WHERE TransactionId = @t;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: trigger Guard chặn sửa Quantity đã chốt (50605)'; ELSE PRINT N'FAIL: Guard sửa Quantity, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== E2. Lỗi sp_ResolveDispute =====
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_ResolveDispute @t, @buyer, N'Completed', N'x';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50603 PRINT N'PASS: ResolveDispute không phải Admin -> 50603'; ELSE PRINT N'FAIL: ResolveDispute không phải Admin, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_ResolveDispute @t, @admin, N'Completed', N'x';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50602 PRINT N'PASS: ResolveDispute khi chưa Disputed -> 50602'; ELSE PRINT N'FAIL: ResolveDispute chưa Disputed, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_ResolveDispute 1, @admin, N'Refunded', N'x'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: ResolveDispute quyết định lạ -> 50605'; ELSE PRINT N'FAIL: ResolveDispute quyết định lạ, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_ResolveDispute -1, @admin, N'Completed', N'x'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50601 PRINT N'PASS: ResolveDispute không tồn tại -> 50601'; ELSE PRINT N'FAIL: ResolveDispute không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== E3. Lỗi sp_RateSeller =====
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_RateSeller @t, @buyer, 5;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50602 PRINT N'PASS: đánh giá khi chưa Completed -> 50602'; ELSE PRINT N'FAIL: đánh giá chưa Completed, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_RateSeller @t, @third, 5;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50603 PRINT N'PASS: người không phải người mua đánh giá -> 50603'; ELSE PRINT N'FAIL: đánh giá sai người, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_RateSeller @t, @buyer, 6;
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: điểm đánh giá 6 -> 50605'; ELSE PRINT N'FAIL: điểm đánh giá 6, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_RateSeller -1, @buyer, 5; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50601 PRINT N'PASS: đánh giá giao dịch không tồn tại -> 50601'; ELSE PRINT N'FAIL: đánh giá không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== M. sp_SendMessage + trg_Messages_CheckParties =====
SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 msg', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    SET @n0 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @seller AND Type = N'Market');
    EXEC mkt.sp_SendMessage @l, @buyer, @seller, N'Còn hàng không bạn?', @NewMessageId = @m OUTPUT;
    SET @n1 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @seller AND Type = N'Market');
    IF EXISTS (SELECT 1 FROM mkt.Messages WHERE MessageId = @m AND ListingId = @l AND SenderId = @buyer AND ReceiverId = @seller)
       AND @n1 = @n0 + 1
        PRINT N'PASS: sp_SendMessage + thông báo cho người nhận';
    ELSE PRINT N'FAIL: sp_SendMessage';
    EXEC mkt.sp_SendMessage @l, @third, @buyer, N'Tôi cũng quan tâm';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50603 PRINT N'PASS: trigger CheckParties chặn hai người không phải người bán -> 50603'; ELSE PRINT N'FAIL: CheckParties, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_SendMessage @l, @buyer, @buyer, N'tự gửi';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: gửi cho chính mình -> 50605'; ELSE PRINT N'FAIL: gửi cho chính mình, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_SendMessage @l, @buyer, @seller, N'   ';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: tin nhắn rỗng -> 50605'; ELSE PRINT N'FAIL: tin nhắn rỗng, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_SendMessage -1, @buyer, @seller, N'xin chào'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50601 PRINT N'PASS: tin nhắn cho tin không tồn tại -> 50601'; ELSE PRINT N'FAIL: tin không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== D. sp_ModerateListing =====
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 vi phạm', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    SET @n0 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @seller AND Type = N'Market');
    EXEC mkt.sp_ModerateListing @l, @admin, N'Nội dung vi phạm quy định';
    SET @n1 = (SELECT COUNT(*) FROM arc.Notifications WHERE UserId = @seller AND Type = N'Market');
    IF EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Status = N'Removed' AND ModerationReason = N'Nội dung vi phạm quy định' AND ModeratedBy = @admin)
       AND NOT EXISTS (SELECT 1 FROM mkt.vw_MarketActive WHERE ListingId = @l) AND @n1 = @n0 + 1
        PRINT N'PASS: sp_ModerateListing gỡ tin + thông báo + ẩn khỏi view';
    ELSE PRINT N'FAIL: sp_ModerateListing';
END TRY
BEGIN CATCH PRINT N'FAIL: sp_ModerateListing, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_ModerateListing @l, @buyer, N'lý do';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50603 PRINT N'PASS: gỡ tin không phải Admin -> 50603'; ELSE PRINT N'FAIL: gỡ tin không phải Admin, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_ModerateListing @l, @admin, N'  ';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50605 PRINT N'PASS: gỡ tin không lý do -> 50605'; ELSE PRINT N'FAIL: gỡ tin không lý do, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 x', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_ModerateListing @l, @admin, N'lần một';
    EXEC mkt.sp_ModerateListing @l, @admin, N'lần hai';
END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50602 PRINT N'PASS: gỡ tin đã Removed -> 50602'; ELSE PRINT N'FAIL: gỡ tin đã Removed, nhận ' + CAST(@e AS NVARCHAR(10));

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_ModerateListing -1, @admin, N'lý do'; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50601 PRINT N'PASS: gỡ tin không tồn tại -> 50601'; ELSE PRINT N'FAIL: gỡ tin không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== R. sp_RunMaintenance =====
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 hết hạn', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 còn hạn', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l2 OUTPUT;
    UPDATE mkt.Listings SET ExpiresAt = DATEADD(DAY, -1, SYSUTCDATETIME()) WHERE ListingId = @l;
    EXEC mkt.sp_RunMaintenance @ClosedListings = @c OUTPUT, @AutoCompleted = @a OUTPUT;
    IF EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Status = N'Closed')
       AND EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l2 AND Status = N'Active') AND @c >= 1
        PRINT N'PASS: sp_RunMaintenance đóng tin hết hạn, giữ tin còn hạn';
    ELSE PRINT N'FAIL: RunMaintenance đóng tin hết hạn';
END TRY
BEGIN CATCH PRINT N'FAIL: RunMaintenance hết hạn, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 auto', @Condition = N'Good', @Price = 1000, @Quantity = 1, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Confirmed';
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Shipped';
    UPDATE mkt.MarketTransactions SET ShippedAt = DATEADD(DAY, -8, SYSUTCDATETIME()) WHERE TransactionId = @t;
    EXEC mkt.sp_RunMaintenance @ClosedListings = @c OUTPUT, @AutoCompleted = @a OUTPUT;
    IF EXISTS (SELECT 1 FROM mkt.MarketTransactions WHERE TransactionId = @t AND Status = N'Completed')
       AND EXISTS (SELECT 1 FROM mkt.Listings WHERE ListingId = @l AND Status = N'Sold') AND @a >= 1
        PRINT N'PASS: sp_RunMaintenance tự hoàn tất giao dịch Shipped quá 7 ngày';
    ELSE PRINT N'FAIL: RunMaintenance tự hoàn tất';
END TRY
BEGIN CATCH PRINT N'FAIL: RunMaintenance tự hoàn tất, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC mkt.sp_RunMaintenance @ActorUserId = @buyer; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50603 PRINT N'PASS: RunMaintenance người không phải Admin -> 50603'; ELSE PRINT N'FAIL: RunMaintenance không phải Admin, nhận ' + CAST(@e AS NVARCHAR(10));

-- ===== A. Trigger audit =====
BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 audit', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    UPDATE mkt.Listings SET Status = N'Closed' WHERE ListingId = @l;
    IF EXISTS (SELECT 1 FROM audit.AuditLogs WHERE TableSchema = N'mkt' AND TableName = N'Listings'
               AND PrimaryKeyValue = CAST(@l AS NVARCHAR(100)) AND Action = N'UPDATE'
               AND JSON_VALUE(OldValues, N'$.Status') = N'Active' AND JSON_VALUE(NewValues, N'$.Status') = N'Closed')
        PRINT N'PASS: trigger Listings_Audit ghi UPDATE';
    ELSE PRINT N'FAIL: Listings_Audit';
END TRY
BEGIN CATCH PRINT N'FAIL: Listings_Audit, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

BEGIN TRAN;
BEGIN TRY
    EXEC mkt.sp_CreateListing @seller, @cat, N'Sell', N'Test11 audit2', @Condition = N'Good', @Price = 1000, @City = N'HN', @NewListingId = @l OUTPUT;
    EXEC mkt.sp_PlaceMarketOrder @l, @buyer, 1, NULL, @NewTransactionId = @t OUTPUT;
    EXEC mkt.sp_UpdateMarketTransaction @t, @seller, N'Confirmed';
    IF EXISTS (SELECT 1 FROM audit.AuditLogs WHERE TableSchema = N'mkt' AND TableName = N'MarketTransactions'
               AND PrimaryKeyValue = CAST(@t AS NVARCHAR(100)) AND Action = N'UPDATE'
               AND JSON_VALUE(OldValues, N'$.Status') = N'Pending' AND JSON_VALUE(NewValues, N'$.Status') = N'Confirmed')
        PRINT N'PASS: trigger MarketTransactions_Audit ghi UPDATE';
    ELSE PRINT N'FAIL: MarketTransactions_Audit';
END TRY
BEGIN CATCH PRINT N'FAIL: MarketTransactions_Audit, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO