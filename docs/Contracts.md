# Contracts: hợp đồng giữa các module (v1.0, đóng băng ở Đợt 4)

> Phần bảng và quan hệ được **sinh tự động** từ `tools/schema_spec.py` và `tools/plan_spec.py` (`python tools/gen_docs.py`).
> **Quy tắc thay đổi:** muốn đổi cột/bảng/chữ ký procedure đã nêu ở đây thì (1) sửa `schema_spec.py` / `plan_spec.py`, (2) chạy lại các script sinh tài liệu, (3) ghi vào mục 10 (Nhật ký thay đổi), (4) báo cả nhóm trong cùng Pull Request.

## 1. Quyết định thiết kế đã chốt

Các quyết định D-01 đến D-15 là **mặc định** của các câu hỏi đã nêu ở Đợt 1, 2, 3. Nhóm phản đối điều nào thì nói **trước khi bắt đầu Đợt 5** (sau đó sửa sẽ tốn công).

| Mã | Quyết định | Nguồn |
|---|---|---|
| D-01 | Hoa hồng nền tảng 10%, trừ vào doanh thu lab; khách trả Subtotal + phí giao | Đợt 1 / Q1 |
| D-02 | Khách được thanh toán từ khi đơn Confirmed; bắt buộc Paid trước Completed | Đợt 1 / Q2 |
| D-03 | Một chủ lab được sở hữu nhiều lab (quan hệ 1-N) | Đợt 1 / Q3 |
| D-04 | Một user có nhiều role (bảng UserRoles N-N) | Đợt 1 / Q4 |
| D-05 | Lưu tọa độ geography cho lab và địa chỉ để tìm lab gần khách | Đợt 1 / Q5 |
| D-06 | Phí giao cố định 25.000 đ mỗi chặng, Admin chỉnh trong FeeConfigs | Đợt 2 / Q1 |
| D-07 | Không giao trả phim khi đơn chưa Paid (BR-DLV-06) | Đợt 2 / Q2 |
| D-08 | Hạn đánh giá và hạn khiếu nại: 30 ngày sau khi đơn Completed | Đợt 2 / Q3 |
| D-09 | Mỗi file scan chỉ 1 StorageUrl (không lưu nhiều phiên bản) | Đợt 2 / Q4 |
| D-10 | Tranh chấp Marketplace xử lý trong mkt.MarketTransactions (Disputed), không dùng ord.Complaints | Đợt 2 / Q5 |
| D-11 | Marketplace không xử lý tiền qua nền tảng; chỉ theo dõi giao dịch và ghi nhận phí | Đợt 3 / Q1 |
| D-12 | Phí Marketplace 5%, người bán chịu, Admin chỉnh trong FeeConfigs | Đợt 3 / Q2 |
| D-13 | Tin đăng hiệu lực 30 ngày; giao dịch Shipped quá 7 ngày không khiếu nại tự Completed | Đợt 3 / Q3 |
| D-14 | Giữ log chat AI 180 ngày | Đợt 3 / Q4 |
| D-15 | Embedding lưu mảng JSON (placeholder), SQL Server 2022 chưa có kiểu vector | Đợt 3 / Q5 |
| D-16 | Module M10 dùng schema audit (sys là schema hệ thống, không dùng được) | Kỹ thuật |
| D-17 | Schema ord tách 2 file ở mỗi tầng: ord.sql (M3) và ord_feedback.sql (M6) để 2 người làm không đụng file nhau | Kỹ thuật |
| D-18 | Enum nhỏ dùng CHECK IN; chỉ giai đoạn đơn (ProcessingStages) dùng bảng danh mục + FK | Kỹ thuật |
| D-19 | Dùng FK ghép (OrderId, CustomerId, LabId) và (ListingId, SellerId) để DB tự bảo đảm khớp | Kỹ thuật |
| D-20 | Full-Text Index tạo trong khối IF SERVERPROPERTY('IsFullTextInstalled') = 1 (image Linux của CI không có Full-Text) | Kỹ thuật |

## 2. Module, file sở hữu và phụ thuộc FK

| Module (unit) | Schema | File ở mỗi tầng `database/<tầng>/` | Bảng | Phụ thuộc FK | Người phụ trách |
|---|---|---|---|---|---|
| M1 Identity & Access | `iam` | `iam.sql` | Users, Roles, UserRoles, Addresses, ExpertProfiles, DeliveryPartners | (gốc) | A |
| M2 Lab & Catalog | `lab` | `lab.sql` | FilmLabs, LabApprovals, FilmFormats, FilmStocks, ServiceTypes, LabServices | `iam` | B |
| M3 Order, Processing, Payment, Fee | `ord` | `ord.sql` | ProcessingStages, Orders, OrderItems, OrderStageLog, Payments, FeeConfigs | `iam`, `lab` | B |
| M6 Review & Complaint | `ord` | `ord_feedback.sql` | Reviews, Complaints | `iam`, `lab` | C |
| M4 Delivery | `dlv` | `dlv.sql` | DeliveryRequests, DeliveryStatusLog | `iam`, `ord` | A |
| M5 Digital Archive | `arc` | `arc.sql` | ScanFiles, PhotoMetadata, Albums, AlbumPhotos, Notifications | `iam`, `lab`, `ord` | C |
| M7 Marketplace | `mkt` | `mkt.sql` | ListingCategories, Listings, ListingImages, MarketTransactions, Messages | `iam` | D |
| M8 Community & Knowledge | `com` | `com.sql` | Articles, ArticleComments, Events, EventRegistrations | `iam`, `lab` | D |
| M9 AI Support | `ai` | `ai.sql` | UserPreferences, AIChatLogs, RecommendationLogs, KnowledgeDocs | `iam`, `lab`, `com` | E |
| M10 System / Audit | `audit` | `audit.sql` | AuditLogs | (không FK, chỉ ghi log) | A |

**Người phụ trách** ghi bằng chữ cái A-E, đối chiếu `docs/Phan-cong.md`.

## 3. Ma trận phụ thuộc FK giữa các schema

Hàng = schema chứa bảng **con** (có FK); cột = schema chứa bảng **cha** (được trỏ tới). Dấu `x` kèm số FK.

| con \ cha | `iam` | `lab` | `ord` | `dlv` | `arc` | `mkt` | `com` | `ai` | `audit` |
|---|---|---|---|---|---|---|---|---|---|
| `iam` |  |  |  |  |  |  |  |  |  |
| `lab` | x2 |  |  |  |  |  |  |  |  |
| `ord` | x7 | x4 |  |  |  |  |  |  |  |
| `dlv` | x3 |  | x1 |  |  |  |  |  |  |
| `arc` | x4 | x1 | x3 |  |  |  |  |  |  |
| `mkt` | x6 |  |  |  |  |  |  |  |  |
| `com` | x5 | x3 |  |  |  |  |  |  |  |
| `ai` | x5 | x1 |  |  |  |  | x1 |  |  |
| `audit` |  |  |  |  |  |  |  |  |  |

Thứ tự dựng module hợp lệ (đã kiểm tra, không có vòng): `iam` -> `lab` -> `ord` -> `dlv` -> `arc` -> `mkt` -> `com` -> `ai` -> `audit`.
Tổng số FK: **77** (liên module **46**, cùng module **31**).

## 4. Phụ thuộc gọi giữa các module (không phải FK)

T-SQL phân giải tên procedure/function **lúc chạy** (deferred name resolution), nên `CREATE OR ALTER` không lỗi dù đối tượng được gọi ở file chạy sau. Chỉ cần đã build đủ trước khi **gọi**.

| Đối tượng gọi | Gọi tới |
|---|---|
| `ord.sp_CreateOrder` | dlv.sp_RequestDelivery, ord.fn_CalcDeliveryFee, lab.fn_LabCapacityLeft |
| `ord.sp_CancelOrder` | dlv.sp_UpdateDeliveryStatus |
| `dlv.sp_UpdateDeliveryStatus` | ord.sp_UpdateOrderStage, arc.sp_CreateNotification |
| `ord.trg_Reviews_UpdateRating` | lab.sp_RecalcLabRating |
| `mkt.sp_PlaceMarketOrder` | mkt.fn_CalcMarketplaceFee (đọc ord.FeeConfigs), arc.sp_CreateNotification |
| `mkt.sp_SendMessage, mkt.sp_UpdateMarketTransaction, com.sp_RegisterEvent, com.sp_CancelEventRegistration` | arc.sp_CreateNotification |
| `ord.trg_Complaints_Notify, arc.trg_ScanFiles_Notify` | arc.sp_CreateNotification |
| `ai.sp_GetLabRecommendations` | ai.fn_LabScores, lab.fn_DistanceKm, đọc ord.Orders, ord.Reviews |
| `Mọi trigger trg_*_Audit` | audit.sp_WriteAudit |

## 5. Thứ tự tạo bảng trong từng module (từ FK cùng module)

Dùng khi viết `01_tables/<module>.sql`. FK liên module **không** tạo ở đây mà ở `02_foreign_keys/`.

| File (`01_tables/<file>.sql`) | Người | Thứ tự `CREATE TABLE` |
|---|---|---|
| `iam.sql` | A | Users -> Roles -> UserRoles -> Addresses -> ExpertProfiles -> DeliveryPartners |
| `lab.sql` | B | FilmLabs -> FilmFormats -> FilmStocks -> ServiceTypes -> LabApprovals -> LabServices |
| `ord.sql` | B | ProcessingStages -> FeeConfigs -> Orders -> OrderItems -> OrderStageLog -> Payments |
| `ord_feedback.sql` | C | Reviews -> Complaints |
| `dlv.sql` | A | DeliveryRequests -> DeliveryStatusLog |
| `arc.sql` | C | ScanFiles -> Notifications -> PhotoMetadata -> Albums -> AlbumPhotos |
| `mkt.sql` | D | ListingCategories -> Listings -> ListingImages -> MarketTransactions -> Messages |
| `com.sql` | D | Articles -> Events -> ArticleComments -> EventRegistrations |
| `ai.sql` | E | UserPreferences -> AIChatLogs -> RecommendationLogs -> KnowledgeDocs |
| `audit.sql` | A | AuditLogs |

Lưu ý: `ord_feedback.sql` chạy **ngay sau** `ord.sql` (FK ghép của `Reviews`, `Complaints` trỏ tới `ord.Orders`).

## 6. Quy ước mã lỗi (`THROW`)

Mã lỗi = **dải của module** + **hậu tố hai chữ số** theo ý nghĩa thống nhất. Thông báo bằng tiếng Việt.

**Dải mã theo module:**

| Dải | Module |
|---|---|
| 50100 | iam |
| 50200 | lab |
| 50300 | ord (gồm review, complaint) |
| 50400 | dlv |
| 50500 | arc |
| 50600 | mkt |
| 50700 | com |
| 50800 | ai |
| 50900 | audit |

**Hậu tố (cộng vào dải):**

| Hậu tố | Ý nghĩa |
|---|---|
| 01 | Không tìm thấy (NotFound) |
| 02 | Sai trạng thái / chuyển trạng thái không hợp lệ |
| 03 | Không có quyền (không phải chủ/Admin) |
| 04 | Trùng / xung đột (Duplicate) |
| 05 | Dữ liệu đầu vào sai (Validation) |
| 06 | Hết năng lực / hết hàng (Capacity) |

Ví dụ: `50302` = module `ord`, sai trạng thái. Mọi procedure ghi dữ liệu đều nhận `@ActorUserId` (hoặc tham số tương đương như `@CustomerId`, `@SellerId`) và gọi `EXEC sp_set_session_context @key = N'UserId', @value = @ActorUserId;` ở đầu để trigger/RLS biết người thực hiện.

## 7. Chữ ký 16 procedure bắt buộc (★)

Đây là **API của database**; web và test chỉ phụ thuộc vào các chữ ký này. Tham số có `=` là tùy chọn.

| # | Procedure | Tham số | Kết quả | Mã lỗi chính | Gọi tới |
|---|---|---|---|---|---|
| 1 | `iam.sp_RegisterUser` | `@Email NVARCHAR(255), @FullName NVARCHAR(100), @PasswordHash NVARCHAR(255)=NULL, @AuthProvider NVARCHAR(20)='Local', @Phone NVARCHAR(20)=NULL, @NewUserId INT OUTPUT` | OUT @NewUserId | 50104 email đã tồn tại; 50105 dữ liệu sai (Local thiếu PasswordHash) | (không) |
| 2 | `lab.sp_ApproveLab` | `@LabId INT, @AdminUserId INT, @Decision NVARCHAR(12), @Reason NVARCHAR(500)=NULL` | Không có (cập nhật FilmLabs.ApprovalStatus, ghi LabApprovals) | 50201 lab không tồn tại; 50202 trạng thái không đổi; 50203 người gọi không phải Admin; 50205 thiếu Reason | (không) |
| 3 | `lab.sp_SearchLabs` | `@Latitude FLOAT=NULL, @Longitude FLOAT=NULL, @MaxDistanceKm DECIMAL(6,2)=NULL, @FormatId INT=NULL, @ServiceTypeId INT=NULL, @MaxPrice DECIMAL(18,0)=NULL, @MaxTurnaroundDays TINYINT=NULL, @MinRating DECIMAL(3,2)=NULL, @Technique NVARCHAR(50)=NULL, @SortBy NVARCHAR(20)='Relevance', @PageNo INT=1, @PageSize INT=20` | Result set: LabId, LabName, City, DistanceKm, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays | 50205 tham số sai (PageNo/PageSize/SortBy) | lab.fn_DistanceKm |
| 4 | `ord.sp_CreateOrder` | `@CustomerId INT, @LabId INT, @FulfillmentMethod NVARCHAR(7), @ReturnMethod NVARCHAR(11), @PickupAddressId INT=NULL, @ReturnAddressId INT=NULL, @ItemsJson NVARCHAR(MAX), @CustomerNote NVARCHAR(500)=NULL, @NewOrderId INT OUTPUT` | OUT @NewOrderId; @ItemsJson = [{labServiceId, filmStockId, quantity, note}] | 50301 khách/lab/dịch vụ không tồn tại; 50302 lab chưa Approved hoặc dịch vụ ngừng bán; 50305 items rỗng/thiếu địa chỉ; 50306 lab hết năng lực | ord.fn_CalcOrderTotal, ord.fn_CalcPlatformFee, ord.fn_CalcDeliveryFee, lab.fn_LabCapacityLeft, dlv.sp_RequestDelivery, arc.sp_CreateNotification |
| 5 | `ord.sp_UpdateOrderStage` | `@OrderId INT, @ActorUserId INT, @NewStageId INT, @Note NVARCHAR(255)=NULL` | Không có (cập nhật Orders.StageId; trigger ghi OrderStageLog) | 50301 đơn không tồn tại; 50302 chuyển giai đoạn không hợp lệ/chưa Paid khi Completed; 50303 không phải lab của đơn hoặc Admin | ord.fn_IsValidTransition, ord.fn_NextStage, arc.sp_CreateNotification |
| 6 | `ord.sp_CancelOrder` | `@OrderId INT, @ActorUserId INT, @Reason NVARCHAR(255)` | Không có (đơn sang Cancelled, hủy chặng giao, hoàn tiền nếu Paid) | 50301 đơn không tồn tại; 50302 đã qua Developing hoặc chặng Pickup đã PickedUp; 50303 không có quyền hủy | dlv.sp_UpdateDeliveryStatus, arc.sp_CreateNotification |
| 7 | `ord.sp_ProcessPayment` | `@OrderId INT, @ActorUserId INT, @Method NVARCHAR(12), @Provider NVARCHAR(30)=NULL, @ProviderTxnId NVARCHAR(100)=NULL, @Amount DECIMAL(18,0), @Succeeded BIT=1, @FailureReason NVARCHAR(255)=NULL, @NewPaymentId INT OUTPUT` | OUT @NewPaymentId (mô phỏng callback của cổng thanh toán) | 50301 đơn không tồn tại; 50302 đơn Pending/Cancelled hoặc đã Paid; 50305 Amount khác TotalAmount | arc.sp_CreateNotification |
| 8 | `ord.sp_AddReview` | `@OrderId INT, @CustomerId INT, @RatingOverall TINYINT, @RatingScanQuality TINYINT=NULL, @RatingSpeed TINYINT=NULL, @Comment NVARCHAR(1000)=NULL, @NewReviewId INT OUTPUT` | OUT @NewReviewId | 50301 đơn không tồn tại; 50302 chưa Completed hoặc quá 30 ngày; 50303 không phải khách của đơn; 50304 đã đánh giá | lab.sp_RecalcLabRating (qua trigger) |
| 9 | `ord.sp_FileComplaint` | `@OrderId INT, @CustomerId INT, @Category NVARCHAR(12), @Title NVARCHAR(150), @Description NVARCHAR(2000), @NewComplaintId INT OUTPUT` | OUT @NewComplaintId | 50301 đơn không tồn tại; 50302 đơn Pending/Cancelled hoặc quá 30 ngày; 50303 không phải khách của đơn; 50304 đã có khiếu nại mở cùng loại | arc.sp_CreateNotification (qua trigger) |
| 10 | `ord.sp_ResolveComplaint` | `@ComplaintId INT, @AdminUserId INT, @Decision NVARCHAR(9), @ResolutionType NVARCHAR(12)=NULL, @Resolution NVARCHAR(1000), @RefundAmount DECIMAL(18,0)=NULL` | Không có (đóng khiếu nại; hoàn tiền toàn bộ thì cập nhật Payments/Orders) | 50301 khiếu nại không tồn tại; 50302 chuyển trạng thái sai; 50303 người gọi không phải Admin; 50305 thiếu Resolution hoặc RefundAmount vượt TotalAmount | arc.sp_CreateNotification (qua trigger) |
| 11 | `dlv.sp_UpdateDeliveryStatus` | `@DeliveryRequestId INT, @ActorUserId INT, @NewStatus NVARCHAR(10), @Note NVARCHAR(255)=NULL, @FailureReason NVARCHAR(255)=NULL` | Không có (đổi trạng thái chặng; có thể đưa đơn sang FilmReceived hoặc Completed) | 50401 chặng không tồn tại; 50402 chuyển trạng thái sai/Return khi đơn chưa Paid; 50403 không phải partner của chặng hoặc lab/Admin; 50405 thiếu FailureReason | ord.sp_UpdateOrderStage, arc.sp_CreateNotification |
| 12 | `arc.sp_UploadScan` | `@OrderId INT, @ActorUserId INT, @FileName NVARCHAR(255), @StorageUrl NVARCHAR(1000), @ContentType NVARCHAR(20), @FileSizeBytes BIGINT, @FrameNumber SMALLINT=NULL, @OrderItemId INT=NULL, @WidthPx INT=NULL, @HeightPx INT=NULL, @ChecksumSha256 CHAR(64)=NULL, @MetadataJson NVARCHAR(MAX)=NULL, @NewScanFileId UNIQUEIDENTIFIER OUTPUT` | OUT @NewScanFileId (tạo ScanFiles + PhotoMetadata trong một Transaction) | 50501 đơn không tồn tại; 50502 đơn không có dịch vụ scan/sai giai đoạn; 50503 không phải lab của đơn hoặc Admin; 50504 trùng tên file; 50505 loại/kích thước file sai | (trigger gọi arc.sp_CreateNotification) |
| 13 | `mkt.sp_CreateListing` | `@SellerId INT, @CategoryId INT, @ListingType NVARCHAR(8), @Title NVARCHAR(200), @Description NVARCHAR(2000)=NULL, @Brand NVARCHAR(50)=NULL, @Model NVARCHAR(100)=NULL, @Condition NVARCHAR(10)=NULL, @Price DECIMAL(18,0)=NULL, @ExchangeWanted NVARCHAR(255)=NULL, @Quantity INT=1, @City NVARCHAR(100), @ImagesJson NVARCHAR(MAX)=NULL, @NewListingId INT OUTPUT` | OUT @NewListingId; @ImagesJson = [{url, isPrimary}] | 50601 danh mục không tồn tại; 50603 người đăng bị khóa; 50605 dữ liệu sai (Sell thiếu Price...) | (không) |
| 14 | `mkt.sp_PlaceMarketOrder` | `@ListingId INT, @BuyerId INT, @Quantity INT, @Note NVARCHAR(500)=NULL, @NewTransactionId INT OUTPUT` | OUT @NewTransactionId (khóa dòng UPDLOCK, HOLDLOCK) | 50601 tin không tồn tại; 50602 tin không Active; 50603 người mua là người bán; 50606 không đủ số lượng | mkt.fn_CalcMarketplaceFee, arc.sp_CreateNotification |
| 15 | `com.sp_RegisterEvent` | `@EventId INT, @UserId INT, @ResultStatus NVARCHAR(10) OUTPUT` | OUT @ResultStatus = 'Registered' hoặc 'Waitlisted' | 50701 sự kiện không tồn tại; 50702 sự kiện không mở đăng ký/quá hạn; 50704 đã đăng ký | com.fn_EventSeatsLeft, arc.sp_CreateNotification |
| 16 | `ai.sp_GetLabRecommendations` | `@UserId INT, @TopN TINYINT=5, @Latitude FLOAT=NULL, @Longitude FLOAT=NULL` | Result set: LabId, LabName, Rank, Score, AvgRating, DistanceKm; ghi RecommendationLogs | 50801 người dùng không tồn tại | ai.fn_LabScores |

## 8. Danh mục đối tượng T-SQL (kế hoạch)

★ = procedure bắt buộc. Tổng: **61 procedure** (16 bắt buộc, 45 mở rộng), **15 function**, **28 trigger**, **14 view**, **2 sequence**.

### `iam`: M1 Identity & Access (người phụ trách A)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `iam.sp_RegisterUser` | Đăng ký tài khoản, tự gán role Customer |
| Procedure | `iam.sp_SaveAddress` | Khách thêm/sửa/xóa mềm địa chỉ nhận/giao phim |
| Procedure | `iam.sp_SetUserStatus` | Admin khóa/mở tài khoản người dùng |
| Procedure | `iam.sp_AssignRole` | Admin gán hoặc gỡ role cho người dùng |
| Procedure | `iam.sp_GetLoginInfo` | Backend lấy hash và role để xác thực đăng nhập (role_Auth) |
| Procedure | `iam.sp_GetMyAddresses` | Khách xem danh sách địa chỉ của mình (SĐT hiện thật) |
| Procedure | `iam.sp_ListUsers` | Admin xem danh sách người dùng, lọc role/trạng thái/từ khóa, có phân trang |
| Trigger | `iam.trg_Users_Audit` (trên `iam.Users`) | Ghi nhật ký thay đổi (loại PasswordHash) |

