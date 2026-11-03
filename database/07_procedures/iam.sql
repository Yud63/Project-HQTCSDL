/* ============================================================
   File    : database/07_procedures/iam.sql
   Module  : iam - M1 Identity & Access
   Purpose : Procedure (★ = bắt buộc): ★sp_RegisterUser. Dùng templates/procedure_template.sql; chữ ký theo docs/Contracts.md mục 7.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (gốc)
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc: iam.Users có filtered index
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE iam.sp_RegisterUser
    @Email         NVARCHAR(255),
    @FullName      NVARCHAR(100),
    @PasswordHash  NVARCHAR(255) = NULL,
    @AuthProvider  NVARCHAR(20)  = N'Local',
    @Phone         NVARCHAR(20)  = NULL,
    @NewUserId     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @Email = LTRIM(RTRIM(@Email));
        IF NULLIF(@Email, N'') IS NULL OR NULLIF(LTRIM(RTRIM(@FullName)), N'') IS NULL
            THROW 50105, N'Email và họ tên không được rỗng.', 1;
        IF @AuthProvider NOT IN (N'Local', N'Google', N'Facebook')
            THROW 50105, N'AuthProvider không hợp lệ.', 1;
        IF @AuthProvider = N'Local' AND NULLIF(@PasswordHash, N'') IS NULL
            THROW 50105, N'Tài khoản Local bắt buộc có PasswordHash.', 1;
        IF EXISTS (SELECT 1 FROM iam.Users WHERE Email = @Email AND IsDeleted = 0)
            THROW 50104, N'Email đã tồn tại.', 1;

        BEGIN TRAN;
            INSERT INTO iam.Users (Email, AuthProvider, PasswordHash, FullName, Phone)
            VALUES (@Email, @AuthProvider, @PasswordHash, @FullName, @Phone);
            SET @NewUserId = SCOPE_IDENTITY();

            EXEC sp_set_session_context @key = N'UserId', @value = @NewUserId;

            INSERT INTO iam.UserRoles (UserId, RoleId, AssignedBy)
            SELECT @NewUserId, RoleId, NULL FROM iam.Roles WHERE RoleCode = N'Customer';
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        -- Hai request cùng email chạy đồng thời: unique index bắt được, đổi sang mã lỗi chuẩn
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50104, N'Email đã tồn tại.', 1;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE iam.sp_SaveAddress
    @UserId        INT,
    @RecipientName NVARCHAR(100),
    @Phone         NVARCHAR(20),
    @Line1         NVARCHAR(255),
    @Ward          NVARCHAR(100),
    @District      NVARCHAR(100),
    @City          NVARCHAR(100),
    @AddressId     INT           = NULL,   -- NULL: thêm mới
    @Label         NVARCHAR(50)  = NULL,
    @Latitude      FLOAT         = NULL,
    @Longitude     FLOAT         = NULL,
    @IsDefault     BIT           = 0,
    @IsDeleted     BIT           = 0,      -- 1: xóa mềm (vẫn phải truyền lại các trường bắt buộc)
    @NewAddressId  INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @UserId;

        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsActive = 1 AND IsDeleted = 0)
            THROW 50101, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;

        SET @RecipientName = LTRIM(RTRIM(@RecipientName));
        SET @Line1 = LTRIM(RTRIM(@Line1));
        SET @Ward = LTRIM(RTRIM(@Ward));
        SET @District = LTRIM(RTRIM(@District));
        SET @City = LTRIM(RTRIM(@City));
        IF NULLIF(@RecipientName, N'') IS NULL OR NULLIF(@Line1, N'') IS NULL OR NULLIF(@Ward, N'') IS NULL
           OR NULLIF(@District, N'') IS NULL OR NULLIF(@City, N'') IS NULL
            THROW 50105, N'Họ tên, địa chỉ, phường, quận và thành phố không được rỗng.', 1;
        IF @Phone IS NULL OR @Phone LIKE N'%[^0-9+]%' OR LEN(@Phone) NOT BETWEEN 9 AND 15
            THROW 50105, N'Số điện thoại không hợp lệ.', 1;
        IF (@Latitude IS NULL AND @Longitude IS NOT NULL) OR (@Latitude IS NOT NULL AND @Longitude IS NULL)
            THROW 50105, N'Phải truyền đủ cả vĩ độ và kinh độ.', 1;
        IF (@Latitude < -90 OR @Latitude > 90) OR (@Longitude < -180 OR @Longitude > 180)
            THROW 50105, N'Vĩ độ hoặc kinh độ nằm ngoài phạm vi hợp lệ.', 1;
        IF @IsDefault IS NULL OR @IsDeleted IS NULL
            THROW 50105, N'IsDefault và IsDeleted không được NULL.', 1;

        BEGIN TRAN;

        DECLARE @Owner INT, @Others INT;
        DECLARE @pt geography = CASE WHEN @Latitude IS NOT NULL THEN geography::Point(@Latitude, @Longitude, 4326) END;

        IF @AddressId IS NOT NULL
        BEGIN
            SELECT @Owner = UserId
            FROM iam.Addresses WITH (UPDLOCK, HOLDLOCK)
            WHERE AddressId = @AddressId AND IsDeleted = 0;
            IF @Owner IS NULL
                THROW 50101, N'Địa chỉ không tồn tại.', 1;
            IF @Owner <> @UserId
                THROW 50103, N'Địa chỉ không thuộc về bạn.', 1;
        END;

        IF @IsDeleted = 1
        BEGIN
            IF @AddressId IS NULL
                THROW 50105, N'Muốn xóa địa chỉ phải truyền AddressId.', 1;
            UPDATE iam.Addresses
            SET IsDeleted = 1, IsDefault = 0, UpdatedAt = SYSUTCDATETIME()
            WHERE AddressId = @AddressId;
            SET @NewAddressId = @AddressId;
            COMMIT;
            RETURN;
        END;

        SET @Others = (SELECT COUNT(*) FROM iam.Addresses
                       WHERE UserId = @UserId AND IsDeleted = 0 AND AddressId <> ISNULL(@AddressId, 0));
        IF @Others = 0 SET @IsDefault = 1;   -- địa chỉ đầu tiên luôn là mặc định
        IF @IsDefault = 1
            UPDATE iam.Addresses
            SET IsDefault = 0, UpdatedAt = SYSUTCDATETIME()
            WHERE UserId = @UserId AND IsDefault = 1 AND IsDeleted = 0 AND AddressId <> ISNULL(@AddressId, 0);

        IF @AddressId IS NULL
        BEGIN
            INSERT INTO iam.Addresses (UserId, Label, RecipientName, Phone, Line1, Ward, District, City, Location, IsDefault)
            VALUES (@UserId, @Label, @RecipientName, @Phone, @Line1, @Ward, @District, @City, @pt, @IsDefault);
            SET @NewAddressId = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE iam.Addresses
            SET Label = @Label, RecipientName = @RecipientName, Phone = @Phone, Line1 = @Line1, Ward = @Ward,
                District = @District, City = @City, Location = @pt, IsDefault = @IsDefault, UpdatedAt = SYSUTCDATETIME()
            WHERE AddressId = @AddressId;
            SET @NewAddressId = @AddressId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE iam.sp_SetUserStatus
    @AdminUserId INT,
    @UserId      INT,
    @IsActive    BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50103, N'Chỉ Admin được khóa hoặc mở tài khoản.', 1;
        IF @IsActive IS NULL
            THROW 50105, N'IsActive không được NULL.', 1;
        IF @UserId = @AdminUserId
            THROW 50105, N'Admin không thể tự khóa tài khoản của mình.', 1;

        BEGIN TRAN;

        DECLARE @Cur BIT;
        SELECT @Cur = IsActive
        FROM iam.Users WITH (UPDLOCK, HOLDLOCK)
        WHERE UserId = @UserId AND IsDeleted = 0;

        IF @Cur IS NULL
            THROW 50101, N'Người dùng không tồn tại.', 1;
        IF @Cur = @IsActive
            THROW 50102, N'Tài khoản đã ở trạng thái này.', 1;

        UPDATE iam.Users
        SET IsActive = @IsActive, UpdatedAt = SYSUTCDATETIME()
        WHERE UserId = @UserId;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE iam.sp_AssignRole
    @AdminUserId INT,
    @UserId      INT,
    @RoleCode    NVARCHAR(30),
    @Action      NVARCHAR(6)      -- 'Add' | 'Remove'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context @key = N'UserId', @value = @AdminUserId;

        IF NOT EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                       WHERE ur.UserId = @AdminUserId AND r.RoleCode = N'Admin')
            THROW 50103, N'Chỉ Admin được gán hoặc gỡ role.', 1;
        IF @Action IS NULL OR @Action NOT IN (N'Add', N'Remove')
            THROW 50105, N'Action phải là Add hoặc Remove.', 1;

        DECLARE @RoleId INT = (SELECT RoleId FROM iam.Roles WHERE RoleCode = @RoleCode);
        IF @RoleId IS NULL
            THROW 50105, N'RoleCode không tồn tại.', 1;

        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM iam.Users WITH (UPDLOCK, HOLDLOCK) WHERE UserId = @UserId AND IsDeleted = 0)
            THROW 50101, N'Người dùng không tồn tại.', 1;

        DECLARE @Has BIT = CASE WHEN EXISTS (SELECT 1 FROM iam.UserRoles WHERE UserId = @UserId AND RoleId = @RoleId)
                                THEN 1 ELSE 0 END;
        IF @Action = N'Add'
        BEGIN
            IF @Has = 1
                THROW 50102, N'Người dùng đã có role này.', 1;
            INSERT INTO iam.UserRoles (UserId, RoleId, AssignedBy) VALUES (@UserId, @RoleId, @AdminUserId);
        END
        ELSE
        BEGIN
            IF @Has = 0
                THROW 50102, N'Người dùng không có role này.', 1;
            IF @UserId = @AdminUserId AND @RoleCode = N'Admin'
                THROW 50105, N'Admin không thể tự gỡ role Admin.', 1;
            IF (SELECT COUNT(*) FROM iam.UserRoles WHERE UserId = @UserId) = 1
                THROW 50105, N'Không được gỡ role cuối cùng của người dùng.', 1;
            DELETE FROM iam.UserRoles WHERE UserId = @UserId AND RoleId = @RoleId;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE iam.sp_GetLoginInfo
    @Email NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @Email = LTRIM(RTRIM(@Email));
        IF NULLIF(@Email, N'') IS NULL
            THROW 50105, N'Email không được rỗng.', 1;

        -- Không có dòng nào = sai email; backend trả 401 chung, không tiết lộ email có tồn tại hay không
        SELECT u.UserId, u.FullName, u.AuthProvider, u.PasswordHash, u.IsActive,
               (SELECT STRING_AGG(r.RoleCode, N',') WITHIN GROUP (ORDER BY r.RoleCode)
                FROM iam.UserRoles ur
                JOIN iam.Roles r ON r.RoleId = ur.RoleId
                WHERE ur.UserId = u.UserId) AS Roles
        FROM iam.Users u
        WHERE u.Email = @Email AND u.IsDeleted = 0;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE iam.sp_GetMyAddresses
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @UserId AND IsActive = 1 AND IsDeleted = 0)
            THROW 50101, N'Người dùng không tồn tại hoặc đã bị khóa.', 1;

        SELECT AddressId, Label, RecipientName, Phone, Line1, Ward, District, City, IsDefault
        FROM iam.Addresses
        WHERE UserId = @UserId AND IsDeleted = 0
        ORDER BY IsDefault DESC, AddressId;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO