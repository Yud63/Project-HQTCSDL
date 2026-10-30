# Requirements: FilmLabDB (bản hợp nhất Đợt 1, 2, 3)

> **Nền tảng kết nối cộng đồng nhiếp ảnh phim và các Film Lab (MiniLab) tích hợp AI**, phần cơ sở dữ liệu (SQL Server 2022 + T-SQL).
> Bản hợp nhất tại Đợt 4: gộp ba tài liệu phân tích và **đã áp dụng** các điều chỉnh liệt kê ở mục "Điều chỉnh" của Đợt 2 và Đợt 3.

## Các tài liệu liên quan (nguồn sự thật)

| Nội dung | File |
|---|---|
| Danh sách bảng, cột, kiểu, ràng buộc, FK (bản chuẩn, đối chiếu khi lệch) | `docs/DataDictionary.xlsx` (sinh từ `tools/schema_spec.py`) |
| Sơ đồ ERD | `diagrams/ERD.md` |
| Quyết định đã chốt, chữ ký 16 procedure, danh mục T-SQL, mã lỗi | `docs/Contracts.md` |
| Kiểm tra chuẩn hóa 3NF và các phi chuẩn hóa có chủ ý | `docs/Normalization.md` |
| Phân công và lịch | `docs/Phan-cong.md` |
| Quy ước đặt tên, kiểu dữ liệu, cách viết T-SQL | `docs/Conventions.md` |

> Khi tài liệu này và `DataDictionary.xlsx`/`Contracts.md` khác nhau, **hai file sau là bản đúng** (sinh từ spec đã kiểm tra tự động).
> Các câu hỏi cuối mỗi đợt (Phần E/F) đã được chốt theo mặc định thành quyết định **D-01 đến D-15** trong `Contracts.md`.

## Điều chỉnh đã áp dụng vào bản hợp nhất

| STT | Điều chỉnh | Vị trí |
|---|---|---|
| 1 | Thêm UQ (`OrderId`, `CustomerId`, `LabId`) vào `ord.Orders` | Đợt 1, bảng `ord.Orders` |
| 2 | Seed `ord.FeeConfigs` thành 3 dòng (hoa hồng, phí giao, phí Marketplace) | Đợt 1, mục Seed reference |
| 3 | `arc.Notifications.Type` thêm giá trị `'Market'` | Đợt 2, bảng `arc.Notifications` |
| 4 | `BR-ORD-09` bổ sung điều kiện giao trả | Đợt 1, business rule M3 |
| 5 | Schema `audit` thay cho `sys`; schema `ord` tách hai file `ord.sql`, `ord_feedback.sql`; log dùng `BIGINT`; Full-Text có điều kiện; module `arc` phụ thuộc thêm `lab` | `Conventions.md`, `Contracts.md` |

---

## ĐỢT 1: (M1 `iam`, M2 `lab`, M3 `ord`)

> Copy vào `docs/Requirements.md`. Các đợt 2, 3 sẽ nối tiếp bên dưới.
> Phạm vi đợt này: **18 bảng** = M1 (6) + M2 (6) + M3 (6). `Reviews` và `Complaints` (cũng nằm trong schema `ord`) làm ở đợt 2.

### 0. Quy ước đọc tài liệu

| Ký hiệu | Nghĩa |
|---|---|
| **(+audit)** | Bảng có thêm 3 cột chuẩn: `CreatedAt DATETIME2(0) DEFAULT SYSUTCDATETIME()`, `UpdatedAt DATETIME2(0) NULL`, `IsDeleted BIT DEFAULT 0` |
| **Lookup** | Bảng danh mục cố định, không có cột audit, có seed `reference` (ID cố định) |
| **PK / FK / UQ / CK / DF** | Khóa chính / khóa ngoại / duy nhất / kiểm tra / mặc định |
| **FK liên module** | Tạo ở `02_foreign_keys/`, FK trong cùng module tạo ngay ở `01_tables/` |
| `BR-xxx-nn` | Business rule (mã để tham chiếu trong code, test, báo cáo) |

**Hai điều chỉnh nhỏ cho `Conventions.md` (cập nhật khi nhóm đồng ý):**

| Điều chỉnh | Nội dung |
|---|---|
| Trạng thái | Enum nhỏ, ít đổi, không có thuộc tính đi kèm -> dùng `CHECK (col IN (...))`. Trạng thái có thứ tự/thuộc tính (giai đoạn xử lý đơn) -> bảng danh mục + FK |
| Người thực hiện | Procedure gọi `sp_set_session_context 'UserId', @UserId` đầu mỗi thao tác; trigger đọc bằng `SESSION_CONTEXT(N'UserId')` để ghi `ChangedBy`, và RLS dùng chính giá trị này |

---

### 1. Phủ 6 Business Flow (kiểm tra không bảng nào "mồ côi")

| Flow | Phục vụ bởi (đợt 1) | Phần còn lại |
|---|---|---|
| 1. Intelligent Film Lab Discovery | `lab.FilmLabs`, `lab.LabServices`, `lab.FilmFormats`, `lab.ServiceTypes`, `iam.Addresses` | Rating (đợt 2), `ai.RecommendationLogs` (đợt 3) |
| 2. Service Booking and Film Collection | `ord.Orders`, `ord.OrderItems`, `iam.Addresses`, `iam.DeliveryPartners` | `dlv.*` (đợt 2) |
| 3. Film Processing Lifecycle | `ord.ProcessingStages`, `ord.OrderStageLog`, `ord.Orders.StageId` | |
| 4. Digital Delivery and Archive | (nền tảng: `ord.Orders`) | `arc.*` (đợt 2) |
| 5. Marketplace | `ord.FeeConfigs` (phí giao dịch) | `mkt.*` (đợt 3) |
| 6. Knowledge/Community | `iam.ExpertProfiles` | `com.*` (đợt 3) |

---

## PHẦN A. MODULE M1: `iam` (Identity & Access)

**Phụ thuộc:** không (module gốc).

### A.1 Quan hệ

```
Users 1──N UserRoles N──1 Roles
Users 1──N Addresses
Users 1──1 ExpertProfiles          (tùy chọn, chỉ user có role Expert)
Users 1──0..1 DeliveryPartners     (tùy chọn, loại Individual)
```

### A.2 `iam.Users` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| UserId | INT IDENTITY | PK | |
| Email | NVARCHAR(255) | NOT NULL, CK định dạng | Unique cho user chưa xóa (filtered unique index, xem BR-IAM-01) |
| AuthProvider | NVARCHAR(20) | NOT NULL, DF `'Local'`, CK IN (`'Local'`,`'Google'`,`'Facebook'`) | Hỗ trợ OAuth2 như đề |
| PasswordHash | NVARCHAR(255) | NULL | Hash do tầng web tạo (bcrypt/argon2), DB **không** lưu mật khẩu thô |
| FullName | NVARCHAR(100) | NOT NULL | |
| Phone | NVARCHAR(20) | NULL, CK chỉ gồm số và dấu `+`, dài 9 đến 15 | Masked ở `09_security` |
| AvatarUrl | NVARCHAR(500) | NULL | |
| IsActive | BIT | NOT NULL, DF 1 | Khóa tài khoản không cần xóa |
| LastLoginAt | DATETIME2(0) | NULL | |

CK nhiều cột: `AuthProvider <> 'Local' OR PasswordHash IS NOT NULL`.

### A.3 `iam.Roles` (Lookup)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| RoleId | INT | PK (ID cố định 1 đến 5, **không** IDENTITY) | |
| RoleCode | NVARCHAR(30) | NOT NULL, UQ | `Customer`, `LabOwner`, `Expert`, `Delivery`, `Admin` |
| RoleName | NVARCHAR(100) | NOT NULL | Tên tiếng Việt hiển thị |
| Description | NVARCHAR(255) | NULL | |

### A.4 `iam.UserRoles`

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| UserId | INT | PK (1/2), FK -> `iam.Users` | |
| RoleId | INT | PK (2/2), FK -> `iam.Roles` | |
| AssignedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |
| AssignedBy | INT | NULL, FK -> `iam.Users` | NULL = tự đăng ký |

Quan hệ N-N giữa Users và Roles (một người có thể vừa Customer vừa Expert).

### A.5 `iam.Addresses` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| AddressId | INT IDENTITY | PK | |
| UserId | INT | NOT NULL, FK -> `iam.Users` | |
| Label | NVARCHAR(50) | NULL | "Nhà", "Công ty" |
| RecipientName | NVARCHAR(100) | NOT NULL | |
| Phone | NVARCHAR(20) | NOT NULL | |
| Line1 | NVARCHAR(255) | NOT NULL | Số nhà, đường |
| Ward / District / City | NVARCHAR(100) | NOT NULL | Phường / Quận / Tỉnh-Thành |
| Location | geography | NULL | Điểm lấy/giao phim, dùng cho tính khoảng cách |
| IsDefault | BIT | NOT NULL, DF 0 | |

### A.6 `iam.ExpertProfiles` (+`CreatedAt`, `UpdatedAt`)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| UserId | INT | PK, FK -> `iam.Users` | Quan hệ 1-1 |
| Bio | NVARCHAR(1000) | NULL | |
| Expertise | NVARCHAR(255) | NULL | Ví dụ "Phim đen trắng, tráng tại nhà" |
| YearsExperience | SMALLINT | NULL, CK >= 0 | |
| PortfolioUrl | NVARCHAR(500) | NULL | |
| IsVerified | BIT | NOT NULL, DF 0 | Admin xác minh |
| VerifiedBy | INT | NULL, FK -> `iam.Users` | |
| VerifiedAt | DATETIME2(0) | NULL | |

### A.7 `iam.DeliveryPartners` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| DeliveryPartnerId | INT IDENTITY | PK | |
| ProviderType | NVARCHAR(12) | NOT NULL, CK IN (`'Platform'`,`'Individual'`) | `Platform` = Ahamove/Lalamove; `Individual` = shipper có tài khoản |
| PartnerName | NVARCHAR(100) | NOT NULL | |
| UserId | INT | NULL, FK -> `iam.Users` | Bắt buộc khi `Individual` |
| VehicleType | NVARCHAR(30) | NULL | |
| PlateNumber | NVARCHAR(20) | NULL | |
| ApiCode | NVARCHAR(50) | NULL | Mã tích hợp với bên thứ ba |
| IsActive | BIT | NOT NULL, DF 1 | |

CK: `ProviderType = 'Platform' OR UserId IS NOT NULL`.

### A.8 Business rules M1

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-IAM-01 | Email duy nhất giữa các user chưa xóa (không phân biệt hoa thường, nhờ collation CI) | Filtered unique index `UX_Users_Email` WHERE `IsDeleted = 0` |
| BR-IAM-02 | Tài khoản `Local` bắt buộc có `PasswordHash`; tài khoản OAuth thì không | CHECK nhiều cột |
| BR-IAM-03 | Đăng ký mới tự gán role `Customer`; mỗi user có ít nhất 1 role | `iam.sp_RegisterUser` |
| BR-IAM-04 | Role `Admin` không thể tự gán khi đăng ký; chỉ Admin khác gán | `sp_RegisterUser` + phân quyền |
| BR-IAM-05 | `ExpertProfiles` chỉ tạo cho user có role `Expert`; `IsVerified` chỉ Admin đặt | Trigger + phân quyền |
| BR-IAM-06 | Mỗi user có tối đa 1 địa chỉ mặc định | Filtered unique index `UX_Addresses_Default` (`UserId`) WHERE `IsDefault = 1 AND IsDeleted = 0` |
| BR-IAM-07 | Không xóa cứng user; khóa bằng `IsActive = 0` hoặc xóa mềm `IsDeleted = 1` (đơn hàng cũ giữ nguyên lịch sử) | Quy ước + DENY DELETE |
| BR-IAM-08 | `DeliveryPartners` loại `Individual` phải trỏ tới user có role `Delivery` | CHECK + Trigger |
| BR-IAM-09 | Email đúng dạng cơ bản; số điện thoại chỉ gồm chữ số và `+` | CHECK |
| BR-IAM-10 | Mọi thay đổi `Users` được ghi vào `audit.AuditLogs` | `trg_Users_Audit` (đợt 3 tạo bảng) |

---

## PHẦN B. MODULE M2: `lab` (Lab & Catalog)

**Phụ thuộc:** `iam`.

### B.1 Quan hệ

```
Users 1──N FilmLabs 1──N LabApprovals N──1 Users(Admin)
FilmLabs 1──N LabServices N──1 ServiceTypes
                          N──1 FilmFormats
FilmStocks  (danh mục phim, dùng ở ord.OrderItems và arc.PhotoMetadata)
```

### B.2 `lab.FilmLabs` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| LabId | INT IDENTITY | PK | |
| OwnerUserId | INT | NOT NULL, FK -> `iam.Users` (liên module) | Chủ lab |
| LabName | NVARCHAR(150) | NOT NULL | |
| Description | NVARCHAR(1000) | NULL | |
| AddressLine | NVARCHAR(255) | NOT NULL | |
| Ward / District / City | NVARCHAR(100) | NOT NULL | |
| Location | geography | NULL | Spatial index, tìm lab gần khách |
| Phone | NVARCHAR(20) | NULL | |
| Email | NVARCHAR(255) | NULL | |
| OpenHoursJson | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | Giờ mở cửa theo thứ |
| SpecialTechniques | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | Ví dụ `["push","pull","cross-process","bw-home"]`, phục vụ lọc ở Flow 1 |
| DailyCapacityRolls | SMALLINT | NOT NULL, DF 50, CK > 0 | Năng lực xử lý/ngày |
| ApprovalStatus | NVARCHAR(12) | NOT NULL, DF `'Pending'`, CK IN (`'Pending'`,`'Approved'`,`'Rejected'`,`'Suspended'`) | |
| AvgRating | DECIMAL(3,2) | NOT NULL, DF 0, CK 0 đến 5 | **Phi chuẩn hóa có chủ ý**, trigger cập nhật từ `Reviews` |
| ReviewCount | INT | NOT NULL, DF 0, CK >= 0 | Như trên |

### B.3 `lab.LabApprovals`

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ApprovalId | INT IDENTITY | PK | |
| LabId | INT | NOT NULL, FK -> `lab.FilmLabs` | |
| ReviewedBy | INT | NOT NULL, FK -> `iam.Users` (liên module) | Admin |
| Decision | NVARCHAR(12) | NOT NULL, CK IN (`'Approved'`,`'Rejected'`,`'Suspended'`) | |
| Reason | NVARCHAR(500) | NULL | |
| DecidedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |

CK: `Decision = 'Approved' OR Reason IS NOT NULL`. Bảng chỉ thêm, không sửa/xóa (lịch sử duyệt).

### B.4 `lab.FilmFormats` (Lookup)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| FormatId | INT | PK (ID cố định) | |
| FormatCode | NVARCHAR(20) | NOT NULL, UQ | `35mm`, `120`, `4x5`, `110`, `APS` |
| FormatName | NVARCHAR(100) | NOT NULL | |

### B.5 `lab.FilmStocks` (Lookup, có `IsActive`)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| StockId | INT | PK (ID cố định) | |
| Brand | NVARCHAR(50) | NOT NULL | Kodak, Fujifilm, Ilford, CineStill |
| StockName | NVARCHAR(100) | NOT NULL | Portra 400, HP5 Plus... |
| Iso | SMALLINT | NOT NULL, CK > 0 | |
| FilmType | NVARCHAR(15) | NOT NULL, CK IN (`'ColorNegative'`,`'BlackWhite'`,`'ColorSlide'`) | |
| ProcessCode | NVARCHAR(10) | NOT NULL, CK IN (`'C-41'`,`'E-6'`,`'BW'`,`'ECN-2'`) | Quy trình tráng |
| IsActive | BIT | NOT NULL, DF 1 | |

UQ (`Brand`, `StockName`). Dùng chung cho đặt đơn, metadata ảnh và AI gợi ý phim.

### B.6 `lab.ServiceTypes` (Lookup)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ServiceTypeId | INT | PK (ID cố định) | |
| ServiceCode | NVARCHAR(20) | NOT NULL, UQ | `DEV`, `SCAN`, `PRINT`, `EXTRA` |
| ServiceName | NVARCHAR(100) | NOT NULL | |
| Category | NVARCHAR(10) | NOT NULL, CK IN (`'Develop'`,`'Scan'`,`'Print'`,`'Other'`) | Dùng để xác định giai đoạn nào áp dụng cho đơn (BR-ORD-05) |
| Description | NVARCHAR(255) | NULL | |

### B.7 `lab.LabServices` (+audit, **Temporal Table**)

Gói dịch vụ và giá của từng lab. Bảng bật `SYSTEM_VERSIONING` (thêm `ValidFrom`, `ValidTo`, bảng lịch sử `lab.LabServicesHistory` do SQL Server tự tạo) để lưu **lịch sử đổi giá**.

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| LabServiceId | INT IDENTITY | PK | |
| LabId | INT | NOT NULL, FK -> `lab.FilmLabs` | |
| ServiceTypeId | INT | NOT NULL, FK -> `lab.ServiceTypes` | |
| FormatId | INT | NOT NULL, FK -> `lab.FilmFormats` | |
| ProcessCode | NVARCHAR(10) | NOT NULL, DF `'ANY'`, CK IN (`'C-41'`,`'E-6'`,`'BW'`,`'ECN-2'`,`'ANY'`) | `ANY` cho dịch vụ không phụ thuộc quy trình (scan, in) |
| PackageName | NVARCHAR(150) | NOT NULL | "Tráng + scan 35mm màu" |
| Description | NVARCHAR(500) | NULL | |
| UnitPrice | DECIMAL(18,0) | NOT NULL, CK >= 0 | VND |
| PriceUnit | NVARCHAR(5) | NOT NULL, DF `'Roll'`, CK IN (`'Roll'`,`'Frame'`) | Tráng/scan tính theo cuộn, in tính theo tấm |
| ScanQuality | NVARCHAR(5) | NULL, CK IN (`'Basic'`,`'High'`,`'Ultra'`) | Chỉ dùng cho gói thuộc Category `Scan` |
| TurnaroundDays | TINYINT | NOT NULL, CK BETWEEN 1 AND 60 | |
| IsActive | BIT | NOT NULL, DF 1 | |

UQ (`LabId`, `PackageName`).

### B.8 Business rules M2

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-LAB-01 | Lab mới ở trạng thái `Pending`; chỉ lab `Approved` xuất hiện trong tìm kiếm và nhận đơn | `sp_SearchLabs`, `sp_CreateOrder` |
| BR-LAB-02 | `OwnerUserId` phải là user có role `LabOwner` | Trigger |
| BR-LAB-03 | Mỗi quyết định duyệt của Admin ghi 1 dòng `LabApprovals`; `Rejected`/`Suspended` bắt buộc có `Reason`; `FilmLabs.ApprovalStatus` luôn khớp quyết định mới nhất | CHECK + `lab.sp_ApproveLab` |
| BR-LAB-04 | Giá >= 0, `TurnaroundDays` >= 1, tên gói không trùng trong cùng lab; đổi giá được lưu lịch sử | CHECK, UQ, Temporal Table |
| BR-LAB-05 | Gói thuộc Category `Scan` phải có `ScanQuality`; gói khác phải để NULL | `trg_LabServices_CheckScan` (CHECK không tra được bảng khác) |
| BR-LAB-06 | `AvgRating` và `ReviewCount` chỉ do trigger cập nhật từ `ord.Reviews`, không ai sửa tay | Trigger (đợt 2) + DENY UPDATE cột |
| BR-LAB-07 | Lab `Suspended`: đơn đang xử lý vẫn tiếp tục, không nhận đơn mới | `sp_CreateOrder` |
| BR-LAB-08 | Tìm lab lọc được theo: khoảng cách, định dạng phim hỗ trợ, loại dịch vụ, giá, thời gian hoàn thành, rating, kỹ thuật đặc biệt | `lab.sp_SearchLabs` + `fn_DistanceKm` + index |
| BR-LAB-09 | Số cuộn đang xử lý của lab không vượt `DailyCapacityRolls` khi nhận thêm đơn | `lab.fn_LabCapacityLeft`, kiểm tra trong `sp_CreateOrder` |
| BR-LAB-10 | Chủ lab chỉ xem/sửa dữ liệu lab của mình (multi-tenant) | Row-Level Security (`09_security`) |

---

## PHẦN C. MODULE M3: `ord` (Order, Processing, Payment, Fee)

**Phụ thuộc:** `iam`, `lab`. (`Reviews`, `Complaints` làm ở đợt 2.)

### C.1 Quan hệ

```
Users 1──N Orders N──1 FilmLabs
Orders N──1 ProcessingStages              (giai đoạn hiện tại)
Orders 1──N OrderItems N──1 LabServices
                       N──0..1 FilmStocks
Orders 1──N OrderStageLog N──1 ProcessingStages (From / To)
Orders 1──N Payments
FeeConfigs 0..N──0..1 FilmLabs            (NULL = áp dụng toàn hệ thống)
```

### C.2 `ord.ProcessingStages` (Lookup)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| StageId | INT | PK (ID cố định) | |
| StageCode | NVARCHAR(20) | NOT NULL, UQ | |
| StageName | NVARCHAR(100) | NOT NULL | Tiếng Việt |
| SortOrder | TINYINT | NOT NULL, UQ | Thứ tự giai đoạn |
| IsTerminal | BIT | NOT NULL, DF 0 | `Completed`, `Cancelled` |

**Danh sách giai đoạn (seed reference):**

| StageId | StageCode | Tên hiển thị | SortOrder | Áp dụng khi |
|---|---|---|---|---|
| 1 | `Pending` | Chờ lab xác nhận | 10 | Luôn |
| 2 | `Confirmed` | Lab đã xác nhận | 20 | Luôn |
| 3 | `AwaitingFilm` | Chờ nhận phim | 30 | Luôn |
| 4 | `FilmReceived` | Đã nhận phim tại lab | 40 | Luôn |
| 5 | `Developing` | Tráng hóa chất | 50 | Đơn có dịch vụ Category `Develop` |
| 6 | `Washing` | Rửa | 60 | Như trên |
| 7 | `Drying` | Sấy | 70 | Như trên |
| 8 | `Scanning` | Scan | 80 | Đơn có dịch vụ Category `Scan` |
| 9 | `ImagePrep` | Chuẩn bị ảnh | 90 | Như trên |
| 10 | `QualityCheck` | Kiểm tra chất lượng | 100 | Luôn |
| 11 | `ReadyToReturn` | Sẵn sàng trả phim/ảnh | 110 | Luôn |
| 12 | `Completed` | Hoàn tất | 120 | Luôn (terminal) |
| 13 | `Cancelled` | Đã hủy | 255 | Hủy (terminal) |

### C.3 `ord.Orders` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| OrderId | INT IDENTITY | PK | |
| OrderCode | NVARCHAR(20) | NOT NULL, UQ | Sinh bằng `SEQUENCE`, dạng `FL-2026-000001` |
| CustomerId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| LabId | INT | NOT NULL, FK -> `lab.FilmLabs` (liên module) | Khóa RLS multi-tenant |
| StageId | INT | NOT NULL, DF 1, FK -> `ord.ProcessingStages` | |
| FulfillmentMethod | NVARCHAR(7) | NOT NULL, CK IN (`'DropOff'`,`'Pickup'`) | Khách tự mang đến hay yêu cầu lấy phim |
| ReturnMethod | NVARCHAR(11) | NOT NULL, CK IN (`'SelfCollect'`,`'Delivery'`) | |
| PickupAddressId | INT | NULL, FK -> `iam.Addresses` (liên module) | |
| ReturnAddressId | INT | NULL, FK -> `iam.Addresses` (liên module) | |
| Subtotal | DECIMAL(18,0) | NOT NULL, CK >= 0 | Tổng các dòng |
| DeliveryFee | DECIMAL(18,0) | NOT NULL, DF 0, CK >= 0 | |
| PlatformFee | DECIMAL(18,0) | NOT NULL, DF 0, CK >= 0 | Hoa hồng nền tảng, **snapshot** lúc đặt |
| TotalAmount | DECIMAL(18,0) | NOT NULL | Khách trả |
| PaymentStatus | NVARCHAR(9) | NOT NULL, DF `'Unpaid'`, CK IN (`'Unpaid'`,`'Paid'`,`'Refunded'`) | Trigger cập nhật từ `Payments` |
| CustomerNote | NVARCHAR(500) | NULL | |
| EstimatedReadyDate | DATE | NULL | |
| CompletedAt | DATETIME2(0) | NULL | |
| CancelReason | NVARCHAR(255) | NULL | |

CHECK nhiều cột:
- `TotalAmount = Subtotal + DeliveryFee`
- `FulfillmentMethod <> 'Pickup' OR PickupAddressId IS NOT NULL`
- `ReturnMethod <> 'Delivery' OR ReturnAddressId IS NOT NULL`

UQ `UQ_Orders_OrderId_CustomerId_LabId` (`OrderId`, `CustomerId`, `LabId`): đích của **FK ghép** từ `ord.Reviews` và `ord.Complaints` (bổ sung ở Đợt 2).

### C.4 `ord.OrderItems` (chỉ `CreatedAt`, không xóa)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| OrderItemId | INT IDENTITY | PK | |
| OrderId | INT | NOT NULL, FK -> `ord.Orders` | |
| LabServiceId | INT | NOT NULL, FK -> `lab.LabServices` (liên module) | |
| FilmStockId | INT | NULL, FK -> `lab.FilmStocks` (liên module) | Loại phim khách gửi |
| Quantity | INT | NOT NULL, CK > 0 | Số cuộn hoặc số tấm tùy `PriceUnit` |
| UnitPriceSnapshot | DECIMAL(18,0) | NOT NULL, CK >= 0 | **Giá chốt lúc đặt**, không đổi khi lab đổi giá |
| LineTotal | computed | `Quantity * UnitPriceSnapshot`, PERSISTED | |
| ProcessingNote | NVARCHAR(255) | NULL | Ví dụ "đẩy +1 stop" |

### C.5 `ord.OrderStageLog` (bất biến)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| LogId | INT IDENTITY | PK | |
| OrderId | INT | NOT NULL, FK -> `ord.Orders` | |
| FromStageId | INT | NULL, FK -> `ord.ProcessingStages` | NULL ở dòng khởi tạo |
| ToStageId | INT | NOT NULL, FK -> `ord.ProcessingStages` | |
| ChangedBy | INT | NULL, FK -> `iam.Users` (liên module) | Lấy từ `SESSION_CONTEXT` |
| Note | NVARCHAR(255) | NULL | |
| ChangedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |

Chỉ do trigger ghi; `DENY UPDATE, DELETE` cho mọi role.

### C.6 `ord.Payments` (+`CreatedAt`, không xóa)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| PaymentId | INT IDENTITY | PK | |
| OrderId | INT | NOT NULL, FK -> `ord.Orders` | |
| Method | NVARCHAR(12) | NOT NULL, CK IN (`'Card'`,`'EWallet'`,`'BankTransfer'`) | Thanh toán online như đề |
| Provider | NVARCHAR(30) | NULL | VNPay, MoMo, ZaloPay... |
| ProviderTxnId | NVARCHAR(100) | NULL | Mã giao dịch bên cổng thanh toán |
| Amount | DECIMAL(18,0) | NOT NULL, CK > 0 | |
| Status | NVARCHAR(9) | NOT NULL, DF `'Pending'`, CK IN (`'Pending'`,`'Succeeded'`,`'Failed'`,`'Refunded'`) | |
| PaidAt | DATETIME2(0) | NULL | |
| RefundedAt | DATETIME2(0) | NULL | |
| FailureReason | NVARCHAR(255) | NULL | |

### C.7 `ord.FeeConfigs` (+`CreatedAt`)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| FeeConfigId | INT IDENTITY | PK | |
| FeeType | NVARCHAR(20) | NOT NULL, CK IN (`'PlatformCommission'`,`'MarketplaceFee'`,`'DeliveryBase'`) | |
| Rate | DECIMAL(5,4) | NULL, CK BETWEEN 0 AND 1 | Ví dụ 0.1000 = 10% |
| FixedAmount | DECIMAL(18,0) | NULL, CK >= 0 | |
| ScopeLabId | INT | NULL, FK -> `lab.FilmLabs` (liên module) | NULL = toàn hệ thống |
| EffectiveFrom | DATE | NOT NULL | |
| EffectiveTo | DATE | NULL | |
| CreatedBy | INT | NOT NULL, FK -> `iam.Users` (liên module) | Admin |

CHECK: `Rate IS NOT NULL OR FixedAmount IS NOT NULL`; `EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom`.

### C.8 Quy tắc chuyển giai đoạn (State Machine)

| Rule | Nội dung |
|---|---|
| Hướng đi | Chỉ tiến (SortOrder tăng), không lùi |
| Bỏ qua giai đoạn | `Developing`, `Washing`, `Drying` bỏ qua nếu đơn không có dịch vụ Category `Develop`; `Scanning`, `ImagePrep` bỏ qua nếu không có Category `Scan` |
| Hợp lệ | Giai đoạn kế tiếp = giai đoạn áp dụng nhỏ nhất có SortOrder lớn hơn hiện tại (`ord.fn_NextStage`); `ord.fn_IsValidTransition` kiểm tra |
| Hủy | Chuyển sang `Cancelled` chỉ khi hiện tại có SortOrder < 50 (chưa vào `Developing`) |
| Terminal | `Completed`, `Cancelled` không đi tiếp |
| Hoàn tất | Vào `Completed` yêu cầu `PaymentStatus = 'Paid'` (và, khi đã có module `arc`, đơn có dịch vụ scan phải có file scan) |