### `lab`: M2 Lab & Catalog (người phụ trách B)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `lab.sp_ApproveLab` | Admin duyệt/từ chối/đình chỉ Film Lab |
| Procedure ★ | `lab.sp_SearchLabs` | Tìm và so sánh lab theo vị trí, định dạng, giá, thời gian, rating |
| Procedure | `lab.sp_RecalcLabRating` | Tính lại AvgRating/ReviewCount của lab (được trigger Reviews gọi) |
| Procedure | `lab.sp_SaveLabProfile` | Chủ lab tạo/sửa hồ sơ lab (lab mới ở trạng thái Pending) |
| Procedure | `lab.sp_SaveLabService` | Chủ lab tạo/sửa/ẩn/xóa mềm gói dịch vụ và giá |
| Procedure | `lab.sp_GetLabDetail` | Chi tiết lab đã duyệt và các gói dịch vụ đang bán |
| Procedure | `lab.sp_GetMyLabs` | Chủ lab xem lab của mình (mọi trạng thái duyệt) và gói dịch vụ |
| Procedure | `lab.sp_GetReferenceData` | Danh mục khổ phim, loại dịch vụ, stage cho form và bộ lọc |
| Procedure | `lab.sp_ListLabsForApproval` | Admin xem lab theo trạng thái duyệt (mặc định Pending), có phân trang |
| Function | `lab.fn_LabCapacityLeft` | Số cuộn còn nhận được trong ngày của lab |
| Function | `lab.fn_DistanceKm` | Khoảng cách km giữa hai điểm geography |
| Trigger | `lab.trg_LabServices_CheckScan` (trên `lab.LabServices`) | Gói Scan phải có ScanQuality, gói khác phải NULL |
| Trigger | `lab.trg_FilmLabs_Audit` (trên `lab.FilmLabs`) | Ghi nhật ký thay đổi |
| View | `lab.vw_TopLabs` | Lab xếp hạng cao |

### `ord`: M3 Order, Processing, Payment, Fee (người phụ trách B)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `ord.sp_CreateOrder` | Tạo đơn trong một Transaction, tạo các chặng giao |
| Procedure ★ | `ord.sp_UpdateOrderStage` | Đổi giai đoạn xử lý đơn (kiểm tra thứ tự hợp lệ) |
| Procedure ★ | `ord.sp_CancelOrder` | Hủy đơn, hủy chặng giao, hoàn tiền nếu đã thanh toán |
| Procedure ★ | `ord.sp_ProcessPayment` | Ghi nhận thanh toán online của đơn |
| Procedure | `ord.sp_SetFeeConfig` | Admin cấu hình phí nền tảng, Marketplace, giao hàng |
| Procedure | `ord.sp_GetMyOrders` | Danh sách đơn của khách hoặc của lab, có lọc stage và phân trang |
| Procedure | `ord.sp_GetOrderDetail` | Chi tiết đơn: item, timeline stage, thanh toán, giao nhận |
| Function | `ord.fn_CalcOrderTotal` | Tính Subtotal, Total của đơn |
| Function | `ord.fn_CalcPlatformFee` | Tính hoa hồng nền tảng hiệu lực |
| Function | `ord.fn_NextStage` | Giai đoạn kế tiếp áp dụng cho đơn |
| Function | `ord.fn_IsValidTransition` | Kiểm tra chuyển giai đoạn hợp lệ |
| Function | `ord.fn_CalcDeliveryFee` | Phí giao mỗi chặng |
| Trigger | `ord.trg_Orders_LogStage` (trên `ord.Orders`) | Ghi OrderStageLog khi đổi StageId |
| Trigger | `ord.trg_Orders_PreventInvalidStage` (trên `ord.Orders`) | Chặn chuyển giai đoạn sai thứ tự |
| Trigger | `ord.trg_Payments_UpdateOrder` (trên `ord.Payments`) | Cập nhật PaymentStatus của đơn |
| Trigger | `ord.trg_FeeConfigs_NoOverlap` (trên `ord.FeeConfigs`) | Không chồng khoảng hiệu lực |
| Trigger | `ord.trg_Payments_Audit` (trên `ord.Payments`) | Ghi nhật ký thay đổi |
| View | `ord.vw_LabRevenue` | Doanh thu theo lab |
| View | `ord.vw_OrdersInProgress` | Đơn đang xử lý |
| Sequence | `ord.seq_OrderCode` | Sinh mã tự động |

### `ord_feedback`: M6 Review & Complaint (người phụ trách C)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `ord.sp_AddReview` | Khách đánh giá lab sau khi đơn hoàn tất |
| Procedure ★ | `ord.sp_FileComplaint` | Khách khiếu nại về đơn |
| Procedure ★ | `ord.sp_ResolveComplaint` | Admin giải quyết khiếu nại (có thể hoàn tiền) |
| Procedure | `ord.sp_ReplyReview` | Lab trả lời đánh giá (1 lần) |
| Procedure | `ord.sp_ModerateReview` | Admin ẩn/hiện đánh giá |
| Function | `ord.fn_LabAvgRating` | Điểm trung bình lab từ review hiển thị |
| Function | `ord.fn_IsValidComplaintTransition` | Kiểm tra chuyển trạng thái khiếu nại |
| Trigger | `ord.trg_Reviews_CheckEligible` (trên `ord.Reviews`) | Chỉ đơn Completed, trong 30 ngày |
| Trigger | `ord.trg_Reviews_UpdateRating` (trên `ord.Reviews`) | Gọi lab.sp_RecalcLabRating |
| Trigger | `ord.trg_Complaints_Guard` (trên `ord.Complaints`) | Chuyển trạng thái khiếu nại hợp lệ |
| Trigger | `ord.trg_Complaints_Notify` (trên `ord.Complaints`) | Thông báo khi tạo/đổi trạng thái |
| Trigger | `ord.trg_Complaints_Audit` (trên `ord.Complaints`) | Ghi nhật ký thay đổi |
| View | `ord.vw_LabReviews` | Đánh giá của lab |
| View | `ord.vw_OpenComplaints` | Hàng đợi khiếu nại của Admin |

### `dlv`: M4 Delivery (người phụ trách A)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `dlv.sp_UpdateDeliveryStatus` | Đổi trạng thái chặng giao, đồng bộ giai đoạn đơn |
| Procedure | `dlv.sp_RequestDelivery` | Tạo chặng giao (được sp_CreateOrder gọi) |
| Procedure | `dlv.sp_AssignPartner` | Phân công đối tác giao nhận |
| Function | `dlv.fn_IsValidDeliveryTransition` | Kiểm tra chuyển trạng thái chặng giao |
| Trigger | `dlv.trg_DeliveryRequests_LogStatus` (trên `dlv.DeliveryRequests`) | Ghi DeliveryStatusLog, đặt PickedUpAt/DeliveredAt |
| Trigger | `dlv.trg_DeliveryRequests_Guard` (trên `dlv.DeliveryRequests`) | Chặn chuyển trạng thái sai |
| View | `dlv.vw_DeliveryBoard` | Bảng việc của shipper |

### `arc`: M5 Digital Archive (người phụ trách C)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `arc.sp_UploadScan` | Lab upload file scan kèm metadata |
| Procedure | `arc.sp_SetScanQuality` | Model AI ghi điểm chất lượng scan |
| Procedure | `arc.sp_CreateNotification` | Điểm tạo thông báo duy nhất cho mọi module |
| Procedure | `arc.sp_MarkNotificationRead` | Đánh dấu đã đọc thông báo |
| Procedure | `arc.sp_SaveAlbum` | Khách tạo/sửa/xóa mềm album trong Digital Film Archive |
| Procedure | `arc.sp_SetAlbumPhoto` | Khách thêm/gỡ ảnh khỏi album |
| Function | `arc.fn_GetPhotoMetadata` | Table-valued: đọc ExtraJson bằng OPENJSON |
| Trigger | `arc.trg_ScanFiles_Notify` (trên `arc.ScanFiles`) | Thông báo ScanReady lần upload đầu của đơn |
| Trigger | `arc.trg_ScanFiles_CheckOwner` (trên `arc.ScanFiles`) | OwnerUserId = Orders.CustomerId |
| Trigger | `arc.trg_AlbumPhotos_CheckOwner` (trên `arc.AlbumPhotos`) | Ảnh trong album phải cùng chủ |
| View | `arc.vw_CustomerArchive` | Digital Film Archive của khách |

