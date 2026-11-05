/* ============================================================
   File    : database/09_security/03_row_level_security.sql
   Module  : security - Row-Level Security (multi-tenant)
   Purpose : Security policy: LabOwner chỉ thấy đơn của lab mình. Làm CUỐI CÙNG rồi test lại toàn bộ.
   Owner   : TBD (chưa chia việc)
   Depends : lab, ord
   Re-run  : DROP SECURITY POLICY IF EXISTS rồi tạo lại.
   Ref     : docs/Conventions.md, docs/Contracts.md
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ===== 0. Gỡ policy cũ (hàm có SCHEMABINDING nên phải gỡ trước khi sửa hàm) =====
DROP SECURITY POLICY IF EXISTS sec.pol_Orders;
DROP SECURITY POLICY IF EXISTS sec.pol_ScanFiles;
DROP SECURITY POLICY IF EXISTS sec.pol_Albums;
DROP SECURITY POLICY IF EXISTS sec.pol_DeliveryRequests;
DROP SECURITY POLICY IF EXISTS sec.pol_Notifications;
DROP SECURITY POLICY IF EXISTS sec.pol_UserPreferences;
DROP SECURITY POLICY IF EXISTS sec.pol_AIChatLogs;
DROP SECURITY POLICY IF EXISTS sec.pol_RecommendationLogs;
DROP SECURITY POLICY IF EXISTS sec.pol_LabApprovals;
DROP SECURITY POLICY IF EXISTS sec.pol_Articles;
DROP SECURITY POLICY IF EXISTS sec.pol_MarketTransactions;
DROP SECURITY POLICY IF EXISTS sec.pol_Messages;
GO

IF SCHEMA_ID(N'sec') IS NULL EXEC (N'CREATE SCHEMA sec AUTHORIZATION dbo;');
GO

-- ===== 1. Predicate functions =====
-- Cho qua: db_owner (dbo, test cũ 02-16) và role_Admin. role_* khác lọc chặt theo UserId.
-- Principal không thuộc role nào và không có UserId cũng không thấy dòng nào (trừ db_owner).

-- Chỉ chủ sở hữu (UserId = người dùng hiện tại)
CREATE OR ALTER FUNCTION sec.fn_OwnerAccess(@UserId INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR @UserId = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
GO

-- Đơn: khách của đơn, chủ lab của đơn, hoặc đối tác đang được giao chặng của đơn (BR-ORD-08)
CREATE OR ALTER FUNCTION sec.fn_OrderAccess(@OrderId INT, @CustomerId INT, @LabId INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR @CustomerId = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
   OR EXISTS (SELECT 1 FROM lab.FilmLabs l
              WHERE l.LabId = @LabId
                AND l.OwnerUserId = CONVERT(INT, SESSION_CONTEXT(N'UserId')))
   OR EXISTS (SELECT 1 FROM dlv.DeliveryRequests d
              JOIN iam.DeliveryPartners p ON p.DeliveryPartnerId = d.DeliveryPartnerId
              WHERE d.OrderId = @OrderId
                AND p.UserId = CONVERT(INT, SESSION_CONTEXT(N'UserId')));
GO

-- Scan: chủ ảnh hoặc chủ lab của đơn (BR-ARC-01, ARC-09)
CREATE OR ALTER FUNCTION sec.fn_ScanAccess(@OwnerUserId INT, @OrderId INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR @OwnerUserId = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
   OR EXISTS (SELECT 1 FROM ord.Orders o
              JOIN lab.FilmLabs l ON l.LabId = o.LabId
              WHERE o.OrderId = @OrderId
                AND l.OwnerUserId = CONVERT(INT, SESSION_CONTEXT(N'UserId')));
GO

-- Album: chủ album, hoặc album công khai (BR-ARC-09)
CREATE OR ALTER FUNCTION sec.fn_AlbumAccess(@OwnerUserId INT, @IsPublic BIT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR @IsPublic = 1
   OR @OwnerUserId = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
GO

-- Album (ghi): chỉ chủ album. Khác fn_AlbumAccess vì album công khai chỉ cho người khác ĐỌC, không cho sửa/xóa
CREATE OR ALTER FUNCTION sec.fn_AlbumWriteAccess(@OwnerUserId INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR @OwnerUserId = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
GO

-- Dữ liệu riêng của lab (LabApprovals): chủ lab của dòng đó đọc được, Admin xem tất cả
CREATE OR ALTER FUNCTION sec.fn_LabPrivateAccess(@LabId INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR EXISTS (SELECT 1 FROM lab.FilmLabs l
              WHERE l.LabId = @LabId
                AND l.OwnerUserId = CONVERT(INT, SESSION_CONTEXT(N'UserId')));
GO

-- Quyết định duyệt lab (ghi): chỉ Admin. Chủ lab chỉ đọc quyết định của lab mình, không được ghi
CREATE OR ALTER FUNCTION sec.fn_LabApprovalWriteAccess(@LabId INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1;
GO

-- Bài viết (đọc, BR-COM-04): bài Published ai cũng thấy; tác giả thấy thêm bài Draft và Hidden của mình; Admin thấy tất cả
CREATE OR ALTER FUNCTION sec.fn_ArticleAccess(@AuthorId INT, @Status NVARCHAR(9))
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR @Status = N'Published'
   OR @AuthorId = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
GO

-- Bài viết (ghi): chỉ tác giả hoặc Admin. Bài Published của người khác chỉ cho đọc, không cho sửa/xóa
CREATE OR ALTER FUNCTION sec.fn_ArticleWriteAccess(@AuthorId INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR @AuthorId = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
GO
-- Hai bên của giao dịch/tin nhắn (BR-MKT-15): một trong hai bên hoặc Admin. Dùng cho mkt.MarketTransactions (Seller, Buyer) và mkt.Messages (Sender, Receiver)
CREATE OR ALTER FUNCTION sec.fn_TwoPartyAccess(@PartyA INT, @PartyB INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR @PartyA = CONVERT(INT, SESSION_CONTEXT(N'UserId'))
   OR @PartyB = CONVERT(INT, SESSION_CONTEXT(N'UserId'));
GO

-- Chặng giao: đối tác được giao, hoặc khách sở hữu địa chỉ của chặng (BR-DLV-11)
CREATE OR ALTER FUNCTION sec.fn_DeliveryAccess(@DeliveryPartnerId INT, @CustomerAddressId INT)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS Allowed
WHERE IS_MEMBER(N'db_owner') = 1 OR IS_MEMBER(N'role_Admin') = 1
   OR EXISTS (SELECT 1 FROM iam.DeliveryPartners p
              WHERE p.DeliveryPartnerId = @DeliveryPartnerId
                AND p.UserId = CONVERT(INT, SESSION_CONTEXT(N'UserId')))
   OR EXISTS (SELECT 1 FROM iam.Addresses a
              WHERE a.AddressId = @CustomerAddressId
                AND a.UserId = CONVERT(INT, SESSION_CONTEXT(N'UserId')));
GO

-- ===== 2. Security policies (FILTER cả 12 bảng; BLOCK cho Albums, ScanFiles, UserPreferences, AIChatLogs, RecommendationLogs, LabApprovals, Articles, MarketTransactions, Messages; Orders, Notifications, DeliveryRequests chỉ FILTER vì procedure ghi hộ người khác) =====
CREATE SECURITY POLICY sec.pol_Orders
    ADD FILTER PREDICATE sec.fn_OrderAccess(OrderId, CustomerId, LabId) ON ord.Orders
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_ScanFiles
    ADD FILTER PREDICATE sec.fn_ScanAccess(OwnerUserId, OrderId) ON arc.ScanFiles,
    ADD BLOCK PREDICATE sec.fn_ScanAccess(OwnerUserId, OrderId) ON arc.ScanFiles AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_ScanAccess(OwnerUserId, OrderId) ON arc.ScanFiles AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_ScanAccess(OwnerUserId, OrderId) ON arc.ScanFiles BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_ScanAccess(OwnerUserId, OrderId) ON arc.ScanFiles BEFORE DELETE
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_Albums
    ADD FILTER PREDICATE sec.fn_AlbumAccess(OwnerUserId, IsPublic) ON arc.Albums,
    ADD BLOCK PREDICATE sec.fn_AlbumWriteAccess(OwnerUserId) ON arc.Albums AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_AlbumWriteAccess(OwnerUserId) ON arc.Albums AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_AlbumWriteAccess(OwnerUserId) ON arc.Albums BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_AlbumWriteAccess(OwnerUserId) ON arc.Albums BEFORE DELETE
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_DeliveryRequests
    ADD FILTER PREDICATE sec.fn_DeliveryAccess(DeliveryPartnerId, CustomerAddressId) ON dlv.DeliveryRequests
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_Notifications
    ADD FILTER PREDICATE sec.fn_OwnerAccess(UserId) ON arc.Notifications
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_UserPreferences
    ADD FILTER PREDICATE sec.fn_OwnerAccess(UserId) ON ai.UserPreferences,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.UserPreferences AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.UserPreferences AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.UserPreferences BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.UserPreferences BEFORE DELETE
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_AIChatLogs
    ADD FILTER PREDICATE sec.fn_OwnerAccess(UserId) ON ai.AIChatLogs,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.AIChatLogs AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.AIChatLogs AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.AIChatLogs BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.AIChatLogs BEFORE DELETE
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_RecommendationLogs
    ADD FILTER PREDICATE sec.fn_OwnerAccess(UserId) ON ai.RecommendationLogs,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.RecommendationLogs AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.RecommendationLogs AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.RecommendationLogs BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(UserId) ON ai.RecommendationLogs BEFORE DELETE
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_LabApprovals
    ADD FILTER PREDICATE sec.fn_LabPrivateAccess(LabId) ON lab.LabApprovals,
    ADD BLOCK PREDICATE sec.fn_LabApprovalWriteAccess(LabId) ON lab.LabApprovals AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_LabApprovalWriteAccess(LabId) ON lab.LabApprovals AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_LabApprovalWriteAccess(LabId) ON lab.LabApprovals BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_LabApprovalWriteAccess(LabId) ON lab.LabApprovals BEFORE DELETE
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_Articles
    ADD FILTER PREDICATE sec.fn_ArticleAccess(AuthorId, Status) ON com.Articles,
    ADD BLOCK PREDICATE sec.fn_ArticleWriteAccess(AuthorId) ON com.Articles AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_ArticleWriteAccess(AuthorId) ON com.Articles AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_ArticleWriteAccess(AuthorId) ON com.Articles BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_ArticleWriteAccess(AuthorId) ON com.Articles BEFORE DELETE
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_MarketTransactions
    ADD FILTER PREDICATE sec.fn_TwoPartyAccess(SellerId, BuyerId) ON mkt.MarketTransactions,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(BuyerId) ON mkt.MarketTransactions AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_TwoPartyAccess(SellerId, BuyerId) ON mkt.MarketTransactions AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_TwoPartyAccess(SellerId, BuyerId) ON mkt.MarketTransactions BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_TwoPartyAccess(SellerId, BuyerId) ON mkt.MarketTransactions BEFORE DELETE
    WITH (STATE = ON);
CREATE SECURITY POLICY sec.pol_Messages
    ADD FILTER PREDICATE sec.fn_TwoPartyAccess(SenderId, ReceiverId) ON mkt.Messages,
    ADD BLOCK PREDICATE sec.fn_OwnerAccess(SenderId) ON mkt.Messages AFTER INSERT,
    ADD BLOCK PREDICATE sec.fn_TwoPartyAccess(SenderId, ReceiverId) ON mkt.Messages AFTER UPDATE,
    ADD BLOCK PREDICATE sec.fn_TwoPartyAccess(SenderId, ReceiverId) ON mkt.Messages BEFORE UPDATE,
    ADD BLOCK PREDICATE sec.fn_TwoPartyAccess(SenderId, ReceiverId) ON mkt.Messages BEFORE DELETE
    WITH (STATE = ON);
GO

-- ===== 3. Quyền thực thi hàm predicate cho các role =====
GRANT SELECT ON SCHEMA::sec TO role_Customer, role_LabOwner, role_Expert, role_Delivery, role_Admin;
GO

