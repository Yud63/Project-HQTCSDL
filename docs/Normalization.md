# Kiểm tra chuẩn hóa (1NF, 2NF, 3NF)

> Bảng tổng hợp ở mục 4 được sinh từ `tools/schema_spec.py`. Phần phân tích (mục 1 đến 3, 5, 6) viết tay, dùng trực tiếp cho chương Thiết kế CSDL của báo cáo.

## 1. Phương pháp

| Bước | Việc làm |
|---|---|
| 1 | Với mỗi bảng, xác định khóa chính và các khóa ứng viên khác (cột `UNIQUE`, filtered unique index) |
| 2 | Liệt kê phụ thuộc hàm (FD) giữa các thuộc tính từ business rule |
| 3 | **1NF**: mỗi ô một giá trị nguyên tử, không nhóm lặp |
| 4 | **2NF**: với khóa ghép, thuộc tính không khóa phụ thuộc vào **toàn bộ** khóa (không phụ thuộc một phần) |
| 5 | **3NF**: thuộc tính không khóa không phụ thuộc bắc cầu vào khóa (không có FD giữa hai thuộc tính không khóa) |
| 6 | Chỗ nào cố ý vi phạm thì ghi lại lý do và **cơ chế giữ nhất quán** (mục 3) |

Ký hiệu cột Dạng chuẩn: `3NF` = đạt; `2NF*` = đạt 2NF nhưng **cố ý** không đạt 3NF (xem mục 3).

## 2. Ví dụ minh họa: từ bảng phẳng đến 3NF

Bắt đầu từ một "phiếu đơn hàng" phẳng mà tiệm lab thường ghi sổ:

| OrderCode | CustomerName | CustomerEmail | LabName | LabCity | ServiceName | Price | Qty | FilmStocks | StageName |
|---|---|---|---|---|---|---|---|---|---|
| FL-001 | An | an@mail.vn | Lab Sài Gòn | HCM | Tráng C-41; Scan High | 60000; 90000 | 1; 1 | Portra 400; Portra 400 | Scanning |

| Dạng | Vấn đề | Cách xử lý | Kết quả trong thiết kế |
|---|---|---|---|
| Chưa chuẩn | Ô chứa nhiều giá trị (`ServiceName`, `Price`, `Qty`, `FilmStocks`) | **1NF**: tách mỗi dịch vụ thành một dòng | `ord.OrderItems` (1 dòng/dịch vụ) |
| 1NF | Khóa (OrderCode, ServiceName): `CustomerName`, `LabName`, `StageName` chỉ phụ thuộc `OrderCode` (phụ thuộc một phần); `Price` phụ thuộc (LabName, ServiceName) | **2NF**: tách theo phần khóa | `ord.Orders` (thông tin đơn), `lab.LabServices` (giá theo lab+dịch vụ) |
| 2NF | `OrderCode -> CustomerEmail -> CustomerName` (bắc cầu); `OrderCode -> LabName -> LabCity`; `OrderCode -> StageName` qua giai đoạn | **3NF**: tách thực thể có khóa riêng | `iam.Users`, `lab.FilmLabs`, `ord.ProcessingStages` |
| 3NF | `Price` đổi theo thời gian nhưng đơn cũ phải giữ giá cũ | Lưu **snapshot** có chủ ý | `OrderItems.UnitPriceSnapshot` (DN-3) |

## 3. Các điểm phi chuẩn hóa / ngoại lệ có chủ ý

Mỗi ngoại lệ có lý do và cơ chế bảo đảm nhất quán; đây là chỗ giảng viên thường hỏi.

| Mã | Vị trí | Vi phạm | Lý do giữ | Cơ chế giữ nhất quán | Phương án chuẩn hóa hoàn toàn (không chọn) |
|---|---|---|---|---|---|
| DN-1 | `lab.FilmLabs.AvgRating`, `ReviewCount` | Dữ liệu dẫn xuất từ `ord.Reviews` | Tìm/xếp hạng lab đọc rất nhiều, tính lại mỗi lần tốn kém | Trigger `trg_Reviews_UpdateRating` gọi `lab.sp_RecalcLabRating`; DENY UPDATE trực tiếp 2 cột | Bỏ 2 cột, tính bằng `fn_LabAvgRating` mỗi lần truy vấn |
| DN-2 | `ord.Orders.Subtotal`, `PlatformFee`, `TotalAmount` | Dẫn xuất/chốt từ OrderItems và FeeConfigs | Đơn là chứng từ tài chính: tổng tiền không được đổi khi giá hay phí đổi | CHECK `TotalAmount = Subtotal + DeliveryFee`; `sp_CreateOrder` tính trong Transaction | Tính tổng từ OrderItems mỗi lần đọc |
| DN-3 | `ord.OrderItems.UnitPriceSnapshot`, `LineTotal` | Lặp giá của `lab.LabServices`; LineTotal là cột tính | Giữ đúng giá lúc đặt dù lab đổi giá sau đó | Chốt trong `sp_CreateOrder`; `LabServices` là Temporal Table nên vẫn truy được giá lịch sử | Tra giá theo thời điểm đặt từ bảng lịch sử |
| DN-4 | `iam.Addresses`, `lab.FilmLabs`: Ward/District/City | Bắc cầu Ward -> District -> City | Địa chỉ nhập tự do, hiển thị nguyên văn; không cần bảng đơn vị hành chính cho đồ án | Bắt buộc không NULL; không có ràng buộc chéo | Bảng `AdministrativeUnits` có cây Tỉnh/Quận/Phường |
| DN-5 | `ord.Reviews`, `ord.Complaints`: CustomerId, LabId | `OrderId -> (CustomerId, LabId)`, dư thừa với Orders | Lọc theo lab/khách không cần JOIN; làm khóa RLS multi-tenant | **FK ghép** (OrderId, CustomerId, LabId) -> `ord.Orders`: DB không cho lệch | Chỉ giữ OrderId, JOIN Orders khi cần |
| DN-6 | `arc.ScanFiles.OwnerUserId` | `OrderId -> OwnerUserId` (= Orders.CustomerId) | Digital Film Archive và RLS lọc theo chủ ảnh rất thường xuyên | `trg_ScanFiles_CheckOwner` + `sp_UploadScan` bảo đảm bằng `Orders.CustomerId` | JOIN Orders để biết chủ ảnh |
| DN-7 | `arc.ScanFiles.QualityStatus` | `QualityScore -> QualityStatus` theo ngưỡng | Lọc ảnh Warning/Failed nhanh, ngưỡng nằm trong procedure | Chỉ `sp_SetScanQuality` ghi cả hai cột; CHECK `NotChecked` thì chưa có điểm | Tính trạng thái từ điểm khi truy vấn |
| DN-8 | `mkt.MarketTransactions.SellerId` | `ListingId -> SellerId` | Người bán xem giao dịch của mình không cần JOIN; làm khóa RLS | **FK ghép** (ListingId, SellerId) -> `mkt.Listings` | Chỉ giữ ListingId |
| DN-9 | Cột JSON: `OpenHoursJson`, `SpecialTechniques`, `Tags`, `ExtraJson` (x2), `SourcesJson`, `ContextJson`, `EmbeddingJson`, `OldValues`, `NewValues` | **1NF**: giá trị đa trị/có cấu trúc trong một ô | Dữ liệu bán cấu trúc, thay đổi theo thời gian, chỉ đọc qua `OPENJSON`; tách bảng làm phình số bảng mà ít giá trị | CHECK `ISJSON = 1`; truy xuất qua `OPENJSON`/`JSON_VALUE` (điểm cộng SQL Server 2022) | Bảng con (LabOpenHours, LabTechniques, ArticleTags...) |
| DN-10 | `com.Articles.Slug` | `Title -> Slug` | Slug là đường dẫn duy nhất của bài, dùng làm khóa tra cứu | Filtered unique index; Slug là khóa ứng viên nên vẫn 3NF (chỉ không BCNF) | Sinh Slug lúc hiển thị từ Title |
| DN-11 | `ai.RecommendationLogs.ItemId`, `audit.AuditLogs.ChangedBy` | Tham chiếu không có FK | Log phải tồn tại độc lập: ItemId trỏ nhiều bảng khác nhau (đa hình), nhật ký không được bị chặn khi dữ liệu nguồn đổi | Quy ước + `RecommendationType` xác định bảng đích; `audit.sp_WriteAudit` là điểm ghi duy nhất | Một bảng log riêng cho từng loại gợi ý, FK đầy đủ |

## 4. Bảng tổng hợp 41 bảng

| Bảng | Khóa chính | Khóa ứng viên khác | Dạng chuẩn | Ghi chú |
|---|---|---|---|---|
| `iam.Users` | UserId | UX_Users_Email (Email) [lọc] | 3NF |  |
| `iam.Roles` | RoleId | RoleCode | 3NF |  |
| `iam.UserRoles` | UserId, RoleId | (không) | 3NF | Khóa ghép; mọi thuộc tính phụ thuộc toàn bộ khóa |
| `iam.Addresses` | AddressId | UX_Addresses_Default (UserId) [lọc] | 2NF* | Ward -> District -> City là phụ thuộc bắc cầu (địa chỉ nhập tự do, xem DN-4) |
| `iam.ExpertProfiles` | UserId | (không) | 3NF |  |
| `iam.DeliveryPartners` | DeliveryPartnerId | (không) | 3NF |  |
| `lab.FilmLabs` | LabId | (không) | 2NF* | Ward -> District -> City bắc cầu (DN-4); AvgRating/ReviewCount là dữ liệu dẫn xuất từ Reviews (DN-1); cột JSON (DN-9) |
| `lab.LabApprovals` | ApprovalId | (không) | 3NF |  |
| `lab.FilmFormats` | FormatId | FormatCode | 3NF |  |
| `lab.FilmStocks` | StockId | UQ (Brand, StockName) | 3NF |  |
| `lab.ServiceTypes` | ServiceTypeId | ServiceCode | 3NF |  |
| `lab.LabServices` | LabServiceId | UQ (LabId, PackageName) | 3NF |  |
| `ord.ProcessingStages` | StageId | StageCode; SortOrder | 3NF |  |
| `ord.Orders` | OrderId | OrderCode; UQ_Orders_OrderId_CustomerId_LabId (OrderId, CustomerId, LabId) | 2NF* | (Subtotal, DeliveryFee) -> TotalAmount; Subtotal/PlatformFee dẫn xuất và chốt lúc đặt (DN-2) |
| `ord.OrderItems` | OrderItemId | (không) | 2NF* | (Quantity, UnitPriceSnapshot) -> LineTotal là cột tính; UnitPriceSnapshot chốt giá (DN-3) |
| `ord.OrderStageLog` | LogId | (không) | 3NF |  |
| `ord.Payments` | PaymentId | UX_Payments_OrderPaid (OrderId) [lọc] | 3NF |  |
| `ord.FeeConfigs` | FeeConfigId | (không) | 3NF |  |
| `ord.Reviews` | ReviewId | OrderId | 3NF | CustomerId, LabId phụ thuộc OrderId (là khóa ứng viên nên không vi phạm); dư thừa liên bảng với Orders được FK ghép kiểm soát (DN-5) |
| `ord.Complaints` | ComplaintId | UX_Complaints_OpenPerCategory (OrderId, Category) [lọc] | 2NF* | OrderId -> (CustomerId, LabId) nhưng OrderId không phải khóa của bảng này (DN-5) |
| `dlv.DeliveryRequests` | DeliveryRequestId | UX_Delivery_ActiveLeg (OrderId, Direction) [lọc] | 3NF |  |
| `dlv.DeliveryStatusLog` | LogId | (không) | 3NF |  |
| `arc.ScanFiles` | ScanFileId | UQ (OrderId, FileName) | 2NF* | OrderId -> OwnerUserId (DN-6); QualityScore -> QualityStatus (DN-7) |
| `arc.PhotoMetadata` | ScanFileId | (không) | 3NF | Cột JSON ExtraJson (DN-9) |
| `arc.Albums` | AlbumId | (OwnerUserId, Title) [lọc] | 3NF |  |
| `arc.AlbumPhotos` | AlbumId, ScanFileId | (không) | 3NF | Khóa ghép; mọi thuộc tính phụ thuộc toàn bộ khóa |
| `arc.Notifications` | NotificationId | (không) | 3NF |  |
| `mkt.ListingCategories` | CategoryId | CategoryCode | 3NF |  |
| `mkt.Listings` | ListingId | UQ_Listings_ListingId_SellerId (ListingId, SellerId) | 3NF |  |
| `mkt.ListingImages` | ImageId | UX_ListingImages_Primary (ListingId) [lọc] | 3NF |  |
| `mkt.MarketTransactions` | TransactionId | TransactionCode | 2NF* | ListingId -> SellerId (DN-8); (Quantity, UnitPrice) -> TotalAmount cột tính |
| `mkt.Messages` | MessageId | (không) | 3NF |  |
| `com.Articles` | ArticleId | UX_Articles_Slug (Slug) [lọc] | 3NF (không BCNF) | Title -> Slug nhưng Slug là khóa ứng viên (unique) nên vẫn đạt 3NF (DN-10); cột JSON Tags (DN-9) |
| `com.ArticleComments` | CommentId | UX_Comments_Accepted (ArticleId) [lọc] | 3NF |  |
| `com.Events` | EventId | (không) | 3NF |  |
| `com.EventRegistrations` | EventId, UserId | (không) | 3NF | Khóa ghép; mọi thuộc tính phụ thuộc toàn bộ khóa |
| `ai.UserPreferences` | UserId | (không) | 3NF | Cột JSON ExtraJson (DN-9) |
| `ai.AIChatLogs` | ChatLogId | (không) | 3NF | Cột JSON SourcesJson (DN-9) |
| `ai.RecommendationLogs` | RecLogId | (không) | 3NF | ItemId không FK có chủ ý (DN-11); cột JSON ContextJson (DN-9) |
| `ai.KnowledgeDocs` | KnowledgeDocId | UX_Knowledge_Chunk (SourceArticleId, ChunkIndex) [lọc] | 3NF | Cột JSON EmbeddingJson (DN-9) |
| `audit.AuditLogs` | AuditLogId | (không) | 3NF | ChangedBy không FK có chủ ý (DN-11); cột JSON OldValues/NewValues (DN-9) |

