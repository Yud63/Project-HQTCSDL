# -*- coding: utf-8 -*-
"""Sinh 04_seed/sample/*.sql cho 9 module (iam do gen_seed.py). Chạy: python tools/gen_seed_sample.py
Mọi khóa tra bằng khóa tự nhiên (Email, LabName, OrderCode, Slug...). Tổng tiền tính ở đây để luôn khớp CHECK."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sql as G
from gen_seed import ord_sample, HDR

class R(str): pass
def lit(v):
    if v is None: return "NULL"
    if isinstance(v, R): return str(v)
    if isinstance(v, (int, float)): return str(v)
    return "N'" + v.replace("'", "''") + "'"
def V(rows):
    for i in range(len(rows[0])):
        if all(r[i] is None for r in rows): raise ValueError("Cột %d toàn NULL trong VALUES (sẽ bị suy ra kiểu int)" % i)
    return ",\n    ".join("(" + ", ".join(lit(x) for x in r) + ")" for r in rows)
def J(o): return json.dumps(o, ensure_ascii=False)
ADMIN = "(SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn')"
FEE = 25000      # D-06
COMM = 0.10      # D-01
MFEE = 0.05      # D-12

# ======================= LAB =======================
LABS = [  # owner, name, desc, addr, ward, district, city, lat, lng, phone, email, hours, tech, cap, status
 ("lab.saigon@filmlab.vn","Sài Gòn Film Lab","Lab tráng và scan phim 35mm, 120 tại trung tâm Quận 1. Nhận push/pull process.",
  "101 Pasteur","Bến Nghé","Quận 1","TP. Hồ Chí Minh",10.7790,106.6990,"0900000002","hello@saigonfilmlab.vn",
  J({"mon-sat":"09:00-18:00","sun":"closed"}), J(["push","pull","cross-process"]), 60, "Approved"),
 ("lab.hanoi@filmlab.vn","Hà Nội Analog Lab","Lab chuyên scan chất lượng cao và tráng phim slide E-6 tại phố cổ.",
  "15 Phố Huế","Ngô Thị Nhậm","Hai Bà Trưng","Hà Nội",21.0150,105.8490,"0900000003","contact@hanoianalog.vn",
  J({"mon-fri":"08:30-17:30","sat":"09:00-12:00","sun":"closed"}), J(["E-6","scan-ultra"]), 40, "Approved"),
 ("lab.hanoi@filmlab.vn","Đà Nẵng Retro Lab","Lab mới đăng ký, đang chờ Admin duyệt.",
  "88 Bạch Đằng","Hải Châu 1","Hải Châu","Đà Nẵng",16.0680,108.2240,"0900000003",None,
  None, None, 30, "Pending")]
SERV = {  # lab -> (package, svc, fmt, process, price, unit, scanq, days, desc)
 "Sài Gòn Film Lab": [
  ("Tráng C-41 35mm","DEV","35mm","C-41",60000,"Roll",None,2,"Tráng phim màu C-41 khổ 35mm"),
  ("Tráng B&W 35mm","DEV","35mm","BW",70000,"Roll",None,3,"Tráng phim đen trắng khổ 35mm"),
  ("Tráng C-41 120","DEV","120","C-41",80000,"Roll",None,2,"Tráng phim màu C-41 khổ 120"),
  ("Scan Basic 35mm","SCAN","35mm","ANY",80000,"Roll","Basic",2,"Scan 2000px, file JPEG"),
  ("Scan High 35mm","SCAN","35mm","ANY",150000,"Roll","High",3,"Scan 4000px, JPEG + TIFF")],
 "Hà Nội Analog Lab": [
  ("Tráng C-41 35mm","DEV","35mm","C-41",55000,"Roll",None,3,"Tráng phim màu C-41 khổ 35mm"),
  ("Tráng E-6 35mm","DEV","35mm","E-6",150000,"Roll",None,5,"Tráng phim slide E-6"),
  ("Scan Ultra 35mm","SCAN","35mm","ANY",200000,"Roll","Ultra",5,"Scan độ phân giải cao nhất, hiệu chỉnh màu thủ công"),
  ("In ảnh 4x6","PRINT","35mm","ANY",5000,"Frame",None,3,"In ảnh 4x6 inch trên giấy lustre")]}
PRICE = {(l, s[0]): s[4] for l, ss in SERV.items() for s in ss}

def lab_sql():
    o = HDR + "-- Film Lab mẫu (2 lab đã duyệt, 1 lab chờ duyệt để demo sp_ApproveLab)\n"
    o += """INSERT INTO lab.FilmLabs (OwnerUserId, LabName, Description, AddressLine, Ward, District, City, Location, Phone, Email, OpenHoursJson, SpecialTechniques, DailyCapacityRolls, ApprovalStatus)
SELECT u.UserId, v.LabName, v.Descr, v.Addr, v.Ward, v.District, v.City, geography::Point(v.Lat, v.Lng, 4326), v.Phone, v.Email, v.Hours, v.Tech, v.Cap, v.Status
FROM (VALUES
    %s
) v(OwnerEmail, LabName, Descr, Addr, Ward, District, City, Lat, Lng, Phone, Email, Hours, Tech, Cap, Status)
JOIN iam.Users u ON u.Email = v.OwnerEmail;
GO

-- Lịch sử duyệt (lab Pending chưa có quyết định)
INSERT INTO lab.LabApprovals (LabId, ReviewedBy, Decision)
SELECT l.LabId, a.UserId, N'Approved'
FROM lab.FilmLabs l CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a
WHERE l.ApprovalStatus = N'Approved';
GO

