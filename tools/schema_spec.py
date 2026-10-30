# -*- coding: utf-8 -*-
"""
NGUỒN DỮ LIỆU DUY NHẤT (single source of truth) mô tả 41 bảng của FilmLabDB.
Từ file này sinh ra: ERD (diagrams/ERD.md), Data Dictionary (docs/DataDictionary.xlsx),
Contracts (phần tự động) và, ở Đợt 5, code CREATE TABLE.

Cú pháp một cột:  "Tên|KIỂU|cờ|ghi chú"
Cờ (ngăn cách bằng dấu phẩy):  P = khóa chính | N = cho phép NULL | U = unique
                               F=schema.Bang = khóa ngoại tới khóa chính của bảng đó (F=self: tự trỏ)
                               D=giá trị mặc định
Ghi chú KHÔNG chứa ký tự '|'.
Cột chuẩn tự thêm theo audit:  'A' = CreatedAt+UpdatedAt+IsDeleted | 'CU' = CreatedAt+UpdatedAt | 'C' = CreatedAt | '' = không
"""

TABLES = []

def T(schema, name, module, kind, flows, desc, audit, cols, cons=(), fks=()):
    TABLES.append(dict(schema=schema, name=name, module=module, kind=kind, flows=flows,
                       desc=desc, audit=audit, cols=list(cols), cons=list(cons), fks=list(fks)))

# ======================= M1 iam =======================
T("iam","Users","M1","Entity","F1,F2,F6","Tài khoản người dùng (khách, chủ lab, expert, shipper, admin)","A",[
 "UserId|INT IDENTITY|P|Khóa chính",
 "Email|NVARCHAR(255)||CK định dạng email; unique cho user chưa xóa",
 "AuthProvider|NVARCHAR(20)|D='Local'|CK IN ('Local','Google','Facebook'); hỗ trợ OAuth2",
 "PasswordHash|NVARCHAR(255)|N|Hash do tầng web tạo; NULL nếu đăng nhập OAuth",
 "FullName|NVARCHAR(100)||Họ tên hiển thị",
 "Phone|NVARCHAR(20)|N|CK chỉ gồm số và dấu +, dài 9-15; bị che (masking) với role không đủ quyền",
 "AvatarUrl|NVARCHAR(500)|N|URL ảnh đại diện",
 "IsActive|BIT|D=1|Khóa tài khoản mà không cần xóa",
 "LastLoginAt|DATETIME2(0)|N|Lần đăng nhập gần nhất"],
 cons=[("CK","AuthProvider <> 'Local' OR PasswordHash IS NOT NULL"),
       ("UQ","Filtered unique index UX_Users_Email (Email) WHERE IsDeleted = 0")])

T("iam","Roles","M1","Lookup","F1-F6","Danh mục vai trò hệ thống","",[
 "RoleId|INT|P|ID cố định 1-5, không IDENTITY",
 "RoleCode|NVARCHAR(30)|U|Customer, LabOwner, Expert, Delivery, Admin",
 "RoleName|NVARCHAR(100)||Tên tiếng Việt hiển thị",
 "Description|NVARCHAR(255)|N|Mô tả quyền hạn"])

T("iam","UserRoles","M1","Junction","F1-F6","Gán vai trò cho người dùng (N-N Users-Roles)","",[
 "UserId|INT|P,F=iam.Users|Khóa chính (1/2)",
 "RoleId|INT|P,F=iam.Roles|Khóa chính (2/2)",
 "AssignedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm gán",
 "AssignedBy|INT|N,F=iam.Users|NULL = tự đăng ký"])

T("iam","Addresses","M1","Entity","F1,F2","Địa chỉ của người dùng (nhận/trả phim)","A",[
 "AddressId|INT IDENTITY|P|Khóa chính",
 "UserId|INT|F=iam.Users|Chủ địa chỉ",
 "Label|NVARCHAR(50)|N|Nhãn: Nhà, Công ty",
 "RecipientName|NVARCHAR(100)||Người nhận",
 "Phone|NVARCHAR(20)||SĐT người nhận",
 "Line1|NVARCHAR(255)||Số nhà, đường",
 "Ward|NVARCHAR(100)||Phường/Xã",
 "District|NVARCHAR(100)||Quận/Huyện",
 "City|NVARCHAR(100)||Tỉnh/Thành",
 "Location|geography|N|Tọa độ, dùng tính khoảng cách",
 "IsDefault|BIT|D=0|Địa chỉ mặc định"],
 cons=[("UQ","Filtered unique index UX_Addresses_Default (UserId) WHERE IsDefault = 1 AND IsDeleted = 0")])

T("iam","ExpertProfiles","M1","Entity","F6","Hồ sơ chuyên gia nhiếp ảnh (1-1 với Users)","CU",[
 "UserId|INT|P,F=iam.Users|Khóa chính, đồng thời FK (quan hệ 1-1)",
 "Bio|NVARCHAR(1000)|N|Giới thiệu",
 "Expertise|NVARCHAR(255)|N|Lĩnh vực chuyên môn",
 "YearsExperience|SMALLINT|N|CK >= 0",
 "PortfolioUrl|NVARCHAR(500)|N|Liên kết portfolio",
 "IsVerified|BIT|D=0|Admin xác minh",
 "VerifiedBy|INT|N,F=iam.Users|Admin xác minh",
 "VerifiedAt|DATETIME2(0)|N|Thời điểm xác minh"])

T("iam","DeliveryPartners","M1","Entity","F2","Đối tác giao nhận (nền tảng như Ahamove/Lalamove hoặc shipper cá nhân)","A",[
 "DeliveryPartnerId|INT IDENTITY|P|Khóa chính",
 "ProviderType|NVARCHAR(12)||CK IN ('Platform','Individual')",
 "PartnerName|NVARCHAR(100)||Tên đối tác",
 "UserId|INT|N,F=iam.Users|Bắt buộc khi Individual",
 "VehicleType|NVARCHAR(30)|N|Loại phương tiện",
 "PlateNumber|NVARCHAR(20)|N|Biển số",
 "ApiCode|NVARCHAR(50)|N|Mã tích hợp bên thứ ba",
 "IsActive|BIT|D=1|Đang hoạt động"],
 cons=[("CK","ProviderType = 'Platform' OR UserId IS NOT NULL")])

# ======================= M2 lab =======================
T("lab","FilmLabs","M2","Entity","F1,F2","Hồ sơ Film Lab (MiniLab)","A",[
 "LabId|INT IDENTITY|P|Khóa chính; khóa RLS multi-tenant",
 "OwnerUserId|INT|F=iam.Users|Chủ lab (role LabOwner)",
 "LabName|NVARCHAR(150)||Tên lab",
 "Description|NVARCHAR(1000)|N|Giới thiệu",
 "AddressLine|NVARCHAR(255)||Địa chỉ",
 "Ward|NVARCHAR(100)||Phường/Xã",
 "District|NVARCHAR(100)||Quận/Huyện",
 "City|NVARCHAR(100)||Tỉnh/Thành",
 "Location|geography|N|Spatial index, tìm lab gần khách",
 "Phone|NVARCHAR(20)|N|SĐT lab",
 "Email|NVARCHAR(255)|N|Email lab",
 "OpenHoursJson|NVARCHAR(MAX)|N|CK ISJSON = 1; giờ mở cửa theo thứ",
 "SpecialTechniques|NVARCHAR(MAX)|N|CK ISJSON = 1; mảng kỹ thuật đặc biệt (push, pull, cross-process...)",
 "DailyCapacityRolls|SMALLINT|D=50|CK > 0; năng lực xử lý cuộn/ngày",
 "ApprovalStatus|NVARCHAR(12)|D='Pending'|CK IN ('Pending','Approved','Rejected','Suspended')",
 "AvgRating|DECIMAL(3,2)|D=0|CK 0..5; phi chuẩn hóa có chủ ý, do trigger cập nhật từ Reviews",
 "ReviewCount|INT|D=0|CK >= 0; phi chuẩn hóa có chủ ý"])

T("lab","LabApprovals","M2","Log","F1","Lịch sử duyệt/từ chối/đình chỉ lab của Admin (chỉ thêm)","",[
 "ApprovalId|INT IDENTITY|P|Khóa chính",
 "LabId|INT|F=lab.FilmLabs|Lab được xét duyệt",
 "ReviewedBy|INT|F=iam.Users|Admin quyết định",
 "Decision|NVARCHAR(12)||CK IN ('Approved','Rejected','Suspended')",
 "Reason|NVARCHAR(500)|N|Bắt buộc khi Rejected/Suspended",
 "DecidedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm quyết định"],
 cons=[("CK","Decision = 'Approved' OR Reason IS NOT NULL")])

T("lab","FilmFormats","M2","Lookup","F1,F2","Danh mục định dạng phim (35mm, 120...)","",[
 "FormatId|INT|P|ID cố định",
 "FormatCode|NVARCHAR(20)|U|35mm, 120, 4x5, 110, APS",
 "FormatName|NVARCHAR(100)||Tên hiển thị"])

T("lab","FilmStocks","M2","Lookup","F2,F4,AI","Danh mục loại phim (Portra 400, HP5...)","",[
 "StockId|INT|P|ID cố định",
 "Brand|NVARCHAR(50)||Hãng",
 "StockName|NVARCHAR(100)||Tên phim",
 "Iso|SMALLINT||CK > 0",
 "FilmType|NVARCHAR(15)||CK IN ('ColorNegative','BlackWhite','ColorSlide')",
 "ProcessCode|NVARCHAR(10)||CK IN ('C-41','E-6','BW','ECN-2'); quy trình tráng",
 "IsActive|BIT|D=1|Còn dùng"],
 cons=[("UQ","UQ (Brand, StockName)")])

T("lab","ServiceTypes","M2","Lookup","F1,F2","Danh mục loại dịch vụ (tráng, scan, in, phụ trợ)","",[
 "ServiceTypeId|INT|P|ID cố định",
 "ServiceCode|NVARCHAR(20)|U|DEV, SCAN, PRINT, EXTRA",
 "ServiceName|NVARCHAR(100)||Tên hiển thị",
 "Category|NVARCHAR(10)||CK IN ('Develop','Scan','Print','Other'); xác định giai đoạn áp dụng của đơn",
 "Description|NVARCHAR(255)|N|Mô tả"])

T("lab","LabServices","M2","Entity","F1,F2","Gói dịch vụ và giá của từng lab (Temporal Table lưu lịch sử đổi giá)","A",[
 "LabServiceId|INT IDENTITY|P|Khóa chính",
 "LabId|INT|F=lab.FilmLabs|Lab cung cấp",
 "ServiceTypeId|INT|F=lab.ServiceTypes|Loại dịch vụ",
 "FormatId|INT|F=lab.FilmFormats|Định dạng phim hỗ trợ",
 "ProcessCode|NVARCHAR(10)|D='ANY'|CK IN ('C-41','E-6','BW','ECN-2','ANY')",
 "PackageName|NVARCHAR(150)||Tên gói",
 "Description|NVARCHAR(500)|N|Mô tả gói",
 "UnitPrice|DECIMAL(18,0)||CK >= 0; VND",
 "PriceUnit|NVARCHAR(5)|D='Roll'|CK IN ('Roll','Frame')",
 "ScanQuality|NVARCHAR(5)|N|CK IN ('Basic','High','Ultra'); chỉ cho gói Category Scan",
 "TurnaroundDays|TINYINT||CK BETWEEN 1 AND 60",
 "IsActive|BIT|D=1|Đang bán"],
 cons=[("UQ","UQ (LabId, PackageName)"),
       ("TEMPORAL","SYSTEM_VERSIONING ON; thêm ValidFrom/ValidTo; bảng lịch sử lab.LabServicesHistory tự sinh")])

# ======================= M3 ord =======================
T("ord","ProcessingStages","M3","Lookup","F3","Danh mục giai đoạn xử lý đơn (13 giai đoạn)","",[
 "StageId|INT|P|ID cố định",
 "StageCode|NVARCHAR(20)|U|Pending, Confirmed, ..., Completed, Cancelled",
 "StageName|NVARCHAR(100)||Tên tiếng Việt",
 "SortOrder|TINYINT|U|Thứ tự giai đoạn",
 "IsTerminal|BIT|D=0|Completed, Cancelled"])

