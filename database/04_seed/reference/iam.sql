/* ============================================================
   File    : database/04_seed/reference/iam.sql
   Module  : iam - M1 Identity & Access
   Purpose : Dữ liệu danh mục cố định: Roles (5 dòng: Customer, LabOwner, Expert, Delivery, Admin; RoleId 1-5).
   Owner   : A (xem docs/Phan-cong.md)
   Depends : (gốc)
   Re-run  : Chạy sau REBUILD=1. Sample seed không gắn cứng ID của bảng IDENTITY.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

SET NOCOUNT ON;

-- Vai trò hệ thống (ID cố định, D-04: user có thể có nhiều role)
INSERT INTO iam.Roles (RoleId, RoleCode, RoleName, Description) VALUES
    (1, N'Customer', N'Khách hàng', N'Đặt đơn, xem scan, mua bán, tham gia cộng đồng'),
    (2, N'LabOwner', N'Chủ Film Lab', N'Quản lý lab, dịch vụ, xử lý đơn, upload scan'),
    (3, N'Expert', N'Chuyên gia', N'Viết bài, tổ chức workshop, đóng góp tri thức cho AI'),
    (4, N'Delivery', N'Giao nhận', N'Nhận và cập nhật các chặng lấy/trả phim'),
    (5, N'Admin', N'Quản trị viên', N'Duyệt lab, kiểm duyệt, xử lý khiếu nại, cấu hình phí');
GO
