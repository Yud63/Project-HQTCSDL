/* ============================================================
   File    : database/09_security/01_roles.sql
   Purpose : Tạo database role tương ứng 5 vai trò hệ thống
   Re-run  : chạy lại được (IF ... IS NULL)
   ============================================================ */
USE FilmLabDB;
GO

IF DATABASE_PRINCIPAL_ID(N'role_Customer')  IS NULL CREATE ROLE role_Customer;   -- Photographer / Customer
IF DATABASE_PRINCIPAL_ID(N'role_LabOwner')  IS NULL CREATE ROLE role_LabOwner;   -- Film Lab Owner
IF DATABASE_PRINCIPAL_ID(N'role_Expert')    IS NULL CREATE ROLE role_Expert;     -- Photography Expert
IF DATABASE_PRINCIPAL_ID(N'role_Delivery')  IS NULL CREATE ROLE role_Delivery;   -- Delivery Partner
IF DATABASE_PRINCIPAL_ID(N'role_Admin')     IS NULL CREATE ROLE role_Admin;      -- System Administrator
IF DATABASE_PRINCIPAL_ID(N'role_Auth')      IS NULL CREATE ROLE role_Auth;       -- Backend đăng ký/đăng nhập (chưa có UserId)
GO