T("ord","Orders","M3","Entity","F2,F3","Đơn dịch vụ tráng/scan/in phim","A",[
 "OrderId|INT IDENTITY|P|Khóa chính",
 "OrderCode|NVARCHAR(20)|U|Sinh bằng SEQUENCE ord.seq_OrderCode, dạng FL-2026-000001",
 "CustomerId|INT|F=iam.Users|Khách đặt đơn",
 "LabId|INT|F=lab.FilmLabs|Lab xử lý; khóa RLS multi-tenant",
 "StageId|INT|F=ord.ProcessingStages,D=1|Giai đoạn hiện tại",
 "FulfillmentMethod|NVARCHAR(7)||CK IN ('DropOff','Pickup')",
 "ReturnMethod|NVARCHAR(11)||CK IN ('SelfCollect','Delivery')",
 "PickupAddressId|INT|N,F=iam.Addresses|Bắt buộc khi Pickup",
 "ReturnAddressId|INT|N,F=iam.Addresses|Bắt buộc khi Delivery",
 "Subtotal|DECIMAL(18,0)||CK >= 0; tổng LineTotal",
 "DeliveryFee|DECIMAL(18,0)|D=0|CK >= 0; tổng phí các chặng giao",
 "PlatformFee|DECIMAL(18,0)|D=0|CK >= 0; hoa hồng nền tảng, snapshot lúc đặt",
 "TotalAmount|DECIMAL(18,0)||Khách trả = Subtotal + DeliveryFee",
 "PaymentStatus|NVARCHAR(9)|D='Unpaid'|CK IN ('Unpaid','Paid','Refunded'); trigger cập nhật từ Payments",
 "CustomerNote|NVARCHAR(500)|N|Ghi chú của khách",
 "EstimatedReadyDate|DATE|N|Ngày dự kiến xong",
 "CompletedAt|DATETIME2(0)|N|Thời điểm hoàn tất",
 "CancelReason|NVARCHAR(255)|N|Lý do hủy"],
 cons=[("CK","TotalAmount = Subtotal + DeliveryFee"),
       ("CK","FulfillmentMethod <> 'Pickup' OR PickupAddressId IS NOT NULL"),
       ("CK","ReturnMethod <> 'Delivery' OR ReturnAddressId IS NOT NULL"),
       ("UQ","UQ_Orders_OrderId_CustomerId_LabId (OrderId, CustomerId, LabId); đích của FK ghép từ Reviews, Complaints")])

T("ord","OrderItems","M3","Entity","F2","Dòng dịch vụ trong đơn","C",[
 "OrderItemId|INT IDENTITY|P|Khóa chính",
 "OrderId|INT|F=ord.Orders|Đơn chứa dòng",
 "LabServiceId|INT|F=lab.LabServices|Gói dịch vụ đặt",
 "FilmStockId|INT|N,F=lab.FilmStocks|Loại phim khách gửi",
 "Quantity|INT||CK > 0; số cuộn hoặc số tấm tùy PriceUnit",
 "UnitPriceSnapshot|DECIMAL(18,0)||CK >= 0; giá chốt lúc đặt",
 "LineTotal|DECIMAL(18,0)|G|Cột tính: Quantity * UnitPriceSnapshot, PERSISTED",
 "ProcessingNote|NVARCHAR(255)|N|Ví dụ: đẩy +1 stop"])

T("ord","OrderStageLog","M3","Log","F3","Nhật ký chuyển giai đoạn của đơn (bất biến, do trigger ghi)","",[
 "LogId|INT IDENTITY|P|Khóa chính",
 "OrderId|INT|F=ord.Orders|Đơn",
 "FromStageId|INT|N,F=ord.ProcessingStages|NULL ở dòng khởi tạo",
 "ToStageId|INT|F=ord.ProcessingStages|Giai đoạn mới",
 "ChangedBy|INT|N,F=iam.Users|Lấy từ SESSION_CONTEXT",
 "Note|NVARCHAR(255)|N|Ghi chú",
 "ChangedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm"])

T("ord","Payments","M3","Entity","F2","Giao dịch thanh toán online của đơn","C",[
 "PaymentId|INT IDENTITY|P|Khóa chính",
 "OrderId|INT|F=ord.Orders|Đơn được thanh toán",
 "Method|NVARCHAR(12)||CK IN ('Card','EWallet','BankTransfer')",
 "Provider|NVARCHAR(30)|N|VNPay, MoMo, ZaloPay...",
 "ProviderTxnId|NVARCHAR(100)|N|Mã giao dịch bên cổng thanh toán",
 "Amount|DECIMAL(18,0)||CK > 0; phải bằng Orders.TotalAmount",
 "Status|NVARCHAR(9)|D='Pending'|CK IN ('Pending','Succeeded','Failed','Refunded')",
 "PaidAt|DATETIME2(0)|N|Thời điểm thanh toán",
 "RefundedAt|DATETIME2(0)|N|Thời điểm hoàn tiền",
 "FailureReason|NVARCHAR(255)|N|Lý do thất bại"],
 cons=[("UQ","Filtered unique index UX_Payments_OrderPaid (OrderId) WHERE Status = 'Succeeded'")])

T("ord","FeeConfigs","M3","Entity","F2,F5","Cấu hình phí (hoa hồng, phí marketplace, phí giao)","C",[
 "FeeConfigId|INT IDENTITY|P|Khóa chính",
 "FeeType|NVARCHAR(20)||CK IN ('PlatformCommission','MarketplaceFee','DeliveryBase')",
 "Rate|DECIMAL(5,4)|N|CK BETWEEN 0 AND 1; 0.1000 = 10%",
 "FixedAmount|DECIMAL(18,0)|N|CK >= 0",
 "ScopeLabId|INT|N,F=lab.FilmLabs|NULL = áp dụng toàn hệ thống",
 "EffectiveFrom|DATE||Bắt đầu hiệu lực",
 "EffectiveTo|DATE|N|Kết thúc hiệu lực",
 "CreatedBy|INT|F=iam.Users|Admin tạo"],
 cons=[("CK","Rate IS NOT NULL OR FixedAmount IS NOT NULL"),
       ("CK","EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom"),
       ("TRIGGER","Không chồng khoảng thời gian cùng (FeeType, ScopeLabId): trg_FeeConfigs_NoOverlap")])

T("ord","Reviews","M6","Entity","F1","Đánh giá lab sau khi đơn hoàn tất (mỗi đơn tối đa 1)","A",[
 "ReviewId|INT IDENTITY|P|Khóa chính",
 "OrderId|INT|U|Mỗi đơn 1 đánh giá; thành phần FK ghép",
 "CustomerId|INT||Thành phần FK ghép tới Orders",
 "LabId|INT||Thành phần FK ghép tới Orders",
 "RatingOverall|TINYINT||CK BETWEEN 1 AND 5",
 "RatingScanQuality|TINYINT|N|CK BETWEEN 1 AND 5",
 "RatingSpeed|TINYINT|N|CK BETWEEN 1 AND 5",
 "Comment|NVARCHAR(1000)|N|Nhận xét",
 "LabReply|NVARCHAR(1000)|N|Lab trả lời (1 lần)",
 "LabRepliedAt|DATETIME2(0)|N|Thời điểm trả lời",
 "IsVisible|BIT|D=1|Admin ẩn nội dung vi phạm",
 "ModeratedBy|INT|N,F=iam.Users|Admin kiểm duyệt",
 "ModeratedAt|DATETIME2(0)|N|Thời điểm kiểm duyệt",
 "ModerationReason|NVARCHAR(255)|N|Bắt buộc khi ẩn"],
 cons=[("CK","IsVisible = 1 OR ModerationReason IS NOT NULL"),
       ("CK","LabReply IS NULL OR LabRepliedAt IS NOT NULL")],
 fks=[("ord.Reviews",["OrderId","CustomerId","LabId"],"ord.Orders",["OrderId","CustomerId","LabId"],"FK ghép: bảo đảm khách và lab khớp với đơn")])

T("ord","Complaints","M6","Entity","Admin","Khiếu nại về đơn hàng và kết quả xử lý của Admin","A",[
 "ComplaintId|INT IDENTITY|P|Khóa chính",
 "OrderId|INT||Thành phần FK ghép tới Orders",
 "CustomerId|INT||Người khiếu nại; thành phần FK ghép",
 "LabId|INT||Lab bị khiếu nại; thành phần FK ghép",
 "Category|NVARCHAR(12)||CK IN ('LostFilm','DamagedFilm','ScanQuality','Delay','Billing','Service','Other')",
 "Title|NVARCHAR(150)||Tiêu đề",
 "Description|NVARCHAR(2000)||Nội dung",
 "Status|NVARCHAR(9)|D='Open'|CK IN ('Open','InReview','Resolved','Rejected')",
 "LabResponse|NVARCHAR(1000)|N|Lab phản hồi",
 "AssignedAdminId|INT|N,F=iam.Users|Admin xử lý",
 "ResolutionType|NVARCHAR(12)|N|CK IN ('Refund','Redo','Compensation','NoAction')",
 "Resolution|NVARCHAR(1000)|N|Kết quả xử lý",
 "RefundAmount|DECIMAL(18,0)|N|CK >= 0; không vượt Orders.TotalAmount",
 "ResolvedAt|DATETIME2(0)|N|Thời điểm giải quyết"],
 cons=[("CK","Status NOT IN ('Resolved','Rejected') OR (Resolution IS NOT NULL AND ResolvedAt IS NOT NULL)"),
       ("CK","Status = 'Open' OR AssignedAdminId IS NOT NULL"),
       ("CK","RefundAmount IS NULL OR ResolutionType = 'Refund'"),
       ("CK","ResolutionType IS NULL OR Status = 'Resolved'"),
       ("UQ","Filtered unique index UX_Complaints_OpenPerCategory (OrderId, Category) WHERE Status IN ('Open','InReview') AND IsDeleted = 0")],
 fks=[("ord.Complaints",["OrderId","CustomerId","LabId"],"ord.Orders",["OrderId","CustomerId","LabId"],"FK ghép: bảo đảm khách và lab khớp với đơn")])

# ======================= M4 dlv =======================
T("dlv","DeliveryRequests","M4","Entity","F2","Chặng lấy phim (Pickup) hoặc trả phim (Return) của đơn","A",[
 "DeliveryRequestId|INT IDENTITY|P|Khóa chính",
 "OrderId|INT|F=ord.Orders|Đơn",
 "Direction|NVARCHAR(6)||CK IN ('Pickup','Return')",
 "CustomerAddressId|INT|F=iam.Addresses|Địa chỉ phía khách",
 "DeliveryPartnerId|INT|N,F=iam.DeliveryPartners|NULL cho tới khi phân công",
 "Status|NVARCHAR(10)|D='Requested'|CK IN ('Requested','Assigned','PickedUp','Delivered','Failed','Cancelled')",
 "Fee|DECIMAL(18,0)||CK >= 0; phí chặng này, chốt lúc tạo đơn",
 "DistanceKm|DECIMAL(6,2)|N|CK >= 0",
 "ScheduledAt|DATETIME2(0)|N|Hẹn giờ lấy/giao",
 "PickedUpAt|DATETIME2(0)|N|Thời điểm lấy hàng",
 "DeliveredAt|DATETIME2(0)|N|Thời điểm giao xong",
 "ExternalTrackingCode|NVARCHAR(50)|N|Mã theo dõi bên Ahamove/Lalamove",
 "FailureReason|NVARCHAR(255)|N|Bắt buộc khi Failed"],
 cons=[("CK","Status <> 'Failed' OR FailureReason IS NOT NULL"),
       ("CK","Status NOT IN ('Assigned','PickedUp','Delivered') OR DeliveryPartnerId IS NOT NULL"),
       ("CK","PickedUpAt IS NULL OR Status IN ('PickedUp','Delivered','Failed')"),
       ("CK","DeliveredAt IS NULL OR Status = 'Delivered'"),
       ("UQ","Filtered unique index UX_Delivery_ActiveLeg (OrderId, Direction) WHERE Status NOT IN ('Failed','Cancelled') AND IsDeleted = 0")])

T("dlv","DeliveryStatusLog","M4","Log","F2","Nhật ký đổi trạng thái chặng giao (bất biến, do trigger ghi)","",[
 "LogId|INT IDENTITY|P|Khóa chính",
 "DeliveryRequestId|INT|F=dlv.DeliveryRequests|Chặng giao",
 "FromStatus|NVARCHAR(10)|N|NULL ở dòng khởi tạo",
 "ToStatus|NVARCHAR(10)||Trạng thái mới",
 "ChangedBy|INT|N,F=iam.Users|Lấy từ SESSION_CONTEXT",
 "Note|NVARCHAR(255)|N|Ghi chú",
 "ChangedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm"])

# ======================= M5 arc =======================
T("arc","ScanFiles","M5","Entity","F4","File ảnh scan (chỉ lưu URL và metadata, không lưu nhị phân)","A",[
 "ScanFileId|UNIQUEIDENTIFIER|P,D=NEWSEQUENTIALID()|Khóa chính (ngoại lệ so với INT)",
 "OrderId|INT|F=ord.Orders|Đơn",
 "OrderItemId|INT|N,F=ord.OrderItems|Cuộn phim nào",
 "OwnerUserId|INT|F=iam.Users|Chủ sở hữu; phải trùng Orders.CustomerId",
 "UploadedBy|INT|F=iam.Users|Nhân viên/chủ lab upload",
 "FrameNumber|SMALLINT|N|CK > 0; số khung trên cuộn",
 "FileName|NVARCHAR(255)||Tên file",
 "StorageUrl|NVARCHAR(1000)||URL trên Blob/Firebase Storage",
 "ContentType|NVARCHAR(20)||CK IN ('image/jpeg','image/tiff','image/png')",
 "FileSizeBytes|BIGINT||CK BETWEEN 1 AND 209715200 (tối đa 200 MB)",
 "WidthPx|INT|N|CK > 0",
 "HeightPx|INT|N|CK > 0",
 "ChecksumSha256|CHAR(64)|N|Phát hiện file hỏng/trùng",
 "QualityScore|DECIMAL(5,2)|N|CK BETWEEN 0 AND 100; điểm Computer Vision",
 "QualityStatus|NVARCHAR(10)|D='NotChecked'|CK IN ('NotChecked','Passed','Warning','Failed')",
 "UploadedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm upload"],
 cons=[("UQ","UQ (OrderId, FileName)"),
       ("CK","QualityStatus = 'NotChecked' OR QualityScore IS NOT NULL")])

T("arc","PhotoMetadata","M5","Entity","F4","Metadata của ảnh scan (1-1 với ScanFiles)","CU",[
 "ScanFileId|UNIQUEIDENTIFIER|P,F=arc.ScanFiles|Khóa chính, đồng thời FK (1-1)",
 "FilmStockId|INT|N,F=lab.FilmStocks|Loại phim",
 "CameraModel|NVARCHAR(100)|N|Máy ảnh",
 "LensModel|NVARCHAR(100)|N|Ống kính",
 "ShootingDate|DATE|N|CK không ở tương lai",
 "ExposedIso|SMALLINT|N|CK > 0; ISO khi chụp",
 "ProcessMethod|NVARCHAR(100)|N|Cách xử lý, ví dụ C-41 đẩy +1",
 "ScannerModel|NVARCHAR(100)|N|Máy scan",
 "ScanResolutionDpi|INT|N|CK > 0",
 "ExtraJson|NVARCHAR(MAX)|N|CK ISJSON = 1; thông số mở rộng"])

T("arc","Albums","M5","Entity","F4","Album do khách tự tổ chức trong Digital Film Archive","A",[
 "AlbumId|INT IDENTITY|P|Khóa chính",
 "OwnerUserId|INT|F=iam.Users|Chủ album",
 "Title|NVARCHAR(150)||Tên album",
 "Description|NVARCHAR(500)|N|Mô tả",
 "CoverScanFileId|UNIQUEIDENTIFIER|N,F=arc.ScanFiles|Ảnh bìa",
 "IsPublic|BIT|D=0|Công khai"],
 cons=[("UQ","Filtered unique index (OwnerUserId, Title) WHERE IsDeleted = 0")])

T("arc","AlbumPhotos","M5","Junction","F4","Ảnh trong album (N-N Albums-ScanFiles)","",[
 "AlbumId|INT|P,F=arc.Albums|Khóa chính (1/2)",
 "ScanFileId|UNIQUEIDENTIFIER|P,F=arc.ScanFiles|Khóa chính (2/2)",
 "SortOrder|SMALLINT|D=0|Thứ tự trong album",
 "AddedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm thêm"])

T("arc","Notifications","M5","Entity","F2,F3,F4","Thông báo cho người dùng (mọi module tạo qua arc.sp_CreateNotification)","C",[
 "NotificationId|INT IDENTITY|P|Khóa chính",
 "UserId|INT|F=iam.Users|Người nhận",
 "Type|NVARCHAR(12)||CK IN ('OrderStage','ScanReady','Delivery','Payment','Review','Complaint','Event','Market','System')",
 "Title|NVARCHAR(150)||Tiêu đề",
 "Body|NVARCHAR(500)|N|Nội dung",
 "OrderId|INT|N,F=ord.Orders|Đơn liên quan",
 "IsRead|BIT|D=0|Đã đọc",
 "ReadAt|DATETIME2(0)|N|Thời điểm đọc"],
 cons=[("CK","IsRead = 0 OR ReadAt IS NOT NULL")])

# ======================= M7 mkt =======================
T("mkt","ListingCategories","M7","Lookup","F5","Danh mục loại hàng Marketplace","",[
 "CategoryId|INT|P|ID cố định",
 "CategoryCode|NVARCHAR(20)|U|CAMERA, LENS, FILM, FLASH, ACCESSORY, OTHER",
 "CategoryName|NVARCHAR(100)||Tên hiển thị",
 "IsActive|BIT|D=1|Còn dùng"])

T("mkt","Listings","M7","Entity","F5","Tin đăng mua, bán, trao đổi thiết bị","A",[
 "ListingId|INT IDENTITY|P|Khóa chính",
 "SellerId|INT|F=iam.Users|Người đăng",
 "CategoryId|INT|F=mkt.ListingCategories|Danh mục",
 "ListingType|NVARCHAR(8)||CK IN ('Sell','Exchange','Wanted')",
 "Title|NVARCHAR(200)||Tiêu đề",
 "Description|NVARCHAR(2000)|N|Mô tả",
 "Brand|NVARCHAR(50)|N|Hãng",
 "Model|NVARCHAR(100)|N|Mẫu",
 "Condition|NVARCHAR(10)|N|CK IN ('New','LikeNew','Good','Fair','ForParts')",
 "Price|DECIMAL(18,0)|N|CK >= 0",
 "ExchangeWanted|NVARCHAR(255)|N|Muốn đổi lấy gì",
 "Quantity|INT|D=1|CK >= 0",
 "City|NVARCHAR(100)||Thành phố",
 "Status|NVARCHAR(8)|D='Active'|CK IN ('Active','Reserved','Sold','Closed','Removed')",
 "ExpiresAt|DATETIME2(0)|D=DATEADD(DAY, 30, SYSUTCDATETIME())|Hết hạn sau 30 ngày",
 "ModerationReason|NVARCHAR(255)|N|Bắt buộc khi Removed",
 "ModeratedBy|INT|N,F=iam.Users|Admin gỡ tin"],
 cons=[("CK","ListingType <> 'Sell' OR Price IS NOT NULL"),
       ("CK","ListingType <> 'Exchange' OR ExchangeWanted IS NOT NULL"),
       ("CK","ListingType = 'Wanted' OR Condition IS NOT NULL"),
       ("CK","Status <> 'Removed' OR ModerationReason IS NOT NULL"),
       ("UQ","UQ_Listings_ListingId_SellerId (ListingId, SellerId); đích của FK ghép từ MarketTransactions"),
       ("FT","Full-Text Index (Title, Description) tạo có điều kiện IsFullTextInstalled")])

T("mkt","ListingImages","M7","Entity","F5","Ảnh của tin đăng (tối đa 8, đúng 1 ảnh chính)","C",[
 "ImageId|INT IDENTITY|P|Khóa chính",
 "ListingId|INT|F=mkt.Listings|Tin đăng",
 "ImageUrl|NVARCHAR(1000)||URL trên Blob Storage",
 "SortOrder|TINYINT|D=0|Thứ tự hiển thị",
 "IsPrimary|BIT|D=0|Ảnh chính"],
 cons=[("UQ","Filtered unique index UX_ListingImages_Primary (ListingId) WHERE IsPrimary = 1")])

T("mkt","MarketTransactions","M7","Entity","F5","Giao dịch mua bán/trao đổi và đánh giá người bán","CU",[
 "TransactionId|INT IDENTITY|P|Khóa chính",
 "TransactionCode|NVARCHAR(20)|U|SEQUENCE mkt.seq_TransactionCode, dạng MK-2026-000001",
 "ListingId|INT||Thành phần FK ghép tới Listings",
 "SellerId|INT||Sao từ tin đăng; thành phần FK ghép",
 "BuyerId|INT|F=iam.Users|Người mua",
 "Quantity|INT||CK > 0",
 "UnitPrice|DECIMAL(18,0)|D=0|CK >= 0; giá chốt lúc đặt, 0 nếu trao đổi",
 "TotalAmount|DECIMAL(18,0)|G|Cột tính: Quantity * UnitPrice, PERSISTED",
 "PlatformFee|DECIMAL(18,0)|D=0|CK >= 0; người bán chịu, chốt lúc đặt",
 "Status|NVARCHAR(9)|D='Pending'|CK IN ('Pending','Confirmed','Shipped','Completed','Cancelled','Disputed')",
 "Note|NVARCHAR(500)|N|Ghi chú",
 "ConfirmedAt|DATETIME2(0)|N|Người bán xác nhận",
 "ShippedAt|DATETIME2(0)|N|Gửi hàng",
 "CompletedAt|DATETIME2(0)|N|Hoàn tất",
 "CancelReason|NVARCHAR(255)|N|Bắt buộc khi Cancelled",
 "DisputeReason|NVARCHAR(500)|N|Bắt buộc khi Disputed",
 "DisputedAt|DATETIME2(0)|N|Thời điểm khiếu nại",
 "DisputeResolution|NVARCHAR(500)|N|Admin giải quyết",
 "ResolvedBy|INT|N,F=iam.Users|Admin giải quyết",
 "ResolvedAt|DATETIME2(0)|N|Thời điểm giải quyết",
 "BuyerRating|TINYINT|N|CK BETWEEN 1 AND 5; đánh giá người bán",
 "BuyerComment|NVARCHAR(500)|N|Nhận xét người bán",
 "RatedAt|DATETIME2(0)|N|Thời điểm đánh giá"],
 cons=[("CK","BuyerId <> SellerId"),
       ("CK","PlatformFee <= TotalAmount"),
       ("CK","Status <> 'Cancelled' OR CancelReason IS NOT NULL"),
       ("CK","Status <> 'Disputed' OR DisputeReason IS NOT NULL"),
       ("CK","BuyerRating IS NULL OR Status = 'Completed'")],
 fks=[("mkt.MarketTransactions",["ListingId","SellerId"],"mkt.Listings",["ListingId","SellerId"],"FK ghép: bảo đảm người bán khớp với tin đăng")])

T("mkt","Messages","M7","Entity","F5","Tin nhắn giữa người mua và người bán về một tin đăng","",[
 "MessageId|INT IDENTITY|P|Khóa chính",
 "ListingId|INT|F=mkt.Listings|Tin đăng",
 "SenderId|INT|F=iam.Users|Người gửi",
 "ReceiverId|INT|F=iam.Users|Người nhận",
 "Body|NVARCHAR(1000)||CK LEN(Body) > 0",
 "SentAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm gửi",
 "ReadAt|DATETIME2(0)|N|Thời điểm đọc"],
 cons=[("CK","SenderId <> ReceiverId")])