### C.9 Business rules M3

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-ORD-01 | Chỉ đặt đơn tại lab `Approved`; dịch vụ phải `IsActive` và thuộc đúng lab đặt | `sp_CreateOrder` |
| BR-ORD-02 | Đơn có ít nhất 1 dòng; `Quantity` > 0; giá lấy từ `LabServices` tại thời điểm đặt rồi lưu `UnitPriceSnapshot` | `sp_CreateOrder` + CHECK |
| BR-ORD-03 | `Subtotal` = tổng `LineTotal`; `TotalAmount` = `Subtotal` + `DeliveryFee`; `PlatformFee` = `Subtotal` x hoa hồng hiệu lực (lab riêng ưu tiên hơn toàn hệ thống), lấy từ `FeeConfigs` rồi chốt vào đơn | `fn_CalcOrderTotal`, `fn_CalcPlatformFee`, CHECK |
| BR-ORD-04 | `Pickup` bắt buộc `PickupAddressId`; `Delivery` bắt buộc `ReturnAddressId`; địa chỉ phải thuộc chính khách đặt đơn | CHECK + `sp_CreateOrder` |
| BR-ORD-05 | Giai đoạn chỉ đi tới và bỏ qua bước không áp dụng theo loại dịch vụ (mục C.8) | `fn_NextStage`, `fn_IsValidTransition`, `trg_Orders_PreventInvalidStage` |
| BR-ORD-06 | Chỉ hủy được khi chưa vào `Developing`; nếu đã `Paid` thì phát sinh hoàn tiền (`Payments.Status = 'Refunded'`, `PaymentStatus = 'Refunded'`) | `ord.sp_CancelOrder` (thêm mới) |
| BR-ORD-07 | Mỗi lần đổi `StageId` tự ghi `OrderStageLog` kèm người đổi từ `SESSION_CONTEXT` | `trg_Orders_LogStage` |
| BR-ORD-08 | Chỉ chủ lab của đơn (hoặc Admin) được đổi giai đoạn xử lý; khách chỉ được hủy | `sp_UpdateOrderStage` + RLS |
| BR-ORD-09 | Vào `Completed` yêu cầu `PaymentStatus = 'Paid'` (và có file scan nếu có dịch vụ scan); phía giao trả, không giao phim khi chưa `Paid` (xem BR-DLV-06) | `sp_UpdateOrderStage` |
| BR-ORD-10 | Thanh toán: `Amount` phải bằng `TotalAmount`; mỗi đơn tối đa 1 payment `Succeeded`; thanh toán thành công thì `PaymentStatus = 'Paid'` | `sp_ProcessPayment`, filtered unique index `UX_Payments_OrderPaid` WHERE `Status = 'Succeeded'`, `trg_Payments_UpdateOrder` |
| BR-ORD-11 | `FeeConfigs` cùng (`FeeType`, `ScopeLabId`) không được chồng khoảng thời gian; chỉ Admin sửa | `trg_FeeConfigs_NoOverlap` + phân quyền |
| BR-ORD-12 | `OrderCode` sinh bằng `SEQUENCE`, không trùng | `ord.seq_OrderCode` + UQ |
| BR-ORD-13 | Không xóa cứng đơn, dòng đơn, payment; `OrderStageLog` bất biến | DENY DELETE/UPDATE |
| BR-ORD-14 | Nhận đơn mới không làm lab vượt `DailyCapacityRolls` (tính theo số cuộn đang xử lý) | `fn_LabCapacityLeft` trong `sp_CreateOrder` |
| BR-ORD-15 | Tạo đơn, thanh toán, hủy chạy trong Transaction (`TRY...CATCH`, `XACT_ABORT ON`); lỗi thì rollback toàn bộ | Template procedure |

---

## PHẦN D. TỔNG HỢP CHO CÁC BƯỚC SAU

### D.1 FK liên module (nội dung `02_foreign_keys/`)

| Module | Tên FK | Từ -> Tới |
|---|---|---|
| `iam` | (không có FK liên module) | Các FK tự trỏ trong `iam` (`UserRoles.AssignedBy`, `ExpertProfiles.VerifiedBy`, `DeliveryPartners.UserId`) tạo luôn ở `01_tables/iam.sql` |
| `lab` | `FK_FilmLabs_Users` | `lab.FilmLabs.OwnerUserId` -> `iam.Users` |
| `lab` | `FK_LabApprovals_Users` | `lab.LabApprovals.ReviewedBy` -> `iam.Users` |
| `ord` | `FK_Orders_Users` | `ord.Orders.CustomerId` -> `iam.Users` |
| `ord` | `FK_Orders_FilmLabs` | `ord.Orders.LabId` -> `lab.FilmLabs` |
| `ord` | `FK_Orders_PickupAddress` | `ord.Orders.PickupAddressId` -> `iam.Addresses` |
| `ord` | `FK_Orders_ReturnAddress` | `ord.Orders.ReturnAddressId` -> `iam.Addresses` |
| `ord` | `FK_OrderItems_LabServices` | `ord.OrderItems.LabServiceId` -> `lab.LabServices` |
| `ord` | `FK_OrderItems_FilmStocks` | `ord.OrderItems.FilmStockId` -> `lab.FilmStocks` |
| `ord` | `FK_OrderStageLog_Users` | `ord.OrderStageLog.ChangedBy` -> `iam.Users` |
| `ord` | `FK_FeeConfigs_FilmLabs` | `ord.FeeConfigs.ScopeLabId` -> `lab.FilmLabs` |
| `ord` | `FK_FeeConfigs_Users` | `ord.FeeConfigs.CreatedBy` -> `iam.Users` |

### D.2 Index dự kiến (`03_indexes/`)

| Bảng | Index | Phục vụ |
|---|---|---|
| `iam.Users` | `UX_Users_Email` (filtered, `IsDeleted = 0`) | Đăng nhập, BR-IAM-01 |
| `iam.Addresses` | `UX_Addresses_Default` (filtered) | BR-IAM-06 |
| `lab.FilmLabs` | `SIX_FilmLabs_Location` (spatial) | Tìm lab gần khách |
| `lab.FilmLabs` | `IX_FilmLabs_Approval_City` (`ApprovalStatus`, `City`) INCLUDE (`AvgRating`) | Flow 1 |
| `lab.LabServices` | `IX_LabServices_Search` (`LabId`, `ServiceTypeId`, `FormatId`) INCLUDE (`UnitPrice`, `TurnaroundDays`) | So sánh dịch vụ/giá |
| `ord.Orders` | `IX_Orders_Customer` (`CustomerId`, `CreatedAt` DESC) | Khách xem đơn của mình |
| `ord.Orders` | `IX_Orders_Lab_Stage` (`LabId`, `StageId`) | Lab xem đơn đang xử lý |
| `ord.OrderItems` | `IX_OrderItems_Order` (`OrderId`) | JOIN |
| `ord.OrderStageLog` | `IX_OrderStageLog_Order` (`OrderId`, `ChangedAt`) | Dòng thời gian đơn |
| `ord.Payments` | `UX_Payments_OrderPaid` (filtered, `Status = 'Succeeded'`) | BR-ORD-10 |

### D.3 Seed reference (`04_seed/reference/`)

| Bảng | Nội dung |
|---|---|
| `iam.Roles` | 5 dòng: Customer, LabOwner, Expert, Delivery, Admin |
| `lab.FilmFormats` | 5 dòng: 35mm, 120, 4x5, 110, APS |
| `lab.ServiceTypes` | 4 dòng: DEV (Develop), SCAN (Scan), PRINT (Print), EXTRA (Other) |
| `lab.FilmStocks` | khoảng 12 dòng: Kodak Portra 160/400/800, Gold 200, UltraMax 400, ColorPlus 200; Fujifilm C200, Superia X-TRA 400, Velvia 50; Ilford HP5 Plus 400, Delta 100; Kodak Tri-X 400; CineStill 800T |
| `ord.ProcessingStages` | 13 dòng như mục C.2 |
| `ord.FeeConfigs` | 3 dòng toàn hệ thống (**giả định**, quyết định D-01, D-06, D-12): `PlatformCommission` `Rate` 0.1000; `DeliveryBase` `FixedAmount` 25000; `MarketplaceFee` `Rate` 0.0500 |

### D.4 Thành phần T-SQL dự kiến cho M1-M3 (cập nhật `Contracts.md`)

| Loại | Tên |
|---|---|
| Procedure | `iam.sp_RegisterUser`, `lab.sp_ApproveLab`, `lab.sp_SearchLabs`, `ord.sp_CreateOrder`, `ord.sp_UpdateOrderStage`, `ord.sp_CancelOrder` (**mới**), `ord.sp_ProcessPayment` |
| Function | `ord.fn_CalcOrderTotal`, `ord.fn_CalcPlatformFee`, `ord.fn_NextStage`, `ord.fn_IsValidTransition`, `lab.fn_LabCapacityLeft`, `lab.fn_DistanceKm` |
| Trigger | `ord.trg_Orders_LogStage`, `ord.trg_Orders_PreventInvalidStage`, `ord.trg_Payments_UpdateOrder`, `ord.trg_FeeConfigs_NoOverlap`, `lab.trg_LabServices_CheckScan`, `iam.trg_Users_Audit` |
| View | `ord.vw_LabRevenue`, `ord.vw_OrdersInProgress`, `lab.vw_TopLabs` |
| Sequence | `ord.seq_OrderCode` |

---

## PHẦN E. CÂU HỎI CẦN NHÓM XÁC NHẬN

Mỗi câu có đề xuất mặc định. Nếu đồng ý hết thì chỉ cần trả lời "ok".

| STT | Câu hỏi | Mặc định |
|---|---|---|
| 1 | Hoa hồng nền tảng tính thế nào? | Trừ vào doanh thu lab (khách trả `Subtotal` + phí giao), mức 10%, Admin chỉnh được trong `FeeConfigs` |
| 2 | Khách thanh toán lúc nào? | Từ khi đơn `Confirmed`; bắt buộc đã `Paid` trước khi `Completed` |
| 3 | Một chủ lab được sở hữu nhiều lab? | Có (quan hệ 1-N) |
| 4 | Một user được có nhiều role (ví dụ Customer + Expert)? | Có (bảng `UserRoles` N-N) |
| 5 | Lưu tọa độ (`geography`) cho lab và địa chỉ để tìm lab gần khách? | Có (là điểm cộng SQL Server 2022 và cần cho Flow 1) |

**Nếu thiếu thời gian có thể cắt** (không ảnh hưởng luồng chính): `iam.ExpertProfiles` (gộp vào `Users`), `lab.FilmStocks` (bỏ FK ở `OrderItems`), temporal table ở `LabServices`.

---

## PHẦN F. THỐNG KÊ ĐỢT 1

| Module | Bảng | Số bảng |
|---|---|---|
| `iam` | Users, Roles, UserRoles, Addresses, ExpertProfiles, DeliveryPartners | 6 |
| `lab` | FilmLabs, LabApprovals, FilmFormats, FilmStocks, ServiceTypes, LabServices | 6 |
| `ord` (phần M3) | Orders, OrderItems, ProcessingStages, OrderStageLog, Payments, FeeConfigs | 6 |
| **Tổng** | | **18** (cộng 1 bảng lịch sử tự sinh `lab.LabServicesHistory`) |

| Loại | Số lượng |
|---|---|
| Business rule | 10 (iam) + 10 (lab) + 15 (ord) = **35** |
| FK liên module | 11 |
| Index dự kiến | 10 |
| Procedure / Function / Trigger / View | 7 / 6 / 6 / 3 |

---

## ĐỢT 2: (M4 `dlv`, M5 `arc`, M6 `ord`: Review và Complaint)

> Nối tiếp phía dưới `docs/Requirements.md` (sau Đợt 1). Dùng lại ký hiệu và quy ước ở mục 0 của Đợt 1 (**+audit**, **Lookup**, `BR-xxx-nn`, FK liên module tạo ở `02_foreign_keys/`).
> Phạm vi: **9 bảng** = M4 (2) + M5 (5) + M6 (2). Cộng với Đợt 1 là **27 bảng**, còn lại 14 bảng ở Đợt 3.
> Các câu hỏi Phần E của Đợt 1 chưa có trả lời nên đang **giả định theo mặc định** (hoa hồng 10%, thanh toán từ `Confirmed`, chủ lab nhiều lab, user nhiều role, có `geography`).

---

### 1. Phủ Business Flow

| Flow | Phục vụ bởi (đợt 2) |
|---|---|
| 2. Service Booking and Film Collection | `dlv.DeliveryRequests` (lấy phim, trả phim), `dlv.DeliveryStatusLog` |
| 4. Digital Delivery and Archive | `arc.ScanFiles`, `arc.PhotoMetadata`, `arc.Albums`, `arc.AlbumPhotos`, `arc.Notifications` |
| 1. Discovery (xếp hạng lab) | `ord.Reviews` (nguồn của `FilmLabs.AvgRating`) |
| Quản trị khiếu nại, tranh chấp (vai trò Admin) | `ord.Complaints` |
| Đánh giá chất lượng scan bằng AI (Computer Vision) | `arc.ScanFiles.QualityScore`, `QualityStatus` (nơi model ghi kết quả) |

### 2. Điều chỉnh cần làm cho tài liệu Đợt 1 (do phát sinh ở Đợt 2)

| STT | Điều chỉnh | Lý do |
|---|---|---|
| 1 | Thêm `UQ_Orders_OrderId_CustomerId_LabId` (`OrderId`, `CustomerId`, `LabId`) vào `ord.Orders` | Để `Reviews` và `Complaints` tham chiếu bằng **FK ghép ba cột**, DB tự bảo đảm khách và lab trong review/khiếu nại đúng là khách và lab của đơn |
| 2 | `ord.FeeConfigs` seed thêm 1 dòng: `DeliveryBase`, `FixedAmount` = 25000, toàn hệ thống (**giả định**) | Phí giao cố định mỗi chặng |
| 3 | Module `arc` phụ thuộc thêm `lab` (iam, lab, ord) | `PhotoMetadata.FilmStockId` trỏ `lab.FilmStocks` |
| 4 | `Contracts.md`: thêm procedure/function mới ở mục 8 bên dưới | |
| 5 | `BR-ORD-09` bổ sung: không giao trả phim khi chưa `Paid` (`BR-DLV-06`), nên vào `Completed` sau giao trả luôn đạt điều kiện thanh toán | Tránh shipper bị kẹt ở giai đoạn cuối |
| 6 | `ord.sp_CreateOrder` gọi `dlv.sp_RequestDelivery` để tạo các chặng giao; thêm `ord.fn_CalcDeliveryFee` | Phí giao phải tính trước khi chèn `Orders` (vì `TotalAmount = Subtotal + DeliveryFee`) |

> **Lưu ý code:** `ord.sp_CreateOrder` (thư mục `07_procedures/ord.sql`) gọi `dlv.sp_RequestDelivery` (`07_procedures/dlv.sql`, chạy sau). SQL Server cho phép vì procedure phân giải tên đối tượng lúc chạy (deferred name resolution), nên build không lỗi. Chỉ cần đã build đủ trước khi **gọi** `sp_CreateOrder`.

---

## PHẦN A. MODULE M4: `dlv` (Delivery)

**Phụ thuộc:** `iam`, `ord`.

### A.1 Quan hệ

```
Orders 1──N DeliveryRequests N──0..1 DeliveryPartners (iam)
                             N──1 Addresses (iam)
DeliveryRequests 1──N DeliveryStatusLog
```

Mỗi đơn có tối đa **2 chặng**: `Pickup` (lấy phim từ khách mang về lab) và `Return` (trả phim, ảnh in về khách). Khách tự mang đến/tự lấy thì không có chặng tương ứng.

### A.2 `dlv.DeliveryRequests` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| DeliveryRequestId | INT IDENTITY | PK | |
| OrderId | INT | NOT NULL, FK -> `ord.Orders` (liên module) | |
| Direction | NVARCHAR(6) | NOT NULL, CK IN (`'Pickup'`,`'Return'`) | |
| CustomerAddressId | INT | NOT NULL, FK -> `iam.Addresses` (liên module) | Địa chỉ phía khách; phía lab lấy từ `lab.FilmLabs` |
| DeliveryPartnerId | INT | NULL, FK -> `iam.DeliveryPartners` (liên module) | NULL cho tới khi phân công |
| Status | NVARCHAR(10) | NOT NULL, DF `'Requested'`, CK IN (`'Requested'`,`'Assigned'`,`'PickedUp'`,`'Delivered'`,`'Failed'`,`'Cancelled'`) | |
| Fee | DECIMAL(18,0) | NOT NULL, CK >= 0 | Phí khách trả cho chặng này, chốt lúc tạo đơn |
| DistanceKm | DECIMAL(6,2) | NULL, CK >= 0 | Thông tin tham khảo |
| ScheduledAt | DATETIME2(0) | NULL | Hẹn giờ lấy/giao |
| PickedUpAt | DATETIME2(0) | NULL | |
| DeliveredAt | DATETIME2(0) | NULL | |
| ExternalTrackingCode | NVARCHAR(50) | NULL | Mã theo dõi bên Ahamove/Lalamove |
| FailureReason | NVARCHAR(255) | NULL | |

