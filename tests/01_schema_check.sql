/* ============================================================
   File    : tests/01_schema_check.sql
   Purpose : Đợt 5 - kiểm tra schema đã dựng đúng: số bảng/FK/index, seed danh mục, temporal,
             và các ràng buộc quan trọng CHẶN được dữ liệu sai. Sai thì THROW. Sinh bởi tools (xem gen_sql.py).
   ============================================================ */
USE FilmLabDB;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

-- 1) 41 bảng (không tính bảng lịch sử của temporal), 77 FK
DECLARE @t INT = (SELECT COUNT(*) FROM sys.tables WHERE temporal_type <> 1
                  AND SCHEMA_NAME(schema_id) IN (N'iam',N'lab',N'ord',N'dlv',N'arc',N'mkt',N'com',N'ai',N'audit'));
DECLARE @f INT = (SELECT COUNT(*) FROM sys.foreign_keys);
IF @t <> 41 BEGIN DECLARE @m1 NVARCHAR(100) = N'Số bảng = ' + CAST(@t AS NVARCHAR(10)) + N', cần 41'; THROW 59001, @m1, 1; END
IF @f <> 77 BEGIN DECLARE @m2 NVARCHAR(100) = N'Số FK = ' + CAST(@f AS NVARCHAR(10)) + N', cần 77'; THROW 59002, @m2, 1; END

-- 2) Index đủ
DECLARE @missing NVARCHAR(MAX) = N'';
SELECT @missing += v.n + N' ' FROM (VALUES
    (N'UX_Users_Email'),
    (N'UX_Addresses_Default'),
    (N'UX_Payments_OrderPaid'),
    (N'UX_Delivery_ActiveLeg'),
    (N'UX_Albums_Owner_Title'),
    (N'UX_ListingImages_Primary'),
    (N'UX_Articles_Slug'),
    (N'UX_Comments_Accepted'),
    (N'UX_Knowledge_Chunk'),
    (N'UX_Complaints_OpenPerCategory'),
    (N'IX_FilmLabs_Approval_City'),
    (N'IX_LabServices_Search'),
    (N'IX_Orders_Customer'),
    (N'IX_Orders_Lab_Stage'),
    (N'IX_OrderItems_Order'),
    (N'IX_OrderStageLog_Order'),
    (N'IX_Delivery_Partner_Status'),
    (N'IX_DeliveryLog_Request'),
    (N'IX_ScanFiles_Owner'),
    (N'IX_ScanFiles_Order'),
    (N'IX_PhotoMetadata_Stock'),
    (N'IX_AlbumPhotos_ScanFile'),
    (N'IX_Notifications_User'),
    (N'IX_Reviews_Lab'),
    (N'IX_Complaints_Status'),
    (N'IX_Listings_Browse'),
    (N'IX_MktTxn_Buyer'),
    (N'IX_MktTxn_Seller_Status'),
    (N'IX_Messages_Thread'),
    (N'IX_Articles_Feed'),
    (N'IX_Comments_Article'),
    (N'IX_Events_Upcoming'),
    (N'IX_EventReg_User'),
    (N'IX_ChatLogs_Session'),
    (N'IX_ChatLogs_User'),
    (N'IX_RecLogs_User'),
    (N'IX_RecLogs_Item'),
    (N'IX_Audit_Record'),
    (N'IX_Audit_User'),
    (N'SIX_FilmLabs_Location')
) v(n) WHERE NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.name = v.n);
IF @missing <> N'' BEGIN DECLARE @m3 NVARCHAR(MAX) = N'Thiếu index: ' + @missing; THROW 59003, @m3, 1; END

-- 3) Temporal table
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID(N'lab.LabServices') AND temporal_type = 2)
    THROW 59004, N'lab.LabServices chưa là temporal table', 1;