**Kết quả:** 34/41 bảng đạt 3NF; 7 bảng (`2NF*`) cố ý không đạt 3NF theo DN-1 đến DN-8. Ngoài ra các cột JSON (DN-9) là ngoại lệ **1NF** có chủ ý (10 cột JSON ở 8 bảng), và 2 cột không có FK có chủ ý (DN-11).

## 5. Ví dụ kiểm tra chi tiết

### 5.1. `ord.Orders`

| Thuộc tính | FD | Nhận xét |
|---|---|---|
| `OrderId` | khóa chính | |
| `OrderCode` | khóa ứng viên (UNIQUE) | `OrderCode -> mọi thuộc tính` |
| `CustomerId, LabId, StageId, FulfillmentMethod, ...` | phụ thuộc trực tiếp vào `OrderId` | Đạt 2NF (khóa đơn) |
| `TotalAmount` | `(Subtotal, DeliveryFee) -> TotalAmount` | FD giữa hai nhóm thuộc tính không khóa: **không 3NF**, ngoại lệ DN-2 (chứng từ tài chính) |

### 5.2. `com.EventRegistrations` (khóa ghép)

| Thuộc tính | Phụ thuộc vào | Nhận xét |
|---|---|---|
| `Status`, `IsPaid`, `CancelledAt` | **toàn bộ** (`EventId`, `UserId`): trạng thái đăng ký của *người này* ở *sự kiện này* | Không phụ thuộc một phần nên đạt 2NF |
| Thông tin sự kiện (tên, giờ, địa điểm) | chỉ `EventId` | Đã tách sang `com.Events` để tránh phụ thuộc một phần |

### 5.3. `arc.ScanFiles` và `arc.PhotoMetadata`

Metadata tách thành bảng 1-1 (`PhotoMetadata`, khóa chính = FK tới `ScanFiles`) vì: (1) nhiều file chưa có metadata nên tránh nhiều cột NULL ở bảng chính; (2) hai nhóm thuộc tính có vòng đời khác nhau (file do lab upload, metadata do khách/lab bổ sung sau).

### 5.4. `lab.LabServices`

Khóa ứng viên `(LabId, PackageName)`; `UnitPrice`, `TurnaroundDays`, `ScanQuality` phụ thuộc đầy đủ vào gói của một lab. Đạt 3NF. `ProcessCode` không suy ra từ `ServiceTypeId` (gói Scan dùng `'ANY'`), nên không có FD bắc cầu.

## 6. Kết luận cho báo cáo

- Thiết kế đạt **3NF ở 34/41 bảng**; 7 bảng phi chuẩn hóa có chủ ý, mỗi bảng có lý do nghiệp vụ và cơ chế kiểm soát (FK ghép, trigger, CHECK, procedure).

- Phi chuẩn hóa tập trung vào hai mục đích: **(a) snapshot chứng từ** (giá, phí, tổng tiền không đổi theo thời gian) và **(b) tăng tốc truy vấn đọc nhiều** (rating, chủ ảnh, khóa RLS).
- Mọi phi chuẩn hóa dạng *dẫn xuất* đều có đúng một nơi ghi (procedure hoặc trigger) để tránh dị thường cập nhật.