CHECK nhiều cột:
- `Status <> 'Failed' OR FailureReason IS NOT NULL`
- `Status NOT IN ('Assigned','PickedUp','Delivered') OR DeliveryPartnerId IS NOT NULL`
- `PickedUpAt IS NULL OR Status IN ('PickedUp','Delivered','Failed')`
- `DeliveredAt IS NULL OR Status = 'Delivered'`

### A.3 `dlv.DeliveryStatusLog` (bất biến)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| LogId | INT IDENTITY | PK | |
| DeliveryRequestId | INT | NOT NULL, FK -> `dlv.DeliveryRequests` | |
| FromStatus | NVARCHAR(10) | NULL | NULL ở dòng khởi tạo |
| ToStatus | NVARCHAR(10) | NOT NULL | |
| ChangedBy | INT | NULL, FK -> `iam.Users` (liên module) | Từ `SESSION_CONTEXT` |
| Note | NVARCHAR(255) | NULL | |
| ChangedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |

### A.4 Chuyển trạng thái chặng giao

| Từ | Sang được | Điều kiện |
|---|---|---|
| `Requested` | `Assigned`, `Cancelled` | `Assigned` cần chọn partner đang `IsActive` |
| `Assigned` | `PickedUp`, `Cancelled`, `Failed` | |
| `PickedUp` | `Delivered`, `Failed` | |
| `Delivered`, `Failed`, `Cancelled` | (kết thúc) | Chặng `Failed` thì tạo chặng mới thay thế |

**Điều kiện theo chiều giao (liên kết với giai đoạn đơn):**

| Chiều | Được `Assigned` khi đơn ở | Được `PickedUp` khi | Khi `Delivered` thì đơn chuyển |
|---|---|---|---|
| `Pickup` | `Confirmed` hoặc `AwaitingFilm` | (không thêm) | `AwaitingFilm` -> `FilmReceived` |
| `Return` | `ReadyToReturn` | `PaymentStatus = 'Paid'` | `ReadyToReturn` -> `Completed` |

### A.5 Business rules M4

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-DLV-01 | Khi tạo đơn, tự tạo chặng `Pickup` nếu `FulfillmentMethod = 'Pickup'` và chặng `Return` nếu `ReturnMethod = 'Delivery'`; địa chỉ lấy từ `Orders.PickupAddressId` / `ReturnAddressId` | `ord.sp_CreateOrder` gọi `dlv.sp_RequestDelivery` |
| BR-DLV-02 | Mỗi đơn chỉ có tối đa 1 chặng **đang hiệu lực** theo mỗi chiều | Filtered unique index `UX_Delivery_ActiveLeg` (`OrderId`, `Direction`) WHERE `Status NOT IN ('Failed','Cancelled') AND IsDeleted = 0` |
| BR-DLV-03 | Trạng thái chỉ chuyển theo bảng A.4, không lùi | `dlv.fn_IsValidDeliveryTransition` + `trg_DeliveryRequests_Guard` |
| BR-DLV-04 | Chỉ phân công partner `IsActive`; partner loại `Individual` phải có user với role `Delivery` | `dlv.sp_AssignPartner` (mới) |
| BR-DLV-05 | Chặng `Pickup` -> `Delivered` thì tự đưa đơn sang `FilmReceived` | `dlv.sp_UpdateDeliveryStatus` gọi `ord.sp_UpdateOrderStage` (dlv **không** ghi trực tiếp bảng `ord`) |
| BR-DLV-06 | **Không giao trả phim khi đơn chưa thanh toán**: chặng `Return` chỉ được `PickedUp` khi `PaymentStatus = 'Paid'` | `sp_UpdateDeliveryStatus` |
| BR-DLV-07 | Chặng `Return` -> `Delivered` thì tự đưa đơn sang `Completed` | `sp_UpdateDeliveryStatus` gọi `ord.sp_UpdateOrderStage` |
| BR-DLV-08 | `Fee` mỗi chặng chốt lúc tạo đơn; `Orders.DeliveryFee` = tổng `Fee` các chặng; không đổi sau đó | `ord.fn_CalcDeliveryFee`, `sp_CreateOrder` |
| BR-DLV-09 | Mọi thay đổi trạng thái ghi `DeliveryStatusLog`; `PickedUpAt`, `DeliveredAt` tự đặt theo trạng thái | `trg_DeliveryRequests_LogStatus` |
| BR-DLV-10 | `Failed` bắt buộc có `FailureReason`; lab/Admin tạo chặng mới thay thế (chặng cũ giữ làm lịch sử) | CHECK + `sp_RequestDelivery` |
| BR-DLV-11 | Partner chỉ thấy và cập nhật chặng được giao cho mình | Row-Level Security (`role_Delivery`) |
| BR-DLV-12 | Không hủy đơn khi chặng `Pickup` đã `PickedUp` hoặc `Delivered`; hủy đơn thì tự hủy các chặng chưa `PickedUp` | `ord.sp_CancelOrder` gọi `dlv.sp_UpdateDeliveryStatus` |

---

## PHẦN B. MODULE M5: `arc` (Digital Archive)

**Phụ thuộc:** `iam`, `lab`, `ord`.

### B.1 Quan hệ

```
Orders 1──N ScanFiles 1──1 PhotoMetadata N──0..1 FilmStocks (lab)
Users  1──N ScanFiles                     (chủ sở hữu = khách của đơn)
Users  1──N Albums N──N ScanFiles         (qua AlbumPhotos)
Users  1──N Notifications N──0..1 Orders
```

> **Nguyên tắc:** DB **không** lưu ảnh nhị phân. `ScanFiles` chỉ lưu `StorageUrl` (file nằm trên Azure Blob/Firebase) cùng metadata, checksum và kết quả AI.

### B.2 `arc.ScanFiles` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ScanFileId | UNIQUEIDENTIFIER | PK, DF `NEWSEQUENTIALID()` | Ngoại lệ so với quy ước INT, đã nêu trong `Conventions.md` |
| OrderId | INT | NOT NULL, FK -> `ord.Orders` (liên module) | |
| OrderItemId | INT | NULL, FK -> `ord.OrderItems` (liên module) | Cuộn phim nào |
| OwnerUserId | INT | NOT NULL, FK -> `iam.Users` (liên module) | Phải trùng `Orders.CustomerId` (BR-ARC-02) |
| UploadedBy | INT | NOT NULL, FK -> `iam.Users` (liên module) | Nhân viên/chủ lab |
| FrameNumber | SMALLINT | NULL, CK > 0 | Số khung trên cuộn |
| FileName | NVARCHAR(255) | NOT NULL | |
| StorageUrl | NVARCHAR(1000) | NOT NULL | |
| ContentType | NVARCHAR(20) | NOT NULL, CK IN (`'image/jpeg'`,`'image/tiff'`,`'image/png'`) | |
| FileSizeBytes | BIGINT | NOT NULL, CK BETWEEN 1 AND 209715200 | Tối đa 200 MB |
| WidthPx / HeightPx | INT | NULL, CK > 0 | |
| ChecksumSha256 | CHAR(64) | NULL | Phát hiện file hỏng/trùng |
| QualityScore | DECIMAL(5,2) | NULL, CK BETWEEN 0 AND 100 | Điểm Computer Vision |
| QualityStatus | NVARCHAR(10) | NOT NULL, DF `'NotChecked'`, CK IN (`'NotChecked'`,`'Passed'`,`'Warning'`,`'Failed'`) | |
| UploadedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |

UQ (`OrderId`, `FileName`). CHECK: `QualityStatus = 'NotChecked' OR QualityScore IS NOT NULL`.

### B.3 `arc.PhotoMetadata` (+`CreatedAt`, `UpdatedAt`)

Quan hệ 1-1 với `ScanFiles`. Lưu đúng nhóm metadata đề yêu cầu (film stock, camera, lens, ngày chụp, cách xử lý, thông số scan).

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ScanFileId | UNIQUEIDENTIFIER | PK, FK -> `arc.ScanFiles` | |
| FilmStockId | INT | NULL, FK -> `lab.FilmStocks` (liên module) | |
| CameraModel | NVARCHAR(100) | NULL | |
| LensModel | NVARCHAR(100) | NULL | |
| ShootingDate | DATE | NULL, CK `<= CAST(SYSUTCDATETIME() AS DATE)` | Không được ở tương lai |
| ExposedIso | SMALLINT | NULL, CK > 0 | ISO khi chụp (có thể khác ISO phim nếu đẩy/kéo) |
| ProcessMethod | NVARCHAR(100) | NULL | Ví dụ "C-41, đẩy +1" |
| ScannerModel | NVARCHAR(100) | NULL | |
| ScanResolutionDpi | INT | NULL, CK > 0 | |
| ExtraJson | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | Thông số mở rộng (EXIF, màu, ghi chú) |

### B.4 `arc.Albums` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| AlbumId | INT IDENTITY | PK | |
| OwnerUserId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| Title | NVARCHAR(150) | NOT NULL | |
| Description | NVARCHAR(500) | NULL | |
| CoverScanFileId | UNIQUEIDENTIFIER | NULL, FK -> `arc.ScanFiles` | |
| IsPublic | BIT | NOT NULL, DF 0 | |

Filtered UQ (`OwnerUserId`, `Title`) WHERE `IsDeleted = 0`.

### B.5 `arc.AlbumPhotos` (bảng liên kết N-N)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| AlbumId | INT | PK (1/2), FK -> `arc.Albums` | |
| ScanFileId | UNIQUEIDENTIFIER | PK (2/2), FK -> `arc.ScanFiles` | |
| SortOrder | SMALLINT | NOT NULL, DF 0 | |
| AddedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |

### B.6 `arc.Notifications` (+`CreatedAt`)

Bảng thuộc `arc`, nhưng **mọi module** tạo thông báo qua `arc.sp_CreateNotification` (module khác không `INSERT` trực tiếp).

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| NotificationId | INT IDENTITY | PK | |
| UserId | INT | NOT NULL, FK -> `iam.Users` (liên module) | Người nhận |
| Type | NVARCHAR(12) | NOT NULL, CK IN (`'OrderStage'`,`'ScanReady'`,`'Delivery'`,`'Payment'`,`'Review'`,`'Complaint'`,`'Event'`,`'Market'`,`'System'`) | |
| Title | NVARCHAR(150) | NOT NULL | |
| Body | NVARCHAR(500) | NULL | |
| OrderId | INT | NULL, FK -> `ord.Orders` (liên module) | Đơn liên quan (nếu có) |
| IsRead | BIT | NOT NULL, DF 0 | |
| ReadAt | DATETIME2(0) | NULL | |

CHECK: `IsRead = 0 OR ReadAt IS NOT NULL`.

### B.7 Business rules M5

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-ARC-01 | Chỉ chủ lab của đơn (hoặc Admin) được upload scan; đơn phải có dịch vụ Category `Scan` và đang ở `Scanning`, `ImagePrep`, `QualityCheck` hoặc `ReadyToReturn` | `arc.sp_UploadScan` + RLS |
| BR-ARC-02 | `OwnerUserId` luôn bằng `Orders.CustomerId` của đơn | `sp_UploadScan` + `trg_ScanFiles_CheckOwner` |
| BR-ARC-03 | DB chỉ lưu URL, không lưu nhị phân; chỉ nhận JPEG/TIFF/PNG, kích thước 1 byte đến 200 MB | CHECK |
| BR-ARC-04 | Tên file không trùng trong cùng đơn | UQ (`OrderId`, `FileName`) |
| BR-ARC-05 | Lần upload **đầu tiên** của một đơn tạo thông báo `ScanReady` cho khách (không tạo lặp mỗi file) | `trg_ScanFiles_Notify` gọi `sp_CreateNotification` |
| BR-ARC-06 | File mới ở `NotChecked`; model AI ghi điểm qua `arc.sp_SetScanQuality` (mới): điểm >= 70 `Passed`, 40 đến dưới 70 `Warning`, dưới 40 `Failed`; ngưỡng nằm trong procedure | `sp_SetScanQuality` |
| BR-ARC-07 | Khi upload, nếu chưa nhập `FilmStockId` thì lấy từ `OrderItems.FilmStockId` | `sp_UploadScan` |
| BR-ARC-08 | Album chỉ chứa ảnh của chính chủ album; một ảnh có thể ở nhiều album; tên album không trùng trong cùng chủ | `trg_AlbumPhotos_CheckOwner`, filtered UQ |
| BR-ARC-09 | Khách chỉ thấy ảnh/album của mình, cộng album `IsPublic = 1` | RLS (`role_Customer`) + `vw_CustomerArchive` |
| BR-ARC-10 | Không xóa cứng file; xóa mềm `IsDeleted = 1` (chủ ảnh hoặc Admin) | DENY DELETE |
| BR-ARC-11 | Mỗi người chỉ đọc và đánh dấu đã đọc thông báo của chính mình | RLS + `arc.sp_MarkNotificationRead` (mới) |
| BR-ARC-12 | Module khác tạo thông báo chỉ qua `arc.sp_CreateNotification` | Quy ước sở hữu dữ liệu |

---

## PHẦN C. MODULE M6: Review và Complaint (schema `ord`)

**Phụ thuộc:** `iam`, `lab`, `ord`. Thêm 2 bảng vào `ord` (file `01_tables/ord.sql`).

### C.1 Quan hệ

```
Orders 1──0..1 Reviews        (mỗi đơn tối đa 1 đánh giá)
Orders 1──N    Complaints
```

Cả hai bảng tham chiếu `Orders` bằng **FK ghép ba cột** (`OrderId`, `CustomerId`, `LabId`) để DB tự bảo đảm khách và lab khớp với đơn (cần thêm UQ ở `Orders`, xem mục 2).

### C.2 `ord.Reviews` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ReviewId | INT IDENTITY | PK | |
| OrderId | INT | NOT NULL, **UQ** | Mỗi đơn 1 đánh giá |
| CustomerId | INT | NOT NULL | |
| LabId | INT | NOT NULL | |
| RatingOverall | TINYINT | NOT NULL, CK BETWEEN 1 AND 5 | |
| RatingScanQuality | TINYINT | NULL, CK BETWEEN 1 AND 5 | |
| RatingSpeed | TINYINT | NULL, CK BETWEEN 1 AND 5 | |
| Comment | NVARCHAR(1000) | NULL | |
| LabReply | NVARCHAR(1000) | NULL | |
| LabRepliedAt | DATETIME2(0) | NULL | |
| IsVisible | BIT | NOT NULL, DF 1 | Admin ẩn nội dung vi phạm |
| ModeratedBy | INT | NULL, FK -> `iam.Users` (liên module) | |
| ModeratedAt | DATETIME2(0) | NULL | |
| ModerationReason | NVARCHAR(255) | NULL | |

FK ghép: (`OrderId`, `CustomerId`, `LabId`) -> `ord.Orders` (`OrderId`, `CustomerId`, `LabId`).
CHECK: `IsVisible = 1 OR ModerationReason IS NOT NULL`; `LabReply IS NULL OR LabRepliedAt IS NOT NULL`.

### C.3 `ord.Complaints` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ComplaintId | INT IDENTITY | PK | |
| OrderId | INT | NOT NULL | |
| CustomerId | INT | NOT NULL | Người khiếu nại |
| LabId | INT | NOT NULL | Lab bị khiếu nại |
| Category | NVARCHAR(12) | NOT NULL, CK IN (`'LostFilm'`,`'DamagedFilm'`,`'ScanQuality'`,`'Delay'`,`'Billing'`,`'Service'`,`'Other'`) | |
| Title | NVARCHAR(150) | NOT NULL | |
| Description | NVARCHAR(2000) | NOT NULL | |
| Status | NVARCHAR(9) | NOT NULL, DF `'Open'`, CK IN (`'Open'`,`'InReview'`,`'Resolved'`,`'Rejected'`) | |
| LabResponse | NVARCHAR(1000) | NULL | Lab phản hồi |
| AssignedAdminId | INT | NULL, FK -> `iam.Users` (liên module) | |
| ResolutionType | NVARCHAR(12) | NULL, CK IN (`'Refund'`,`'Redo'`,`'Compensation'`,`'NoAction'`) | |
| Resolution | NVARCHAR(1000) | NULL | |
| RefundAmount | DECIMAL(18,0) | NULL, CK >= 0 | |
| ResolvedAt | DATETIME2(0) | NULL | |

FK ghép: (`OrderId`, `CustomerId`, `LabId`) -> `ord.Orders`.
CHECK nhiều cột:
- `Status NOT IN ('Resolved','Rejected') OR (Resolution IS NOT NULL AND ResolvedAt IS NOT NULL)`
- `Status = 'Open' OR AssignedAdminId IS NOT NULL`
- `RefundAmount IS NULL OR ResolutionType = 'Refund'`
- `ResolutionType IS NULL OR Status = 'Resolved'`

Filtered UQ (`OrderId`, `Category`) WHERE `Status IN ('Open','InReview') AND IsDeleted = 0`.

> Tranh chấp ở **Marketplace** (mua bán thiết bị) không nằm ở bảng này, xử lý ở Đợt 3 bằng trạng thái `Disputed` trong `mkt.MarketTransactions`.

### C.4 Chuyển trạng thái khiếu nại

| Từ | Sang được | Ai thực hiện |
|---|---|---|
| `Open` | `InReview`, `Rejected` | Admin |
| `InReview` | `Resolved`, `Rejected` | Admin |
| `Resolved`, `Rejected` | (kết thúc) | |

### C.5 Business rules M6

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-REV-01 | Chỉ khách của đơn được đánh giá; đơn phải `Completed`; trong 30 ngày kể từ `CompletedAt`; mỗi đơn tối đa 1 đánh giá | `ord.sp_AddReview` + `trg_Reviews_CheckEligible` + UQ `OrderId` |
| BR-REV-02 | Điểm tổng 1 đến 5 (bắt buộc); điểm thành phần 1 đến 5 (tùy chọn) | CHECK |
| BR-REV-03 | `CustomerId`, `LabId` của review luôn khớp đơn | FK ghép ba cột |
| BR-REV-04 | Lab trả lời đúng 1 lần, chỉ lab của đơn; không ai sửa nội dung review (chỉ ẩn/hiện bởi Admin) | `ord.sp_ReplyReview` (mới) + DENY UPDATE cột |
| BR-REV-05 | Admin ẩn review bắt buộc ghi lý do; review ẩn không tính điểm | CHECK + `ord.sp_ModerateReview` (mới) |
| BR-REV-06 | Mỗi thay đổi `Reviews` tính lại `FilmLabs.AvgRating` = trung bình `RatingOverall` (làm tròn 2 số) của review `IsVisible = 1` và chưa xóa, cùng `ReviewCount` | `ord.trg_Reviews_UpdateRating` gọi `lab.sp_RecalcLabRating` (mới), vì bảng `FilmLabs` thuộc module `lab` |
| BR-CMP-01 | Chỉ khách của đơn khiếu nại; đơn không ở `Pending`/`Cancelled`; hạn tối đa 30 ngày sau `Completed` | `ord.sp_FileComplaint` |
| BR-CMP-02 | Không có 2 khiếu nại đang mở trùng (`OrderId`, `Category`) | Filtered unique index |
| BR-CMP-03 | Trạng thái chỉ đi tới theo mục C.4; chỉ Admin xử lý, từ `InReview` phải có `AssignedAdminId` | CHECK + `trg_Complaints_Guard` |
| BR-CMP-04 | `Resolved`/`Rejected` bắt buộc có `Resolution` và `ResolvedAt`; `ResolutionType` chỉ khi `Resolved` | CHECK |
| BR-CMP-05 | `RefundAmount` <= `Orders.TotalAmount`. Hoàn **toàn bộ** thì `Payments.Status = 'Refunded'` và `Orders.PaymentStatus = 'Refunded'`; hoàn **một phần** chỉ ghi nhận ở khiếu nại, không đổi `PaymentStatus` (giới hạn đã chấp nhận để mô hình đơn giản) | `ord.sp_ResolveComplaint` |
| BR-CMP-06 | Lab được phản hồi (`LabResponse`) khi khiếu nại `Open`/`InReview`, chỉ lab của đơn | `sp_ResolveComplaint`/RLS |
| BR-CMP-07 | Tạo khiếu nại hoặc đổi trạng thái thì thông báo cho khách, lab và Admin | `trg_Complaints_Notify` gọi `arc.sp_CreateNotification` |
| BR-CMP-08 | Không xóa cứng khiếu nại | DENY DELETE |

---

## PHẦN D. TỔNG HỢP CHO CÁC BƯỚC SAU

### D.1 FK liên module (`02_foreign_keys/`)

| Module | Tên FK | Từ -> Tới |
|---|---|---|
| `dlv` | `FK_DeliveryRequests_Orders` | `dlv.DeliveryRequests.OrderId` -> `ord.Orders` |
| `dlv` | `FK_DeliveryRequests_Addresses` | `CustomerAddressId` -> `iam.Addresses` |
| `dlv` | `FK_DeliveryRequests_Partners` | `DeliveryPartnerId` -> `iam.DeliveryPartners` |
| `dlv` | `FK_DeliveryStatusLog_Users` | `dlv.DeliveryStatusLog.ChangedBy` -> `iam.Users` |
| `arc` | `FK_ScanFiles_Orders` | `arc.ScanFiles.OrderId` -> `ord.Orders` |
| `arc` | `FK_ScanFiles_OrderItems` | `OrderItemId` -> `ord.OrderItems` |
| `arc` | `FK_ScanFiles_Owner` | `OwnerUserId` -> `iam.Users` |
| `arc` | `FK_ScanFiles_UploadedBy` | `UploadedBy` -> `iam.Users` |
| `arc` | `FK_PhotoMetadata_FilmStocks` | `arc.PhotoMetadata.FilmStockId` -> `lab.FilmStocks` |
| `arc` | `FK_Albums_Users` | `arc.Albums.OwnerUserId` -> `iam.Users` |
| `arc` | `FK_Notifications_Users` | `arc.Notifications.UserId` -> `iam.Users` |
| `arc` | `FK_Notifications_Orders` | `arc.Notifications.OrderId` -> `ord.Orders` |
| `ord` | `FK_Reviews_ModeratedBy` | `ord.Reviews.ModeratedBy` -> `iam.Users` |
| `ord` | `FK_Complaints_AssignedAdmin` | `ord.Complaints.AssignedAdminId` -> `iam.Users` |

FK **trong cùng module** (tạo ở `01_tables/`): `DeliveryStatusLog` -> `DeliveryRequests`; `PhotoMetadata`, `AlbumPhotos` -> `ScanFiles`; `AlbumPhotos` -> `Albums`; `Albums.CoverScanFileId` -> `ScanFiles`; `Reviews`/`Complaints` -> `Orders` (FK ghép ba cột).

### D.2 Index dự kiến (`03_indexes/`)

| Bảng | Index | Phục vụ |
|---|---|---|
| `dlv.DeliveryRequests` | `UX_Delivery_ActiveLeg` (filtered) | BR-DLV-02 |
| `dlv.DeliveryRequests` | `IX_Delivery_Partner_Status` (`DeliveryPartnerId`, `Status`) INCLUDE (`OrderId`, `Direction`) | Bảng việc của shipper |
| `dlv.DeliveryStatusLog` | `IX_DeliveryLog_Request` (`DeliveryRequestId`, `ChangedAt`) | Dòng thời gian giao hàng |
| `arc.ScanFiles` | `IX_ScanFiles_Owner` (`OwnerUserId`, `UploadedAt` DESC) | Digital Film Archive của khách |
| `arc.ScanFiles` | `IX_ScanFiles_Order` (`OrderId`) | Ảnh theo đơn |
| `arc.PhotoMetadata` | `IX_PhotoMetadata_Stock` (`FilmStockId`) | Lọc ảnh theo loại phim |
| `arc.AlbumPhotos` | `IX_AlbumPhotos_ScanFile` (`ScanFileId`) | Tra ngược ảnh nằm ở album nào |
| `arc.Notifications` | `IX_Notifications_User` (`UserId`, `IsRead`, `CreatedAt` DESC) | Hộp thông báo |
| `ord.Reviews` | `IX_Reviews_Lab` (`LabId`, `IsVisible`) INCLUDE (`RatingOverall`) | Tính điểm lab |
| `ord.Complaints` | `IX_Complaints_Status` (`Status`, `CreatedAt`) | Hàng đợi của Admin |
| `ord.Complaints` | `UX_Complaints_OpenPerCategory` (filtered) | BR-CMP-02 |

### D.3 Seed reference

Đợt 2 **không có bảng Lookup mới** (các enum đều dùng `CHECK`). Chỉ bổ sung 1 dòng `FeeConfigs` (mục 2, điều chỉnh 2).

### D.4 Gợi ý dữ liệu mẫu cho demo (`04_seed/sample/`)

| Bảng | Số dòng gợi ý | Mục đích demo |
|---|---|---|
| `iam.DeliveryPartners` (Đợt 1) | 2 `Platform` (Ahamove, Lalamove) + 2 `Individual` | Phân công chặng giao |
| `dlv.DeliveryRequests` | 6 (đủ các trạng thái, cả `Pickup` và `Return`) | Bảng việc của shipper |
| `arc.ScanFiles` + `PhotoMetadata` | 30 file thuộc 6 đơn, vài file `Warning`/`Failed` | Digital Archive, lọc theo phim/máy |
| `arc.Albums` | 4 (1 public) | Tổ chức ảnh |
| `arc.Notifications` | 15 (lẫn đã đọc/chưa đọc) | Hộp thông báo |
| `ord.Reviews` | 10, trải điểm 3 đến 5, có 1 review bị ẩn | Rating lab tự cập nhật |
| `ord.Complaints` | 4 (đủ `Open`, `InReview`, `Resolved`, `Rejected`) | Quy trình xử lý khiếu nại |

### D.5 Thành phần T-SQL dự kiến cho M4-M6 (cập nhật `Contracts.md`)

| Loại | Tên |
|---|---|
| Procedure | `dlv.sp_RequestDelivery`, `dlv.sp_AssignPartner` (**mới**), `dlv.sp_UpdateDeliveryStatus`, `arc.sp_UploadScan`, `arc.sp_SetScanQuality` (**mới**), `arc.sp_CreateNotification` (**mới**), `arc.sp_MarkNotificationRead` (**mới**), `ord.sp_AddReview`, `ord.sp_ReplyReview` (**mới**), `ord.sp_ModerateReview` (**mới**), `ord.sp_FileComplaint`, `ord.sp_ResolveComplaint`, `lab.sp_RecalcLabRating` (**mới**) |
| Function | `ord.fn_CalcDeliveryFee` (**mới**), `dlv.fn_IsValidDeliveryTransition` (**mới**), `arc.fn_GetPhotoMetadata` (table-valued, đọc `ExtraJson` bằng `OPENJSON`), `ord.fn_LabAvgRating` |
| Trigger | `dlv.trg_DeliveryRequests_LogStatus`, `dlv.trg_DeliveryRequests_Guard`, `arc.trg_ScanFiles_Notify`, `arc.trg_ScanFiles_CheckOwner`, `arc.trg_AlbumPhotos_CheckOwner`, `ord.trg_Reviews_CheckEligible`, `ord.trg_Reviews_UpdateRating`, `ord.trg_Complaints_Guard`, `ord.trg_Complaints_Notify` |
| View | `arc.vw_CustomerArchive`, `dlv.vw_DeliveryBoard`, `ord.vw_LabReviews`, `ord.vw_OpenComplaints` |

**Phụ thuộc gọi giữa các module (không phải FK):**

| Procedure gọi | Gọi tới |
|---|---|
| `ord.sp_CreateOrder` | `dlv.sp_RequestDelivery`, `ord.fn_CalcDeliveryFee` |
| `ord.sp_CancelOrder` | `dlv.sp_UpdateDeliveryStatus` |
| `dlv.sp_UpdateDeliveryStatus` | `ord.sp_UpdateOrderStage`, `arc.sp_CreateNotification` |
| `ord.trg_Reviews_UpdateRating` | `lab.sp_RecalcLabRating` |
| `ord.trg_Complaints_Notify`, `arc.trg_ScanFiles_Notify` | `arc.sp_CreateNotification` |

---

## PHẦN E. CÂU HỎI CẦN NHÓM XÁC NHẬN

| STT | Câu hỏi | Mặc định |
|---|---|---|
| 1 | Phí giao tính thế nào? | Cố định theo chặng, 25.000 đ/chặng, Admin chỉnh trong `FeeConfigs` |
| 2 | Không giao trả phim khi đơn chưa thanh toán (`BR-DLV-06`)? | Có |
| 3 | Hạn đánh giá và hạn khiếu nại? | 30 ngày sau khi đơn `Completed` |
| 4 | File scan có cần nhiều phiên bản (bản gốc, thumbnail)? | Không, 1 `StorageUrl` mỗi file |
| 5 | Tranh chấp Marketplace xử lý ở Đợt 3 trong `mkt` (không dùng `Complaints`)? | Có |

**Nếu thiếu thời gian có thể cắt:** `arc.Albums` + `AlbumPhotos` (giữ archive theo đơn), `DeliveryStatusLog` (gộp vào log chung `audit.AuditLogs`), điểm thành phần `RatingScanQuality`/`RatingSpeed`.

---

## PHẦN F. THỐNG KÊ ĐỢT 2

| Module | Bảng | Số bảng |
|---|---|---|
| `dlv` | DeliveryRequests, DeliveryStatusLog | 2 |
| `arc` | ScanFiles, PhotoMetadata, Albums, AlbumPhotos, Notifications | 5 |
| `ord` (phần M6) | Reviews, Complaints | 2 |
| **Tổng đợt 2** | | **9** |
| **Lũy kế (Đợt 1 + 2)** | | **27 / 41** |

| Loại | Số lượng đợt 2 |
|---|---|
| Business rule | 12 (dlv) + 12 (arc) + 6 (review) + 8 (complaint) = **38** |
| FK liên module | 14 |
| Index dự kiến | 11 |
| Procedure / Function / Trigger / View | 13 / 4 / 9 / 4 |

---

## ĐỢT 3: (M7 `mkt`, M8 `com`, M9 `ai`, M10 `audit`)

> Nối tiếp phía dưới `docs/Requirements.md` (sau Đợt 1, 2). Dùng lại ký hiệu ở mục 0 của Đợt 1 (**+audit**, **Lookup**, `BR-xxx-nn`, FK liên module tạo ở `02_foreign_keys/`).
> Phạm vi: **14 bảng** = M7 (5) + M8 (4) + M9 (4) + M10 (1). Cộng Đợt 1, 2 là **41 bảng, đủ toàn bộ thiết kế**.
> Các câu hỏi Phần E của Đợt 1, 2 chưa có trả lời nên vẫn **giả định theo mặc định**.

---

### 1. Phủ Business Flow

| Flow | Phục vụ bởi (đợt 3) |
|---|---|
| 5. Marketplace and Equipment Exchange | `mkt.Listings`, `mkt.ListingCategories`, `mkt.ListingImages`, `mkt.MarketTransactions`, `mkt.Messages` |
| 6. Knowledge Sharing and Community | `com.Articles`, `com.ArticleComments`, `com.Events`, `com.EventRegistrations` |
| AI-powered Personalized Assistance | `ai.UserPreferences`, `ai.AIChatLogs`, `ai.RecommendationLogs`, `ai.KnowledgeDocs` |
| Admin: giám sát, kiểm duyệt, nhật ký | `audit.AuditLogs` + views tổng hợp |