### `mkt`: M7 Marketplace (người phụ trách D)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `mkt.sp_CreateListing` | Đăng tin mua/bán/trao đổi kèm ảnh |
| Procedure ★ | `mkt.sp_PlaceMarketOrder` | Đặt mua có khóa dòng, chống bán lố |
| Procedure | `mkt.sp_SearchListings` | Tìm tin nâng cao (Full-Text, lọc giá/danh mục) |
| Procedure | `mkt.sp_UpdateMarketTransaction` | Xác nhận/gửi hàng/hoàn tất/hủy/khiếu nại giao dịch |
| Procedure | `mkt.sp_ResolveDispute` | Admin giải quyết tranh chấp giao dịch |
| Procedure | `mkt.sp_RateSeller` | Người mua đánh giá người bán |
| Procedure | `mkt.sp_SendMessage` | Gửi tin nhắn mua bán |
| Procedure | `mkt.sp_ModerateListing` | Admin gỡ tin vi phạm |
| Procedure | `mkt.sp_RunMaintenance` | Đóng tin hết hạn, tự hoàn tất giao dịch quá 7 ngày |
| Function | `mkt.fn_CalcMarketplaceFee` | Phí Marketplace hiệu lực |
| Function | `mkt.fn_SellerRating` | Điểm trung bình người bán |
| Trigger | `mkt.trg_Listings_Guard` (trên `mkt.Listings`) | Chặn đổi trạng thái/số lượng sai |
| Trigger | `mkt.trg_ListingImages_Limit` (trên `mkt.ListingImages`) | Tối đa 8 ảnh |
| Trigger | `mkt.trg_MarketTransactions_Guard` (trên `mkt.MarketTransactions`) | Chuyển trạng thái giao dịch hợp lệ |
| Trigger | `mkt.trg_Messages_CheckParties` (trên `mkt.Messages`) | Một bên phải là người bán của tin |
| Trigger | `mkt.trg_Listings_Audit` (trên `mkt.Listings`) | Ghi nhật ký thay đổi |
| Trigger | `mkt.trg_MarketTransactions_Audit` (trên `mkt.MarketTransactions`) | Ghi nhật ký thay đổi |
| View | `mkt.vw_MarketActive` | Tin đang bán |
| View | `mkt.vw_SellerStats` | Thống kê người bán |
| Sequence | `mkt.seq_TransactionCode` | Sinh mã tự động |

### `com`: M8 Community & Knowledge (người phụ trách D)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `com.sp_RegisterEvent` | Đăng ký sự kiện (Registered hoặc Waitlisted) |
| Procedure | `com.sp_PublishArticle` | Xuất bản bài viết |
| Procedure | `com.sp_ModerateArticle` | Admin ẩn/hiện bài |
| Procedure | `com.sp_AddComment` | Thêm bình luận (1 cấp trả lời) |
| Procedure | `com.sp_AcceptAnswer` | Chọn câu trả lời cho bài Question |
| Procedure | `com.sp_CancelEventRegistration` | Hủy đăng ký, đẩy người hàng chờ lên |
| Procedure | `com.sp_SaveEvent` | Expert/Chủ lab tạo và sửa workshop, photowalk |
| Function | `com.fn_EventSeatsLeft` | Số chỗ còn lại của sự kiện |
| Trigger | `com.trg_Articles_CheckAuthorRole` (trên `com.Articles`) | Loại bài vs role tác giả |
| Trigger | `com.trg_ArticleComments_CheckLevel` (trên `com.ArticleComments`) | Chỉ 1 cấp trả lời |
| Trigger | `com.trg_EventRegistrations_CheckSeats` (trên `com.EventRegistrations`) | Chặn vượt sức chứa |
| View | `com.vw_ExpertContributions` | Đóng góp của chuyên gia |
| View | `com.vw_UpcomingEvents` | Sự kiện sắp tới |

### `ai`: M9 AI Support (người phụ trách E)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure ★ | `ai.sp_GetLabRecommendations` | Gợi ý lab theo công thức điểm, ghi RecommendationLogs |
| Procedure | `ai.sp_SaveUserPreferences` | Lưu sở thích người dùng |
| Procedure | `ai.sp_LogChatMessage` | Ghi một lượt hội thoại AI |
| Procedure | `ai.sp_RecordRecommendationAction` | Ghi phản ứng của người dùng với gợi ý |
| Procedure | `ai.sp_ApproveKnowledgeDoc` | Admin duyệt chunk tri thức |
| Procedure | `ai.sp_PurgeOldLogs` | Dọn log chat quá 180 ngày |
| Procedure | `ai.sp_SearchKnowledge` | Tìm chunk tri thức đã duyệt (Full-Text, fallback LIKE) cho chatbot RAG |
| Function | `ai.fn_LabScores` | Inline table-valued: điểm gợi ý lab |
| Trigger | `ai.trg_KnowledgeDocs_Guard` (trên `ai.KnowledgeDocs`) | Chỉ Expert đóng góp, Admin duyệt |
| View | `ai.vw_RecommendationMetrics` | CTR, tỷ lệ đặt đơn theo ModelVersion |

### `audit`: M10 System / Audit (người phụ trách A)

| Loại | Tên | Mục đích |
|---|---|---|
| Procedure | `audit.sp_WriteAudit` | Điểm ghi nhật ký duy nhất cho mọi trigger audit |
| View | `audit.vw_RecentChanges` | Thay đổi gần đây |
| View | `audit.vw_AdminDashboard` | Dashboard tổng hợp toàn nền tảng |

## 9. Danh sách FK (tên theo quy ước, dùng khi viết 02_foreign_keys)

Danh sách đầy đủ 77 FK (kèm bảng cha/cột, bản số, tầng tạo) nằm ở `docs/DataDictionary.xlsx`, sheet `Relationships`. Tên FK: `FK_<Bảng con>_<Bảng cha>`, trùng thì thêm `_<Cột>`.

| Schema (con) | FK liên module (tạo ở `02_foreign_keys/<file>.sql`) |
|---|---|
| `lab` | `FK_FilmLabs_Users`, `FK_LabApprovals_Users` |
| `ord` | `FK_Orders_Users`, `FK_Orders_FilmLabs`, `FK_Orders_Addresses_PickupAddressId`, `FK_Orders_Addresses_ReturnAddressId`, `FK_OrderItems_LabServices`, `FK_OrderItems_FilmStocks`, `FK_OrderStageLog_Users`, `FK_FeeConfigs_FilmLabs`, `FK_FeeConfigs_Users`, `FK_Reviews_Users`, `FK_Complaints_Users` |
| `dlv` | `FK_DeliveryRequests_Orders`, `FK_DeliveryRequests_Addresses`, `FK_DeliveryRequests_DeliveryPartners`, `FK_DeliveryStatusLog_Users` |
| `arc` | `FK_ScanFiles_Orders`, `FK_ScanFiles_OrderItems`, `FK_ScanFiles_Users_OwnerUserId`, `FK_ScanFiles_Users_UploadedBy`, `FK_PhotoMetadata_FilmStocks`, `FK_Albums_Users`, `FK_Notifications_Users`, `FK_Notifications_Orders` |
| `mkt` | `FK_Listings_Users_SellerId`, `FK_Listings_Users_ModeratedBy`, `FK_MarketTransactions_Users_BuyerId`, `FK_MarketTransactions_Users_ResolvedBy`, `FK_Messages_Users_SenderId`, `FK_Messages_Users_ReceiverId` |
| `com` | `FK_Articles_Users_AuthorId`, `FK_Articles_FilmLabs`, `FK_Articles_FilmStocks`, `FK_Articles_Users_ModeratedBy`, `FK_ArticleComments_Users`, `FK_Events_Users`, `FK_Events_FilmLabs`, `FK_EventRegistrations_Users` |
| `ai` | `FK_UserPreferences_Users`, `FK_UserPreferences_FilmFormats`, `FK_AIChatLogs_Users`, `FK_RecommendationLogs_Users`, `FK_KnowledgeDocs_Articles`, `FK_KnowledgeDocs_Users_ContributedBy`, `FK_KnowledgeDocs_Users_ApprovedBy` |