-- Gói dịch vụ và giá (LabServices là temporal table: mọi thay đổi giá về sau tự lưu lịch sử)
INSERT INTO lab.LabServices (LabId, ServiceTypeId, FormatId, ProcessCode, PackageName, Description, UnitPrice, PriceUnit, ScanQuality, TurnaroundDays)
SELECT l.LabId, st.ServiceTypeId, ff.FormatId, v.Process, v.Pkg, v.Descr, v.Price, v.Unit, v.ScanQ, v.Days
FROM (VALUES
    %s
) v(LabName, ServiceCode, FormatCode, Process, Pkg, Descr, Price, Unit, ScanQ, Days)
JOIN lab.FilmLabs l ON l.LabName = v.LabName
JOIN lab.ServiceTypes st ON st.ServiceCode = v.ServiceCode
JOIN lab.FilmFormats ff ON ff.FormatCode = v.FormatCode;
GO
""" % (V([list(x) for x in LABS]),
       V([[lab, s[1], s[2], s[3], s[0], s[8], s[4], s[5], s[6], s[7]] for lab, ss in SERV.items() for s in ss]))
    return o

# ======================= ORD =======================
L1, L2 = "Sài Gòn Film Lab", "Hà Nội Analog Lab"
ORDERS = [ # code, cust, lab, stage, fulfil, ret, pickupLbl, retLbl, pay, daysAgo, completedDaysAgo, legs, note, items
 ("FL-2026-000001","an.nguyen@example.com",L1,12,"DropOff","SelfCollect",None,None,"Paid",20,12,[],"Phim đi Đà Lạt tháng trước",
   [("Tráng C-41 35mm",2,"Kodak","Portra 400",None),("Scan High 35mm",2,"Kodak","Portra 400",None)]),
 ("FL-2026-000002","binh.tran@example.com",L1,5,"DropOff","SelfCollect",None,None,"Unpaid",6,None,[],None,
   [("Tráng B&W 35mm",1,"Kodak","Tri-X 400","Đẩy +1 stop")]),
 ("FL-2026-000003","chi.le@example.com",L2,11,"DropOff","Delivery",None,"Nhà","Paid",9,None,[("Return","Assigned")],"Giao trả phim tận nhà",
   [("Tráng C-41 35mm",1,"Fujifilm","Superia X-tra 400",None),("Scan Ultra 35mm",1,"Fujifilm","Superia X-tra 400",None)]),
 ("FL-2026-000004","an.nguyen@example.com",L1,1,"Pickup","Delivery","Nhà","Nhà","Unpaid",1,None,[("Pickup","Requested"),("Return","Requested")],None,
   [("Tráng C-41 120",1,"Kodak","Portra 160",None)]),
 ("FL-2026-000005","binh.tran@example.com",L1,13,"DropOff","SelfCollect",None,None,"Unpaid",15,None,[],None,
   [("Scan Basic 35mm",1,None,None,None)]),
 ("FL-2026-000006","binh.tran@example.com",L1,12,"DropOff","Delivery",None,"Nhà","Paid",18,9,[("Return","Delivered")],None,
   [("Tráng C-41 35mm",1,"Kodak","Ultramax 400",None),("Scan Basic 35mm",1,"Kodak","Ultramax 400",None)])]
PATH = {12: list(range(1, 13)), 5: [1,2,3,4,5], 11: list(range(1, 12)), 1: [1], 13: [1, 13]}
OWNER = {L1: "lab.saigon@filmlab.vn", L2: "lab.hanoi@filmlab.vn"}

def tot(o):
    sub = sum(PRICE[(o[2], it[0])] * it[1] for it in o[13])
    fee = FEE * len(o[11]); plat = round(sub * COMM)
    return sub, fee, plat, sub + fee

def ord_sql():
    rows = []
    for o in ORDERS:
        sub, fee, plat, total = tot(o)
        rows.append([o[0], o[1], o[2], o[3], o[4], o[5], o[6], o[7], sub, fee, plat, total, o[8], o[12],
                     3 if o[3] in (1, 2, 4) else None, o[9], o[10], "Khách đổi ý, không cần xử lý nữa" if o[3] == 13 else None])
    items = [[o[0], it[0], it[2], it[3], it[1], it[4]] for o in ORDERS for it in o[13]]
    logs = []
    for o in ORDERS:
        p = PATH[o[3]]
        for i, st in enumerate(p):
            logs.append([o[0], None if i == 0 else p[i - 1], st, o[1] if i == 0 else OWNER[o[2]], "Khởi tạo đơn" if i == 0 else None, i])
    s = ord_sample + "\n-- Đơn hàng mẫu: nhiều giai đoạn, tổng tiền tính theo D-01 (hoa hồng 10%) và D-06 (25.000đ/chặng)\n"
    s += """INSERT INTO ord.Orders (OrderCode, CustomerId, LabId, StageId, FulfillmentMethod, ReturnMethod, PickupAddressId, ReturnAddressId,
                        Subtotal, DeliveryFee, PlatformFee, TotalAmount, PaymentStatus, CustomerNote, EstimatedReadyDate, CompletedAt, CancelReason, CreatedAt)
SELECT v.OrderCode, u.UserId, l.LabId, v.StageId, v.Fulfil, v.Ret, pa.AddressId, ra.AddressId,
       v.Subtotal, v.DeliveryFee, v.PlatformFee, v.Total, v.PayStatus, v.Note,
       CASE WHEN v.Est IS NOT NULL THEN CAST(DATEADD(DAY, v.Est, SYSUTCDATETIME()) AS DATE) END,
       CASE WHEN v.CompD IS NOT NULL THEN DATEADD(DAY, -v.CompD, SYSUTCDATETIME()) END,
       v.CancelReason, DATEADD(DAY, -v.D, SYSUTCDATETIME())
FROM (VALUES
    %s
) v(OrderCode, Email, LabName, StageId, Fulfil, Ret, PickupLbl, ReturnLbl, Subtotal, DeliveryFee, PlatformFee, Total, PayStatus, Note, Est, D, CompD, CancelReason)
JOIN iam.Users u ON u.Email = v.Email
JOIN lab.FilmLabs l ON l.LabName = v.LabName
LEFT JOIN iam.Addresses pa ON pa.UserId = u.UserId AND pa.Label = v.PickupLbl
LEFT JOIN iam.Addresses ra ON ra.UserId = u.UserId AND ra.Label = v.ReturnLbl;
GO

-- Chi tiết đơn (giá chốt từ LabServices lúc đặt)
INSERT INTO ord.OrderItems (OrderId, LabServiceId, FilmStockId, Quantity, UnitPriceSnapshot, ProcessingNote)
SELECT o.OrderId, ls.LabServiceId, fs.StockId, v.Qty, ls.UnitPrice, v.Note
FROM (VALUES
    %s
) v(OrderCode, Pkg, Brand, Stock, Qty, Note)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN lab.LabServices ls ON ls.LabId = o.LabId AND ls.PackageName = v.Pkg
LEFT JOIN lab.FilmStocks fs ON fs.Brand = v.Brand AND fs.StockName = v.Stock;
GO

-- Nhật ký giai đoạn (trigger ghi tự động sẽ có ở Đợt 6; dữ liệu mẫu ghi tay cho khớp)
INSERT INTO ord.OrderStageLog (OrderId, FromStageId, ToStageId, ChangedBy, Note, ChangedAt)
SELECT o.OrderId, v.FromStage, v.ToStage, u.UserId, v.Note, DATEADD(HOUR, v.H, o.CreatedAt)
FROM (VALUES
    %s
) v(OrderCode, FromStage, ToStage, ByEmail, Note, H)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN iam.Users u ON u.Email = v.ByEmail;
GO

-- Thanh toán: số tiền lấy đúng Orders.TotalAmount; đơn 000002 có 1 lần thất bại
INSERT INTO ord.Payments (OrderId, Method, Provider, ProviderTxnId, Amount, Status, PaidAt, FailureReason)
SELECT o.OrderId, v.Method, v.Provider, v.Txn, o.TotalAmount, v.Status,
       CASE WHEN v.Status = N'Succeeded' THEN DATEADD(HOUR, 2, o.CreatedAt) END, v.Reason
FROM (VALUES
    %s
) v(OrderCode, Method, Provider, Txn, Status, Reason)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode;
GO

-- Kiểm tra nhanh: tổng tiền khớp chi tiết đơn (THROW nếu seed lệch)
IF EXISTS (SELECT 1 FROM ord.Orders o
           WHERE o.Subtotal <> (SELECT SUM(LineTotal) FROM ord.OrderItems i WHERE i.OrderId = o.OrderId))
    THROW 50399, N'Seed ord: Subtotal không khớp tổng LineTotal', 1;
GO
""" % (V(rows), V(items), V(logs), V([
        ["FL-2026-000001","EWallet","MoMo","MOMO-20260001","Succeeded",None],
        ["FL-2026-000002","Card","VNPay",None,"Failed","Thẻ bị từ chối"],
        ["FL-2026-000003","Card","VNPay","VNP-20260003","Succeeded",None],
        ["FL-2026-000006","BankTransfer","Vietcombank","VCB-20260006","Succeeded",None]]))
    return s

# ======================= ORD_FEEDBACK =======================
def fb_sql():
    s = HDR + """-- Đánh giá (đơn Completed, trong 30 ngày). AvgRating/ReviewCount sẽ do trigger cập nhật ở Đợt 6; ở đây tính tay cho khớp.
INSERT INTO ord.Reviews (OrderId, CustomerId, LabId, RatingOverall, RatingScanQuality, RatingSpeed, Comment, LabReply, LabRepliedAt, CreatedAt)
SELECT o.OrderId, o.CustomerId, o.LabId, v.Overall, v.ScanQ, v.Speed, v.Comment, v.Reply,
       CASE WHEN v.Reply IS NOT NULL THEN DATEADD(DAY, 2, o.CompletedAt) END, DATEADD(DAY, 1, o.CompletedAt)
FROM (VALUES
    %s
) v(OrderCode, Overall, ScanQ, Speed, Comment, Reply)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode;
GO

UPDATE l SET AvgRating = r.AvgR, ReviewCount = r.Cnt
FROM lab.FilmLabs l
JOIN (SELECT LabId, CAST(AVG(CAST(RatingOverall AS DECIMAL(5,2))) AS DECIMAL(3,2)) AS AvgR, COUNT(*) AS Cnt
      FROM ord.Reviews WHERE IsVisible = 1 AND IsDeleted = 0 GROUP BY LabId) r ON r.LabId = l.LabId;
GO

-- Khiếu nại: 1 Open, 1 InReview, 1 Resolved (hoàn một phần phí)
INSERT INTO ord.Complaints (OrderId, CustomerId, LabId, Category, Title, Description, Status, LabResponse, AssignedAdminId, ResolutionType, Resolution, RefundAmount, ResolvedAt)
SELECT o.OrderId, o.CustomerId, o.LabId, v.Category, v.Title, v.Descr, v.Status, v.LabResp,
       CASE WHEN v.Status = N'Open' THEN NULL ELSE a.UserId END,
       v.ResType, v.Resolution, v.Refund, CASE WHEN v.Status = N'Resolved' THEN DATEADD(DAY, -1, SYSUTCDATETIME()) END
FROM (VALUES
    %s
) v(OrderCode, Category, Title, Descr, Status, LabResp, ResType, Resolution, Refund)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO
""" % (V([["FL-2026-000001",5,5,4,"Màu Portra 400 rất đẹp, scan sắc nét. Nhân viên nhiệt tình.","Cảm ơn bạn đã tin tưởng, hẹn gặp lại ở cuộn tiếp theo!"],
          ["FL-2026-000006",4,3,5,"Tráng nhanh, giao tận nhà. Vài khung scan hơi tối.",None]]),
       V([["FL-2026-000003","Delay","Giao trả phim chậm hơn dự kiến","Hẹn giao trước 2 ngày nhưng đến nay chưa nhận được phim.","Open",None,None,None,None],
          ["FL-2026-000002","Delay","Thời gian tráng lâu hơn hẹn","Đơn đã quá thời gian dự kiến nhưng vẫn ở bước tráng.","InReview","Lab đang bù ca xử lý, sẽ hoàn tất trong hôm nay.",None,None,None],
          ["FL-2026-000006","ScanQuality","Một số khung scan bị tối","Khung 5 và 6 scan tối hơn so với mẫu.","Resolved","Lab đồng ý scan lại hoặc hoàn một phần phí.","Refund","Hoàn 20.000đ phí scan cho các khung lỗi.",20000]]))
    return s

# ======================= DLV =======================
def dlv_sql():
    legs = []
    for o in ORDERS:
        for (d, st) in o[11]:
            partner = {"Assigned": "Ahamove", "Delivered": "Võ Văn Tài", "Requested": None}[st]
            legs.append([o[0], d, "Nhà", partner, st, FEE, {"Assigned": 4.80, "Delivered": 5.40}.get(st, 3.10),
                         "AHM-778812" if st == "Assigned" else None])
    logs = []
    for l in legs:
        path = {"Requested": ["Requested"], "Assigned": ["Requested", "Assigned"], "Delivered": ["Requested", "Assigned", "PickedUp", "Delivered"]}[l[4]]
        for i, st in enumerate(path):
            logs.append([l[0], l[1], None if i == 0 else path[i - 1], st, i])
    return HDR + """-- Chặng giao nhận mẫu: 1 đã giao (đơn 000006), 1 đã phân công (000003), 2 đang chờ phân công (000004)
INSERT INTO dlv.DeliveryRequests (OrderId, Direction, CustomerAddressId, DeliveryPartnerId, Status, Fee, DistanceKm, ScheduledAt, PickedUpAt, DeliveredAt, ExternalTrackingCode, CreatedAt)
SELECT o.OrderId, v.Direction, a.AddressId, p.DeliveryPartnerId, v.Status, v.Fee, v.Dist,
       CASE WHEN v.Status = N'Delivered' THEN DATEADD(DAY, -1, o.CompletedAt) WHEN v.Status = N'Assigned' THEN DATEADD(DAY, 1, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Delivered' THEN DATEADD(HOUR, -5, o.CompletedAt) END,
       CASE WHEN v.Status = N'Delivered' THEN o.CompletedAt END,
       v.Track, DATEADD(HOUR, 3, o.CreatedAt)
FROM (VALUES
    %s
) v(OrderCode, Direction, AddrLbl, Partner, Status, Fee, Dist, Track)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN iam.Addresses a ON a.UserId = o.CustomerId AND a.Label = v.AddrLbl
LEFT JOIN iam.DeliveryPartners p ON p.PartnerName = v.Partner;
GO

-- Nhật ký trạng thái chặng giao
INSERT INTO dlv.DeliveryStatusLog (DeliveryRequestId, FromStatus, ToStatus, ChangedBy, ChangedAt)
SELECT d.DeliveryRequestId, v.FromSt, v.ToSt, o.CustomerId, DATEADD(HOUR, v.H, d.CreatedAt)
FROM (VALUES
    %s
) v(OrderCode, Direction, FromSt, ToSt, H)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN dlv.DeliveryRequests d ON d.OrderId = o.OrderId AND d.Direction = v.Direction;
GO

-- Kiểm tra: DeliveryFee của đơn = tổng phí các chặng (THROW nếu seed lệch)
IF EXISTS (SELECT 1 FROM ord.Orders o
           WHERE o.DeliveryFee <> ISNULL((SELECT SUM(Fee) FROM dlv.DeliveryRequests d WHERE d.OrderId = o.OrderId), 0))
    THROW 50499, N'Seed dlv: Orders.DeliveryFee không khớp tổng phí các chặng', 1;
GO
""" % (V(legs), V(logs))

# ======================= ARC =======================
def arc_sql():
    files, meta = [], []
    spec = [("FL-2026-000001", 4, "Scan High 35mm", "Passed", 92.5, "Kodak", "Portra 400"),
            ("FL-2026-000006", 2, "Scan Basic 35mm", "Warning", 71.0, "Kodak", "Ultramax 400"),
            ("FL-2026-000003", 2, "Scan Ultra 35mm", "NotChecked", None, "Fujifilm", "Superia X-tra 400")]
    for code, n, pkg, qs, sc, br, sk in spec:
        for i in range(1, n + 1):
            fn = "%s_%03d.jpg" % (code, i)
            files.append([code, pkg, i, fn, "https://storage.filmlab.vn/scans/%s/%03d.jpg" % (code, i), 3500000 + i * 1000, 3000, 2000, sc, qs])
            if qs != "NotChecked":
                meta.append([code, fn, br, sk, "Canon AE-1 Program", "FD 50mm f/1.8", 40 + i, 400 if "400" in sk else 160,
                             "C-41", "Noritsu HS-1800", 4000, J({"push": "+0"})])
    notifs = [["an.nguyen@example.com","ScanReady","Scan phim đã sẵn sàng","Đơn FL-2026-000001 đã có 4 ảnh scan.","FL-2026-000001",1],
              ["an.nguyen@example.com","OrderStage","Đơn đã hoàn tất","Cảm ơn bạn đã sử dụng dịch vụ.","FL-2026-000001",0],
              ["an.nguyen@example.com","Delivery","Đã tạo yêu cầu lấy phim","Đơn FL-2026-000004 đang chờ phân công shipper.","FL-2026-000004",0],
              ["binh.tran@example.com","OrderStage","Đơn đang tráng phim","Đơn FL-2026-000002 đang ở bước tráng hóa chất.","FL-2026-000002",0],
              ["chi.le@example.com","Delivery","Đã phân công giao phim","Ahamove sẽ giao phim cho đơn FL-2026-000003.","FL-2026-000003",0],
              ["lab.saigon@filmlab.vn","Review","Có đánh giá mới","Khách vừa đánh giá 5 sao cho đơn FL-2026-000001.","FL-2026-000001",1],
              ["admin@filmlab.vn","Complaint","Khiếu nại mới cần xử lý","Đơn FL-2026-000003: giao trả phim chậm.","FL-2026-000003",0]]
    return HDR + """-- File scan mẫu (URL giả; checksum là SHA-256 của tên file, chỉ để demo)
INSERT INTO arc.ScanFiles (OrderId, OrderItemId, OwnerUserId, UploadedBy, FrameNumber, FileName, StorageUrl, ContentType, FileSizeBytes, WidthPx, HeightPx, ChecksumSha256, QualityScore, QualityStatus)
SELECT o.OrderId, oi.OrderItemId, o.CustomerId, l.OwnerUserId, v.Frame, v.FileName, v.Url, N'image/jpeg', v.Size, v.W, v.H,
       CONVERT(CHAR(64), HASHBYTES('SHA2_256', v.FileName), 2), v.Score, v.QStatus
FROM (VALUES
    %s
) v(OrderCode, Pkg, Frame, FileName, Url, Size, W, H, Score, QStatus)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN lab.FilmLabs l ON l.LabId = o.LabId
JOIN ord.OrderItems oi ON oi.OrderId = o.OrderId
JOIN lab.LabServices ls ON ls.LabServiceId = oi.LabServiceId AND ls.PackageName = v.Pkg;
GO

-- Metadata ảnh (1-1 với ScanFiles, chỉ cho ảnh đã kiểm tra)
INSERT INTO arc.PhotoMetadata (ScanFileId, FilmStockId, CameraModel, LensModel, ShootingDate, ExposedIso, ProcessMethod, ScannerModel, ScanResolutionDpi, ExtraJson)
SELECT sf.ScanFileId, fs.StockId, v.Camera, v.Lens, CAST(DATEADD(DAY, -v.DaysAgo, SYSUTCDATETIME()) AS DATE), v.Iso, v.Process, v.Scanner, v.Dpi, v.Extra
FROM (VALUES
    %s
) v(OrderCode, FileName, Brand, Stock, Camera, Lens, DaysAgo, Iso, Process, Scanner, Dpi, Extra)
JOIN ord.Orders o ON o.OrderCode = v.OrderCode
JOIN arc.ScanFiles sf ON sf.OrderId = o.OrderId AND sf.FileName = v.FileName
JOIN lab.FilmStocks fs ON fs.Brand = v.Brand AND fs.StockName = v.Stock;
GO

-- Album của khách
INSERT INTO arc.Albums (OwnerUserId, Title, Description, CoverScanFileId, IsPublic)
SELECT u.UserId, v.Title, v.Descr, sf.ScanFileId, v.IsPublic
FROM (VALUES
    (N'an.nguyen@example.com', N'Đà Lạt 2026', N'Những khung hình Portra 400 trong chuyến đi Đà Lạt.', N'FL-2026-000001_001.jpg', 1),
    (N'binh.tran@example.com', N'Phim đầu tay', N'Cuộn Ultramax 400 đầu tiên.', N'FL-2026-000006_001.jpg', 0)
) v(Email, Title, Descr, CoverFile, IsPublic)
JOIN iam.Users u ON u.Email = v.Email
LEFT JOIN arc.ScanFiles sf ON sf.FileName = v.CoverFile;
GO

INSERT INTO arc.AlbumPhotos (AlbumId, ScanFileId, SortOrder)
SELECT a.AlbumId, sf.ScanFileId, v.Sort
FROM (VALUES
    (N'Đà Lạt 2026', N'FL-2026-000001_001.jpg', 1), (N'Đà Lạt 2026', N'FL-2026-000001_002.jpg', 2), (N'Đà Lạt 2026', N'FL-2026-000001_003.jpg', 3),
    (N'Phim đầu tay', N'FL-2026-000006_001.jpg', 1), (N'Phim đầu tay', N'FL-2026-000006_002.jpg', 2)
) v(Title, FileName, Sort)
JOIN arc.Albums a ON a.Title = v.Title
JOIN arc.ScanFiles sf ON sf.FileName = v.FileName;
GO

-- Thông báo (mọi module sẽ tạo qua arc.sp_CreateNotification ở Đợt 6)
INSERT INTO arc.Notifications (UserId, Type, Title, Body, OrderId, IsRead, ReadAt)
SELECT u.UserId, v.Type, v.Title, v.Body, o.OrderId, v.IsRead,
       CASE WHEN v.IsRead = 1 THEN DATEADD(HOUR, -1, SYSUTCDATETIME()) END
FROM (VALUES
    %s
) v(Email, Type, Title, Body, OrderCode, IsRead)
JOIN iam.Users u ON u.Email = v.Email
LEFT JOIN ord.Orders o ON o.OrderCode = v.OrderCode;
GO
""" % (V(files), V(meta), V(notifs))

# ======================= MKT =======================
def mkt_sql():
    L = [ # seller, cat, type, title, desc, brand, model, cond, price, exch, qty, city, status
     ("an.nguyen@example.com","CAMERA","Sell","Canon AE-1 Program kèm lens 50mm f/1.8","Máy hoạt động tốt, kèm dây đeo và bao da.","Canon","AE-1 Program","Good",4500000,None,1,"TP. Hồ Chí Minh","Reserved"),
     ("chi.le@example.com","LENS","Sell","Helios 44-2 58mm f/2 (M42)","Ống kính Liên Xô, bokeh xoáy đặc trưng.","Helios","44-2","Good",900000,None,1,"Hà Nội","Reserved"),
     ("binh.tran@example.com","CAMERA","Exchange","Đổi Olympus Trip 35 lấy Yashica T4","Trip 35 còn rất mới, đổi ngang.","Olympus","Trip 35","LikeNew",None,"Yashica T4",1,"TP. Hồ Chí Minh","Active"),
     ("lab.saigon@filmlab.vn","FILM","Sell","Kodak Portra 400 (hạn dùng 2027)","Cuộn mới, bảo quản tủ lạnh.","Kodak","Portra 400","New",120000,None,10,"TP. Hồ Chí Minh","Active"),
     ("an.nguyen@example.com","CAMERA","Wanted","Cần tìm Nikon FM2","Ưu tiên bản body còn đẹp, giá hợp lý.","Nikon","FM2",None,None,None,1,"TP. Hồ Chí Minh","Active"),
     ("chi.le@example.com","CAMERA","Sell","Pentax K1000 body","Máy cơ nguyên bản, đã bán.","Pentax","K1000","Good",3200000,None,1,"Hà Nội","Sold")]
    IMG = [(L[i][3], "https://storage.filmlab.vn/market/%d_%d.jpg" % (i + 1, k), k, 1 if k == 0 else 0) for i in range(6) for k in range(2 if i < 4 else 1)]
    T = [ # code, listing title, buyer, qty, status, note
     ("MK-2026-000001", L[5][3], "binh.tran@example.com", 1, "Completed", "Đã nhận máy, đúng mô tả."),
     ("MK-2026-000002", L[0][3], "chi.le@example.com", 1, "Confirmed", "Hẹn gặp trực tiếp cuối tuần."),
     ("MK-2026-000003", L[1][3], "an.nguyen@example.com", 1, "Disputed", None),
     ("MK-2026-000004", L[3][3], "an.nguyen@example.com", 2, "Cancelled", None)]
    M = [(L[0][3], "chi.le@example.com", "an.nguyen@example.com", "Máy còn bảo hành đèn pin không bạn?", 300, 1),
         (L[0][3], "an.nguyen@example.com", "chi.le@example.com", "Máy không bảo hành nhưng mình cho dùng thử trước.", 280, 1),
         (L[2][3], "an.nguyen@example.com", "binh.tran@example.com", "Mình có Yashica T4 đời đầu, bạn có muốn đổi không?", 60, 0)]
    return HDR + """-- Tin đăng mẫu (6 tin: bán, đổi, cần mua; đủ trạng thái Active/Reserved/Sold)
INSERT INTO mkt.Listings (SellerId, CategoryId, ListingType, Title, Description, Brand, Model, Condition, Price, ExchangeWanted, Quantity, City, Status)
SELECT u.UserId, c.CategoryId, v.Type, v.Title, v.Descr, v.Brand, v.Model, v.Cond, v.Price, v.Exch, v.Qty, v.City, v.Status
FROM (VALUES
    %s
) v(Email, CatCode, Type, Title, Descr, Brand, Model, Cond, Price, Exch, Qty, City, Status)
JOIN iam.Users u ON u.Email = v.Email
JOIN mkt.ListingCategories c ON c.CategoryCode = v.CatCode;
GO

INSERT INTO mkt.ListingImages (ListingId, ImageUrl, SortOrder, IsPrimary)
SELECT l.ListingId, v.Url, v.Sort, v.IsPrimary
FROM (VALUES
    %s
) v(Title, Url, Sort, IsPrimary)
JOIN mkt.Listings l ON l.Title = v.Title;
GO

-- Giao dịch: giá chốt từ tin đăng, phí marketplace 5%% (D-12, chỉ ghi nhận, không xử lý tiền thật)
INSERT INTO mkt.MarketTransactions (TransactionCode, ListingId, SellerId, BuyerId, Quantity, UnitPrice, PlatformFee, Status, Note,
                                    ConfirmedAt, ShippedAt, CompletedAt, CancelReason, DisputeReason, DisputedAt, BuyerRating, BuyerComment, RatedAt)
SELECT v.Code, l.ListingId, l.SellerId, b.UserId, v.Qty, l.Price, CAST(ROUND(l.Price * v.Qty * 0.05, 0) AS DECIMAL(18,0)), v.Status, v.Note,
       CASE WHEN v.Status IN (N'Confirmed', N'Completed', N'Disputed') THEN DATEADD(DAY, -3, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Completed' THEN DATEADD(DAY, -2, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Completed' THEN DATEADD(DAY, -1, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Cancelled' THEN N'Người mua đổi ý' END,
       CASE WHEN v.Status = N'Disputed' THEN N'Ống kính bị mốc nhẹ, không đúng mô tả' END,
       CASE WHEN v.Status = N'Disputed' THEN DATEADD(DAY, -1, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Completed' THEN 5 END,
       CASE WHEN v.Status = N'Completed' THEN N'Người bán nhiệt tình, máy đúng mô tả.' END,
       CASE WHEN v.Status = N'Completed' THEN SYSUTCDATETIME() END
FROM (VALUES
    %s
) v(Code, Title, BuyerEmail, Qty, Status, Note)
JOIN mkt.Listings l ON l.Title = v.Title
JOIN iam.Users b ON b.Email = v.BuyerEmail;
GO

INSERT INTO mkt.Messages (ListingId, SenderId, ReceiverId, Body, SentAt, ReadAt)
SELECT l.ListingId, s.UserId, r.UserId, v.Body, DATEADD(MINUTE, -v.MinAgo, SYSUTCDATETIME()),
       CASE WHEN v.IsRead = 1 THEN DATEADD(MINUTE, -v.MinAgo + 5, SYSUTCDATETIME()) END
FROM (VALUES
    %s
) v(Title, SenderEmail, ReceiverEmail, Body, MinAgo, IsRead)
JOIN mkt.Listings l ON l.Title = v.Title
JOIN iam.Users s ON s.Email = v.SenderEmail
JOIN iam.Users r ON r.Email = v.ReceiverEmail;
GO
""" % (V([list(x) for x in L]), V(IMG), V(T), V(M))

# ======================= COM =======================
def com_sql():
    A = [ # author, type, title, slug, summary, body, tags, labName, brand, stock, status, daysAgo
     ("expert@filmlab.vn","Tutorial","Hướng dẫn tráng phim C-41 tại nhà","huong-dan-trang-phim-c41-tai-nha",
      "Các bước tráng phim màu C-41 với bộ hóa chất cơ bản.",
      "Chuẩn bị tank, hóa chất C-41 (developer, blix, stabilizer) và nhiệt kế. Giữ nhiệt độ developer ở 38°C, tráng 3 phút 15 giây, khuấy đều theo chu kỳ. Sau đó blix, rửa và ngâm stabilizer trước khi treo khô.",
      J(["c41","trang-phim","tai-nha"]),None,None,None,"Published",14),
     ("expert@filmlab.vn","Review","Review Kodak Portra 400: màu da đẹp, dải nhạy sáng rộng","review-kodak-portra-400",
      "Đánh giá Portra 400 sau 10 cuộn: màu da, độ hạt, khả năng đẩy.",
      "Portra 400 cho màu da ấm, độ hạt mịn và latitude rộng. Phim chịu được push +1 đến +2 stop mà vẫn giữ màu. Phù hợp chân dung và street trong điều kiện ánh sáng thay đổi.",
      J(["portra","kodak","review"]),None,"Kodak","Portra 400","Published",9),
     ("expert@filmlab.vn","LabGuide","Cách chọn film lab ở TP.HCM","cach-chon-film-lab-tphcm",
      "Tiêu chí chọn lab: chất lượng scan, thời gian, giá, dịch vụ giao nhận.",
      "Hãy so sánh chất lượng scan mẫu, thời gian trả phim, mức giá theo cuộn và chính sách xử lý khi có sự cố. Lab có đánh giá công khai và chính sách khiếu nại rõ ràng thường đáng tin hơn.",
      J(["film-lab","tphcm"]),"Sài Gòn Film Lab",None,None,"Published",5),
     ("expert@filmlab.vn","Technical","Push và pull process: khi nào nên dùng","push-pull-process",
      "Giải thích push/pull, ảnh hưởng đến độ tương phản và hạt.",
      "Bản nháp, sẽ bổ sung ví dụ thực tế.",
      J(["push","pull"]),None,None,None,"Draft",None),
     ("an.nguyen@example.com","Question","Phim C-41 hết hạn 2 năm có tráng được không?","phim-c41-het-han-2-nam",
      "Mình có cuộn Gold 200 hết hạn 2 năm, bảo quản nhiệt độ phòng.",
      "Cuộn phim hết hạn 2 năm, để ở nhiệt độ phòng. Mình nên overexpose bao nhiêu stop và có cần báo lab không?",
      J(["het-han","c41"]),None,"Kodak","Gold 200","Published",3),
     ("expert@filmlab.vn","Experience","Bài đã bị ẩn do vi phạm quy định","bai-bi-an-vi-pham",
      "Bài mẫu để demo kiểm duyệt.","Nội dung vi phạm quy định cộng đồng (mẫu).",
      None,None,None,None,"Hidden",7)]
    rows = [list(a) for a in A]
    C = [("phim-c41-het-han-2-nam","expert@filmlab.vn","Thường nên overexpose 1-2 stop và báo lab để họ tráng đúng quy trình. Phim bảo quản nhiệt độ phòng có thể bị fog nhẹ.",1),
         ("huong-dan-trang-phim-c41-tai-nha","an.nguyen@example.com","Bài rất dễ hiểu! Cho mình hỏi dùng nước máy để pha hóa chất được không?",0),
         ("review-kodak-portra-400","binh.tran@example.com","Cảm ơn bạn, mình đang cân nhắc Portra 400 cho chuyến đi sắp tới.",0)]
    REP = [("huong-dan-trang-phim-c41-tai-nha","expert@filmlab.vn","Nên dùng nước cất hoặc nước lọc để tránh cặn, nhất là bước pha stabilizer.",
            "Bài rất dễ hiểu! Cho mình hỏi dùng nước máy để pha hóa chất được không?")]
    E = [ # organizer, hostLab, type, title, desc, startDays, hours, deadlineDays, venue, addr, city, lat, lng, cap, fee, status
     ("expert@filmlab.vn","Sài Gòn Film Lab","Workshop","Workshop tráng phim đen trắng tại nhà","Thực hành tráng B&W từ A-Z, mang theo cuộn phim của bạn.",14,3,12,"Sài Gòn Film Lab","101 Pasteur, Quận 1","TP. Hồ Chí Minh",10.7790,106.6990,12,250000,"Open"),
     ("expert@filmlab.vn",None,"Photowalk","Photowalk Chợ Lớn cùng máy film","Đi bộ chụp phim khu Chợ Lớn, chia sẻ kỹ thuật đo sáng.",21,4,None,"Chùa Bà Thiên Hậu","710 Nguyễn Trãi, Quận 5","TP. Hồ Chí Minh",10.7530,106.6600,20,0,"Open"),
     ("expert@filmlab.vn","Hà Nội Analog Lab","Workshop","Workshop scan phim và xử lý màu","Đã tổ chức xong, mẫu cho trạng thái Completed.",-20,3,-22,"Hà Nội Analog Lab","15 Phố Huế","Hà Nội",21.0150,105.8490,10,200000,"Completed")]
    def dt(d, h=0): return "DATEADD(HOUR, %d, DATEADD(DAY, %d, SYSUTCDATETIME()))" % (h, d)
    erows = [[e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10], e[11], e[12], e[13], e[14], e[15]] for e in E]
    REG = [("Workshop tráng phim đen trắng tại nhà","an.nguyen@example.com","Registered",1),
           ("Workshop tráng phim đen trắng tại nhà","binh.tran@example.com","Registered",1),
           ("Workshop tráng phim đen trắng tại nhà","chi.le@example.com","Cancelled",0),
           ("Photowalk Chợ Lớn cùng máy film","an.nguyen@example.com","Registered",0),
           ("Workshop scan phim và xử lý màu","chi.le@example.com","Attended",1)]
    return HDR + """-- Bài viết (Expert viết; có Draft, Hidden để demo kiểm duyệt; 1 câu hỏi của khách)
INSERT INTO com.Articles (AuthorId, ArticleType, Title, Slug, Summary, Body, Tags, RelatedLabId, RelatedStockId, Status, PublishedAt, ModerationReason, ModeratedBy)
SELECT u.UserId, v.Type, v.Title, v.Slug, v.Summ, v.Body, v.Tags, l.LabId, fs.StockId, v.Status,
       CASE WHEN v.DaysAgo IS NOT NULL THEN DATEADD(DAY, -v.DaysAgo, SYSUTCDATETIME()) END,
       CASE WHEN v.Status = N'Hidden' THEN N'Vi phạm quy định cộng đồng (bài mẫu)' END,
       CASE WHEN v.Status = N'Hidden' THEN a.UserId END
FROM (VALUES
    %s
) v(Email, Type, Title, Slug, Summ, Body, Tags, LabName, Brand, Stock, Status, DaysAgo)
JOIN iam.Users u ON u.Email = v.Email
LEFT JOIN lab.FilmLabs l ON l.LabName = v.LabName
LEFT JOIN lab.FilmStocks fs ON fs.Brand = v.Brand AND fs.StockName = v.Stock
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO

-- Bình luận cấp 1 (câu trả lời của Expert cho bài Question được chọn là đúng)
INSERT INTO com.ArticleComments (ArticleId, UserId, Body, IsAccepted)
SELECT a.ArticleId, u.UserId, v.Body, v.IsAccepted
FROM (VALUES
    %s
) v(Slug, Email, Body, IsAccepted)
JOIN com.Articles a ON a.Slug = v.Slug
JOIN iam.Users u ON u.Email = v.Email;
GO

-- Trả lời bình luận (chỉ 1 cấp)
INSERT INTO com.ArticleComments (ArticleId, UserId, ParentCommentId, Body)
SELECT a.ArticleId, u.UserId, p.CommentId, v.Body
FROM (VALUES
    %s
) v(Slug, Email, Body, ParentBody)
JOIN com.Articles a ON a.Slug = v.Slug
JOIN iam.Users u ON u.Email = v.Email
JOIN com.ArticleComments p ON p.ArticleId = a.ArticleId AND p.Body = v.ParentBody;
GO

-- Sự kiện: 2 sắp diễn ra, 1 đã hoàn tất
INSERT INTO com.Events (OrganizerId, HostLabId, EventType, Title, Description, StartAt, EndAt, RegistrationDeadline, VenueName, AddressLine, City, Location, Capacity, Fee, Status)
SELECT u.UserId, l.LabId, v.Type, v.Title, v.Descr,
       DATEADD(DAY, v.StartD, SYSUTCDATETIME()), DATEADD(HOUR, v.Hours, DATEADD(DAY, v.StartD, SYSUTCDATETIME())),
       CASE WHEN v.DeadlineD IS NOT NULL THEN DATEADD(DAY, v.DeadlineD, SYSUTCDATETIME()) END,
       v.Venue, v.Addr, v.City, geography::Point(v.Lat, v.Lng, 4326), v.Cap, v.Fee, v.Status
FROM (VALUES
    %s
) v(Email, LabName, Type, Title, Descr, StartD, Hours, DeadlineD, Venue, Addr, City, Lat, Lng, Cap, Fee, Status)
JOIN iam.Users u ON u.Email = v.Email
LEFT JOIN lab.FilmLabs l ON l.LabName = v.LabName;
GO

INSERT INTO com.EventRegistrations (EventId, UserId, Status, IsPaid, CancelledAt)
SELECT e.EventId, u.UserId, v.Status, v.IsPaid, CASE WHEN v.Status = N'Cancelled' THEN DATEADD(DAY, -1, SYSUTCDATETIME()) END
FROM (VALUES
    %s
) v(Title, Email, Status, IsPaid)
JOIN com.Events e ON e.Title = v.Title
JOIN iam.Users u ON u.Email = v.Email;
GO
""" % (V(rows), V([list(c) for c in C]), V([list(r) for r in REP]), V(erows), V([list(r) for r in REG]))

# ======================= AI =======================
def ai_sql():
    K = [("huong-dan-trang-phim-c41-tai-nha",0,"Tráng phim C-41: nhiệt độ và thời gian","C-41","Developer C-41 giữ ở 38°C, thời gian 3 phút 15 giây, khuấy đảo đều theo chu kỳ để tránh loang màu.",1,"[0.12,0.08,0.31]"),
         ("huong-dan-trang-phim-c41-tai-nha",1,"Tráng phim C-41: blix, rửa và stabilizer","C-41","Sau developer là blix 6 phút, rửa nước 3 phút, ngâm stabilizer 1 phút rồi treo khô nơi sạch bụi.",1,"[0.05,0.22,0.17]"),
         ("review-kodak-portra-400",0,"Kodak Portra 400: đặc điểm","Film stock","Portra 400 cho màu da ấm, hạt mịn, latitude rộng, chịu push +1 đến +2 stop.",1,"[0.40,0.11,0.09]"),
         ("cach-chon-film-lab-tphcm",0,"Tiêu chí chọn film lab","Film lab","So sánh chất lượng scan, thời gian trả phim, giá theo cuộn và chính sách khiếu nại.",0,None)]
    CHAT = [("6F9619FF-8B86-D011-B42D-00C04FC964FF","an.nguyen@example.com","User","Tôi nên tráng phim C-41 ở nhiệt độ nào?",None,None,None,None,None,None,30),
            ("6F9619FF-8B86-D011-B42D-00C04FC964FF","an.nguyen@example.com","Assistant","Developer C-41 thường giữ ở 38°C trong khoảng 3 phút 15 giây, bạn nên khuấy đều theo chu kỳ.","filmlab-assistant-v1",120,60,850,
             R("CONCAT('[', (SELECT MIN(KnowledgeDocId) FROM ai.KnowledgeDocs WHERE Topic = N'C-41'), ']')"),"Helpful",29),
            ("0B7F1E2A-5C31-4A58-9D77-3E8C5A6B1D02","binh.tran@example.com","User","Gợi ý lab scan chất lượng cao ở Hà Nội?",None,None,None,None,None,None,20),
            ("0B7F1E2A-5C31-4A58-9D77-3E8C5A6B1D02","binh.tran@example.com","Assistant","Hà Nội Analog Lab có gói Scan Ultra 35mm, thời gian khoảng 5 ngày.","filmlab-assistant-v1",95,48,720,None,None,19)]
    REC = [("an.nguyen@example.com","Lab","Sài Gòn Film Lab",1,0.8123,J({"format":"35mm","city":"TP. Hồ Chí Minh"}),"Clicked"),
           ("an.nguyen@example.com","Lab","Hà Nội Analog Lab",2,0.6120,J({"format":"35mm","city":"TP. Hồ Chí Minh"}),None),
           ("binh.tran@example.com","Lab","Sài Gòn Film Lab",1,0.7740,J({"format":"35mm"}),"Ordered")]
    return HDR + """-- Sở thích người dùng (nguồn dữ liệu cho điểm gợi ý lab)
INSERT INTO ai.UserPreferences (UserId, PreferredFormatId, PreferredFilmType, PreferredCity, MaxDistanceKm, MaxBudgetPerRoll, PrioritizeQuality, PrioritizeSpeed, Source)
SELECT u.UserId, ff.FormatId, v.FilmType, v.City, v.MaxKm, v.Budget, v.PQ, v.PS, v.Source
FROM (VALUES
    (N'an.nguyen@example.com', N'35mm', N'ColorNegative', N'TP. Hồ Chí Minh', 10.0, 200000, 1, 0, N'UserSet'),
    (N'binh.tran@example.com', N'35mm', N'BlackWhite', N'TP. Hồ Chí Minh', 15.0, 150000, 0, 1, N'Inferred')
) v(Email, FormatCode, FilmType, City, MaxKm, Budget, PQ, PS, Source)
JOIN iam.Users u ON u.Email = v.Email
JOIN lab.FilmFormats ff ON ff.FormatCode = v.FormatCode;
GO

-- Tri thức cho RAG (chunk từ bài viết Expert; chỉ chunk đã duyệt mới dùng cho AI; embedding là placeholder)
INSERT INTO ai.KnowledgeDocs (SourceArticleId, ChunkIndex, Title, Topic, Content, ContentHash, EmbeddingJson, EmbeddingModel, ContributedBy, IsApproved, ApprovedBy, ApprovedAt)
SELECT a.ArticleId, v.Chunk, v.Title, v.Topic, v.Content, CONVERT(CHAR(64), HASHBYTES('SHA2_256', v.Content), 2),
       v.Emb, CASE WHEN v.Emb IS NOT NULL THEN N'placeholder-embedding-v0' END, e.UserId, v.Approved,
       CASE WHEN v.Approved = 1 THEN ad.UserId END, CASE WHEN v.Approved = 1 THEN SYSUTCDATETIME() END
FROM (VALUES
    %s
) v(Slug, Chunk, Title, Topic, Content, Approved, Emb)
JOIN com.Articles a ON a.Slug = v.Slug
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'expert@filmlab.vn') e
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') ad;
GO

-- Nhật ký chat với trợ lý AI
INSERT INTO ai.AIChatLogs (SessionId, UserId, Role, Message, ModelName, PromptTokens, CompletionTokens, LatencyMs, SourcesJson, Feedback, CreatedAt)
SELECT CONVERT(UNIQUEIDENTIFIER, v.Session), u.UserId, v.Role, v.Msg, v.Model, v.PT, v.CT, v.Lat, v.Src, v.Fb, DATEADD(MINUTE, -v.MinAgo, SYSUTCDATETIME())
FROM (VALUES
    %s
) v(Session, Email, Role, Msg, Model, PT, CT, Lat, Src, Fb, MinAgo)
JOIN iam.Users u ON u.Email = v.Email;
GO

-- Nhật ký gợi ý lab (ItemId trỏ tới lab.FilmLabs.LabId, không có FK có chủ ý)
INSERT INTO ai.RecommendationLogs (UserId, RecommendationType, ItemId, Rank, Score, ModelVersion, ContextJson, Action, ActedAt)
SELECT u.UserId, v.Type, l.LabId, v.Rnk, v.Score, N'tsql-v1', v.Ctx, v.Action,
       CASE WHEN v.Action IS NOT NULL THEN DATEADD(MINUTE, -10, SYSUTCDATETIME()) END
FROM (VALUES
    %s
) v(Email, Type, LabName, Rnk, Score, Ctx, Action)
JOIN iam.Users u ON u.Email = v.Email
JOIN lab.FilmLabs l ON l.LabName = v.LabName;
GO
""" % (V([list(k) for k in K]), V([list(c) for c in CHAT]), V([list(r) for r in REC]))

# ======================= AUDIT =======================
def audit_sql():
    def pk(q): return R("(SELECT CAST(%s AS NVARCHAR(100)))" % q)
    rows = [
     ["ord","Orders",pk("(SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001')"),"INSERT",None,J({"OrderCode":"FL-2026-000001","StageId":1}),20],
     ["ord","Orders",pk("(SELECT OrderId FROM ord.Orders WHERE OrderCode = N'FL-2026-000001')"),"UPDATE",J({"StageId":11}),J({"StageId":12,"PaymentStatus":"Paid"}),12],
     ["lab","FilmLabs",pk("(SELECT LabId FROM lab.FilmLabs WHERE LabName = N'Hà Nội Analog Lab')"),"UPDATE",J({"ApprovalStatus":"Pending"}),J({"ApprovalStatus":"Approved"}),30],
     ["mkt","Listings",pk("(SELECT ListingId FROM mkt.Listings WHERE Title = N'Pentax K1000 body')"),"UPDATE",J({"Status":"Active"}),J({"Status":"Sold"}),2]]
    return HDR + """-- Nhật ký thay đổi mẫu (trigger *_Audit ghi tự động ở Đợt 6; ChangedBy = Admin)
INSERT INTO audit.AuditLogs (TableSchema, TableName, PrimaryKeyValue, Action, ChangedBy, OldValues, NewValues, ChangedAt)
SELECT v.Sch, v.Tbl, v.Pk, v.Act, a.UserId, v.OldV, v.NewV, DATEADD(DAY, -v.DaysAgo, SYSUTCDATETIME())
FROM (VALUES
    %s
) v(Sch, Tbl, Pk, Act, OldV, NewV, DaysAgo)
CROSS JOIN (SELECT UserId FROM iam.Users WHERE Email = N'admin@filmlab.vn') a;
GO
""" % V(rows)

def main():
    out = {"lab": lab_sql(), "ord": ord_sql(), "ord_feedback": fb_sql(), "dlv": dlv_sql(), "arc": arc_sql(),
           "mkt": mkt_sql(), "com": com_sql(), "ai": ai_sql(), "audit": audit_sql()}
    for k, v in out.items():
        G.write_into(os.path.join(G.ROOT, "04_seed", "sample", k + ".sql"), v)
    print("OK: sample seed cho", ", ".join(out))
if __name__ == "__main__":
    main()
