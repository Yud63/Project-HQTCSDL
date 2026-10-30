USE FilmLabDB;
GO
SET NOCOUNT ON;
BEGIN TRAN;
DECLARE @id INT, @e INT, @ok BIT;

-- 1. Đăng ký đúng: tạo user + gán role Customer
EXEC iam.sp_RegisterUser N'test.reg@example.com', N'Test Reg', N'hash123', @NewUserId = @id OUTPUT;
SET @ok = CASE WHEN EXISTS (SELECT 1 FROM iam.UserRoles ur JOIN iam.Roles r ON r.RoleId = ur.RoleId
                            WHERE ur.UserId = @id AND r.RoleCode = N'Customer') THEN 1 ELSE 0 END;
IF @ok = 1 PRINT N'PASS: đăng ký + gán role Customer'; ELSE PRINT N'FAIL: đăng ký';

-- 2. Email trùng -> 50104
SET @e = 0;
BEGIN TRY EXEC iam.sp_RegisterUser N'test.reg@example.com', N'Dup', N'h', @NewUserId = @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50104 PRINT N'PASS: email trùng -> 50104'; ELSE PRINT N'FAIL: trùng, nhận ' + CAST(@e AS NVARCHAR(10));

-- 3. Local thiếu PasswordHash -> 50105
SET @e = 0;
BEGIN TRY EXEC iam.sp_RegisterUser N'x1@example.com', N'X', NULL, N'Local', @NewUserId = @id OUTPUT; END TRY
BEGIN CATCH SET @e = ERROR_NUMBER(); END CATCH;
IF @e = 50105 PRINT N'PASS: Local thiếu hash -> 50105'; ELSE PRINT N'FAIL: thiếu hash, nhận ' + CAST(@e AS NVARCHAR(10));

IF @@TRANCOUNT > 0 ROLLBACK;
GO