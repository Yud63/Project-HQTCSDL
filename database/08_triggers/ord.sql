/* ============================================================
   File    : database/08_triggers/ord.sql
   Module  : ord - M3 Order, Processing, Payment, Fee
   Purpose : Trigger: trg_Orders_LogStage, trg_Orders_PreventInvalidStage, trg_Payments_UpdateOrder, trg_FeeConfigs_NoOverlap, trg_Payments_Audit. Dùng templates/trigger_template.sql.
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

-- Chặn chuyển giai đoạn sai thứ tự (bảo vệ cả khi ai đó UPDATE trực tiếp, không qua procedure)
CREATE OR ALTER TRIGGER ord.trg_Orders_PreventInvalidStage
ON ord.Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT UPDATE(StageId) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i JOIN deleted d ON d.OrderId = i.OrderId
               WHERE i.StageId <> d.StageId
                 AND ord.fn_IsValidTransition(i.OrderId, d.StageId, i.StageId) = 0)
        THROW 50302, N'Chuyển giai đoạn đơn không hợp lệ.', 1;
END
GO

-- Ghi OrderStageLog khi tạo đơn và khi đổi StageId
CREATE OR ALTER TRIGGER ord.trg_Orders_LogStage
ON ord.Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    INSERT INTO ord.OrderStageLog (OrderId, FromStageId, ToStageId, ChangedBy, Note)
    SELECT i.OrderId, d.StageId, i.StageId,
           TRY_CONVERT(INT, SESSION_CONTEXT(N'UserId')),
           CASE WHEN d.OrderId IS NULL THEN N'Khởi tạo đơn'
                ELSE CONVERT(NVARCHAR(255), SESSION_CONTEXT(N'StageNote')) END
    FROM inserted i
    LEFT JOIN deleted d ON d.OrderId = i.OrderId
    WHERE d.OrderId IS NULL OR d.StageId <> i.StageId;
END
GO

-- Đồng bộ Orders.PaymentStatus theo các dòng Payments (Succeeded -> Paid, Refunded -> Refunded, còn lại Unpaid)
CREATE OR ALTER TRIGGER ord.trg_Payments_UpdateOrder
ON ord.Payments
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    ;WITH x AS (
        SELECT o.OrderId,
               NewStatus = CASE
                   WHEN EXISTS (SELECT 1 FROM ord.Payments p WHERE p.OrderId = o.OrderId AND p.Status = N'Succeeded') THEN N'Paid'
                   WHEN EXISTS (SELECT 1 FROM ord.Payments p WHERE p.OrderId = o.OrderId AND p.Status = N'Refunded')  THEN N'Refunded'
                   ELSE N'Unpaid' END
        FROM ord.Orders o
        WHERE o.OrderId IN (SELECT OrderId FROM inserted UNION SELECT OrderId FROM deleted))
    UPDATE o SET PaymentStatus = x.NewStatus, UpdatedAt = SYSUTCDATETIME()
    FROM ord.Orders o JOIN x ON x.OrderId = o.OrderId
    WHERE o.PaymentStatus <> x.NewStatus;
END
GO

-- Không cho hai khoảng hiệu lực chồng nhau cùng (FeeType, ScopeLabId); NULL scope = toàn hệ thống
CREATE OR ALTER TRIGGER ord.trg_FeeConfigs_NoOverlap
ON ord.FeeConfigs
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT (UPDATE(FeeType) OR UPDATE(ScopeLabId) OR UPDATE(EffectiveFrom) OR UPDATE(EffectiveTo)) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i
               JOIN ord.FeeConfigs f
                 ON f.FeeConfigId <> i.FeeConfigId
                AND f.FeeType = i.FeeType
                AND ISNULL(f.ScopeLabId, 0) = ISNULL(i.ScopeLabId, 0)
                AND f.EffectiveFrom <= ISNULL(i.EffectiveTo, CONVERT(DATE, '9999-12-31'))
                AND i.EffectiveFrom <= ISNULL(f.EffectiveTo, CONVERT(DATE, '9999-12-31')))
        THROW 50304, N'Khoảng hiệu lực của cấu hình phí bị chồng với cấu hình khác cùng loại và phạm vi.', 1;
END
GO

-- Ghi nhật ký khi Payments đổi dữ liệu nghiệp vụ (chỉ UPDATE)
CREATE OR ALTER TRIGGER ord.trg_Payments_Audit
ON ord.Payments
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT (UPDATE(Method) OR UPDATE(Amount) OR UPDATE(Status) OR UPDATE(PaidAt)
            OR UPDATE(RefundedAt) OR UPDATE(FailureReason)) RETURN;

    DECLARE @Pk NVARCHAR(100), @Old NVARCHAR(MAX), @New NVARCHAR(MAX);
    DECLARE @By INT = TRY_CAST(SESSION_CONTEXT(N'UserId') AS INT);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT CAST(i.PaymentId AS NVARCHAR(100)),
               (SELECT d.PaymentId, d.OrderId, d.Method, d.Provider, d.ProviderTxnId, d.Amount,
                       d.Status, d.PaidAt, d.RefundedAt, d.FailureReason
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER),
               (SELECT i.PaymentId, i.OrderId, i.Method, i.Provider, i.ProviderTxnId, i.Amount,
                       i.Status, i.PaidAt, i.RefundedAt, i.FailureReason
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER)
        FROM inserted i
        JOIN deleted d ON d.PaymentId = i.PaymentId
        WHERE EXISTS (SELECT i.Method, i.Amount, i.Status, i.PaidAt, i.RefundedAt, i.FailureReason
                      EXCEPT
                      SELECT d.Method, d.Amount, d.Status, d.PaidAt, d.RefundedAt, d.FailureReason);

    OPEN c;
    FETCH NEXT FROM c INTO @Pk, @Old, @New;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC audit.sp_WriteAudit N'ord', N'Payments', @Pk, N'UPDATE', @Old, @New, @By;
        FETCH NEXT FROM c INTO @Pk, @Old, @New;
    END;
    CLOSE c;
    DEALLOCATE c;
END
GO