-- 4) Seed danh mục
DECLARE @bad NVARCHAR(MAX) = N'';
SELECT @bad += v.tbl + N'=' + CAST(v.actual AS NVARCHAR(10)) + N'(cần ' + CAST(v.expected AS NVARCHAR(10)) + N') ' FROM (VALUES
    (N'iam.Roles', (SELECT COUNT(*) FROM iam.Roles), 5),
    (N'ord.ProcessingStages', (SELECT COUNT(*) FROM ord.ProcessingStages), 13),
    (N'lab.FilmFormats', (SELECT COUNT(*) FROM lab.FilmFormats), 5),
    (N'lab.ServiceTypes', (SELECT COUNT(*) FROM lab.ServiceTypes), 4),
    (N'lab.FilmStocks', (SELECT COUNT(*) FROM lab.FilmStocks), 15),
    (N'mkt.ListingCategories', (SELECT COUNT(*) FROM mkt.ListingCategories), 6),
    (N'ord.FeeConfigs', (SELECT COUNT(*) FROM ord.FeeConfigs), 3)
) v(tbl, actual, expected) WHERE v.actual <> v.expected;
IF @bad <> N'' BEGIN DECLARE @m4 NVARCHAR(MAX) = N'Seed sai số dòng: ' + @bad; THROW 59005, @m4, 1; END

-- 5) Ràng buộc phải CHẶN dữ liệu sai (mỗi lệnh phải lỗi; chạy trong transaction rồi rollback)
DECLARE @fail NVARCHAR(MAX) = N'';
DECLARE @cases TABLE (id INT IDENTITY, name NVARCHAR(100), sqltext NVARCHAR(MAX));
INSERT @cases(name, sqltext) VALUES
 (N'Email sai định dạng',            N'INSERT iam.Users (Email,FullName) VALUES (N''khong-phai-email'', N''X'')'),
 (N'Email trùng (user chưa xóa)',    N'INSERT iam.Users (Email,PasswordHash,FullName) VALUES (N''admin@filmlab.vn'', N''h'', N''X'')'),
 (N'Local mà không có PasswordHash', N'INSERT iam.Users (Email,AuthProvider,FullName) VALUES (N''a1@x.vn'', N''Local'', N''X'')'),
 (N'SĐT chứa chữ',                   N'INSERT iam.Users (Email,PasswordHash,FullName,Phone) VALUES (N''a2@x.vn'', N''h'', N''X'', N''09abc12345'')'),
 (N'Hai địa chỉ mặc định',           N'INSERT iam.Addresses (UserId,RecipientName,Phone,Line1,Ward,District,City,IsDefault) SELECT UserId,N''X'',N''0911000001'',N''x'',N''x'',N''x'',N''x'',1 FROM iam.Users WHERE Email=N''an.nguyen@example.com'''),
 (N'Đối tác Individual thiếu UserId',N'INSERT iam.DeliveryPartners (ProviderType,PartnerName) VALUES (N''Individual'', N''X'')'),
 (N'Role trùng mã',                  N'INSERT iam.Roles (RoleId,RoleCode,RoleName) VALUES (99, N''Admin'', N''X'')'),
 (N'Hoa hồng ngoài 0..1',            N'INSERT ord.FeeConfigs (FeeType,Rate,EffectiveFrom,CreatedBy) SELECT N''PlatformCommission'',1.5,''2026-01-01'',UserId FROM iam.Users WHERE Email=N''admin@filmlab.vn''');
DECLARE @i INT = 1, @max INT = (SELECT MAX(id) FROM @cases), @sql NVARCHAR(MAX), @nm NVARCHAR(100), @ok BIT;
WHILE @i <= @max
BEGIN
    SELECT @sql = sqltext, @nm = name FROM @cases WHERE id = @i;
    SET @ok = 0;
    BEGIN TRAN;
    BEGIN TRY EXEC (@sql); END TRY BEGIN CATCH SET @ok = 1; END CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    IF @ok = 0 SET @fail += @nm + N'; ';
    SET @i += 1;
END
IF @fail <> N'' BEGIN DECLARE @m5 NVARCHAR(MAX) = N'Ràng buộc KHÔNG chặn được: ' + @fail; THROW 59006, @m5, 1; END

PRINT N'SCHEMA CHECK (Đợt 5): PASS';
GO