# ======================= M8 com =======================
T("com","Articles","M8","Entity","F6","Bài viết: hướng dẫn, review, kỹ thuật, kinh nghiệm, câu hỏi","A",[
 "ArticleId|INT IDENTITY|P|Khóa chính",
 "AuthorId|INT|F=iam.Users|Tác giả",
 "ArticleType|NVARCHAR(10)||CK IN ('Tutorial','Review','Technical','LabGuide','Experience','Question')",
 "Title|NVARCHAR(200)||Tiêu đề",
 "Slug|NVARCHAR(220)||Đường dẫn; unique cho bài chưa xóa",
 "Summary|NVARCHAR(500)|N|Tóm tắt",
 "Body|NVARCHAR(MAX)||Nội dung",
 "Tags|NVARCHAR(MAX)|N|CK ISJSON = 1; mảng JSON",
 "RelatedLabId|INT|N,F=lab.FilmLabs|Lab liên quan",
 "RelatedStockId|INT|N,F=lab.FilmStocks|Loại phim liên quan",
 "Status|NVARCHAR(9)|D='Draft'|CK IN ('Draft','Published','Hidden')",
 "PublishedAt|DATETIME2(0)|N|Thời điểm xuất bản lần đầu",
 "ModerationReason|NVARCHAR(255)|N|Bắt buộc khi Hidden",
 "ModeratedBy|INT|N,F=iam.Users|Admin ẩn bài"],
 cons=[("CK","Status = 'Draft' OR PublishedAt IS NOT NULL"),
       ("CK","Status <> 'Hidden' OR ModerationReason IS NOT NULL"),
       ("UQ","Filtered unique index UX_Articles_Slug (Slug) WHERE IsDeleted = 0"),
       ("FT","Full-Text Index (Title, Summary, Body) tạo có điều kiện IsFullTextInstalled")])

T("com","ArticleComments","M8","Entity","F6","Bình luận và trả lời (1 cấp) của bài viết","A",[
 "CommentId|INT IDENTITY|P|Khóa chính",
 "ArticleId|INT|F=com.Articles|Bài viết",
 "UserId|INT|F=iam.Users|Người bình luận",
 "ParentCommentId|INT|N,F=self|Bình luận cha, chỉ 1 cấp",
 "Body|NVARCHAR(1000)||Nội dung",
 "IsAccepted|BIT|D=0|Câu trả lời được chọn (chỉ bài Question)",
 "IsVisible|BIT|D=1|Hiển thị"],
 cons=[("UQ","Filtered unique index UX_Comments_Accepted (ArticleId) WHERE IsAccepted = 1")])

T("com","Events","M8","Entity","F6","Workshop và photowalk","A",[
 "EventId|INT IDENTITY|P|Khóa chính",
 "OrganizerId|INT|F=iam.Users|Người tổ chức (Expert)",
 "HostLabId|INT|N,F=lab.FilmLabs|Lab đăng cai",
 "EventType|NVARCHAR(9)||CK IN ('Workshop','Photowalk')",
 "Title|NVARCHAR(200)||Tiêu đề",
 "Description|NVARCHAR(2000)|N|Mô tả",
 "StartAt|DATETIME2(0)||Bắt đầu",
 "EndAt|DATETIME2(0)||Kết thúc",
 "RegistrationDeadline|DATETIME2(0)|N|Hạn đăng ký",
 "VenueName|NVARCHAR(200)||Địa điểm",
 "AddressLine|NVARCHAR(255)||Địa chỉ",
 "City|NVARCHAR(100)||Thành phố",
 "Location|geography|N|Tọa độ",
 "Capacity|SMALLINT||CK > 0; sức chứa",
 "Fee|DECIMAL(18,0)|D=0|CK >= 0",
 "Status|NVARCHAR(9)|D='Draft'|CK IN ('Draft','Open','Closed','Cancelled','Completed')"],
 cons=[("CK","EndAt > StartAt"),
       ("CK","RegistrationDeadline IS NULL OR RegistrationDeadline <= StartAt")])

T("com","EventRegistrations","M8","Junction","F6","Đăng ký sự kiện, có hàng chờ (N-N Events-Users)","CU",[
 "EventId|INT|P,F=com.Events|Khóa chính (1/2)",
 "UserId|INT|P,F=iam.Users|Khóa chính (2/2)",
 "Status|NVARCHAR(10)|D='Registered'|CK IN ('Registered','Waitlisted','Cancelled','Attended')",
 "IsPaid|BIT|D=0|Chỉ đánh dấu, không qua cổng thanh toán",
 "CancelledAt|DATETIME2(0)|N|Bắt buộc khi Cancelled"],
 cons=[("CK","Status <> 'Cancelled' OR CancelledAt IS NOT NULL")])

# ======================= M9 ai =======================
T("ai","UserPreferences","M9","Entity","AI","Sở thích dùng cho gợi ý cá nhân hóa (1-1 với Users)","CU",[
 "UserId|INT|P,F=iam.Users|Khóa chính, đồng thời FK (1-1)",
 "PreferredFormatId|INT|N,F=lab.FilmFormats|Định dạng phim ưa thích",
 "PreferredFilmType|NVARCHAR(15)|N|CK IN ('ColorNegative','BlackWhite','ColorSlide')",
 "PreferredCity|NVARCHAR(100)|N|Thành phố",
 "MaxDistanceKm|DECIMAL(6,2)|N|CK > 0",
 "MaxBudgetPerRoll|DECIMAL(18,0)|N|CK >= 0",
 "PrioritizeQuality|BIT|D=0|Ưu tiên chất lượng",
 "PrioritizeSpeed|BIT|D=0|Ưu tiên tốc độ",
 "Source|NVARCHAR(8)|D='UserSet'|CK IN ('UserSet','Inferred')",
 "ExtraJson|NVARCHAR(MAX)|N|CK ISJSON = 1"])

T("ai","AIChatLogs","M9","Log","AI","Nhật ký hội thoại với AI Assistant (chỉ thêm)","",[
 "ChatLogId|BIGINT IDENTITY|P|Khóa chính",
 "SessionId|UNIQUEIDENTIFIER||Gom một cuộc hội thoại",
 "UserId|INT|F=iam.Users|Người dùng",
 "Role|NVARCHAR(9)||CK IN ('User','Assistant','System')",
 "Message|NVARCHAR(MAX)||Nội dung",
 "ModelName|NVARCHAR(50)|N|Bắt buộc khi Assistant",
 "PromptTokens|INT|N|CK >= 0",
 "CompletionTokens|INT|N|CK >= 0",
 "LatencyMs|INT|N|CK >= 0",
 "SourcesJson|NVARCHAR(MAX)|N|CK ISJSON = 1; KnowledgeDocId mà RAG đã trích",
 "Feedback|NVARCHAR(10)|N|CK IN ('Helpful','NotHelpful'); chỉ cho dòng Assistant",
 "CreatedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm"],
 cons=[("CK","Role <> 'Assistant' OR ModelName IS NOT NULL"),
       ("CK","Feedback IS NULL OR Role = 'Assistant'")])

T("ai","RecommendationLogs","M9","Log","AI","Nhật ký gợi ý và phản ứng người dùng (dữ liệu đánh giá mô hình)","",[
 "RecLogId|BIGINT IDENTITY|P|Khóa chính",
 "UserId|INT|F=iam.Users|Người được gợi ý",
 "RecommendationType|NVARCHAR(9)||CK IN ('Lab','FilmStock','Article','Event','Listing')",
 "ItemId|INT||ID mục được gợi ý; KHÔNG có FK có chủ ý (trỏ nhiều bảng, log phải trụ qua khi mục bị xóa)",
 "Rank|TINYINT||CK >= 1",
 "Score|DECIMAL(6,4)||CK BETWEEN 0 AND 1",
 "ModelVersion|NVARCHAR(30)||Ví dụ tsql-v1",
 "ContextJson|NVARCHAR(MAX)|N|CK ISJSON = 1; bộ lọc lúc gợi ý",
 "Action|NVARCHAR(9)|N|CK IN ('Clicked','Ordered','Dismissed')",
 "ActedAt|DATETIME2(0)|N|Thời điểm phản ứng",
 "CreatedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm gợi ý"],
 cons=[("CK","Action IS NULL OR ActedAt IS NOT NULL")])

T("ai","KnowledgeDocs","M9","Entity","AI","Đoạn tri thức (chunk) cho Retrieval-Augmented Generation","A",[
 "KnowledgeDocId|INT IDENTITY|P|Khóa chính",
 "SourceArticleId|INT|N,F=com.Articles|Bài gốc",
 "ChunkIndex|INT|D=0|CK >= 0; thứ tự đoạn trong bài",
 "Title|NVARCHAR(200)||Tiêu đề",
 "Topic|NVARCHAR(50)|N|Chủ đề",
 "Content|NVARCHAR(4000)||CK LEN(Content) > 0; một chunk",
 "ContentHash|CHAR(64)|N|Phát hiện nội dung đổi",
 "EmbeddingJson|NVARCHAR(MAX)|N|CK ISJSON = 1; vector dạng mảng JSON (placeholder, SQL Server 2022 chưa có kiểu vector)",
 "EmbeddingModel|NVARCHAR(50)|N|Model tạo embedding",
 "ContributedBy|INT|F=iam.Users|Expert đóng góp",
 "IsApproved|BIT|D=0|Chỉ chunk đã duyệt mới dùng cho AI",
 "ApprovedBy|INT|N,F=iam.Users|Admin duyệt",
 "ApprovedAt|DATETIME2(0)|N|Thời điểm duyệt"],
 cons=[("CK","IsApproved = 0 OR (ApprovedBy IS NOT NULL AND ApprovedAt IS NOT NULL)"),
       ("UQ","Filtered unique index UX_Knowledge_Chunk (SourceArticleId, ChunkIndex) WHERE SourceArticleId IS NOT NULL AND IsDeleted = 0"),
       ("FT","Full-Text Index (Title, Content) tạo có điều kiện IsFullTextInstalled")])

# ======================= M10 audit =======================
T("audit","AuditLogs","M10","Log","Admin","Nhật ký thay đổi dữ liệu (chỉ thêm, ghi qua audit.sp_WriteAudit)","",[
 "AuditLogId|BIGINT IDENTITY|P|Khóa chính",
 "TableSchema|NVARCHAR(128)||Schema của bảng bị đổi",
 "TableName|NVARCHAR(128)||Tên bảng bị đổi",
 "PrimaryKeyValue|NVARCHAR(100)||Giá trị khóa của dòng bị đổi",
 "Action|NVARCHAR(6)||CK IN ('INSERT','UPDATE','DELETE')",
 "ChangedBy|INT|N|Từ SESSION_CONTEXT; KHÔNG có FK có chủ ý (nhật ký độc lập)",
 "OldValues|NVARCHAR(MAX)|N|CK ISJSON = 1",
 "NewValues|NVARCHAR(MAX)|N|CK ISJSON = 1",
 "AppName|NVARCHAR(128)|N,D=APP_NAME()|Ứng dụng gây ra thay đổi",
 "HostName|NVARCHAR(128)|N,D=HOST_NAME()|Máy gây ra thay đổi",
 "ChangedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm"],
 cons=[("CK","(Action = 'INSERT' AND OldValues IS NULL) OR (Action = 'DELETE' AND NewValues IS NULL) OR Action = 'UPDATE'")])

# ------------------------------------------------------------------
# Cột chuẩn theo audit
# ------------------------------------------------------------------
STD = {
 "CreatedAt": "CreatedAt|DATETIME2(0)|D=SYSUTCDATETIME()|Thời điểm tạo (cột chuẩn)",
 "UpdatedAt": "UpdatedAt|DATETIME2(0)|N|Thời điểm sửa gần nhất (cột chuẩn)",
 "IsDeleted": "IsDeleted|BIT|D=0|Xóa mềm (cột chuẩn)",
}
AUDIT_COLS = {"A": ["CreatedAt","UpdatedAt","IsDeleted"], "CU": ["CreatedAt","UpdatedAt"], "C": ["CreatedAt"], "": []}

MODULE_NAMES = {
 "iam":"M1 Identity & Access", "lab":"M2 Lab & Catalog", "ord":"M3 Order + M6 Review/Complaint",
 "dlv":"M4 Delivery", "arc":"M5 Digital Archive", "mkt":"M7 Marketplace",
 "com":"M8 Community", "ai":"M9 AI Support", "audit":"M10 System/Audit"}
MODULE_ORDER = ["iam","lab","ord","dlv","arc","mkt","com","ai","audit"]
