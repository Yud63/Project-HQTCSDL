/* ============================================================
   File    : database/07_procedures/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : Procedure (★ = bắt buộc): ★sp_CreateListing, ★sp_PlaceMarketOrder, sp_SearchListings, sp_UpdateMarketTransaction, sp_ResolveDispute, sp_RateSeller, sp_SendMessage, sp_ModerateListing, sp_RunMaintenance. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
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

CREATE OR ALTER PROCEDURE mkt.sp_CreateListing
    @SellerId        INT,
    @CategoryId      INT,
    @ListingType     NVARCHAR(8),
    @Title           NVARCHAR(200),
    @Description     NVARCHAR(2000) = NULL,
    @Brand           NVARCHAR(50)   = NULL,
    @Model           NVARCHAR(100)  = NULL,
    @Condition       NVARCHAR(10)   = NULL,
    @Price           DECIMAL(18,0)  = NULL,
    @ExchangeWanted  NVARCHAR(255)  = NULL,
    @Quantity        INT            = 1,
    @City            NVARCHAR(100),
    @ImagesJson      NVARCHAR(MAX)  = NULL,
    @NewListingId    INT            = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @ImgCount INT = 0, @PrimCount INT = 0;

        EXEC sp_set_session_context @key = N'UserId', @value = @SellerId;

        IF NOT EXISTS (SELECT 1 FROM mkt.ListingCategories WHERE CategoryId = @CategoryId AND IsActive = 1)
            THROW 50601, N'Danh mục không tồn tại hoặc đã ngừng dùng.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @SellerId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50603, N'Người đăng không tồn tại hoặc đã bị khóa.', 1;

        IF @ListingType NOT IN (N'Sell', N'Exchange', N'Wanted')
            THROW 50605, N'Loại tin không hợp lệ.', 1;
        IF NULLIF(LTRIM(RTRIM(@Title)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@City)), N'') IS NULL
            THROW 50605, N'Tiêu đề và thành phố không được rỗng.', 1;
        IF @Quantity IS NULL OR @Quantity < 1
            THROW 50605, N'Số lượng phải từ 1 trở lên.', 1;
        IF @Price IS NOT NULL AND @Price < 0
            THROW 50605, N'Giá không được âm.', 1;
        IF @ListingType = N'Sell' AND @Price IS NULL
            THROW 50605, N'Tin bán phải có giá.', 1;
        IF @ListingType = N'Exchange' AND NULLIF(LTRIM(RTRIM(@ExchangeWanted)), N'') IS NULL
            THROW 50605, N'Tin trao đổi phải nêu món muốn đổi.', 1;
        IF @ListingType <> N'Wanted' AND @Condition IS NULL
            THROW 50605, N'Tin bán/trao đổi phải có tình trạng hàng.', 1;
        IF @Condition IS NOT NULL AND @Condition NOT IN (N'New', N'LikeNew', N'Good', N'Fair', N'ForParts')
            THROW 50605, N'Tình trạng hàng không hợp lệ.', 1;

        IF @ImagesJson IS NOT NULL
        BEGIN
            IF ISJSON(@ImagesJson) <> 1 OR LEFT(LTRIM(@ImagesJson), 1) <> N'['
                THROW 50605, N'ImagesJson phải là mảng JSON.', 1;

            SELECT @ImgCount = COUNT(*),
                   @PrimCount = ISNULL(SUM(CASE WHEN TRY_CAST(JSON_VALUE(j.[value], N'$.isPrimary') AS BIT) = 1 THEN 1 ELSE 0 END), 0)
            FROM OPENJSON(@ImagesJson) j;

            IF @ImgCount > 8
                THROW 50605, N'Mỗi tin tối đa 8 ảnh.', 1;
            IF @PrimCount > 1
                THROW 50605, N'Chỉ được một ảnh chính.', 1;
            IF EXISTS (SELECT 1 FROM OPENJSON(@ImagesJson) j
                       WHERE NULLIF(LTRIM(RTRIM(JSON_VALUE(j.[value], N'$.url'))), N'') IS NULL)
                THROW 50605, N'Mỗi ảnh phải có url.', 1;
        END

        BEGIN TRAN;

        INSERT INTO mkt.Listings
            (SellerId, CategoryId, ListingType, Title, Description, Brand, Model, Condition,
             Price, ExchangeWanted, Quantity, City)
        VALUES
            (@SellerId, @CategoryId, @ListingType, @Title, @Description, @Brand, @Model, @Condition,
             @Price, @ExchangeWanted, @Quantity, @City);

        SET @NewListingId = SCOPE_IDENTITY();

        IF @ImgCount > 0
            INSERT INTO mkt.ListingImages (ListingId, ImageUrl, SortOrder, IsPrimary)
            SELECT @NewListingId,
                   JSON_VALUE(j.[value], N'$.url'),
                   CAST(j.[key] AS TINYINT),
                   CASE WHEN TRY_CAST(JSON_VALUE(j.[value], N'$.isPrimary') AS BIT) = 1
                          OR (@PrimCount = 0 AND CAST(j.[key] AS INT) = 0) THEN 1 ELSE 0 END
            FROM OPENJSON(@ImagesJson) j;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE mkt.sp_PlaceMarketOrder
    @ListingId        INT,
    @BuyerId          INT,
    @Quantity         INT,
    @Note             NVARCHAR(500) = NULL,
    @NewTransactionId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @SellerId INT, @Status NVARCHAR(8), @Type NVARCHAR(8), @Price DECIMAL(18,0);
        DECLARE @Stock INT, @Expires DATETIME2(0), @ListingTitle NVARCHAR(200);
        DECLARE @UnitPrice DECIMAL(18,0), @Fee DECIMAL(18,0);
        DECLARE @Seq BIGINT, @Code NVARCHAR(20), @Body NVARCHAR(500), @NotiTitle NVARCHAR(150);

        EXEC sp_set_session_context @key = N'UserId', @value = @BuyerId;

        IF @Quantity IS NULL OR @Quantity < 1
            THROW 50605, N'Số lượng đặt phải từ 1 trở lên.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @BuyerId AND IsDeleted = 0 AND IsActive = 1)
            THROW 50603, N'Người mua không tồn tại hoặc đã bị khóa.', 1;

        BEGIN TRAN;

        SELECT @SellerId = SellerId, @Status = Status, @Type = ListingType, @Price = Price,
               @Stock = Quantity, @Expires = ExpiresAt, @ListingTitle = Title
        FROM mkt.Listings WITH (UPDLOCK, HOLDLOCK)
        WHERE ListingId = @ListingId AND IsDeleted = 0;

        IF @SellerId IS NULL
            THROW 50601, N'Tin đăng không tồn tại.', 1;
        IF @Status <> N'Active' OR @Expires <= SYSUTCDATETIME()
            THROW 50602, N'Tin không còn nhận đặt mua (không Active hoặc đã hết hạn).', 1;
        IF @Type = N'Wanted'
            THROW 50605, N'Tin cần mua (Wanted) không thể đặt mua.', 1;
        IF @BuyerId = @SellerId
            THROW 50603, N'Người mua không được là người bán.', 1;
        IF @Stock < @Quantity
            THROW 50606, N'Không đủ số lượng.', 1;

        SET @UnitPrice = ISNULL(@Price, 0);
        SET @Fee = mkt.fn_CalcMarketplaceFee(@Quantity * @UnitPrice, CAST(SYSUTCDATETIME() AS DATE));

        SET @Seq = NEXT VALUE FOR mkt.seq_TransactionCode;
        SET @Code = N'MK-' + CAST(YEAR(SYSUTCDATETIME()) AS NVARCHAR(4)) + N'-'
                  + RIGHT(N'000000' + CAST(@Seq AS NVARCHAR(10)), 6);

        INSERT INTO mkt.MarketTransactions
            (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee, Note)
        VALUES
            (@Code, @ListingId, @SellerId, @BuyerId, @Quantity, @UnitPrice, @Fee, @Note);

        SET @NewTransactionId = SCOPE_IDENTITY();

        UPDATE mkt.Listings
        SET Quantity = Quantity - @Quantity,
            Status = CASE WHEN Quantity - @Quantity = 0 THEN N'Reserved' ELSE Status END,
            UpdatedAt = SYSUTCDATETIME()
        WHERE ListingId = @ListingId;

        SET @NotiTitle = N'Có người đặt mua tin của bạn';
        SET @Body = N'Giao dịch ' + @Code + N': ' + CAST(@Quantity AS NVARCHAR(10)) + N' x ' + LEFT(@ListingTitle, 120);
        EXEC arc.sp_CreateNotification @SellerId, N'Market', @NotiTitle, @Body;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- WITH EXECUTE AS OWNER: nhánh Full-Text chạy bằng dynamic SQL (không đi theo ownership chaining),
-- người gọi không có SELECT trực tiếp trên mkt.Listings nên nếu không có EXECUTE AS OWNER sẽ bị lỗi 229.
CREATE OR ALTER PROCEDURE mkt.sp_SearchListings
    @Keyword     NVARCHAR(200)  = NULL,
    @CategoryId  INT            = NULL,
    @ListingType NVARCHAR(8)    = NULL,
    @Condition   NVARCHAR(10)   = NULL,
    @MinPrice    DECIMAL(18,0)  = NULL,
    @MaxPrice    DECIMAL(18,0)  = NULL,
    @City        NVARCHAR(100)  = NULL,
    @SortBy      NVARCHAR(20)   = N'Newest',
    @PageNo      INT            = 1,
    @PageSize    INT            = 20
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @Like NVARCHAR(220), @Ft NVARCHAR(400);

        IF @SortBy NOT IN (N'Newest', N'PriceAsc', N'PriceDesc')
            THROW 50605, N'SortBy không hợp lệ (Newest, PriceAsc, PriceDesc).', 1;
        IF @PageNo IS NULL OR @PageNo < 1 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100
            THROW 50605, N'PageNo phải >= 1 và PageSize từ 1 đến 100.', 1;
        IF @MinPrice IS NOT NULL AND @MaxPrice IS NOT NULL AND @MinPrice > @MaxPrice
            THROW 50605, N'MinPrice không được lớn hơn MaxPrice.', 1;
        IF @ListingType IS NOT NULL AND @ListingType NOT IN (N'Sell', N'Exchange', N'Wanted')
            THROW 50605, N'ListingType không hợp lệ.', 1;

        SET @Keyword = NULLIF(LTRIM(RTRIM(REPLACE(@Keyword, N'"', N''))), N'');

        CREATE TABLE #kw (ListingId INT NOT NULL PRIMARY KEY);

        IF @Keyword IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'mkt.Listings'))
            BEGIN
                SET @Ft = N'"' + @Keyword + N'*"';
                EXEC sp_executesql
                     N'INSERT INTO #kw (ListingId) SELECT ListingId FROM mkt.Listings WHERE CONTAINS((Title, Description), @q)',
                     N'@q NVARCHAR(400)', @q = @Ft;
            END
            ELSE
            BEGIN
                SET @Like = N'%' + REPLACE(REPLACE(REPLACE(@Keyword, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';
                INSERT INTO #kw (ListingId)
                SELECT ListingId FROM mkt.Listings WHERE Title LIKE @Like OR Description LIKE @Like;
            END
        END

        SELECT v.*, COUNT(*) OVER () AS TotalRows
        FROM mkt.vw_MarketActive v
        WHERE (@CategoryId  IS NULL OR v.CategoryId  = @CategoryId)
          AND (@ListingType IS NULL OR v.ListingType = @ListingType)
          AND (@Condition   IS NULL OR v.Condition   = @Condition)
          AND (@MinPrice    IS NULL OR v.Price >= @MinPrice)
          AND (@MaxPrice    IS NULL OR v.Price <= @MaxPrice)
          AND (@City        IS NULL OR v.City = @City)
          AND (@Keyword     IS NULL OR v.ListingId IN (SELECT ListingId FROM #kw))
        ORDER BY CASE WHEN @SortBy IN (N'PriceAsc', N'PriceDesc') AND v.Price IS NULL THEN 1 ELSE 0 END,
                 CASE WHEN @SortBy = N'PriceAsc'  THEN v.Price END ASC,
                 CASE WHEN @SortBy = N'PriceDesc' THEN v.Price END DESC,
                 v.CreatedAt DESC, v.ListingId DESC
        OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE mkt.sp_UpdateMarketTransaction
    @TransactionId INT,
    @ActorUserId   INT,
    @NewStatus     NVARCHAR(9),
    @Reason        NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(9), @SellerId INT, @BuyerId INT, @ListingId INT, @Qty INT, @Code NVARCHAR(20);
        DECLARE @Target INT, @NotiTitle NVARCHAR(150), @Body NVARCHAR(500), @Now DATETIME2(0) = SYSUTCDATETIME();

        EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;

        IF @NewStatus NOT IN (N'Confirmed', N'Shipped', N'Completed', N'Cancelled', N'Disputed')
            THROW 50605, N'Trạng thái mới không hợp lệ.', 1;

        BEGIN TRAN;

        SELECT @Status = Status, @SellerId = SellerId, @BuyerId = BuyerId, @ListingId = ListingId,
               @Qty = Quantity, @Code = TransactionCode
        FROM mkt.MarketTransactions WITH (UPDLOCK, HOLDLOCK)
        WHERE TransactionId = @TransactionId;

        IF @Status IS NULL
            THROW 50601, N'Giao dịch không tồn tại.', 1;

        IF NOT ((@NewStatus IN (N'Confirmed', N'Shipped') AND @ActorUserId = @SellerId)
             OR (@NewStatus IN (N'Completed', N'Disputed') AND @ActorUserId = @BuyerId)
             OR (@NewStatus = N'Cancelled' AND @ActorUserId IN (@SellerId, @BuyerId)))
            THROW 50603, N'Bạn không có quyền thực hiện chuyển trạng thái này.', 1;

        IF NOT ((@Status = N'Pending'   AND @NewStatus IN (N'Confirmed', N'Cancelled'))
             OR (@Status = N'Confirmed' AND @NewStatus IN (N'Shipped', N'Cancelled'))
             OR (@Status = N'Shipped'   AND @NewStatus IN (N'Completed', N'Disputed')))
            THROW 50602, N'Chuyển trạng thái giao dịch không hợp lệ.', 1;

        IF @NewStatus = N'Cancelled' AND (NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL OR LEN(@Reason) > 255)
            THROW 50605, N'Hủy giao dịch cần lý do (tối đa 255 ký tự).', 1;
        IF @NewStatus = N'Disputed' AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
            THROW 50605, N'Khiếu nại cần nêu lý do.', 1;

        UPDATE mkt.MarketTransactions
        SET Status        = @NewStatus,
            ConfirmedAt   = CASE WHEN @NewStatus = N'Confirmed' THEN @Now ELSE ConfirmedAt END,
            ShippedAt     = CASE WHEN @NewStatus = N'Shipped'   THEN @Now ELSE ShippedAt END,
            CompletedAt   = CASE WHEN @NewStatus = N'Completed' THEN @Now ELSE CompletedAt END,
            CancelReason  = CASE WHEN @NewStatus = N'Cancelled' THEN @Reason ELSE CancelReason END,
            DisputeReason = CASE WHEN @NewStatus = N'Disputed'  THEN @Reason ELSE DisputeReason END,
            DisputedAt    = CASE WHEN @NewStatus = N'Disputed'  THEN @Now ELSE DisputedAt END,
            UpdatedAt     = @Now
        WHERE TransactionId = @TransactionId;

        IF @NewStatus = N'Cancelled'
            UPDATE mkt.Listings
            SET Quantity = Quantity + @Qty,
                Status = CASE WHEN Status = N'Reserved' THEN N'Active' ELSE Status END,
                UpdatedAt = @Now
            WHERE ListingId = @ListingId AND Status IN (N'Active', N'Reserved');

        IF @NewStatus = N'Completed'
            UPDATE mkt.Listings
            SET Status = N'Sold', UpdatedAt = @Now
            WHERE ListingId = @ListingId AND Status = N'Reserved' AND Quantity = 0
              AND NOT EXISTS (SELECT 1 FROM mkt.MarketTransactions t
                              WHERE t.ListingId = @ListingId
                                AND t.Status IN (N'Pending', N'Confirmed', N'Shipped', N'Disputed'));

        SET @Target = CASE WHEN @ActorUserId = @SellerId THEN @BuyerId ELSE @SellerId END;
        SET @NotiTitle = N'Giao dịch ' + @Code + N' chuyển sang ' + @NewStatus;
        SET @Body = LEFT(ISNULL(@Reason, N''), 500);
        EXEC arc.sp_CreateNotification @Target, N'Market', @NotiTitle, @Body;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE mkt.sp_ResolveDispute
    @TransactionId INT,
    @AdminUserId   INT,
    @Decision      NVARCHAR(9),
    @Resolution    NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(9), @SellerId INT, @BuyerId INT, @ListingId INT, @Qty INT, @Code NVARCHAR(20);
        DECLARE @NotiTitle NVARCHAR(150), @Body NVARCHAR(500), @Now DATETIME2(0) = SYSUTCDATETIME();

        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        IF @Decision NOT IN (N'Completed', N'Cancelled')
            THROW 50605, N'Quyết định phải là Completed hoặc Cancelled.', 1;
        IF NULLIF(LTRIM(RTRIM(@Resolution)), N'') IS NULL
            THROW 50605, N'Phải nêu nội dung giải quyết.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50603, N'Chỉ Admin mới được giải quyết tranh chấp.', 1;

        BEGIN TRAN;

        SELECT @Status = Status, @SellerId = SellerId, @BuyerId = BuyerId, @ListingId = ListingId,
               @Qty = Quantity, @Code = TransactionCode
        FROM mkt.MarketTransactions WITH (UPDLOCK, HOLDLOCK)
        WHERE TransactionId = @TransactionId;

        IF @Status IS NULL
            THROW 50601, N'Giao dịch không tồn tại.', 1;
        IF @Status <> N'Disputed'
            THROW 50602, N'Giao dịch không ở trạng thái Disputed.', 1;

        UPDATE mkt.MarketTransactions
        SET Status            = @Decision,
            DisputeResolution = @Resolution,
            ResolvedBy        = @AdminUserId,
            ResolvedAt        = @Now,
            CompletedAt       = CASE WHEN @Decision = N'Completed' THEN @Now ELSE CompletedAt END,
            CancelReason      = CASE WHEN @Decision = N'Cancelled' THEN LEFT(@Resolution, 255) ELSE CancelReason END,
            UpdatedAt         = @Now
        WHERE TransactionId = @TransactionId;

        IF @Decision = N'Cancelled'
            UPDATE mkt.Listings
            SET Quantity = Quantity + @Qty,
                Status = CASE WHEN Status = N'Reserved' THEN N'Active' ELSE Status END,
                UpdatedAt = @Now
            WHERE ListingId = @ListingId AND Status IN (N'Active', N'Reserved');

        IF @Decision = N'Completed'
            UPDATE mkt.Listings
            SET Status = N'Sold', UpdatedAt = @Now
            WHERE ListingId = @ListingId AND Status = N'Reserved' AND Quantity = 0
              AND NOT EXISTS (SELECT 1 FROM mkt.MarketTransactions t
                              WHERE t.ListingId = @ListingId
                                AND t.Status IN (N'Pending', N'Confirmed', N'Shipped', N'Disputed'));

        SET @NotiTitle = N'Tranh chấp giao dịch ' + @Code + N' đã được giải quyết (' + @Decision + N')';
        SET @Body = LEFT(@Resolution, 500);
        EXEC arc.sp_CreateNotification @SellerId, N'Market', @NotiTitle, @Body;
        EXEC arc.sp_CreateNotification @BuyerId,  N'Market', @NotiTitle, @Body;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE mkt.sp_RateSeller
    @TransactionId INT,
    @BuyerId       INT,
    @Rating        TINYINT,
    @Comment       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(9), @TxBuyer INT, @SellerId INT, @Rated TINYINT, @Code NVARCHAR(20);
        DECLARE @NotiTitle NVARCHAR(150), @Body NVARCHAR(500), @Now DATETIME2(0) = SYSUTCDATETIME();

        EXEC sp_set_session_context @key = N'UserId', @value = @BuyerId;

        BEGIN TRAN;

        SELECT @Status = Status, @TxBuyer = BuyerId, @SellerId = SellerId, @Rated = BuyerRating, @Code = TransactionCode
        FROM mkt.MarketTransactions WITH (UPDLOCK, HOLDLOCK)
        WHERE TransactionId = @TransactionId;

        IF @Status IS NULL
            THROW 50601, N'Giao dịch không tồn tại.', 1;
        IF @TxBuyer <> @BuyerId
            THROW 50603, N'Chỉ người mua của giao dịch mới được đánh giá.', 1;
        IF @Rating IS NULL OR @Rating NOT BETWEEN 1 AND 5
            THROW 50605, N'Điểm đánh giá phải từ 1 đến 5.', 1;
        IF @Status <> N'Completed'
            THROW 50602, N'Chỉ đánh giá được giao dịch đã Completed.', 1;
        IF @Rated IS NOT NULL
            THROW 50604, N'Giao dịch này đã được đánh giá.', 1;

        UPDATE mkt.MarketTransactions
        SET BuyerRating = @Rating, BuyerComment = @Comment, RatedAt = @Now, UpdatedAt = @Now
        WHERE TransactionId = @TransactionId;

        SET @NotiTitle = N'Bạn nhận được đánh giá ' + CAST(@Rating AS NVARCHAR(1)) + N' sao';
        SET @Body = N'Giao dịch ' + @Code + ISNULL(N': ' + LEFT(@Comment, 300), N'');
        EXEC arc.sp_CreateNotification @SellerId, N'Market', @NotiTitle, @Body;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE mkt.sp_SendMessage
    @ListingId    INT,
    @SenderId     INT,
    @ReceiverId   INT,
    @Body         NVARCHAR(1000),
    @NewMessageId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @Status NVARCHAR(8), @NotiTitle NVARCHAR(150), @NotiBody NVARCHAR(500);

        EXEC sp_set_session_context @key = N'UserId', @value = @SenderId;

        IF NULLIF(LTRIM(RTRIM(@Body)), N'') IS NULL
            THROW 50605, N'Nội dung tin nhắn không được rỗng.', 1;
        IF @SenderId = @ReceiverId
            THROW 50605, N'Không thể gửi tin nhắn cho chính mình.', 1;

        SELECT @Status = Status FROM mkt.Listings WHERE ListingId = @ListingId AND IsDeleted = 0;
        IF @Status IS NULL
            THROW 50601, N'Tin đăng không tồn tại.', 1;
        IF @Status = N'Removed'
            THROW 50602, N'Tin đăng đã bị gỡ.', 1;
        IF (SELECT COUNT(*) FROM iam.Users WHERE UserId IN (@SenderId, @ReceiverId) AND IsDeleted = 0 AND IsActive = 1) <> 2
            THROW 50601, N'Người gửi hoặc người nhận không tồn tại.', 1;

        BEGIN TRAN;

        INSERT INTO mkt.Messages (ListingId, SenderId, ReceiverId, Body)
        VALUES (@ListingId, @SenderId, @ReceiverId, @Body);
        SET @NewMessageId = SCOPE_IDENTITY();

        SET @NotiTitle = N'Bạn có tin nhắn mới về một tin đăng';
        SET @NotiBody = LEFT(@Body, 200);
        EXEC arc.sp_CreateNotification @ReceiverId, N'Market', @NotiTitle, @NotiBody;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE mkt.sp_ModerateListing
    @ListingId   INT,
    @AdminUserId INT,
    @Reason      NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @SellerId INT, @Status NVARCHAR(8), @Title NVARCHAR(200);
        DECLARE @NotiTitle NVARCHAR(150), @Body NVARCHAR(500), @Now DATETIME2(0) = SYSUTCDATETIME();

        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
            THROW 50605, N'Phải nêu lý do gỡ tin.', 1;
        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50603, N'Chỉ Admin mới được gỡ tin vi phạm.', 1;

        BEGIN TRAN;

        SELECT @SellerId = SellerId, @Status = Status, @Title = Title
        FROM mkt.Listings WITH (UPDLOCK, HOLDLOCK)
        WHERE ListingId = @ListingId AND IsDeleted = 0;

        IF @SellerId IS NULL
            THROW 50601, N'Tin đăng không tồn tại.', 1;
        IF @Status IN (N'Removed', N'Sold', N'Closed')
            THROW 50602, N'Tin đã ở trạng thái cuối, không thể gỡ.', 1;

        UPDATE mkt.Listings
        SET Status = N'Removed', ModerationReason = @Reason, ModeratedBy = @AdminUserId, UpdatedAt = @Now
        WHERE ListingId = @ListingId;

        SET @NotiTitle = N'Tin đăng của bạn đã bị gỡ';
        SET @Body = LEFT(N'Tin "' + @Title + N'" bị gỡ: ' + @Reason, 500);
        EXEC arc.sp_CreateNotification @SellerId, N'Market', @NotiTitle, @Body;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE mkt.sp_RunMaintenance
    @ActorUserId   INT = NULL,
    @ClosedListings INT = NULL OUTPUT,
    @AutoCompleted  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        DECLARE @t INT, @buyer INT;

        SET @ClosedListings = 0;
        SET @AutoCompleted = 0;

        IF @ActorUserId IS NOT NULL
        BEGIN
            EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;
            IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                           WHERE ur.UserId = @ActorUserId AND r.RoleCode = N'Admin')
                THROW 50603, N'Chỉ Admin (hoặc job hệ thống) mới được chạy bảo trì.', 1;
        END

        -- 1. Đóng tin Active đã hết hạn
        UPDATE mkt.Listings
        SET Status = N'Closed', UpdatedAt = SYSUTCDATETIME()
        WHERE Status = N'Active' AND IsDeleted = 0 AND ExpiresAt <= SYSUTCDATETIME();
        SET @ClosedListings = @@ROWCOUNT;

        -- 2. Tự hoàn tất giao dịch Shipped quá 7 ngày (thay mặt người mua)
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT TransactionId, BuyerId FROM mkt.MarketTransactions
            WHERE Status = N'Shipped' AND ShippedAt <= DATEADD(DAY, -7, SYSUTCDATETIME());
        OPEN c;
        FETCH NEXT FROM c INTO @t, @buyer;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                EXEC mkt.sp_UpdateMarketTransaction @t, @buyer, N'Completed';
                SET @AutoCompleted = @AutoCompleted + 1;
            END TRY
            BEGIN CATCH
                SET @buyer = @buyer;  -- bỏ qua giao dịch lỗi, xử lý tiếp giao dịch khác
            END CATCH
            FETCH NEXT FROM c INTO @t, @buyer;
        END
        CLOSE c;
        DEALLOCATE c;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO