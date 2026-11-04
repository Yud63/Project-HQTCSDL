/* ============================================================
   File    : database/09_security/05_sql_logins.sql
   Purpose : Tạo SQL login cho backend (mỗi role một login) và gắn vào database role.
   Re-run  : Chạy lại được (login đã có thì chỉ đổi mật khẩu).
   Chạy (từ thư mục gốc repo, MỘT DÒNG; mật khẩu mạnh, không dùng ^ & % " trong mật khẩu):
     sqlcmd -S localhost -E -C -f 65001 -d FilmLabDB -v PwAuth="..." PwCustomer="..." PwLabOwner="..." PwExpert="..." PwDelivery="..." PwAdmin="..." -i database\09_security\05_sql_logins.sql
   KHÔNG đưa file này vào 99_run_all.sql / build.cmd. KHÔNG cấp sysadmin hay db_owner (sẽ qua mặt RLS).
   ============================================================ */
USE FilmLabDB;
GO

-- ===== 1. Login mức server =====
IF SUSER_ID(N'fl_auth') IS NULL
    CREATE LOGIN fl_auth      WITH PASSWORD = N'$(PwAuth)',     DEFAULT_DATABASE = FilmLabDB, CHECK_POLICY = ON;
ELSE ALTER LOGIN fl_auth      WITH PASSWORD = N'$(PwAuth)';
IF SUSER_ID(N'fl_customer') IS NULL
    CREATE LOGIN fl_customer  WITH PASSWORD = N'$(PwCustomer)', DEFAULT_DATABASE = FilmLabDB, CHECK_POLICY = ON;
ELSE ALTER LOGIN fl_customer  WITH PASSWORD = N'$(PwCustomer)';
IF SUSER_ID(N'fl_labowner') IS NULL
    CREATE LOGIN fl_labowner  WITH PASSWORD = N'$(PwLabOwner)', DEFAULT_DATABASE = FilmLabDB, CHECK_POLICY = ON;
ELSE ALTER LOGIN fl_labowner  WITH PASSWORD = N'$(PwLabOwner)';
IF SUSER_ID(N'fl_expert') IS NULL
    CREATE LOGIN fl_expert    WITH PASSWORD = N'$(PwExpert)',   DEFAULT_DATABASE = FilmLabDB, CHECK_POLICY = ON;
ELSE ALTER LOGIN fl_expert    WITH PASSWORD = N'$(PwExpert)';
IF SUSER_ID(N'fl_delivery') IS NULL
    CREATE LOGIN fl_delivery  WITH PASSWORD = N'$(PwDelivery)', DEFAULT_DATABASE = FilmLabDB, CHECK_POLICY = ON;
ELSE ALTER LOGIN fl_delivery  WITH PASSWORD = N'$(PwDelivery)';
IF SUSER_ID(N'fl_admin') IS NULL
    CREATE LOGIN fl_admin     WITH PASSWORD = N'$(PwAdmin)',    DEFAULT_DATABASE = FilmLabDB, CHECK_POLICY = ON;
ELSE ALTER LOGIN fl_admin     WITH PASSWORD = N'$(PwAdmin)';
GO

-- ===== 2. User trong FilmLabDB + gắn database role =====
IF DATABASE_PRINCIPAL_ID(N'fl_auth')     IS NULL CREATE USER fl_auth     FOR LOGIN fl_auth;
IF DATABASE_PRINCIPAL_ID(N'fl_customer') IS NULL CREATE USER fl_customer FOR LOGIN fl_customer;
IF DATABASE_PRINCIPAL_ID(N'fl_labowner') IS NULL CREATE USER fl_labowner FOR LOGIN fl_labowner;
IF DATABASE_PRINCIPAL_ID(N'fl_expert')   IS NULL CREATE USER fl_expert   FOR LOGIN fl_expert;
IF DATABASE_PRINCIPAL_ID(N'fl_delivery') IS NULL CREATE USER fl_delivery FOR LOGIN fl_delivery;
IF DATABASE_PRINCIPAL_ID(N'fl_admin')    IS NULL CREATE USER fl_admin    FOR LOGIN fl_admin;

ALTER ROLE role_Auth     ADD MEMBER fl_auth;
ALTER ROLE role_Customer ADD MEMBER fl_customer;
ALTER ROLE role_LabOwner ADD MEMBER fl_labowner;
ALTER ROLE role_Expert   ADD MEMBER fl_expert;
ALTER ROLE role_Delivery ADD MEMBER fl_delivery;
ALTER ROLE role_Admin    ADD MEMBER fl_admin;
GO

-- ===== 3. Kết quả: 6 dòng login -> role =====
SELECT l.name AS LoginName, r.name AS DbRole
FROM sys.database_role_members m
JOIN sys.database_principals r ON r.principal_id = m.role_principal_id
JOIN sys.database_principals u ON u.principal_id = m.member_principal_id
JOIN sys.server_principals   l ON l.sid = u.sid
WHERE l.name LIKE N'fl[_]%'
ORDER BY l.name;
GO