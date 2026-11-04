/* ============================================================
   File    : demo/seed_dashboard/03_orders.sql
   Purpose : Seed dashboard C3 - 12 đơn của Cần Thơ Film Lab, phủ đủ 13 stage khi cộng với 6 đơn seed mẫu.
   Depends : 01_customers.sql, 02_labs.sql
   Cách làm: Đi qua sp_CreateOrder -> sp_UpdateOrderStage (từng bước) -> sp_ProcessPayment -> sp_CancelOrder,
             nên OrderStageLog, thông báo, chặng giao, audit đều được ghi thật.
   Re-run  : Chạy lại được. Mỗi đơn đánh dấu "[seed-c3-xx]" ở đầu CustomerNote; đơn đã có thì chỉ đẩy tiếp tới Target.
   Thêm đơn: Thêm 1 dòng vào @plan (Tag mới) và các dòng tương ứng vào @items, rồi chạy lại.
   Chạy    : sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -W -i demo\seed_dashboard\03_orders.sql
   Lưu ý   : KHÔNG đưa vào 99_run_all.sql / build.cmd. Không tạo đơn cho khách cũ (UserId 6/7/8).
   ============================================================ */
USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET NOCOUNT ON;

DECLARE @LabId INT, @LabOwner INT, @LabStatus NVARCHAR(12);
SELECT @LabId = LabId, @LabOwner = OwnerUserId, @LabStatus = ApprovalStatus
FROM lab.FilmLabs WHERE LabName = N'Cần Thơ Film Lab' AND IsDeleted = 0;
IF @LabId IS NULL
    THROW 50000, N'Thiếu Cần Thơ Film Lab: chạy 02_labs.sql trước.', 1;

-- ===== 1. BẢNG KẾ HOẠCH (sửa / thêm dòng ở đây) =====
-- Target: stage muốn dừng (1-12). Nếu có CancelReason thì Target là stage trước khi hủy (phải < 5).
-- Paid = 1: thanh toán ngay khi đơn tới stage >= 2.
DECLARE @plan TABLE (Seq INT IDENTITY(1,1), Tag NVARCHAR(20), Email NVARCHAR(255), Fulfil NVARCHAR(7), Ret NVARCHAR(11),
                     Target INT, Paid BIT, Method NVARCHAR(12), CancelReason NVARCHAR(255), Note NVARCHAR(200));
INSERT @plan (Tag, Email, Fulfil, Ret, Target, Paid, Method, CancelReason, Note) VALUES
    (N'seed-c3-01', N'khach.minh@example.com', N'Pickup',  N'Delivery',    1,  0, NULL,           NULL, N'Đơn mới, chờ lab xác nhận'),
    (N'seed-c3-02', N'khach.lan@example.com',  N'DropOff', N'SelfCollect', 2,  0, NULL,           NULL, N'Lab đã xác nhận, chưa thanh toán'),
    (N'seed-c3-03', N'khach.nam@example.com',  N'DropOff', N'SelfCollect', 3,  1, N'EWallet',     NULL, N'Đã thanh toán, chờ nhận phim'),
    (N'seed-c3-04', N'khach.minh@example.com', N'DropOff', N'Delivery',    4,  1, N'Card',        NULL, N'Phim slide E-6 đã tới lab'),
    (N'seed-c3-05', N'khach.lan@example.com',  N'Pickup',  N'Delivery',    8,  1, N'BankTransfer', NULL, N'Đang scan độ phân giải cao'),
    (N'seed-c3-06', N'khach.nam@example.com',  N'DropOff', N'SelfCollect', 10, 1, N'EWallet',     NULL, N'Chỉ scan, đang kiểm tra chất lượng'),
    (N'seed-c3-07', N'khach.minh@example.com', N'DropOff', N'SelfCollect', 12, 1, N'Card',        NULL, N'Đơn đã hoàn tất'),
    (N'seed-c3-08', N'khach.lan@example.com',  N'Pickup',  N'SelfCollect', 2,  1, N'EWallet',     N'Khách đổi ý sau khi thanh toán', N'Đơn hủy sau khi thanh toán, được hoàn tiền'),
    (N'seed-c3-09', N'khach.nam@example.com',  N'DropOff', N'SelfCollect', 1,  0, NULL,           N'Khách đặt nhầm lab', N'Đơn hủy khi chưa thanh toán'),
    (N'seed-c3-10', N'khach.lan@example.com',  N'DropOff', N'Delivery',    6,  1, N'EWallet',     NULL, N'Đang rửa phim'),
    (N'seed-c3-11', N'khach.minh@example.com', N'DropOff', N'SelfCollect', 7,  1, N'BankTransfer', NULL, N'Đang sấy phim'),
    (N'seed-c3-12', N'khach.nam@example.com',  N'DropOff', N'SelfCollect', 9,  1, N'Card',        NULL, N'Đang chuẩn bị ảnh scan');

