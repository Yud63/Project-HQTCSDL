/* ============================================================
   File    : database/09_security/04_data_masking.sql
   Module  : security - Dynamic Data Masking
   Purpose : Che số điện thoại, email với role không đủ quyền.
   Owner   : TBD (chưa chia việc)
   Depends : iam
   Re-run  : Chạy lại được (ALTER COLUMN ... MASKED WITH).
   Ref     : docs/Conventions.md, docs/Contracts.md
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ===== 1. Che dữ liệu liên lạc =====
ALTER TABLE iam.Users
    ALTER COLUMN Phone ADD MASKED WITH (FUNCTION = 'partial(3, "XXXX", 2)');
ALTER TABLE iam.Users
    ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE iam.Addresses
    ALTER COLUMN Phone ADD MASKED WITH (FUNCTION = 'partial(3, "XXXX", 2)');
GO

-- ===== 2. Quyền xem dữ liệu thật (UNMASK) =====
GRANT UNMASK TO role_Admin;                              -- Admin xem tất cả
GRANT UNMASK ON iam.Addresses(Phone) TO role_Delivery;   -- shipper cần SĐT người nhận
GO

