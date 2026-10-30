/* ============================================================
   File    : database/05_functions/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : Function: fn_CalcOrderTotal, fn_CalcPlatformFee, fn_NextStage, fn_IsValidTransition, fn_CalcDeliveryFee.
   Owner   : B (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Giai đoạn kế tiếp áp dụng cho đơn (bỏ qua Develop 5-7 / Scan 8-9 nếu đơn không có). NULL nếu đã kết thúc.
CREATE OR ALTER FUNCTION ord.fn_NextStage (@OrderId INT, @FromStageId INT)
RETURNS INT
AS
BEGIN
    DECLARE @Next INT = NULL;
    DECLARE @HasDevelop BIT = CASE WHEN EXISTS (
        SELECT 1 FROM ord.OrderItems oi
        JOIN lab.LabServices ls ON ls.LabServiceId = oi.LabServiceId
        JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId
        WHERE oi.OrderId = @OrderId AND st.Category = N'Develop') THEN 1 ELSE 0 END;
    DECLARE @HasScan BIT = CASE WHEN EXISTS (
        SELECT 1 FROM ord.OrderItems oi
        JOIN lab.LabServices ls ON ls.LabServiceId = oi.LabServiceId
        JOIN lab.ServiceTypes st ON st.ServiceTypeId = ls.ServiceTypeId
        WHERE oi.OrderId = @OrderId AND st.Category = N'Scan') THEN 1 ELSE 0 END;

    IF @FromStageId IS NOT NULL AND @FromStageId < 12
        SELECT @Next = MIN(StageId)
        FROM ord.ProcessingStages
        WHERE StageId > @FromStageId
          AND StageId < 13                                   -- 13 = Cancelled, không phải bước kế tiếp
          AND (StageId NOT BETWEEN 5 AND 7 OR @HasDevelop = 1)
          AND (StageId NOT BETWEEN 8 AND 9 OR @HasScan = 1);

    RETURN @Next;
END
GO

-- 1 = chuyển giai đoạn hợp lệ, 0 = không. @FromStageId NULL = khởi tạo đơn (chỉ được vào 1).
CREATE OR ALTER FUNCTION ord.fn_IsValidTransition (@OrderId INT, @FromStageId INT, @ToStageId INT)
RETURNS BIT
AS
BEGIN
    DECLARE @ok BIT = 0;

    IF @FromStageId IS NULL
        SET @ok = CASE WHEN @ToStageId = 1 THEN 1 ELSE 0 END;
    ELSE IF @FromStageId IN (12, 13)                         -- đã kết thúc
        SET @ok = 0;
    ELSE IF @ToStageId = 13                                  -- hủy: chỉ khi chưa vào Developing
        SET @ok = CASE WHEN @FromStageId < 5 THEN 1 ELSE 0 END;
    ELSE IF @ToStageId = ISNULL(ord.fn_NextStage(@OrderId, @FromStageId), -1)
        SET @ok = CASE WHEN @ToStageId = 12
                       AND NOT EXISTS (SELECT 1 FROM ord.Orders WHERE OrderId = @OrderId AND PaymentStatus = N'Paid')
                       THEN 0 ELSE 1 END;                    -- Completed bắt buộc đã Paid

    RETURN @ok;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = N'seq_OrderCode' AND schema_id = SCHEMA_ID(N'ord'))
    CREATE SEQUENCE ord.seq_OrderCode AS INT START WITH 7 INCREMENT BY 1 NO CYCLE;
GO

CREATE OR ALTER FUNCTION ord.fn_CalcOrderTotal (@Subtotal DECIMAL(18,0), @DeliveryFee DECIMAL(18,0))
RETURNS DECIMAL(18,0)
AS
BEGIN
    RETURN ISNULL(@Subtotal, 0) + ISNULL(@DeliveryFee, 0);   -- D-01: khách trả Subtotal + phí giao
END
GO

-- Hoa hồng nền tảng = Subtotal x Rate hiệu lực (ưu tiên cấu hình riêng của lab, mặc định 10%)
CREATE OR ALTER FUNCTION ord.fn_CalcPlatformFee (@LabId INT, @Subtotal DECIMAL(18,0), @OnDate DATE)
RETURNS DECIMAL(18,0)
AS
BEGIN
    DECLARE @Rate DECIMAL(5,4) = (
        SELECT TOP 1 Rate FROM ord.FeeConfigs
        WHERE FeeType = N'PlatformCommission' AND Rate IS NOT NULL
          AND (ScopeLabId = @LabId OR ScopeLabId IS NULL)
          AND EffectiveFrom <= @OnDate AND (EffectiveTo IS NULL OR EffectiveTo >= @OnDate)
        ORDER BY CASE WHEN ScopeLabId IS NULL THEN 1 ELSE 0 END, EffectiveFrom DESC);
    RETURN CAST(ROUND(@Subtotal * ISNULL(@Rate, 0.1000), 0) AS DECIMAL(18,0));
END
GO

-- Phí giao của MỖI chặng (mặc định 25.000đ)
CREATE OR ALTER FUNCTION ord.fn_CalcDeliveryFee (@LabId INT, @OnDate DATE)
RETURNS DECIMAL(18,0)
AS
BEGIN
    DECLARE @Fee DECIMAL(18,0) = (
        SELECT TOP 1 FixedAmount FROM ord.FeeConfigs
        WHERE FeeType = N'DeliveryBase' AND FixedAmount IS NOT NULL
          AND (ScopeLabId = @LabId OR ScopeLabId IS NULL)
          AND EffectiveFrom <= @OnDate AND (EffectiveTo IS NULL OR EffectiveTo >= @OnDate)
        ORDER BY CASE WHEN ScopeLabId IS NULL THEN 1 ELSE 0 END, EffectiveFrom DESC);
    RETURN ISNULL(@Fee, 25000);
END
GO