### 2. Điều chỉnh cần làm cho tài liệu Đợt 1, 2 (do phát sinh ở Đợt 3)

| STT | Điều chỉnh | Lý do |
|---|---|---|
| 1 | `ord.FeeConfigs` seed thêm 1 dòng: `MarketplaceFee`, `Rate` = 0.0500, toàn hệ thống (**giả định**) | Phí giao dịch Marketplace |
| 2 | `arc.Notifications.Type`: thêm giá trị `'Market'` vào CHECK | Thông báo giao dịch và tin nhắn Marketplace |
| 3 | `Conventions.md`: bảng log tăng nhanh (`ai.AIChatLogs`, `ai.RecommendationLogs`, `audit.AuditLogs`) dùng `BIGINT IDENTITY` thay `INT` | Tránh tràn khóa |
| 4 | `Conventions.md`: thêm mẫu **FK ghép** (`OrderId`, `CustomerId`, `LabId`; `ListingId`, `SellerId`) để DB tự bảo đảm khớp | Đã dùng ở Đợt 2, dùng tiếp ở `mkt` |
| 5 | `Conventions.md`: Full-Text Index tạo trong khối `IF SERVERPROPERTY('IsFullTextInstalled') = 1` | Image SQL Server Linux dùng trong CI **không cài Full-Text**, nếu không bọc điều kiện thì build CI lỗi |
| 6 | `Contracts.md`: phụ thuộc mới: `com` -> `iam`, `lab`; `ai` -> `iam`, `lab`, `com`; `mkt` -> `iam`; `audit` -> (không FK) | |
| 7 | `iam.trg_Users_Audit` (Đợt 1) ghi qua `audit.sp_WriteAudit` | Một điểm ghi duy nhất |

---

## PHẦN A. MODULE M7: `mkt` (Marketplace)

**Phụ thuộc:** `iam`. Đọc `ord.FeeConfigs` (phí) và gọi `arc.sp_CreateNotification` (thông báo) qua function/procedure, không có FK.

> **Giới hạn phạm vi (chủ ý):** Marketplace **không xử lý tiền** qua nền tảng. Hệ thống theo dõi giao dịch và ghi nhận phí (`PlatformFee`) để báo cáo doanh thu; người mua và người bán tự thỏa thuận thanh toán. Cần thanh toán thật thì mở rộng sau.

### A.1 Quan hệ

```
ListingCategories 1──N Listings N──1 Users (Seller)
Listings 1──N ListingImages
Listings 1──N MarketTransactions N──1 Users (Buyer)
Listings 1──N Messages (Sender, Receiver = Users)
```

### A.2 `mkt.ListingCategories` (Lookup)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| CategoryId | INT | PK (ID cố định) | |
| CategoryCode | NVARCHAR(20) | NOT NULL, UQ | `CAMERA`, `LENS`, `FILM`, `FLASH`, `ACCESSORY`, `OTHER` |
| CategoryName | NVARCHAR(100) | NOT NULL | |
| IsActive | BIT | NOT NULL, DF 1 | |

### A.3 `mkt.Listings` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ListingId | INT IDENTITY | PK | |
| SellerId | INT | NOT NULL, FK -> `iam.Users` (liên module) | Người đăng |
| CategoryId | INT | NOT NULL, FK -> `mkt.ListingCategories` | |
| ListingType | NVARCHAR(8) | NOT NULL, CK IN (`'Sell'`,`'Exchange'`,`'Wanted'`) | Bán / trao đổi / cần mua |
| Title | NVARCHAR(200) | NOT NULL | |
| Description | NVARCHAR(2000) | NULL | |
| Brand | NVARCHAR(50) | NULL | |
| Model | NVARCHAR(100) | NULL | |
| Condition | NVARCHAR(10) | NULL, CK IN (`'New'`,`'LikeNew'`,`'Good'`,`'Fair'`,`'ForParts'`) | |
| Price | DECIMAL(18,0) | NULL, CK >= 0 | |
| ExchangeWanted | NVARCHAR(255) | NULL | Muốn đổi lấy gì |
| Quantity | INT | NOT NULL, DF 1, CK >= 0 | |
| City | NVARCHAR(100) | NOT NULL | |
| Status | NVARCHAR(8) | NOT NULL, DF `'Active'`, CK IN (`'Active'`,`'Reserved'`,`'Sold'`,`'Closed'`,`'Removed'`) | |
| ExpiresAt | DATETIME2(0) | NOT NULL, DF `DATEADD(DAY, 30, SYSUTCDATETIME())` | |
| ModerationReason | NVARCHAR(255) | NULL | |
| ModeratedBy | INT | NULL, FK -> `iam.Users` (liên module) | |

UQ `UQ_Listings_ListingId_SellerId` (`ListingId`, `SellerId`) để `MarketTransactions` dùng FK ghép.

CHECK nhiều cột:
- `ListingType <> 'Sell' OR Price IS NOT NULL`
- `ListingType <> 'Exchange' OR ExchangeWanted IS NOT NULL`
- `ListingType = 'Wanted' OR Condition IS NOT NULL`
- `Status <> 'Removed' OR ModerationReason IS NOT NULL`

### A.4 `mkt.ListingImages` (chỉ `CreatedAt`)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ImageId | INT IDENTITY | PK | |
| ListingId | INT | NOT NULL, FK -> `mkt.Listings` | |
| ImageUrl | NVARCHAR(1000) | NOT NULL | URL trên Blob Storage |
| SortOrder | TINYINT | NOT NULL, DF 0 | |
| IsPrimary | BIT | NOT NULL, DF 0 | |

Filtered UQ `UX_ListingImages_Primary` (`ListingId`) WHERE `IsPrimary = 1`.

### A.5 `mkt.MarketTransactions` (+`CreatedAt`, `UpdatedAt`)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| TransactionId | INT IDENTITY | PK | |
| TransactionCode | NVARCHAR(20) | NOT NULL, UQ | `SEQUENCE`, dạng `MK-2026-000001` |
| ListingId | INT | NOT NULL | |
| SellerId | INT | NOT NULL | Sao từ tin đăng, FK ghép với `ListingId` |
| BuyerId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| Quantity | INT | NOT NULL, CK > 0 | |
| UnitPrice | DECIMAL(18,0) | NOT NULL, DF 0, CK >= 0 | Giá chốt lúc đặt (0 nếu trao đổi) |
| TotalAmount | computed | `Quantity * UnitPrice`, PERSISTED | |
| PlatformFee | DECIMAL(18,0) | NOT NULL, DF 0, CK >= 0 | Chốt lúc đặt, người bán chịu |
| Status | NVARCHAR(9) | NOT NULL, DF `'Pending'`, CK IN (`'Pending'`,`'Confirmed'`,`'Shipped'`,`'Completed'`,`'Cancelled'`,`'Disputed'`) | |
| Note | NVARCHAR(500) | NULL | |
| ConfirmedAt / ShippedAt / CompletedAt | DATETIME2(0) | NULL | |
| CancelReason | NVARCHAR(255) | NULL | |
| DisputeReason | NVARCHAR(500) | NULL | |
| DisputedAt | DATETIME2(0) | NULL | |
| DisputeResolution | NVARCHAR(500) | NULL | |
| ResolvedBy | INT | NULL, FK -> `iam.Users` (liên module) | Admin |
| ResolvedAt | DATETIME2(0) | NULL | |
| BuyerRating | TINYINT | NULL, CK BETWEEN 1 AND 5 | Đánh giá người bán |
| BuyerComment | NVARCHAR(500) | NULL | |
| RatedAt | DATETIME2(0) | NULL | |

FK ghép: (`ListingId`, `SellerId`) -> `mkt.Listings` (`ListingId`, `SellerId`).
CHECK nhiều cột:
- `BuyerId <> SellerId`
- `PlatformFee <= TotalAmount`
- `Status <> 'Cancelled' OR CancelReason IS NOT NULL`
- `Status <> 'Disputed' OR DisputeReason IS NOT NULL`
- `BuyerRating IS NULL OR Status = 'Completed'`

> Điểm người bán (`seller ratings` của đề) **không lưu sẵn**: tính bằng `mkt.fn_SellerRating` = trung bình `BuyerRating`. Nhờ đó không cần thêm bảng.

### A.6 `mkt.Messages` (không xóa)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| MessageId | INT IDENTITY | PK | |
| ListingId | INT | NOT NULL, FK -> `mkt.Listings` | Cuộc trò chuyện về tin nào |
| SenderId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| ReceiverId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| Body | NVARCHAR(1000) | NOT NULL, CK `LEN(Body) > 0` | |
| SentAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |
| ReadAt | DATETIME2(0) | NULL | |

CHECK: `SenderId <> ReceiverId`.

### A.7 Chuyển trạng thái giao dịch

| Từ | Sang | Ai thực hiện |
|---|---|---|
| `Pending` | `Confirmed` | Người bán |
| `Pending` | `Cancelled` | Người mua hoặc người bán (có lý do) |
| `Confirmed` | `Shipped` | Người bán |
| `Confirmed` | `Cancelled` | Người bán hoặc người mua trước khi gửi |
| `Shipped` | `Completed` | Người mua xác nhận đã nhận (hoặc tự động sau 7 ngày không khiếu nại) |
| `Shipped` | `Disputed` | Người mua, trong 7 ngày kể từ `ShippedAt` |
| `Disputed` | `Completed` hoặc `Cancelled` | **Chỉ Admin** (kèm `DisputeResolution`) |

**Số lượng tin đăng theo giao dịch:** đặt mua thì `Listings.Quantity` giảm ngay; về 0 thì tin sang `Reserved`; hủy giao dịch thì hoàn số lượng và tin về `Active`; `Completed` giao dịch cuối khi `Quantity = 0` và không còn giao dịch mở thì tin sang `Sold`.

### A.8 Business rules M7

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-MKT-01 | Người đăng phải đăng nhập và `IsActive`; không tự mua tin của mình | `mkt.sp_CreateListing`, CHECK `BuyerId <> SellerId` |
| BR-MKT-02 | `Sell` bắt buộc `Price`; `Exchange` bắt buộc `ExchangeWanted`; `Sell`/`Exchange` bắt buộc `Condition` | CHECK nhiều cột |
| BR-MKT-03 | Tin đăng thuộc danh mục đang `IsActive`; mặc định hiệu lực 30 ngày | FK + DF `ExpiresAt` |
| BR-MKT-04 | Mỗi tin tối đa 8 ảnh và đúng 1 ảnh chính | `trg_ListingImages_Limit` + filtered unique index |
| BR-MKT-05 | Tìm kiếm nâng cao theo danh mục, khoảng giá, tình trạng, thành phố, hãng, từ khóa (Full-Text) | `mkt.sp_SearchListings` (mới) + index |
| BR-MKT-06 | Đặt mua chạy trong Transaction với khóa dòng (`UPDLOCK, HOLDLOCK`): tin phải `Active`, số lượng đủ, không bán lố khi hai người đặt đồng thời | `mkt.sp_PlaceMarketOrder` |
| BR-MKT-07 | `UnitPrice`, `PlatformFee` chốt lúc đặt; phí = `TotalAmount` x phí hiệu lực trong `FeeConfigs` (`MarketplaceFee`); trao đổi thì phí 0 | `mkt.fn_CalcMarketplaceFee` |
| BR-MKT-08 | Trạng thái giao dịch chỉ đổi theo bảng A.7; mỗi vai trò chỉ làm đúng bước của mình | `mkt.sp_UpdateMarketTransaction` (mới) + `trg_MarketTransactions_Guard` |
| BR-MKT-09 | Hủy giao dịch hoàn lại số lượng và trạng thái cho tin đăng | `sp_UpdateMarketTransaction` |
| BR-MKT-10 | Khiếu nại (`Disputed`) trong 7 ngày kể từ `ShippedAt`; chỉ Admin giải quyết, bắt buộc ghi `DisputeResolution` | `mkt.sp_ResolveDispute` (mới) |
| BR-MKT-11 | Chỉ người mua đánh giá người bán, khi giao dịch `Completed`, tối đa 1 lần; điểm người bán tính động | `mkt.sp_RateSeller` (mới), `mkt.fn_SellerRating` |
| BR-MKT-12 | Tin nhắn chỉ giữa người mua tiềm năng và **người bán của tin đó**; mỗi tin nhắn mới tạo thông báo `Market` cho người nhận | `mkt.sp_SendMessage` (mới), `trg_Messages_CheckParties` |
| BR-MKT-13 | Admin gỡ tin vi phạm (`Removed`) bắt buộc ghi lý do; tin hết hạn tự `Closed`; giao dịch `Shipped` quá 7 ngày không khiếu nại tự `Completed` | `mkt.sp_ModerateListing` (mới), `mkt.sp_RunMaintenance` (mới, gọi định kỳ bởi web/scheduler) |
| BR-MKT-14 | Không xóa cứng tin, giao dịch, tin nhắn | DENY DELETE |
| BR-MKT-15 | Chỉ người trong cuộc (mua/bán) thấy giao dịch và tin nhắn của mình; Admin thấy tất cả | Row-Level Security |

---

## PHẦN B. MODULE M8: `com` (Community & Knowledge)

**Phụ thuộc:** `iam`, `lab`. Thông báo qua `arc.sp_CreateNotification`.

### B.1 Quan hệ

```
Users 1──N Articles 1──N ArticleComments (tự trỏ: trả lời 1 cấp)
Articles N──0..1 FilmLabs, N──0..1 FilmStocks      (bài liên quan)
Users 1──N Events 1──N EventRegistrations N──1 Users
Events N──0..1 FilmLabs                              (lab đăng cai)
```

### B.2 `com.Articles` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ArticleId | INT IDENTITY | PK | |
| AuthorId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| ArticleType | NVARCHAR(10) | NOT NULL, CK IN (`'Tutorial'`,`'Review'`,`'Technical'`,`'LabGuide'`,`'Experience'`,`'Question'`) | |
| Title | NVARCHAR(200) | NOT NULL | |
| Slug | NVARCHAR(220) | NOT NULL | Filtered UQ (`IsDeleted = 0`) |
| Summary | NVARCHAR(500) | NULL | |
| Body | NVARCHAR(MAX) | NOT NULL | |
| Tags | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | Mảng JSON, ví dụ `["35mm","portra400"]` |
| RelatedLabId | INT | NULL, FK -> `lab.FilmLabs` (liên module) | Bài review/gợi ý về lab |
| RelatedStockId | INT | NULL, FK -> `lab.FilmStocks` (liên module) | Bài về loại phim |
| Status | NVARCHAR(9) | NOT NULL, DF `'Draft'`, CK IN (`'Draft'`,`'Published'`,`'Hidden'`) | |
| PublishedAt | DATETIME2(0) | NULL | |
| ModerationReason | NVARCHAR(255) | NULL | |
| ModeratedBy | INT | NULL, FK -> `iam.Users` (liên module) | |

CHECK: `Status = 'Draft' OR PublishedAt IS NOT NULL`; `Status <> 'Hidden' OR ModerationReason IS NOT NULL`.

### B.3 `com.ArticleComments` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| CommentId | INT IDENTITY | PK | |
| ArticleId | INT | NOT NULL, FK -> `com.Articles` | |
| UserId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| ParentCommentId | INT | NULL, FK -> `com.ArticleComments` | Trả lời, chỉ 1 cấp |
| Body | NVARCHAR(1000) | NOT NULL | |
| IsAccepted | BIT | NOT NULL, DF 0 | Câu trả lời được chọn (chỉ cho bài `Question`) |
| IsVisible | BIT | NOT NULL, DF 1 | |

Filtered UQ `UX_Comments_Accepted` (`ArticleId`) WHERE `IsAccepted = 1`.

### B.4 `com.Events` (+audit)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| EventId | INT IDENTITY | PK | |
| OrganizerId | INT | NOT NULL, FK -> `iam.Users` (liên module) | Expert |
| HostLabId | INT | NULL, FK -> `lab.FilmLabs` (liên module) | Lab đăng cai (nếu có) |
| EventType | NVARCHAR(9) | NOT NULL, CK IN (`'Workshop'`,`'Photowalk'`) | |
| Title | NVARCHAR(200) | NOT NULL | |
| Description | NVARCHAR(2000) | NULL | |
| StartAt / EndAt | DATETIME2(0) | NOT NULL | |
| RegistrationDeadline | DATETIME2(0) | NULL | |
| VenueName | NVARCHAR(200) | NOT NULL | |
| AddressLine / City | NVARCHAR(255) / NVARCHAR(100) | NOT NULL | |
| Location | geography | NULL | |
| Capacity | SMALLINT | NOT NULL, CK > 0 | |
| Fee | DECIMAL(18,0) | NOT NULL, DF 0, CK >= 0 | |
| Status | NVARCHAR(9) | NOT NULL, DF `'Draft'`, CK IN (`'Draft'`,`'Open'`,`'Closed'`,`'Cancelled'`,`'Completed'`) | |

CHECK: `EndAt > StartAt`; `RegistrationDeadline IS NULL OR RegistrationDeadline <= StartAt`.

### B.5 `com.EventRegistrations` (+`CreatedAt`, `UpdatedAt`; bảng liên kết N-N)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| EventId | INT | PK (1/2), FK -> `com.Events` | |
| UserId | INT | PK (2/2), FK -> `iam.Users` (liên module) | |
| Status | NVARCHAR(10) | NOT NULL, DF `'Registered'`, CK IN (`'Registered'`,`'Waitlisted'`,`'Cancelled'`,`'Attended'`) | |
| IsPaid | BIT | NOT NULL, DF 0 | Chỉ đánh dấu, không qua cổng thanh toán |
| CancelledAt | DATETIME2(0) | NULL | |

CHECK: `Status <> 'Cancelled' OR CancelledAt IS NOT NULL`.

### B.6 Business rules M8

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-COM-01 | Bài `Tutorial`, `Review`, `Technical`, `LabGuide` chỉ user có role `Expert` đăng; `Experience`, `Question` mọi thành viên đăng được | `trg_Articles_CheckAuthorRole` |
| BR-COM-02 | `Slug` sinh từ tiêu đề, không trùng giữa các bài chưa xóa | Filtered unique index |
| BR-COM-03 | `Draft` -> `Published` (đặt `PublishedAt` lần đầu); Admin ẩn (`Hidden`) bắt buộc ghi lý do | `com.sp_PublishArticle` (mới), `com.sp_ModerateArticle` (mới), CHECK |
| BR-COM-04 | Chỉ thấy bài `Published` (tác giả thấy thêm `Draft` của mình) | `com.vw_...` + RLS |
| BR-COM-05 | Bình luận chỉ 1 cấp trả lời (cha phải là bình luận gốc, cùng bài) | `trg_ArticleComments_CheckLevel` |
| BR-COM-06 | Bài `Question`: chỉ tác giả câu hỏi chọn 1 câu trả lời `IsAccepted`; mỗi bài tối đa 1 | `com.sp_AcceptAnswer` (mới), filtered unique index |
| BR-COM-07 | Sự kiện do `Expert` tổ chức; mở đăng ký (`Open`) khi còn trước `RegistrationDeadline`/`StartAt` | `com.Events` CHECK + `sp_RegisterEvent` |
| BR-COM-08 | Đăng ký chạy trong Transaction với khóa: còn chỗ thì `Registered`, hết chỗ thì `Waitlisted`; mỗi người 1 đăng ký mỗi sự kiện | `com.sp_RegisterEvent`, PK (`EventId`, `UserId`), `trg_EventRegistrations_CheckSeats` |
| BR-COM-09 | Hủy đăng ký được tới trước `StartAt`; hủy xong tự đẩy người đầu hàng chờ lên `Registered` và gửi thông báo | `com.sp_CancelEventRegistration` (mới) |
| BR-COM-10 | `Attended` chỉ do người tổ chức đánh dấu sau khi sự kiện kết thúc | `sp_RegisterEvent`/quyền |
| BR-COM-11 | Không xóa cứng bài, bình luận, sự kiện; tìm bài bằng Full-Text trên `Title`, `Summary`, `Body` | DENY DELETE, Full-Text Index |

---

## PHẦN C. MODULE M9: `ai` (AI Support)

**Phụ thuộc:** `iam`, `lab`, `com`. Đọc `ord`, `arc`, `lab` qua view/function để tính gợi ý.

> **Vai trò của module trong đồ án:** DB chứa **dữ liệu nuôi AI** (sở thích, lịch sử hội thoại, nhật ký gợi ý, kho tri thức cho RAG) và một thủ tục gợi ý lab bằng T-SQL. Model ML, LLM, embedding thật chạy ở dịch vụ AI bên ngoài, ghi kết quả vào các bảng này.

### C.1 Quan hệ

```
Users 1──0..1 UserPreferences N──0..1 FilmFormats
Users 1──N AIChatLogs (nhóm theo SessionId)
Users 1──N RecommendationLogs
Articles 1──N KnowledgeDocs (chunk)   Users 1──N KnowledgeDocs (người đóng góp)
```

### C.2 `ai.UserPreferences` (+`CreatedAt`, `UpdatedAt`)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| UserId | INT | PK, FK -> `iam.Users` (liên module) | 1-1 |
| PreferredFormatId | INT | NULL, FK -> `lab.FilmFormats` (liên module) | |
| PreferredFilmType | NVARCHAR(15) | NULL, CK IN (`'ColorNegative'`,`'BlackWhite'`,`'ColorSlide'`) | |
| PreferredCity | NVARCHAR(100) | NULL | |
| MaxDistanceKm | DECIMAL(6,2) | NULL, CK > 0 | |
| MaxBudgetPerRoll | DECIMAL(18,0) | NULL, CK >= 0 | |
| PrioritizeQuality | BIT | NOT NULL, DF 0 | |
| PrioritizeSpeed | BIT | NOT NULL, DF 0 | |
| Source | NVARCHAR(8) | NOT NULL, DF `'UserSet'`, CK IN (`'UserSet'`,`'Inferred'`) | Người dùng đặt hay hệ thống suy ra |
| ExtraJson | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | |

### C.3 `ai.AIChatLogs` (**BIGINT** IDENTITY, chỉ thêm)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| ChatLogId | BIGINT IDENTITY | PK | |
| SessionId | UNIQUEIDENTIFIER | NOT NULL | Gom một cuộc hội thoại |
| UserId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| Role | NVARCHAR(9) | NOT NULL, CK IN (`'User'`,`'Assistant'`,`'System'`) | |
| Message | NVARCHAR(MAX) | NOT NULL | |
| ModelName | NVARCHAR(50) | NULL | Bắt buộc khi `Assistant` |
| PromptTokens / CompletionTokens | INT | NULL, CK >= 0 | |
| LatencyMs | INT | NULL, CK >= 0 | |
| SourcesJson | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | `KnowledgeDocId` mà RAG đã trích |
| Feedback | NVARCHAR(10) | NULL, CK IN (`'Helpful'`,`'NotHelpful'`) | Chỉ cho dòng `Assistant` |
| CreatedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |

CHECK: `Role <> 'Assistant' OR ModelName IS NOT NULL`; `Feedback IS NULL OR Role = 'Assistant'`.

### C.4 `ai.RecommendationLogs` (**BIGINT** IDENTITY, chỉ thêm)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| RecLogId | BIGINT IDENTITY | PK | |
| UserId | INT | NOT NULL, FK -> `iam.Users` (liên module) | |
| RecommendationType | NVARCHAR(9) | NOT NULL, CK IN (`'Lab'`,`'FilmStock'`,`'Article'`,`'Event'`,`'Listing'`) | |
| ItemId | INT | NOT NULL | ID mục được gợi ý. **Không FK có chủ ý** (log phải trụ qua khi mục bị xóa và trỏ tới nhiều bảng khác nhau) |
| Rank | TINYINT | NOT NULL, CK >= 1 | |
| Score | DECIMAL(6,4) | NOT NULL, CK BETWEEN 0 AND 1 | |
| ModelVersion | NVARCHAR(30) | NOT NULL | Ví dụ `tsql-v1` |
| ContextJson | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | Bộ lọc/truy vấn lúc gợi ý |
| Action | NVARCHAR(9) | NULL, CK IN (`'Clicked'`,`'Ordered'`,`'Dismissed'`) | Phản ứng của người dùng |
| ActedAt | DATETIME2(0) | NULL | |
| CreatedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |

CHECK: `Action IS NULL OR ActedAt IS NOT NULL`.

> Bảng này là **dữ liệu đánh giá mô hình** của đề tài nghiên cứu (RBL): tính CTR, tỷ lệ đặt đơn sau gợi ý, precision@k bằng truy vấn trên `Action`, `Rank`.

### C.5 `ai.KnowledgeDocs` (+audit)

Các đoạn tri thức (chunk) cho Retrieval-Augmented Generation.

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| KnowledgeDocId | INT IDENTITY | PK | |
| SourceArticleId | INT | NULL, FK -> `com.Articles` (liên module) | Bài gốc (nếu có) |
| ChunkIndex | INT | NOT NULL, DF 0, CK >= 0 | Thứ tự đoạn trong bài |
| Title | NVARCHAR(200) | NOT NULL | |
| Topic | NVARCHAR(50) | NULL | Ví dụ `developing`, `film-selection` |
| Content | NVARCHAR(4000) | NOT NULL, CK `LEN(Content) > 0` | Một chunk |
| ContentHash | CHAR(64) | NULL | Phát hiện nội dung đổi để làm lại embedding |
| EmbeddingJson | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | Vector dạng mảng JSON (**placeholder**, xem BR-AI-08) |
| EmbeddingModel | NVARCHAR(50) | NULL | |
| ContributedBy | INT | NOT NULL, FK -> `iam.Users` (liên module) | Expert |
| IsApproved | BIT | NOT NULL, DF 0 | |
| ApprovedBy | INT | NULL, FK -> `iam.Users` (liên module) | |
| ApprovedAt | DATETIME2(0) | NULL | |

CHECK: `IsApproved = 0 OR (ApprovedBy IS NOT NULL AND ApprovedAt IS NOT NULL)`.
Filtered UQ `UX_Knowledge_Chunk` (`SourceArticleId`, `ChunkIndex`) WHERE `SourceArticleId IS NOT NULL AND IsDeleted = 0`.

### C.6 Công thức điểm gợi ý lab (mẫu, nhóm chỉnh được)

Dùng cho `ai.sp_GetLabRecommendations` (inline function `ai.fn_LabScores`). Chỉ xét lab `Approved` có gói dịch vụ đúng `PreferredFormatId` (nếu đã chọn).

| Thành phần | Công thức chuẩn hóa về [0, 1] | Trọng số mặc định |
|---|---|---|
| Rating | Làm mượt: `(AvgRating x ReviewCount + 3.5 x 5) / (ReviewCount + 5) / 5` | 0.35 |
| Khoảng cách | `1 - MIN(distance / MaxDistanceKm, 1)` (dùng `STDistance`) | 0.25 |
| Giá | 1 nếu <= `MaxBudgetPerRoll`; ngược lại `MAX(0, 1 - (price - budget) / budget)` | 0.20 |
| Tốc độ | `MAX(0, 1 - (TurnaroundDays - 1) / 14)` | 0.10 |
| Lịch sử | 1 nếu từng dùng lab và đánh giá >= 4; 0.5 nếu từng dùng; 0 nếu chưa | 0.10 |

Điều chỉnh: `PrioritizeQuality` cộng 0.10 cho Rating, trừ 0.10 của Giá; `PrioritizeSpeed` cộng 0.10 cho Tốc độ, trừ 0.10 của Giá. Điểm cuối ghi vào `RecommendationLogs` (Rank, Score, `ModelVersion = 'tsql-v1'`).

### C.7 Business rules M9

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-AI-01 | Mỗi user tối đa 1 hàng `UserPreferences`; chỉ chủ sở hữu đọc/sửa | PK 1-1 + RLS + `ai.sp_SaveUserPreferences` (mới) |
| BR-AI-02 | `AIChatLogs` chỉ thêm; chỉ cột `Feedback` được cập nhật, và chỉ trên dòng `Assistant` của chính user | `ai.sp_LogChatMessage` (mới), DENY UPDATE trừ cột `Feedback`, RLS |
| BR-AI-03 | Người dùng chỉ xem log chat/gợi ý của mình; Admin xem tổng hợp | RLS (`role_Customer`, `role_Admin`) |
| BR-AI-04 | Log hội thoại quá 180 ngày được dọn bằng thủ tục chuyên dụng (đường duy nhất được xóa) | `ai.sp_PurgeOldLogs` (mới), DENY DELETE |
| BR-AI-05 | Mỗi lần gợi ý ghi 1 dòng cho từng mục (`Rank` 1..N, `Score`, `ModelVersion`); phản ứng người dùng cập nhật bằng thủ tục riêng | `ai.sp_GetLabRecommendations`, `ai.sp_RecordRecommendationAction` (mới) |
| BR-AI-06 | Điểm gợi ý theo công thức C.6; thiếu sở thích thì bỏ thành phần đó và chia lại trọng số | `ai.fn_LabScores` |
| BR-AI-07 | Chỉ chunk `IsApproved = 1` được AI Assistant dùng; chunk do Expert đóng góp, Admin duyệt | `ai.sp_ApproveKnowledgeDoc` (mới), CHECK |
| BR-AI-08 | SQL Server 2022 chưa có kiểu vector: embedding lưu mảng JSON (placeholder); **tìm kiếm ngữ nghĩa thực tế do dịch vụ AI ngoài đảm nhiệm**, DB hỗ trợ truy xuất từ khóa bằng Full-Text trên `Title`, `Content` | Thiết kế + Full-Text Index |
| BR-AI-09 | Có view thống kê chất lượng gợi ý (CTR, tỷ lệ `Ordered`, theo `ModelVersion`) để so sánh mô hình | `ai.vw_RecommendationMetrics` |

---

## PHẦN D. MODULE M10: `audit` (System / Audit)

**Phụ thuộc:** không có FK. Mọi module gọi `audit.sp_WriteAudit` từ trigger.

### D.1 `audit.AuditLogs` (**BIGINT** IDENTITY, chỉ thêm)

| Cột | Kiểu | Ràng buộc | Ghi chú |
|---|---|---|---|
| AuditLogId | BIGINT IDENTITY | PK | |
| TableSchema | NVARCHAR(128) | NOT NULL | |
| TableName | NVARCHAR(128) | NOT NULL | |
| PrimaryKeyValue | NVARCHAR(100) | NOT NULL | Giá trị khóa của dòng bị đổi |
| Action | NVARCHAR(6) | NOT NULL, CK IN (`'INSERT'`,`'UPDATE'`,`'DELETE'`) | |
| ChangedBy | INT | NULL | Từ `SESSION_CONTEXT(N'UserId')`. **Không FK có chủ ý**: nhật ký độc lập, không bị chặn khi dữ liệu nguồn đổi |
| OldValues | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | |
| NewValues | NVARCHAR(MAX) | NULL, CK `ISJSON = 1` | |
| AppName | NVARCHAR(128) | NULL, DF `APP_NAME()` | |
| HostName | NVARCHAR(128) | NULL, DF `HOST_NAME()` | |
| ChangedAt | DATETIME2(0) | NOT NULL, DF `SYSUTCDATETIME()` | |

CHECK: `(Action = 'INSERT' AND OldValues IS NULL) OR (Action = 'DELETE' AND NewValues IS NULL) OR Action = 'UPDATE'`.

### D.2 Business rules M10

| Mã | Rule | Thực thi bằng |
|---|---|---|
| BR-AUD-01 | Nhật ký chỉ thêm, không ai sửa/xóa | DENY UPDATE, DELETE cho mọi role |
| BR-AUD-02 | Mọi module ghi nhật ký qua **một điểm duy nhất** `audit.sp_WriteAudit` (nhận JSON cũ/mới) | Quy ước + DENY INSERT trực tiếp |
| BR-AUD-03 | Bảng được giám sát: `iam.Users`, `lab.FilmLabs`, `ord.Payments`, `ord.Complaints`, `mkt.Listings`, `mkt.MarketTransactions` | 6 trigger `trg_<Bang>_Audit` |
| BR-AUD-04 | Cột nhạy cảm (`PasswordHash`) **không** đưa vào JSON | Trigger loại cột |
| BR-AUD-05 | Chỉ `role_Admin` được đọc `AuditLogs` | GRANT/DENY |
| BR-AUD-06 | Có view tra cứu thay đổi gần đây và dashboard tổng hợp toàn nền tảng cho Admin | `audit.vw_RecentChanges`, `audit.vw_AdminDashboard` |

---

## PHẦN E. TỔNG HỢP CHO CÁC BƯỚC SAU

### E.1 FK liên module (`02_foreign_keys/`)

| Module | FK (từ -> tới) |
|---|---|
| `mkt` (6) | `Listings.SellerId` -> `iam.Users`; `Listings.ModeratedBy` -> `iam.Users`; `MarketTransactions.BuyerId` -> `iam.Users`; `MarketTransactions.ResolvedBy` -> `iam.Users`; `Messages.SenderId` -> `iam.Users`; `Messages.ReceiverId` -> `iam.Users` |
| `com` (8) | `Articles.AuthorId` -> `iam.Users`; `Articles.ModeratedBy` -> `iam.Users`; `Articles.RelatedLabId` -> `lab.FilmLabs`; `Articles.RelatedStockId` -> `lab.FilmStocks`; `ArticleComments.UserId` -> `iam.Users`; `Events.OrganizerId` -> `iam.Users`; `Events.HostLabId` -> `lab.FilmLabs`; `EventRegistrations.UserId` -> `iam.Users` |
| `ai` (7) | `UserPreferences.UserId` -> `iam.Users`; `UserPreferences.PreferredFormatId` -> `lab.FilmFormats`; `AIChatLogs.UserId` -> `iam.Users`; `RecommendationLogs.UserId` -> `iam.Users`; `KnowledgeDocs.SourceArticleId` -> `com.Articles`; `KnowledgeDocs.ContributedBy` -> `iam.Users`; `KnowledgeDocs.ApprovedBy` -> `iam.Users` |
| `audit` (0) | Không có FK (chủ ý, xem D.1) |

FK **trong cùng module** (`01_tables/`): `Listings` -> `ListingCategories`; `ListingImages`, `Messages` -> `Listings`; `MarketTransactions` -> `Listings` (FK ghép `ListingId`, `SellerId`); `ArticleComments` -> `Articles` và tự trỏ; `EventRegistrations` -> `Events`.

### E.2 Index dự kiến (`03_indexes/`)

| Bảng | Index | Phục vụ |
|---|---|---|
| `mkt.Listings` | `IX_Listings_Browse` (`Status`, `CategoryId`, `Price`) INCLUDE (`Title`, `City`) | Duyệt/lọc tin |
| `mkt.Listings` | Full-Text (`Title`, `Description`)* | Tìm kiếm từ khóa |
| `mkt.ListingImages` | `UX_ListingImages_Primary` (filtered) | BR-MKT-04 |
| `mkt.MarketTransactions` | `IX_MktTxn_Buyer` (`BuyerId`, `CreatedAt` DESC) | Lịch sử mua |
| `mkt.MarketTransactions` | `IX_MktTxn_Seller_Status` (`SellerId`, `Status`) | Việc cần xử lý của người bán |
| `mkt.Messages` | `IX_Messages_Thread` (`ListingId`, `SentAt`) | Luồng trò chuyện |
| `com.Articles` | `UX_Articles_Slug` (filtered) | BR-COM-02 |
| `com.Articles` | `IX_Articles_Feed` (`Status`, `ArticleType`, `PublishedAt` DESC) | Bảng tin |
| `com.Articles` | Full-Text (`Title`, `Summary`, `Body`)* | Tìm bài |
| `com.ArticleComments` | `IX_Comments_Article` (`ArticleId`, `CreatedAt`) | Hiển thị bình luận |
| `com.ArticleComments` | `UX_Comments_Accepted` (filtered) | BR-COM-06 |
| `com.Events` | `IX_Events_Upcoming` (`Status`, `StartAt`) | Sự kiện sắp tới |
| `com.EventRegistrations` | `IX_EventReg_User` (`UserId`, `Status`) | Sự kiện của tôi |
| `ai.AIChatLogs` | `IX_ChatLogs_Session` (`SessionId`, `CreatedAt`) | Dựng lại hội thoại |
| `ai.AIChatLogs` | `IX_ChatLogs_User` (`UserId`, `CreatedAt` DESC) | Lịch sử của user |
| `ai.RecommendationLogs` | `IX_RecLogs_User` (`UserId`, `CreatedAt` DESC) | |
| `ai.RecommendationLogs` | `IX_RecLogs_Item` (`RecommendationType`, `ItemId`) | Thống kê hiệu quả theo mục |
| `ai.KnowledgeDocs` | `UX_Knowledge_Chunk` (filtered) | Không trùng chunk |
| `ai.KnowledgeDocs` | Full-Text (`Title`, `Content`)* | Truy xuất từ khóa cho RAG |
| `audit.AuditLogs` | `IX_Audit_Record` (`TableSchema`, `TableName`, `PrimaryKeyValue`, `ChangedAt` DESC) | Lịch sử một bản ghi |
| `audit.AuditLogs` | `IX_Audit_User` (`ChangedBy`, `ChangedAt` DESC) | Ai đã làm gì |

\* Full-Text Index tạo trong khối `IF SERVERPROPERTY('IsFullTextInstalled') = 1` (điều chỉnh số 5 ở mục 2).

### E.3 Seed reference

| Bảng | Nội dung |
|---|---|
| `mkt.ListingCategories` | 6 dòng: CAMERA (Máy ảnh), LENS (Ống kính), FILM (Phim), FLASH (Đèn/Flash), ACCESSORY (Phụ kiện), OTHER (Khác) |
| `ord.FeeConfigs` | Thêm 1 dòng `MarketplaceFee`, `Rate` 0.0500 (**giả định**) |

### E.4 Gợi ý dữ liệu mẫu cho demo (`04_seed/sample/`)

| Bảng | Số dòng gợi ý | Mục đích demo |
|---|---|---|
| `mkt.Listings` | 20 (đủ `Sell`, `Exchange`, `Wanted`, đủ trạng thái) + ảnh | Tìm kiếm, lọc |
| `mkt.MarketTransactions` | 8 (đủ trạng thái, 1 `Disputed`) | Vòng đời giao dịch |
| `mkt.Messages` | 20 | Trò chuyện mua bán |
| `com.Articles` | 12 (đủ loại, có `Question` kèm câu trả lời được chọn) | Bảng tin, Q&A |
| `com.Events` + `EventRegistrations` | 4 sự kiện (1 đầy, có người `Waitlisted`) | Đăng ký, hàng chờ |
| `ai.UserPreferences` | 5 | Gợi ý cá nhân hóa |
| `ai.RecommendationLogs` | 60 (có `Action`) | View thống kê mô hình |
| `ai.AIChatLogs` | 20 dòng (3 phiên) | Lịch sử hội thoại |
| `ai.KnowledgeDocs` | 15 chunk (10 đã duyệt) | Kho tri thức RAG |
| `audit.AuditLogs` | Do trigger tự sinh khi chạy seed/demo | Truy vết thay đổi |

### E.5 Thành phần T-SQL dự kiến cho M7-M10 (cập nhật `Contracts.md`)

| Loại | Tên |
|---|---|
| Procedure (22) | `mkt.sp_CreateListing`, `mkt.sp_SearchListings`, `mkt.sp_PlaceMarketOrder`, `mkt.sp_UpdateMarketTransaction`, `mkt.sp_ResolveDispute`, `mkt.sp_RateSeller`, `mkt.sp_SendMessage`, `mkt.sp_ModerateListing`, `mkt.sp_RunMaintenance`, `com.sp_PublishArticle`, `com.sp_ModerateArticle`, `com.sp_AddComment`, `com.sp_AcceptAnswer`, `com.sp_RegisterEvent`, `com.sp_CancelEventRegistration`, `ai.sp_GetLabRecommendations`, `ai.sp_SaveUserPreferences`, `ai.sp_LogChatMessage`, `ai.sp_RecordRecommendationAction`, `ai.sp_ApproveKnowledgeDoc`, `ai.sp_PurgeOldLogs`, `audit.sp_WriteAudit` |
| Function (4) | `mkt.fn_CalcMarketplaceFee`, `mkt.fn_SellerRating`, `com.fn_EventSeatsLeft`, `ai.fn_LabScores` (inline table-valued) |
| Trigger (13) | `mkt.trg_Listings_Guard`, `mkt.trg_ListingImages_Limit`, `mkt.trg_MarketTransactions_Guard`, `mkt.trg_Messages_CheckParties`, `mkt.trg_Listings_Audit`, `mkt.trg_MarketTransactions_Audit`, `com.trg_Articles_CheckAuthorRole`, `com.trg_ArticleComments_CheckLevel`, `com.trg_EventRegistrations_CheckSeats`, `ai.trg_KnowledgeDocs_Guard`, `lab.trg_FilmLabs_Audit`, `ord.trg_Payments_Audit`, `ord.trg_Complaints_Audit` |
| View (7) | `mkt.vw_MarketActive`, `mkt.vw_SellerStats`, `com.vw_ExpertContributions`, `com.vw_UpcomingEvents`, `ai.vw_RecommendationMetrics`, `audit.vw_RecentChanges`, `audit.vw_AdminDashboard` |
| Sequence | `mkt.seq_TransactionCode` |

**Phụ thuộc gọi giữa các module (không phải FK):**

| Procedure gọi | Gọi tới |
|---|---|
| `mkt.sp_PlaceMarketOrder` | `mkt.fn_CalcMarketplaceFee` (đọc `ord.FeeConfigs`), `arc.sp_CreateNotification` |
| `mkt.sp_SendMessage`, `mkt.sp_UpdateMarketTransaction`, `com.sp_RegisterEvent`, `com.sp_CancelEventRegistration` | `arc.sp_CreateNotification` |
| `ai.sp_GetLabRecommendations` | `lab.vw_...`, `lab.fn_DistanceKm`, đọc `ord.Orders`, `ord.Reviews` |
| Mọi trigger `trg_*_Audit` | `audit.sp_WriteAudit` |

### E.6 Danh sách procedure bắt buộc (★) và mở rộng

Với 42 procedure cộng dồn trên cả ba đợt, **chia hai mức** để lên kế hoạch:

| Mức | Procedure | Ghi chú |
|---|---|---|
| **★ Bắt buộc (16)** | `iam.sp_RegisterUser`, `lab.sp_ApproveLab`, `lab.sp_SearchLabs`, `ord.sp_CreateOrder`, `ord.sp_UpdateOrderStage`, `ord.sp_CancelOrder`, `ord.sp_ProcessPayment`, `dlv.sp_UpdateDeliveryStatus`, `arc.sp_UploadScan`, `ord.sp_AddReview`, `ord.sp_FileComplaint`, `ord.sp_ResolveComplaint`, `mkt.sp_CreateListing`, `mkt.sp_PlaceMarketOrder`, `com.sp_RegisterEvent`, `ai.sp_GetLabRecommendations` | Đủ phủ 6 flow, đủ cho demo và chấm điểm |
| Mở rộng (26) | Các procedure còn lại | Làm theo thời gian còn lại, ưu tiên cái nào demo cần |

---

## PHẦN F. CÂU HỎI CẦN NHÓM XÁC NHẬN

| STT | Câu hỏi | Mặc định |
|---|---|---|
| 1 | Marketplace có xử lý tiền qua nền tảng không? | Không: chỉ theo dõi giao dịch và ghi nhận phí để báo cáo |
| 2 | Phí Marketplace do ai chịu, mức bao nhiêu? | Người bán chịu, 5%, Admin chỉnh trong `FeeConfigs` |
| 3 | Thời hạn tin đăng và thời hạn tự hoàn tất giao dịch? | 30 ngày; 7 ngày sau khi gửi hàng |
| 4 | Giữ log chat AI bao lâu? | 180 ngày |
| 5 | Embedding lưu dạng mảng JSON (placeholder) vì SQL Server 2022 chưa có kiểu vector? | Có |

**Nếu thiếu thời gian có thể cắt:** `mkt.Messages` (chat chuyển sang kênh ngoài), `com.ArticleComments.IsAccepted` (bỏ Q&A), `com.Events.Fee`/`IsPaid`, các cột embedding của `KnowledgeDocs`, bớt trigger audit (giữ `Users`, `Payments`).

---

## PHẦN G. THỐNG KÊ ĐỢT 3 VÀ TỔNG KẾT TOÀN BỘ THIẾT KẾ

| Module | Bảng | Số bảng |
|---|---|---|
| `mkt` | ListingCategories, Listings, ListingImages, MarketTransactions, Messages | 5 |
| `com` | Articles, ArticleComments, Events, EventRegistrations | 4 |
| `ai` | UserPreferences, AIChatLogs, RecommendationLogs, KnowledgeDocs | 4 |
| `audit` | AuditLogs | 1 |
| **Tổng đợt 3** | | **14** |

**Tổng toàn bộ (Đợt 1 + 2 + 3):**

| Hạng mục | Đợt 1 | Đợt 2 | Đợt 3 | **Cộng** |
|---|---|---|---|---|
| Bảng | 18 | 9 | 14 | **41** |
| Business rule | 35 | 38 | 15 + 11 + 9 + 6 = 41 | **114** |
| FK liên module | 11 | 14 | 21 | **46** |
| Index dự kiến | 10 | 11 | 21 | **42** |
| Procedure | 7 | 13 | 22 | **42** (16 bắt buộc) |
| Function | 6 | 4 | 4 | **14** |
| Trigger | 6 | 9 | 13 | **28** |
| View | 3 | 4 | 7 | **14** |

Thêm 1 bảng lịch sử tự sinh `lab.LabServicesHistory` (temporal table) và 2 sequence (`ord.seq_OrderCode`, `mkt.seq_TransactionCode`).

### Checklist trước khi sang Đợt 4 (ERD, chuẩn hóa, Data Dictionary)

| STT | Việc | Ai |
|---|---|---|
| 1 | Nhóm đọc cả 3 đợt, ghi chỗ thiếu/sai so với đề | Cả nhóm |
| 2 | Trả lời các câu hỏi Phần E/F của 3 đợt (hoặc "ok mặc định") | Cả nhóm |
| 3 | Áp các điều chỉnh liệt kê ở mục 2 của Đợt 2 và Đợt 3 vào tài liệu | Người giữ `docs/` |
| 4 | Gộp 3 file vào `docs/Requirements.md`, commit | Người giữ `docs/` |
| 5 | Cập nhật `Conventions.md` (BIGINT cho bảng log, FK ghép, Full-Text có điều kiện, enum bằng CHECK) và `Contracts.md` (phụ thuộc, procedure) | Người giữ `docs/` |
