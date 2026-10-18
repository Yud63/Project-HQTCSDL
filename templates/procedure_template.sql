/* TEMPLATE Stored Procedure - copy vào database/07_procedures/<module>.sql
   Quy tắc: schema.sp_VerbNoun | SET NOCOUNT + XACT_ABORT | TRY/CATCH | THROW theo dải mã lỗi của module
   Dải mã lỗi: iam 50100 | lab 50200 | ord 50300 | dlv 50400 | arc 50500 | mkt 50600 | com 50700 | ai 50800 | audit 50900 */
CREATE OR ALTER PROCEDURE ord.sp_ExampleAction
    @CustomerId INT,
    @LabId      INT,
    @NewId      INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- 1) Validate đầu vào
        IF NOT EXISTS (SELECT 1 FROM iam.Users WHERE UserId = @CustomerId AND IsDeleted = 0)
            THROW 50301, N'Khách hàng không tồn tại.', 1;

        BEGIN TRAN;

        -- 2) Logic nghiệp vụ (chỉ GHI vào bảng của module mình;
        --    muốn ghi module khác -> gọi procedure của module đó)

        -- 3) Trả kết quả
        -- SET @NewId = SCOPE_IDENTITY();

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;   -- ném lại lỗi gốc cho nơi gọi (web / SSMS)
    END CATCH
END
GO
