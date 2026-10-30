USE FilmLabDB;
GO
SET NOCOUNT ON;

DECLARE @an INT = (SELECT UserId FROM iam.Users WHERE Email = N'an.nguyen@example.com');
DECLARE @binh INT = (SELECT UserId FROM iam.Users WHERE Email = N'binh.tran@example.com');
DECLARE @sgLab INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Sài Gòn Film Lab');
DECLARE @hnLab INT = (SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Hà Nội Analog Lab');
DECLARE @svc1 INT = (SELECT LabServiceId FROM lab.LabServices WHERE LabId = @sgLab AND PackageName = N'Tráng C-41 35mm');
DECLARE @svc2 INT = (SELECT LabServiceId FROM lab.LabServices WHERE LabId = @sgLab AND PackageName = N'Scan High 35mm');
DECLARE @hnSvc INT = (SELECT LabServiceId FROM lab.LabServices WHERE LabId = @hnLab AND PackageName = N'Tráng C-41 35mm');
DECLARE @stock INT = (SELECT StockId FROM lab.FilmStocks WHERE Brand = N'Kodak' AND StockName = N'Portra 400');
DECLARE @addr INT = (SELECT AddressId FROM iam.Addresses WHERE UserId = @an AND Label = N'Nhà');
DECLARE @binhAddr INT = (SELECT TOP 1 AddressId FROM iam.Addresses WHERE UserId = @binh);
DECLARE @p1 DECIMAL(18,0) = (SELECT UnitPrice FROM lab.LabServices WHERE LabServiceId = @svc1);
DECLARE @p2 DECIMAL(18,0) = (SELECT UnitPrice FROM lab.LabServices WHERE LabServiceId = @svc2);
DECLARE @items NVARCHAR(MAX) = CONCAT(N'[{"labServiceId":', @svc1, N',"filmStockId":', @stock, N',"quantity":2,"note":"test"},',
                                      N'{"labServiceId":', @svc2, N',"filmStockId":', @stock, N',"quantity":1}]');
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @id INT, @e INT, @sub DECIMAL(18,0) = 2 * @p1 + @p2;

DECLARE @itemsHn   NVARCHAR(MAX) = CONCAT(N'[{"labServiceId":', @hnSvc, N',"quantity":1}]');
DECLARE @itemsZero NVARCHAR(MAX) = CONCAT(N'[{"labServiceId":', @svc1,  N',"quantity":0}]');
DECLARE @itemsBig  NVARCHAR(MAX) = CONCAT(N'[{"labServiceId":', @svc1,  N',"quantity":100000}]');

-- 1. lab.fn_DistanceKm
IF lab.fn_DistanceKm(NULL, NULL) IS NULL PRINT N'PASS: fn_DistanceKm NULL khi thiếu tọa độ'; ELSE PRINT N'FAIL: fn_DistanceKm';

-- 2. Hàm phí (D-01 10%, D-06 25.000đ)
IF ord.fn_CalcPlatformFee(@sgLab, 255000, @today) = 25500 AND ord.fn_CalcDeliveryFee(@sgLab, @today) = 25000
   AND ord.fn_CalcOrderTotal(255000, 25000) = 280000
    PRINT N'PASS: fn_CalcPlatformFee, fn_CalcDeliveryFee, fn_CalcOrderTotal';
ELSE PRINT N'FAIL: các hàm phí';

-- 3. Năng lực lab
IF lab.fn_LabCapacityLeft(@sgLab, @today) = (SELECT DailyCapacityRolls FROM lab.FilmLabs WHERE LabId = @sgLab)
    PRINT N'PASS: fn_LabCapacityLeft (chưa có đơn hôm nay = đủ năng lực)';
ELSE PRINT N'FAIL: fn_LabCapacityLeft';

-- 4. Tạo đơn DropOff + SelfCollect: đúng tiền, StageId 1, 1 dòng log, thông báo cho chủ lab, không có chặng giao
BEGIN TRAN;
BEGIN TRY
    EXEC ord.sp_CreateOrder @an, @sgLab, N'DropOff', N'SelfCollect', NULL, NULL, @items, N'Test', @id OUTPUT;
    IF EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @id AND StageId = 1 AND Subtotal = @sub AND DeliveryFee = 0
                 AND PlatformFee = ROUND(@sub * 0.1, 0) AND TotalAmount = @sub AND OrderCode LIKE N'FL-%')
       AND (SELECT COUNT(*) FROM ord.OrderStageLog WHERE OrderId = @id AND FromStageId IS NULL AND ToStageId = 1 AND ChangedBy = @an) = 1
       AND (SELECT COUNT(*) FROM ord.OrderItems WHERE OrderId = @id) = 2
       AND EXISTS (SELECT 1 FROM arc.Notifications n JOIN lab.FilmLabs l ON l.OwnerUserId = n.UserId WHERE n.OrderId = @id AND l.LabId = @sgLab)
       AND NOT EXISTS (SELECT 1 FROM dlv.DeliveryRequests WHERE OrderId = @id)
        PRINT N'PASS: tạo đơn DropOff/SelfCollect';
    ELSE PRINT N'FAIL: tạo đơn DropOff/SelfCollect';
