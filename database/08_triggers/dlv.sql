/* ============================================================
   File    : database/08_triggers/dlv.sql
   Module  : dlv - M4 Delivery
   Purpose : Trigger: trg_DeliveryRequests_LogStatus, trg_DeliveryRequests_Guard. Dùng templates/trigger_template.sql.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : iam, ord
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Ghi DeliveryStatusLog khi tạo chặng và khi đổi Status
CREATE OR ALTER TRIGGER dlv.trg_DeliveryRequests_LogStatus
ON dlv.DeliveryRequests
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    INSERT INTO dlv.DeliveryStatusLog (DeliveryRequestId, FromStatus, ToStatus, ChangedBy, Note)
    SELECT i.DeliveryRequestId, d.Status, i.Status,
           TRY_CONVERT(INT, SESSION_CONTEXT(N'UserId')),
           CASE WHEN d.DeliveryRequestId IS NULL THEN N'Tạo chặng giao'
                ELSE CONVERT(NVARCHAR(255), SESSION_CONTEXT(N'DeliveryNote')) END
    FROM inserted i
    LEFT JOIN deleted d ON d.DeliveryRequestId = i.DeliveryRequestId
    WHERE d.DeliveryRequestId IS NULL OR d.Status <> i.Status;
END
GO

-- Chặn chuyển trạng thái chặng giao sai (kể cả UPDATE trực tiếp, không qua procedure)
CREATE OR ALTER TRIGGER dlv.trg_DeliveryRequests_Guard
ON dlv.DeliveryRequests
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT UPDATE(Status) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i JOIN deleted d ON d.DeliveryRequestId = i.DeliveryRequestId
               WHERE i.Status <> d.Status
                 AND dlv.fn_IsValidDeliveryTransition(d.Status, i.Status) = 0)
        THROW 50402, N'Chuyển trạng thái chặng giao không hợp lệ.', 1;
END
GO