DECLARE @items TABLE (ItemSeq INT IDENTITY(1,1), Tag NVARCHAR(20), Pkg NVARCHAR(150), Qty INT, Brand NVARCHAR(50), Stock NVARCHAR(100));
INSERT @items (Tag, Pkg, Qty, Brand, Stock) VALUES
    (N'seed-c3-01', N'Tráng C-41 35mm', 1, N'Kodak', N'Portra 400'),
    (N'seed-c3-02', N'Tráng B&W 35mm',  2, N'Kodak', N'Tri-X 400'),
    (N'seed-c3-03', N'Tráng C-41 120',  1, N'Kodak', N'Portra 160'),
    (N'seed-c3-04', N'Tráng E-6 35mm',  1, N'Kodak', N'Ektachrome E100'),
    (N'seed-c3-05', N'Tráng C-41 35mm', 1, N'Kodak', N'Portra 400'),
    (N'seed-c3-05', N'Scan High 35mm',  1, N'Kodak', N'Portra 400'),
    (N'seed-c3-06', N'Scan Basic 35mm', 1, NULL, NULL),
    (N'seed-c3-07', N'Tráng C-41 35mm', 1, N'Fujifilm', N'Superia X-tra 400'),
    (N'seed-c3-07', N'Scan Basic 35mm', 1, N'Fujifilm', N'Superia X-tra 400'),
    (N'seed-c3-08', N'Tráng B&W 35mm',  1, N'Ilford', N'HP5 Plus 400'),
    (N'seed-c3-09', N'Tráng C-41 35mm', 1, N'Kodak', N'Gold 200'),
    (N'seed-c3-10', N'Tráng C-41 120',  1, N'Kodak', N'Portra 160'),
    (N'seed-c3-11', N'Tráng B&W 35mm',  1, N'Kodak', N'T-Max 100'),
    (N'seed-c3-12', N'Tráng C-41 35mm', 1, N'Kodak', N'Ultramax 400'),
    (N'seed-c3-12', N'Scan Basic 35mm', 1, N'Kodak', N'Ultramax 400');

-- ===== 2. Kiểm tra kế hoạch =====
IF EXISTS (SELECT 1 FROM @plan WHERE Target NOT BETWEEN 1 AND 12 OR (CancelReason IS NOT NULL AND Target >= 5)
                                   OR (Paid = 1 AND (Target < 2 AND CancelReason IS NULL)) OR (Paid = 1 AND Method IS NULL))
    THROW 50000, N'Bảng kế hoạch sai: Target 1-12; có CancelReason thì Target < 5; Paid = 1 cần Method và Target >= 2.', 1;
IF EXISTS (SELECT 1 FROM @plan p WHERE NOT EXISTS (SELECT 1 FROM iam.Users u WHERE u.Email = p.Email AND u.IsDeleted = 0))
    THROW 50000, N'Thiếu khách trong kế hoạch: chạy 01_customers.sql trước.', 1;
IF EXISTS (SELECT 1 FROM @plan p WHERE NOT EXISTS (SELECT 1 FROM @items i WHERE i.Tag = p.Tag))
    THROW 50000, N'Có Tag trong @plan nhưng không có dòng nào trong @items.', 1;

-- ===== 3. Tạo đơn, đẩy stage, thanh toán, hủy =====
DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @plan);
DECLARE @Tag NVARCHAR(20), @Mark NVARCHAR(24), @Email NVARCHAR(255), @Fulfil NVARCHAR(7), @Ret NVARCHAR(11),
        @Target INT, @Paid BIT, @Method NVARCHAR(12), @Cancel NVARCHAR(255), @Note NVARCHAR(200),
        @Cust INT, @Addr INT, @PickAddr INT, @RetAddr INT, @Json NVARCHAR(MAX), @CustNote NVARCHAR(500),
        @OrderId INT, @Cur INT, @Pay NVARCHAR(9), @Total DECIMAL(18,0), @Next INT, @PayId INT, @StepNote NVARCHAR(255),
        @Prov NVARCHAR(30), @TxnId NVARCHAR(100);

WHILE @i <= @n
BEGIN
    SELECT @Tag = Tag, @Email = Email, @Fulfil = Fulfil, @Ret = Ret, @Target = Target, @Paid = Paid,
           @Method = Method, @Cancel = CancelReason, @Note = Note
    FROM @plan WHERE Seq = @i;

    SET @Mark = N'[' + @Tag + N']';
    SET @Cust = (SELECT UserId FROM iam.Users WHERE Email = @Email AND IsDeleted = 0);
    SET @OrderId = (SELECT OrderId FROM ord.Orders
                    WHERE IsDeleted = 0 AND LabId = @LabId AND LEFT(CustomerNote, LEN(@Mark)) = @Mark);

    -- 3a. Tạo đơn nếu chưa có
    IF @OrderId IS NULL
    BEGIN
        IF @LabStatus <> N'Approved'
            THROW 50000, N'Cần Thơ Film Lab không còn Approved, không thể tạo đơn mới.', 1;

        SET @Addr = (SELECT TOP (1) AddressId FROM iam.Addresses WHERE UserId = @Cust AND Label = N'Nhà' AND IsDeleted = 0 ORDER BY AddressId);
        SET @PickAddr = CASE WHEN @Fulfil = N'Pickup'   THEN @Addr END;
        SET @RetAddr  = CASE WHEN @Ret    = N'Delivery' THEN @Addr END;

        SET @Json = (SELECT s.LabServiceId AS labServiceId, fs.StockId AS filmStockId, i.Qty AS quantity
                     FROM @items i
                     JOIN lab.LabServices s ON s.LabId = @LabId AND s.PackageName = i.Pkg AND s.IsDeleted = 0
                     LEFT JOIN lab.FilmStocks fs ON fs.Brand = i.Brand AND fs.StockName = i.Stock
                     WHERE i.Tag = @Tag
                     ORDER BY i.ItemSeq
                     FOR JSON PATH);
        IF @Json IS NULL OR (SELECT COUNT(*) FROM OPENJSON(@Json)) <> (SELECT COUNT(*) FROM @items WHERE Tag = @Tag)
            THROW 50000, N'Có gói dịch vụ trong @items không tồn tại ở Cần Thơ Film Lab.', 1;

        SET @CustNote = @Mark + N' ' + @Note;
        EXEC ord.sp_CreateOrder @CustomerId = @Cust, @LabId = @LabId, @FulfillmentMethod = @Fulfil, @ReturnMethod = @Ret,
                                @PickupAddressId = @PickAddr, @ReturnAddressId = @RetAddr, @ItemsJson = @Json,
                                @CustomerNote = @CustNote, @NewOrderId = @OrderId OUTPUT;
    END;

    -- 3b. Đẩy tới Target, thanh toán khi tới stage >= 2
    WHILE 1 = 1
    BEGIN
        SELECT @Cur = StageId, @Pay = PaymentStatus, @Total = TotalAmount FROM ord.Orders WHERE OrderId = @OrderId;
        IF @Cur IN (12, 13) BREAK;

        IF @Paid = 1 AND @Pay = N'Unpaid' AND @Cur >= 2
        BEGIN
            SET @Prov  = CASE @Method WHEN N'Card' THEN N'Visa' WHEN N'EWallet' THEN N'MoMo' ELSE N'Vietcombank' END;
            SET @TxnId = N'SEED-' + @Tag;
            EXEC ord.sp_ProcessPayment @OrderId = @OrderId, @ActorUserId = @Cust, @Method = @Method,
                                       @Provider = @Prov, @ProviderTxnId = @TxnId, @Amount = @Total,
                                       @Succeeded = 1, @NewPaymentId = @PayId OUTPUT;
        END;

        IF @Cur >= @Target BREAK;

        SET @Next = ord.fn_NextStage(@OrderId, @Cur);
        IF @Next IS NULL OR @Next > @Target
            THROW 50000, N'Target không hợp lệ với các gói của đơn (stage bị bỏ qua vì không có gói Tráng/Scan).', 1;

        SET @StepNote = N'Seed demo: chuyển sang stage ' + CAST(@Next AS NVARCHAR(3));
        EXEC ord.sp_UpdateOrderStage @OrderId = @OrderId, @ActorUserId = @LabOwner, @NewStageId = @Next, @Note = @StepNote;
    END;

    -- 3c. Hủy (khách tự hủy) nếu kế hoạch có CancelReason
    IF @Cancel IS NOT NULL AND (SELECT StageId FROM ord.Orders WHERE OrderId = @OrderId) <> 13
        EXEC ord.sp_CancelOrder @OrderId = @OrderId, @ActorUserId = @Cust, @Reason = @Cancel;

    SET @i += 1;
END;

EXEC sp_set_session_context @key = N'UserId', @value = NULL;
GO

-- ===== 4. Kiểm tra nhanh =====
-- 4a. 12 đơn seed C3
SELECT SUBSTRING(o.CustomerNote, 2, CHARINDEX(N']', o.CustomerNote) - 2) AS Tag,
       o.OrderCode, u.Email, ps.StageId, ps.StageCode, o.PaymentStatus, o.TotalAmount,
       (SELECT COUNT(*) FROM ord.OrderItems oi WHERE oi.OrderId = o.OrderId) AS Items
FROM ord.Orders o
JOIN iam.Users u ON u.UserId = o.CustomerId
JOIN ord.ProcessingStages ps ON ps.StageId = o.StageId
WHERE o.IsDeleted = 0 AND o.CustomerNote LIKE N'[[]seed-c3-%'
ORDER BY o.OrderId;

-- 4b. Phủ stage (tất cả đơn)
SELECT ps.StageId, ps.StageCode, COUNT(o.OrderId) AS Orders
FROM ord.ProcessingStages ps
LEFT JOIN ord.Orders o ON o.StageId = ps.StageId AND o.IsDeleted = 0
GROUP BY ps.StageId, ps.StageCode
ORDER BY ps.StageId;

-- 4c. Thanh toán và tổng đơn
SELECT PaymentStatus, COUNT(*) AS Orders FROM ord.Orders WHERE IsDeleted = 0 GROUP BY PaymentStatus ORDER BY PaymentStatus;
SELECT (SELECT COUNT(*) FROM ord.Orders WHERE IsDeleted = 0) AS TotalOrders,
       (SELECT COUNT(*) FROM ord.Orders o JOIN iam.Users u ON u.UserId = o.CustomerId
        WHERE u.Email = N'an.nguyen@example.com') AS OrdersOfAn;
GO