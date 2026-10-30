/* ============================================================
   File    : database/08_triggers/ord_feedback.sql
   Module  : ord_feedback - M6 Review & Complaint
   Purpose : Trigger: trg_Reviews_CheckEligible, trg_Reviews_UpdateRating, trg_Complaints_Guard, trg_Complaints_Notify, trg_Complaints_Audit. Dùng templates/trigger_template.sql.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord (ord.sql chạy trước)
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Chỉ cho phép đánh giá đơn Completed trong 30 ngày (bảo vệ cả khi INSERT trực tiếp)
CREATE OR ALTER TRIGGER ord.trg_Reviews_CheckEligible
ON ord.Reviews
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i JOIN ord.Orders o ON o.OrderId = i.OrderId
               WHERE o.StageId <> 12 OR o.CompletedAt IS NULL
                  OR DATEADD(DAY, 30, o.CompletedAt) < SYSUTCDATETIME())
        THROW 50302, N'Chỉ đánh giá được đơn đã hoàn tất trong vòng 30 ngày.', 1;
END
GO

-- Tính lại AvgRating/ReviewCount của lab khi có đánh giá mới, đổi điểm, ẩn/hiện hoặc xóa mềm
CREATE OR ALTER TRIGGER ord.trg_Reviews_UpdateRating
ON ord.Reviews
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF EXISTS (SELECT 1 FROM deleted)
       AND NOT (UPDATE(RatingOverall) OR UPDATE(IsVisible) OR UPDATE(IsDeleted))
        RETURN;

    DECLARE @labs TABLE (Seq INT IDENTITY(1,1), LabId INT);
    INSERT INTO @labs (LabId) SELECT LabId FROM inserted UNION SELECT LabId FROM deleted;

    DECLARE @s INT = 0, @lab INT;
    WHILE 1 = 1
    BEGIN
        SELECT TOP 1 @s = Seq, @lab = LabId FROM @labs WHERE Seq > @s ORDER BY Seq;
        IF @@ROWCOUNT = 0 BREAK;
        EXEC lab.sp_RecalcLabRating @LabId = @lab;
    END;
END
GO

-- Chặn chuyển trạng thái khiếu nại sai (kể cả UPDATE trực tiếp)
CREATE OR ALTER TRIGGER ord.trg_Complaints_Guard
ON ord.Complaints
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    IF NOT UPDATE(Status) RETURN;

    IF EXISTS (SELECT 1
               FROM inserted i JOIN deleted d ON d.ComplaintId = i.ComplaintId
               WHERE i.Status <> d.Status
                 AND ord.fn_IsValidComplaintTransition(d.Status, i.Status) = 0)
        THROW 50302, N'Chuyển trạng thái khiếu nại không hợp lệ.', 1;
END
GO

-- Thông báo khi tạo khiếu nại (báo chủ lab) và khi đổi trạng thái (báo khách, kết thúc thì báo thêm chủ lab)
CREATE OR ALTER TRIGGER ord.trg_Complaints_Notify
ON ord.Complaints
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @n TABLE (Seq INT IDENTITY(1,1), UserId INT, Title NVARCHAR(150), Body NVARCHAR(500), OrderId INT);

    INSERT INTO @n (UserId, Title, Body, OrderId)
    SELECT l.OwnerUserId, N'Khiếu nại mới cho đơn ' + o.OrderCode, LEFT(i.Title, 500), i.OrderId
    FROM inserted i
    LEFT JOIN deleted d ON d.ComplaintId = i.ComplaintId
    JOIN ord.Orders o ON o.OrderId = i.OrderId
    JOIN lab.FilmLabs l ON l.LabId = i.LabId
    WHERE d.ComplaintId IS NULL;

    INSERT INTO @n (UserId, Title, Body, OrderId)
    SELECT i.CustomerId,
           N'Khiếu nại đơn ' + o.OrderCode + N': '
             + CASE i.Status WHEN N'InReview' THEN N'đang được xử lý'
                             WHEN N'Resolved' THEN N'đã được giải quyết'
                             WHEN N'Rejected' THEN N'bị từ chối' ELSE i.Status END,
           LEFT(i.Resolution, 500), i.OrderId
    FROM inserted i
    JOIN deleted d ON d.ComplaintId = i.ComplaintId
    JOIN ord.Orders o ON o.OrderId = i.OrderId
    WHERE d.Status <> i.Status;

    INSERT INTO @n (UserId, Title, Body, OrderId)
    SELECT l.OwnerUserId,
           N'Khiếu nại đơn ' + o.OrderCode + N' đã ' + CASE i.Status WHEN N'Resolved' THEN N'được giải quyết' ELSE N'bị từ chối' END,
           LEFT(i.Resolution, 500), i.OrderId
    FROM inserted i
    JOIN deleted d ON d.ComplaintId = i.ComplaintId
    JOIN ord.Orders o ON o.OrderId = i.OrderId
    JOIN lab.FilmLabs l ON l.LabId = i.LabId
    WHERE d.Status <> i.Status AND i.Status IN (N'Resolved', N'Rejected');

    DECLARE @s INT = 0, @u INT, @t NVARCHAR(150), @b NVARCHAR(500), @oid INT;
    WHILE 1 = 1
    BEGIN
        SELECT TOP 1 @s = Seq, @u = UserId, @t = Title, @b = Body, @oid = OrderId FROM @n WHERE Seq > @s ORDER BY Seq;
        IF @@ROWCOUNT = 0 BREAK;
        EXEC arc.sp_CreateNotification @UserId = @u, @Type = N'Complaint', @Title = @t, @Body = @b, @OrderId = @oid;
    END;
END
GO

-- Ghi nhật ký thay đổi khiếu nại qua audit.sp_WriteAudit
CREATE OR ALTER TRIGGER ord.trg_Complaints_Audit
ON ord.Complaints
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @ids TABLE (Seq INT IDENTITY(1,1), Id INT, IsNew BIT);
    INSERT INTO @ids (Id, IsNew)
    SELECT i.ComplaintId, CASE WHEN d.ComplaintId IS NULL THEN 1 ELSE 0 END
    FROM inserted i LEFT JOIN deleted d ON d.ComplaintId = i.ComplaintId;

    DECLARE @s INT = 0, @id INT, @isnew BIT, @act NVARCHAR(6), @pk NVARCHAR(100), @old NVARCHAR(MAX), @new NVARCHAR(MAX);
    WHILE 1 = 1
    BEGIN
        SELECT TOP 1 @s = Seq, @id = Id, @isnew = IsNew FROM @ids WHERE Seq > @s ORDER BY Seq;
        IF @@ROWCOUNT = 0 BREAK;

        SET @new = (SELECT ComplaintId, OrderId, CustomerId, LabId, Category, Title, Status, AssignedAdminId,
                           ResolutionType, Resolution, RefundAmount, ResolvedAt, IsDeleted
                    FROM inserted WHERE ComplaintId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SET @old = CASE WHEN @isnew = 1 THEN NULL ELSE
                   (SELECT ComplaintId, OrderId, CustomerId, LabId, Category, Title, Status, AssignedAdminId,
                           ResolutionType, Resolution, RefundAmount, ResolvedAt, IsDeleted
                    FROM deleted WHERE ComplaintId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) END;
        SET @act = CASE WHEN @isnew = 1 THEN N'INSERT' ELSE N'UPDATE' END;
        SET @pk = CAST(@id AS NVARCHAR(100));

        EXEC audit.sp_WriteAudit @TableSchema = N'ord', @TableName = N'Complaints', @PrimaryKeyValue = @pk,
                                 @Action = @act, @OldValues = @old, @NewValues = @new;
    END;
END
GO
