/* TEMPLATE Trigger - copy vào database/08_triggers/<module>.sql
   Quy tắc: set-based (xử lý nhiều dòng), không dùng biến scalar từ inserted;
            không UPDATE lại chính bảng đã kích hoạt; chống đệ quy bằng TRIGGER_NESTLEVEL. */
CREATE OR ALTER TRIGGER ord.trg_Orders_LogStage
ON ord.Orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;                 -- chống trigger gọi vòng
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;
    IF NOT UPDATE(StageId) RETURN;                     -- chỉ chạy khi đổi giai đoạn

    INSERT INTO ord.OrderStageLog (OrderId, StageId, ChangedAt)
    SELECT i.OrderId, i.StageId, SYSUTCDATETIME()
    FROM inserted i
    JOIN deleted  d ON d.OrderId = i.OrderId
    WHERE i.StageId <> d.StageId;
END
GO
