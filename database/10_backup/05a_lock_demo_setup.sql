/* ============================================================
   Purpose : Phần 1/4 demo UPDLOCK/HOLDLOCK hai cửa sổ cho BR-MKT-06
             (mkt.sp_PlaceMarketOrder, không bán lố khi hai người đặt
             đồng thời). Dựng 1 tin thử Quantity = 2 và bảng điều khiển
             dbo.LockDemoCtx (ListingId, SellerId, Buyer1Id, Buyer2Id).
             CHẠY TAY bằng sqlcmd, không nằm trong 99_run_all.sql.
   ============================================================ */
USE FilmLabDB;
GO
IF OBJECT_ID(N'dbo.LockDemoCtx') IS NOT NULL
    THROW 51000, N'Demo đang dở (còn dbo.LockDemoCtx). Chạy file dọn trước khi dựng lại.', 1;
GO
DECLARE @Seller INT, @B1 INT, @B2 INT, @Cat INT, @ListingId INT;

;WITH u AS
(
    SELECT UserId, ROW_NUMBER() OVER (ORDER BY UserId) AS rn
    FROM iam.Users
    WHERE IsActive = 1 AND IsDeleted = 0
)
SELECT @Seller = MAX(CASE WHEN rn = 1 THEN UserId END),
       @B1     = MAX(CASE WHEN rn = 2 THEN UserId END),
       @B2     = MAX(CASE WHEN rn = 3 THEN UserId END)
FROM u;

SELECT @Cat = MIN(CategoryId) FROM mkt.ListingCategories WHERE IsActive = 1;

IF @Seller IS NULL OR @B1 IS NULL OR @B2 IS NULL OR @Cat IS NULL
    THROW 51001, N'Thiếu dữ liệu nền: cần ít nhất 3 người dùng hoạt động và 1 danh mục tin.', 1;

INSERT INTO mkt.Listings
    (SellerId, CategoryId, ListingType, Title, Condition, Price, Quantity, City)
VALUES
    (@Seller, @Cat, N'Sell', N'LOCKDEMO-BR-MKT-06', N'Good', 100000, 2, N'Ho Chi Minh');
SET @ListingId = SCOPE_IDENTITY();

CREATE TABLE dbo.LockDemoCtx
(
    ListingId INT NOT NULL,
    SellerId  INT NOT NULL,
    Buyer1Id  INT NOT NULL,
    Buyer2Id  INT NOT NULL
);
INSERT dbo.LockDemoCtx VALUES (@ListingId, @Seller, @B1, @B2);
GO
-- Kiểm tra: 1 dòng, Quantity = 2, Status = Active, 3 UserId khác nhau
SELECT c.ListingId, c.SellerId, c.Buyer1Id, c.Buyer2Id, l.Quantity, l.Status, l.Title
FROM dbo.LockDemoCtx AS c
JOIN mkt.Listings AS l ON l.ListingId = c.ListingId;
GO