## 10. Nhật ký thay đổi hợp đồng

| Phiên bản | Ngày | Người đổi | Thay đổi | Ảnh hưởng |
|---|---|---|---|---|
| 1.0 | (Đợt 4) | Nhóm | Đóng băng thiết kế: 41 bảng, 77 FK, 42 procedure | Toàn bộ |
| 1.1 | Đợt 6 | Nhóm | Nhóm 0-4. Chữ ký mới: audit.sp_WriteAudit(@TableSchema,@TableName,@PrimaryKeyValue,@Action,@OldValues,@NewValues,@ChangedBy); arc.sp_CreateNotification(@UserId,@Type,@Title,@Body,@OrderId,@NewNotificationId OUT); dlv.sp_RequestDelivery(@OrderId,@Direction,@CustomerAddressId,@Fee,@NewDeliveryRequestId OUT); dlv.sp_AssignPartner(@DeliveryRequestId,@ActorUserId,@DeliveryPartnerId). Function mới: ord.fn_NextStage(@OrderId,@FromStageId), ord.fn_IsValidTransition(@OrderId,@FromStageId,@ToStageId), ord.fn_CalcOrderTotal(@Subtotal,@DeliveryFee), ord.fn_CalcPlatformFee(@LabId,@Subtotal,@OnDate), ord.fn_CalcDeliveryFee(@LabId,@OnDate), lab.fn_DistanceKm(@From,@To), lab.fn_LabCapacityLeft(@LabId,@OnDate), dlv.fn_IsValidDeliveryTransition(@From,@To), ord.fn_IsValidComplaintTransition(@From,@To) (function thứ 15, ngoài kế hoạch 14). Thêm @CallerAuthorized BIT=0 cho ord.sp_UpdateOrderStage và dlv.sp_UpdateDeliveryStatus. sp_AddReview gửi thêm thông báo cho chủ lab; sp_ApproveLab không gửi thông báo. ord.seq_OrderCode START 7. lab.vw_TopLabs cột (RankNo, LabId, LabName, City, District, AvgRating, ReviewCount, MinPrice, MinTurnaroundDays) | iam, lab, ord, dlv, arc, audit |
| 1.2 | Đợt 6 | Nhóm | Nhóm 5 Archive. arc.sp_SetScanQuality(@ScanFileId,@ActorUserId,@QualityScore,@QualityStatus=NULL) (NULL thì tự suy: >=70 Passed, >=50 Warning, <50 Failed); arc.sp_MarkNotificationRead(@NotificationId,@UserId) (idempotent); arc.fn_GetPhotoMetadata(@ScanFileId) trả ScanFileId, MetaKey, MetaValue, JsonType. sp_UploadScan: chỉ StageId 8-10 và đơn có dịch vụ Category='Scan'; quyền = chủ lab của đơn hoặc Admin; thứ tự lỗi 50501, 50503, 50505, 50502, 50504; metadata JSON tách 8 khóa chuẩn (filmStockId, cameraModel, lensModel, shootingDate, exposedIso, processMethod, scannerModel, scanResolutionDpi), khóa còn lại vào ExtraJson. trg_ScanFiles_CheckOwner lỗi 50505; trg_AlbumPhotos_CheckOwner lỗi 50503; trg_ScanFiles_Notify chỉ báo ScanReady ở lần upload đầu của đơn. arc.vw_CustomerArchive cột: OwnerUserId, ScanFileId, OrderId, OrderCode, LabId, LabName, OrderItemId, FrameNumber, FileName, StorageUrl, ContentType, FileSizeBytes, WidthPx, HeightPx, QualityScore, QualityStatus, UploadedAt, FilmStockId, FilmBrand, FilmStockName, CameraModel, LensModel, ShootingDate, ExposedIso, ProcessMethod, ScannerModel, ScanResolutionDpi, AlbumCount | arc |
| 1.3 | Đợt 6 | Nhóm | Nhóm 6 Marketplace. mkt.fn_CalcMarketplaceFee(@Amount,@OnDate) (FeeConfigs MarketplaceFee toàn hệ thống, mặc định 5%, không vượt Amount); mkt.fn_SellerRating(@SellerId) DECIMAL(3,2), NULL nếu chưa có đánh giá; mkt.seq_TransactionCode START 5 (tạo có điều kiện trong 05_functions/mkt.sql). mkt.sp_SearchListings(@Keyword,@CategoryId,@ListingType,@Condition,@MinPrice,@MaxPrice,@City,@SortBy='Newest'/'PriceAsc'/'PriceDesc',@PageNo,@PageSize) trả cột vw_MarketActive + TotalRows (Full-Text nếu có index, không thì LIKE). mkt.sp_UpdateMarketTransaction(@TransactionId,@ActorUserId,@NewStatus,@Reason=NULL): Pending->Confirmed/Cancelled, Confirmed->Shipped/Cancelled, Shipped->Completed/Disputed; Confirmed/Shipped do người bán, Completed/Disputed do người mua, Cancelled cả hai kèm lý do <=255; hủy hoàn Quantity, tin Reserved về Active; Completed hết hàng và không còn giao dịch mở thì tin Sold. mkt.sp_ResolveDispute(@TransactionId,@AdminUserId,@Decision 'Completed'/'Cancelled',@Resolution); mkt.sp_RateSeller(@TransactionId,@BuyerId,@Rating,@Comment=NULL) (50604 nếu đã đánh giá); mkt.sp_SendMessage(@ListingId,@SenderId,@ReceiverId,@Body,@NewMessageId OUT); mkt.sp_ModerateListing(@ListingId,@AdminUserId,@Reason); mkt.sp_RunMaintenance(@ActorUserId=NULL,@ClosedListings OUT,@AutoCompleted OUT) (NULL = job hệ thống, có giá trị thì phải Admin; đóng tin Active hết hạn; tự Completed Shipped quá 7 ngày). sp_PlaceMarketOrder trừ Quantity ngay lúc đặt, về 0 thì tin Reserved; tin Wanted không đặt mua được (50605). Trạng thái tin: Active->Reserved/Sold/Closed/Removed, Reserved->Active/Sold/Closed/Removed, Sold/Closed/Removed là cuối (trg_Listings_Guard: sai chuyển 50602; đổi Quantity khi trạng thái cuối hoặc Active với Quantity 0 là 50605). trg_ListingImages_Limit tối đa 8 ảnh (50605). trg_MarketTransactions_Guard: chuyển sai 50602, sửa ListingId/SellerId/BuyerId/Quantity/UnitPrice/PlatformFee 50605 (cho phép Disputed->Completed/Cancelled). trg_Messages_CheckParties 50603. Trigger audit chỉ ghi UPDATE. vw_MarketActive cột: ListingId, SellerId, SellerName, SellerRating, CategoryId, CategoryName, ListingType, Title, Brand, Model, Condition, Price, ExchangeWanted, Quantity, City, PrimaryImageUrl, ExpiresAt, CreatedAt. vw_SellerStats cột: SellerId, SellerName, TotalListings, ActiveListings, TotalTransactions, CompletedTransactions, CancelledTransactions, DisputedTransactions, CompletedRevenue, PlatformFeeTotal, AvgRating, RatingCount | mkt |
| 1.4 | Đợt 6 | Nhóm | Nhóm 7a Community (lỗi dải 507xx). com.fn_EventSeatsLeft(@EventId): Capacity trừ số đăng ký Registered và Attended, tối thiểu 0; NULL nếu sự kiện không tồn tại. sp_RegisterEvent(@EventId,@UserId,@ResultStatus OUT 'Registered'/'Waitlisted'): khóa dòng Event bằng UPDLOCK/HOLDLOCK; mở đăng ký khi Status='Open' và trước ISNULL(RegistrationDeadline, StartAt) (sai là 50702); trùng là 50704; đăng ký lại sau Cancelled dùng lại dòng cũ và đặt lại CreatedAt; Fee>0 vẫn cho đăng ký (IsPaid=0); gửi thông báo Event. sp_CancelEventRegistration(@EventId,@UserId,@PromotedUserId OUT): chưa đăng ký là 50701; đã Cancelled/Attended hoặc sự kiện Completed là 50702; hủy người Registered thì đẩy người đầu hàng chờ (theo CreatedAt, UserId) lên và gửi thông báo Event. sp_PublishArticle(@AuthorId,@ArticleType,@Title,@Summary=NULL,@Body,@Tags=NULL,@RelatedLabId=NULL,@RelatedStockId=NULL,@Slug=NULL,@NewArticleId OUT): đăng thẳng Published; @Slug NULL tự sinh bai-viet-<guid>; trùng slug 50704; Tags không phải JSON 50705. sp_ModerateArticle(@ArticleId,@AdminUserId,@Action 'Hide'/'Show',@Reason=NULL): Hide bắt buộc Reason (50705); không phải Admin 50703; sai trạng thái 50702. sp_AddComment(@ArticleId,@UserId,@Body,@ParentCommentId=NULL,@NewCommentId OUT): chỉ bình luận bài Published (50702). sp_AcceptAnswer(@CommentId,@UserId): chỉ bài Question (50702), chỉ tác giả bài (50703), chỉ bình luận cấp 1 (50705); chỉ giữ 1 câu được chọn. trg_Articles_CheckAuthorRole: Tutorial/Technical/LabGuide chỉ Expert hoặc Admin (50703). trg_ArticleComments_CheckLevel: trả lời 1 cấp, cùng bài (50705). trg_EventRegistrations_CheckSeats: vượt sức chứa 50706. View: vw_UpcomingEvents, vw_ExpertContributions (cột xem file 06_views/com.sql) | com |
| 1.5 | Đợt 6 | Nhóm | Nhóm 7b AI (lỗi dải 508xx: 01 notfound, 02 sai trạng thái, 03 không quyền, 05 dữ liệu sai). ai.fn_LabScores(@UserId,@Latitude,@Longitude) inline TVF, cột: LabId, LabName, AvgRating, ReviewCount, DistanceKm, MinPrice, MinTurnaroundDays, RatingScore, DistanceScore, PriceScore, SpeedScore, HistoryScore, Score. Score = 0.35 Rating + 0.25 Distance + 0.20 Price + 0.10 Speed + 0.10 History. Rating = (n*AvgRating + 5*C)/(n+5) rồi chia 5 (C là trung bình toàn hệ thống, mặc định 3.0). Distance = 1 - km/MaxDist (MaxDist = MaxDistanceKm của user, mặc định 30; không xác định gốc thì 0.5; dùng lab.fn_DistanceKm). Price, Speed: min-max trên lab ứng viên; giá chỉ xét PreferredFormatId nếu có; vượt MaxBudgetPerRoll thì điểm giá 0. History: đơn Completed (StageId=12) tại lab: 0 đơn là 0, 1 đơn là 0.5, từ 2 đơn là 1; user từng đánh giá lab <=2 sao thì 0. PrioritizeQuality/PrioritizeSpeed chỉ lưu, chưa dùng. sp_GetLabRecommendations(@UserId,@TopN=5,@Latitude=NULL,@Longitude=NULL): @TopN 1-20 (50805); phải truyền đủ cặp tọa độ (50805); user không tồn tại 50801; ghi ai.RecommendationLogs với ModelVersion='tsql-v1'; trả LabId, LabName, [Rank], Score, AvgRating, DistanceKm. sp_SaveUserPreferences(@UserId,@PreferredFormatId,@PreferredFilmType,@PreferredCity,@MaxDistanceKm,@MaxBudgetPerRoll,@PrioritizeQuality=0,@PrioritizeSpeed=0,@Source='UserSet',@ExtraJson): upsert, ghi đè toàn bộ. sp_LogChatMessage(@UserId,@SessionId,@Role,@Message,@ModelName,@PromptTokens,@CompletionTokens,@LatencyMs,@SourcesJson,@NewChatLogId OUT): Assistant bắt buộc ModelName (50805). sp_RecordRecommendationAction(@RecLogId,@UserId,@Action 'Clicked'/'Ordered'/'Dismissed'): log của người khác 50803; Ordered là trạng thái cuối (50802). sp_ApproveKnowledgeDoc(@KnowledgeDocId,@AdminUserId,@Approve=1): 0 là bỏ duyệt; không đổi trạng thái 50802. sp_PurgeOldLogs(@ActorUserId=NULL,@RetentionDays=180,@DeletedCount OUT): NULL là job hệ thống, có giá trị thì phải Admin (50803); RetentionDays<1 là 50805. trg_KnowledgeDocs_Guard: chỉ Expert đóng góp, chỉ Admin duyệt (50803). vw_RecommendationMetrics cột: ModelVersion, RecommendationType, Impressions, Clicked, Ordered, Dismissed, CtrRate, OrderRate, AvgScore, FirstAt, LastAt | ai |
| 1.6 | Đợt 6 | Nhóm | Nhóm 8 Feedback và Audit (lỗi dải 503xx). ord.fn_LabAvgRating(@LabId) DECIMAL(3,2): trung bình RatingOverall của review IsVisible=1 và IsDeleted=0, NULL nếu chưa có. ord.sp_ReplyReview(@ReviewId,@LabOwnerId,@Reply): chỉ chủ lab của review; thứ tự lỗi 50301, 50303, 50305 (Reply rỗng), 50302 (review đang ẩn), 50304 (đã trả lời); thông báo Review cho khách. ord.sp_ModerateReview(@ReviewId,@AdminUserId,@Action 'Hide'/'Show',@Reason=NULL): thứ tự lỗi 50301, 50303, 50305 (Action sai hoặc Hide thiếu Reason), 50302 (không đổi trạng thái); gọi lab.sp_RecalcLabRating, thông báo cho khách. ord.trg_FeeConfigs_NoOverlap: chồng khoảng hiệu lực cùng (FeeType, ScopeLabId; NULL là một phạm vi) là 50304. ord.trg_Payments_Audit và iam.trg_Users_Audit: chỉ ghi UPDATE khi cột nghiệp vụ đổi; Users không ghi PasswordHash, chỉ cờ PasswordChanged ở NewValues, đổi LastLoginAt không ghi. View: ord.vw_LabRevenue (doanh thu chỉ tính đơn Completed và Paid), ord.vw_OrdersInProgress (StageId 2-11), ord.vw_LabReviews (gồm review ẩn), ord.vw_OpenComplaints (Open/InReview), dlv.vw_DeliveryBoard (chặng Requested/Assigned/PickedUp), audit.vw_RecentChanges (30 ngày), audit.vw_AdminDashboard (1 dòng tổng hợp); cột xem file 06_views | ord, iam, dlv, audit |
| 1.7 | Đợt 6 | Nhóm | Chốt Đợt 6: 42 procedure, 15 function, 14 view, 28 trigger, 2 sequence (khớp mục 8 cộng ord.fn_IsValidComplaintTransition); 41 bảng, 77 FK; tests/02-16 đạt 355 PASS (15_inventory_check đối chiếu danh mục, 16_integration_test chạy xuyên module) | Toàn bộ |
| 1.8 | Đợt 8 | Nhóm | Bổ sung 9 procedure quản trị cho web (tổng 51 procedure, 15 function). Thứ tự lỗi: không tồn tại, quyền, trạng thái, dữ liệu. iam.sp_SaveAddress(@UserId,@RecipientName,@Phone,@Line1,@Ward,@District,@City,@AddressId=NULL,@Label=NULL,@Latitude=NULL,@Longitude=NULL,@IsDefault=0,@IsDeleted=0,@NewAddressId OUT): 50101 user/địa chỉ không tồn tại, 50103 địa chỉ của người khác, 50105 dữ liệu sai; địa chỉ đầu tiên tự là mặc định. iam.sp_SetUserStatus(@AdminUserId,@UserId,@IsActive): 50101, 50102 trạng thái không đổi, 50103 không phải Admin, 50105 tự khóa mình. iam.sp_AssignRole(@AdminUserId,@UserId,@RoleCode,@Action 'Add'/'Remove'): 50101, 50102 đã có/chưa có role, 50103, 50105 (RoleCode/Action sai, gỡ role cuối, Admin tự gỡ Admin). lab.sp_SaveLabProfile(@OwnerUserId,@LabName,@AddressLine,@Ward,@District,@City,@LabId=NULL,@Description=NULL,@Latitude=NULL,@Longitude=NULL,@Phone=NULL,@Email=NULL,@OpenHoursJson=NULL,@SpecialTechniques=NULL,@DailyCapacityRolls=50,@NewLabId OUT): lab mới luôn Pending, sửa không đổi ApprovalStatus; 50201, 50203 (không phải LabOwner hoặc không phải chủ lab), 50205. lab.sp_SaveLabService(@OwnerUserId,@LabId,@ServiceTypeId,@FormatId,@PackageName,@UnitPrice,@TurnaroundDays,@LabServiceId=NULL,@ProcessCode='ANY',@Description=NULL,@PriceUnit='Roll',@ScanQuality=NULL,@IsActive=1,@IsDeleted=0,@NewLabServiceId OUT): 50201, 50203, 50205 (kể cả trùng tên gói). ord.sp_SetFeeConfig(@AdminUserId,@FeeType,@EffectiveFrom,@Rate=NULL,@FixedAmount=NULL,@EffectiveTo=NULL,@ScopeLabId=NULL,@NewFeeConfigId OUT): tự đóng bản đang mở cùng loại và phạm vi (EffectiveTo = EffectiveFrom - 1); 50301, 50303, 50304 chồng hiệu lực, 50305. arc.sp_SaveAlbum(@OwnerUserId,@Title,@AlbumId=NULL,@Description=NULL,@IsPublic=0,@CoverScanFileId=NULL,@IsDeleted=0,@NewAlbumId OUT): 50501, 50503, 50505. arc.sp_SetAlbumPhoto(@OwnerUserId,@AlbumId,@ScanFileId,@Action 'Add'/'Remove',@SortOrder=0): idempotent; 50501, 50503, 50505. com.sp_SaveEvent(@OrganizerId,@EventType,@Title,@VenueName,@AddressLine,@City,@StartAt,@EndAt,@Capacity,@EventId=NULL,@Description=NULL,@RegistrationDeadline=NULL,@Latitude=NULL,@Longitude=NULL,@Fee=0,@HostLabId=NULL,@Status='Draft',@NewEventId OUT): Status chỉ Draft/Open/Closed, không đưa sự kiện đã công bố về Draft; 50701, 50702, 50703 (Expert/LabOwner/Admin, chủ sự kiện), 50705. Role: Customer + SaveAddress/SaveAlbum/SetAlbumPhoto; LabOwner + SaveLabProfile/SaveLabService/SaveEvent; Expert + SaveEvent; Admin có sẵn theo schema | iam, lab, ord, arc, com |
| 1.9 | Đợt 8a | Nhóm | Bổ sung 6 procedure đọc và role_Auth cho web (tổng 57 procedure, 15 function). iam.sp_GetLoginInfo(@Email): 1 dòng UserId, FullName, AuthProvider, PasswordHash, IsActive, Roles (CSV RoleCode); không thấy email thì trả rỗng, backend trả 401 chung; 50105 email rỗng. iam.sp_GetMyAddresses(@UserId): AddressId, Label, RecipientName, Phone (hiện thật nhờ UNMASK cột Addresses.Phone cho role_Customer), Line1, Ward, District, City, IsDefault; 50101. lab.sp_GetLabDetail(@LabId): 2 result set (lab Approved; gói dịch vụ đang bán); 50201 nếu không có hoặc chưa duyệt. lab.sp_GetMyLabs(@OwnerUserId): 2 result set (lab mọi trạng thái kèm quyết định duyệt gần nhất; gói dịch vụ kể cả đang ẩn). ord.sp_GetMyOrders(@UserId,@AsRole='Customer'|'LabOwner',@StageCode=NULL,@PageNo=1,@PageSize=20): 1 result set có TotalRows; 50305. ord.sp_GetOrderDetail(@OrderId,@UserId): 5 result set theo thứ tự đơn, item, timeline stage, thanh toán, giao nhận; 50301 không tồn tại, 50303 không có quyền xem (dưới role, RLS có thể trả 50301). Role: role_Auth (mới) EXECUTE sp_RegisterUser và sp_GetLoginInfo; Customer + sp_GetMyAddresses; Customer, LabOwner + sp_GetMyOrders, sp_GetOrderDetail; Customer, LabOwner, Expert + sp_GetLabDetail; LabOwner + sp_GetMyLabs | iam, lab, ord |
| 1.10 | Đợt 8a-2 | Nhóm | Bổ sung 4 procedure đọc cho web và AI (tổng 61 procedure, 15 function). lab.sp_GetReferenceData(): 3 result set theo thứ tự FilmFormats (FormatId, FormatCode, FormatName), ServiceTypes (ServiceTypeId, ServiceCode, ServiceName, Category, Description), ProcessingStages (StageId, StageCode, StageName, SortOrder, IsTerminal); GRANT Customer, LabOwner, Expert. lab.sp_ListLabsForApproval(@AdminUserId,@Status='Pending' (NULL = mọi trạng thái),@PageNo=1,@PageSize=20): LabId, LabName, OwnerUserId, OwnerName, OwnerEmail, AddressLine, Ward, District, City, Phone, ApprovalStatus, ServiceCount, CreatedAt, LastDecision, LastDecisionReason, LastDecidedAt, TotalRows; 50203 không phải Admin, 50205 status hoặc phân trang sai. iam.sp_ListUsers(@AdminUserId,@RoleCode=NULL,@IsActive=NULL,@Keyword=NULL,@PageNo=1,@PageSize=20): UserId, Email, FullName, AuthProvider, IsActive, Roles (CSV), LastLoginAt, CreatedAt, TotalRows, không trả PasswordHash và Phone; 50103 không phải Admin, 50105 RoleCode hoặc phân trang sai. ai.sp_SearchKnowledge(@UserId,@Query,@TopN=3,@Topic=NULL): chỉ chunk IsApproved=1, Full-Text (FREETEXTTABLE) nếu có FT index, không khớp thì LIKE theo từng từ; cột KnowledgeDocId, SourceArticleId, ChunkIndex, Title, Topic, Content, Score, MatchMode; 50801 user không hợp lệ, 50805 query rỗng hoặc TopN ngoài 1-10; WITH EXECUTE AS OWNER vì dynamic SQL. Admin gọi cả 4 qua GRANT EXECUTE theo schema | Toàn bộ |