END TRY
BEGIN CATCH PRINT N'FAIL: tạo đơn DropOff, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 5. Tạo đơn Pickup + Delivery: 2 chặng giao, phí giao 50.000đ
BEGIN TRAN;
BEGIN TRY
    EXEC ord.sp_CreateOrder @an, @sgLab, N'Pickup', N'Delivery', @addr, @addr, @items, NULL, @id OUTPUT;
    IF (SELECT COUNT(*) FROM dlv.DeliveryRequests WHERE OrderId = @id AND Fee = 25000) = 2
       AND EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @id AND DeliveryFee = 50000 AND TotalAmount = @sub + 50000)
        PRINT N'PASS: tạo đơn Pickup/Delivery (2 chặng, phí giao 50.000)';
    ELSE PRINT N'FAIL: tạo đơn Pickup/Delivery';
END TRY
BEGIN CATCH PRINT N'FAIL: tạo đơn Pickup/Delivery, lỗi ' + CAST(ERROR_NUMBER() AS NVARCHAR(10)) + N' ' + ERROR_MESSAGE(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;

-- 6. Items rỗng -> 50305
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CreateOrder @an, @sgLab, N'DropOff', N'SelfCollect', NULL, NULL, N'[]', NULL, @id OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: items rỗng -> 50305'; ELSE PRINT N'FAIL: items rỗng, nhận ' + CAST(@e AS NVARCHAR(10));

-- 7. Lab không tồn tại -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CreateOrder @an, -1, N'DropOff', N'SelfCollect', NULL, NULL, @items, NULL, @id OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: lab không tồn tại -> 50301'; ELSE PRINT N'FAIL: lab không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));

-- 8. Pickup thiếu địa chỉ -> 50305
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CreateOrder @an, @sgLab, N'Pickup', N'SelfCollect', NULL, NULL, @items, NULL, @id OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: Pickup thiếu địa chỉ -> 50305'; ELSE PRINT N'FAIL: thiếu địa chỉ, nhận ' + CAST(@e AS NVARCHAR(10));

-- 9. Địa chỉ của người khác -> 50305
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CreateOrder @an, @sgLab, N'Pickup', N'SelfCollect', @binhAddr, NULL, @items, NULL, @id OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: địa chỉ của người khác -> 50305'; ELSE PRINT N'FAIL: địa chỉ người khác, nhận ' + CAST(@e AS NVARCHAR(10));

-- 10. Dịch vụ của lab khác -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CreateOrder @an, @sgLab, N'DropOff', N'SelfCollect', NULL, NULL, @itemsHn, NULL, @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: dịch vụ của lab khác -> 50301'; ELSE PRINT N'FAIL: dịch vụ lab khác, nhận ' + CAST(@e AS NVARCHAR(10));

-- 11. Số lượng 0 -> 50305
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CreateOrder @an, @sgLab, N'DropOff', N'SelfCollect', NULL, NULL, @itemsZero, NULL, @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50305 PRINT N'PASS: số lượng 0 -> 50305'; ELSE PRINT N'FAIL: số lượng 0, nhận ' + CAST(@e AS NVARCHAR(10));

-- 12. Vượt năng lực -> 50306
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CreateOrder @an, @sgLab, N'DropOff', N'SelfCollect', NULL, NULL, @itemsBig, NULL, @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50306 PRINT N'PASS: vượt năng lực -> 50306'; ELSE PRINT N'FAIL: vượt năng lực, nhận ' + CAST(@e AS NVARCHAR(10));

-- 13. Lab chưa Approved -> 50302
SET @e = 0; BEGIN TRAN;
UPDATE lab.FilmLabs SET ApprovalStatus = N'Pending' WHERE LabId = @sgLab;
BEGIN TRY EXEC ord.sp_CreateOrder @an, @sgLab, N'DropOff', N'SelfCollect', NULL, NULL, @items, NULL, @id OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50302 PRINT N'PASS: lab chưa Approved -> 50302'; ELSE PRINT N'FAIL: lab chưa Approved, nhận ' + CAST(@e AS NVARCHAR(10));

-- 14. Khách không tồn tại -> 50301
SET @e = 0; BEGIN TRAN;
BEGIN TRY EXEC ord.sp_CreateOrder -1, @sgLab, N'DropOff', N'SelfCollect', NULL, NULL, @items, NULL, @id OUTPUT; END TRY BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
IF @e = 50301 PRINT N'PASS: khách không tồn tại -> 50301'; ELSE PRINT N'FAIL: khách không tồn tại, nhận ' + CAST(@e AS NVARCHAR(10));
GO