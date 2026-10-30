# ERD: FilmLabDB (41 bảng)

> **File này được sinh tự động** từ `tools/schema_spec.py` bằng `python tools/gen_erd.py`. Không sửa tay; muốn đổi thiết kế thì sửa `schema_spec.py` rồi chạy lại.

**Cách xem:** GitHub hiển thị sơ đồ Mermaid ngay trong trang này. Để chỉnh sửa/xuất ảnh: dán khối code vào <https://mermaid.live> hoặc draw.io (*Arrange > Insert > Advanced > Mermaid*).

**Quy ước ký hiệu:**

| Ký hiệu | Nghĩa |
|---|---|
| `PK` / `FK` / `UK` | Khóa chính / khóa ngoại / duy nhất |
| `\|\|--o{` | Cha bắt buộc (1) - con có nhiều (0..N) |
| `\|o--o{` | Cha tùy chọn (0..1) - con có nhiều (0..N), cột FK cho phép NULL |
| `\|\|--o\|` | Quan hệ 1-1 (FK đồng thời là khóa chính hoặc unique) |
| Tên thực thể `iam_Users` | Schema `iam`, bảng `Users` |

Một số FK ghép (nhiều cột) được vẽ bằng một đường nối, nhãn là danh sách cột (ví dụ `OrderId,CustomerId,LabId`).

## 1. Tổng quan quan hệ giữa các bảng (không hiển thị cột)

```mermaid
erDiagram
    iam_Users ||--o{ iam_UserRoles : "UserId"
    iam_Roles ||--o{ iam_UserRoles : "RoleId"
    iam_Users |o--o{ iam_UserRoles : "AssignedBy"
    iam_Users ||--o{ iam_Addresses : "UserId"
    iam_Users ||--o| iam_ExpertProfiles : "UserId"
    iam_Users |o--o{ iam_ExpertProfiles : "VerifiedBy"
    iam_Users |o--o{ iam_DeliveryPartners : "UserId"
    iam_Users ||--o{ lab_FilmLabs : "OwnerUserId"
    lab_FilmLabs ||--o{ lab_LabApprovals : "LabId"
    iam_Users ||--o{ lab_LabApprovals : "ReviewedBy"
    lab_FilmLabs ||--o{ lab_LabServices : "LabId"
    lab_ServiceTypes ||--o{ lab_LabServices : "ServiceTypeId"
    lab_FilmFormats ||--o{ lab_LabServices : "FormatId"
    iam_Users ||--o{ ord_Orders : "CustomerId"
    lab_FilmLabs ||--o{ ord_Orders : "LabId"
    ord_ProcessingStages ||--o{ ord_Orders : "StageId"
    iam_Addresses |o--o{ ord_Orders : "PickupAddressId"
    iam_Addresses |o--o{ ord_Orders : "ReturnAddressId"
    ord_Orders ||--o{ ord_OrderItems : "OrderId"
    lab_LabServices ||--o{ ord_OrderItems : "LabServiceId"
    lab_FilmStocks |o--o{ ord_OrderItems : "FilmStockId"
    ord_Orders ||--o{ ord_OrderStageLog : "OrderId"
    ord_ProcessingStages |o--o{ ord_OrderStageLog : "FromStageId"
    ord_ProcessingStages ||--o{ ord_OrderStageLog : "ToStageId"
    iam_Users |o--o{ ord_OrderStageLog : "ChangedBy"
    ord_Orders ||--o{ ord_Payments : "OrderId"
    lab_FilmLabs |o--o{ ord_FeeConfigs : "ScopeLabId"
    iam_Users ||--o{ ord_FeeConfigs : "CreatedBy"
    iam_Users |o--o{ ord_Reviews : "ModeratedBy"
    iam_Users |o--o{ ord_Complaints : "AssignedAdminId"
    ord_Orders ||--o| ord_Reviews : "OrderId,CustomerId,LabId"
    ord_Orders ||--o{ ord_Complaints : "OrderId,CustomerId,LabId"
    ord_Orders ||--o{ dlv_DeliveryRequests : "OrderId"
    iam_Addresses ||--o{ dlv_DeliveryRequests : "CustomerAddressId"
    iam_DeliveryPartners |o--o{ dlv_DeliveryRequests : "DeliveryPartnerId"
    dlv_DeliveryRequests ||--o{ dlv_DeliveryStatusLog : "DeliveryRequestId"
    iam_Users |o--o{ dlv_DeliveryStatusLog : "ChangedBy"
    ord_Orders ||--o{ arc_ScanFiles : "OrderId"
    ord_OrderItems |o--o{ arc_ScanFiles : "OrderItemId"
    iam_Users ||--o{ arc_ScanFiles : "OwnerUserId"
    iam_Users ||--o{ arc_ScanFiles : "UploadedBy"
    arc_ScanFiles ||--o| arc_PhotoMetadata : "ScanFileId"
    lab_FilmStocks |o--o{ arc_PhotoMetadata : "FilmStockId"
    iam_Users ||--o{ arc_Albums : "OwnerUserId"
    arc_ScanFiles |o--o{ arc_Albums : "CoverScanFileId"
    arc_Albums ||--o{ arc_AlbumPhotos : "AlbumId"
    arc_ScanFiles ||--o{ arc_AlbumPhotos : "ScanFileId"
    iam_Users ||--o{ arc_Notifications : "UserId"
    ord_Orders |o--o{ arc_Notifications : "OrderId"
    iam_Users ||--o{ mkt_Listings : "SellerId"
    mkt_ListingCategories ||--o{ mkt_Listings : "CategoryId"
    iam_Users |o--o{ mkt_Listings : "ModeratedBy"
    mkt_Listings ||--o{ mkt_ListingImages : "ListingId"
    iam_Users ||--o{ mkt_MarketTransactions : "BuyerId"
    iam_Users |o--o{ mkt_MarketTransactions : "ResolvedBy"
    mkt_Listings ||--o{ mkt_Messages : "ListingId"
    iam_Users ||--o{ mkt_Messages : "SenderId"
    iam_Users ||--o{ mkt_Messages : "ReceiverId"
    mkt_Listings ||--o{ mkt_MarketTransactions : "ListingId,SellerId"
    iam_Users ||--o{ com_Articles : "AuthorId"
    lab_FilmLabs |o--o{ com_Articles : "RelatedLabId"
    lab_FilmStocks |o--o{ com_Articles : "RelatedStockId"
    iam_Users |o--o{ com_Articles : "ModeratedBy"
    com_Articles ||--o{ com_ArticleComments : "ArticleId"
    iam_Users ||--o{ com_ArticleComments : "UserId"
    com_ArticleComments |o--o{ com_ArticleComments : "ParentCommentId"
    iam_Users ||--o{ com_Events : "OrganizerId"
    lab_FilmLabs |o--o{ com_Events : "HostLabId"
    com_Events ||--o{ com_EventRegistrations : "EventId"
    iam_Users ||--o{ com_EventRegistrations : "UserId"
    iam_Users ||--o| ai_UserPreferences : "UserId"
    lab_FilmFormats |o--o{ ai_UserPreferences : "PreferredFormatId"
    iam_Users ||--o{ ai_AIChatLogs : "UserId"
    iam_Users ||--o{ ai_RecommendationLogs : "UserId"
    com_Articles |o--o{ ai_KnowledgeDocs : "SourceArticleId"
    iam_Users ||--o{ ai_KnowledgeDocs : "ContributedBy"
    iam_Users |o--o{ ai_KnowledgeDocs : "ApprovedBy"
```

## 2. Các module và bảng

| Schema | Module | Bảng |
|---|---|---|
| `iam` | M1 Identity & Access | Users, Roles, UserRoles, Addresses, ExpertProfiles, DeliveryPartners |
| `lab` | M2 Lab & Catalog | FilmLabs, LabApprovals, FilmFormats, FilmStocks, ServiceTypes, LabServices |
| `ord` | M3 Order + M6 Review/Complaint | ProcessingStages, Orders, OrderItems, OrderStageLog, Payments, FeeConfigs, Reviews, Complaints |
| `dlv` | M4 Delivery | DeliveryRequests, DeliveryStatusLog |
| `arc` | M5 Digital Archive | ScanFiles, PhotoMetadata, Albums, AlbumPhotos, Notifications |
| `mkt` | M7 Marketplace | ListingCategories, Listings, ListingImages, MarketTransactions, Messages |
| `com` | M8 Community | Articles, ArticleComments, Events, EventRegistrations |
| `ai` | M9 AI Support | UserPreferences, AIChatLogs, RecommendationLogs, KnowledgeDocs |
| `audit` | M10 System/Audit | AuditLogs |

## 3. Module `iam`: M1 Identity & Access

```mermaid
erDiagram
    iam_Users {
        int UserId PK
        nvarchar Email
        nvarchar AuthProvider
        nvarchar PasswordHash
        nvarchar FullName
        nvarchar Phone
        nvarchar AvatarUrl
        bit IsActive
        datetime2 LastLoginAt
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    iam_Roles {
        int RoleId PK
        nvarchar RoleCode UK
        nvarchar RoleName
        nvarchar Description
    }
    iam_UserRoles {
        int UserId PK,FK
        int RoleId PK,FK
        datetime2 AssignedAt
        int AssignedBy FK
    }
    iam_Addresses {
        int AddressId PK
        int UserId FK
        nvarchar Label
        nvarchar RecipientName
        nvarchar Phone
        nvarchar Line1
        nvarchar Ward
        nvarchar District
        nvarchar City
        geography Location
        bit IsDefault
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    iam_ExpertProfiles {
        int UserId PK,FK
        nvarchar Bio
        nvarchar Expertise
        smallint YearsExperience
        nvarchar PortfolioUrl
        bit IsVerified
        int VerifiedBy FK
        datetime2 VerifiedAt
        datetime2 CreatedAt
        datetime2 UpdatedAt
    }
    iam_DeliveryPartners {
        int DeliveryPartnerId PK
        nvarchar ProviderType
        nvarchar PartnerName
        int UserId FK
        nvarchar VehicleType
        nvarchar PlateNumber
        nvarchar ApiCode
        bit IsActive
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    iam_Users ||--o{ iam_UserRoles : "UserId"
    iam_Roles ||--o{ iam_UserRoles : "RoleId"
    iam_Users |o--o{ iam_UserRoles : "AssignedBy"
    iam_Users ||--o{ iam_Addresses : "UserId"
    iam_Users ||--o| iam_ExpertProfiles : "UserId"
    iam_Users |o--o{ iam_ExpertProfiles : "VerifiedBy"
    iam_Users |o--o{ iam_DeliveryPartners : "UserId"
```

## 4. Module `lab`: M2 Lab & Catalog

```mermaid
erDiagram
    lab_FilmLabs {
        int LabId PK
        int OwnerUserId FK
        nvarchar LabName
        nvarchar Description
        nvarchar AddressLine
        nvarchar Ward
        nvarchar District
        nvarchar City
        geography Location
        nvarchar Phone
        nvarchar Email
        nvarchar OpenHoursJson
        nvarchar SpecialTechniques
        smallint DailyCapacityRolls
        nvarchar ApprovalStatus
        decimal AvgRating
        int ReviewCount
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    lab_LabApprovals {
        int ApprovalId PK
        int LabId FK
        int ReviewedBy FK
        nvarchar Decision
        nvarchar Reason
        datetime2 DecidedAt
    }
    lab_FilmFormats {
        int FormatId PK
        nvarchar FormatCode UK
        nvarchar FormatName
    }
    lab_FilmStocks {
        int StockId PK
        nvarchar Brand
        nvarchar StockName
        smallint Iso
        nvarchar FilmType
        nvarchar ProcessCode
        bit IsActive
    }
    lab_ServiceTypes {
        int ServiceTypeId PK
        nvarchar ServiceCode UK
        nvarchar ServiceName
        nvarchar Category
        nvarchar Description
    }
    lab_LabServices {
        int LabServiceId PK
        int LabId FK
        int ServiceTypeId FK
        int FormatId FK
        nvarchar ProcessCode
        nvarchar PackageName
        nvarchar Description
        decimal UnitPrice
        nvarchar PriceUnit
        nvarchar ScanQuality
        tinyint TurnaroundDays
        bit IsActive
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    iam_Users {
        int UserId PK
    }
    iam_Users ||--o{ lab_FilmLabs : "OwnerUserId"
    lab_FilmLabs ||--o{ lab_LabApprovals : "LabId"
    iam_Users ||--o{ lab_LabApprovals : "ReviewedBy"
    lab_FilmLabs ||--o{ lab_LabServices : "LabId"
    lab_ServiceTypes ||--o{ lab_LabServices : "ServiceTypeId"
    lab_FilmFormats ||--o{ lab_LabServices : "FormatId"
```

Bảng ngoài module (chỉ hiện khóa chính): `iam.Users`.

## 5. Module `ord`: M3 Order + M6 Review/Complaint

```mermaid
erDiagram
    ord_ProcessingStages {
        int StageId PK
        nvarchar StageCode UK
        nvarchar StageName
        tinyint SortOrder UK
        bit IsTerminal
    }
    ord_Orders {
        int OrderId PK
        nvarchar OrderCode UK
        int CustomerId FK
        int LabId FK
        int StageId FK
        nvarchar FulfillmentMethod
        nvarchar ReturnMethod
        int PickupAddressId FK
        int ReturnAddressId FK
        decimal Subtotal
        decimal DeliveryFee
        decimal PlatformFee
        decimal TotalAmount
        nvarchar PaymentStatus
        nvarchar CustomerNote
        date EstimatedReadyDate
        datetime2 CompletedAt
        nvarchar CancelReason
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    ord_OrderItems {
        int OrderItemId PK
        int OrderId FK
        int LabServiceId FK
        int FilmStockId FK
        int Quantity
        decimal UnitPriceSnapshot
        decimal LineTotal
        nvarchar ProcessingNote
        datetime2 CreatedAt
    }
    ord_OrderStageLog {
        int LogId PK
        int OrderId FK
        int FromStageId FK
        int ToStageId FK
        int ChangedBy FK
        nvarchar Note
        datetime2 ChangedAt
    }
    ord_Payments {
        int PaymentId PK
        int OrderId FK
        nvarchar Method
        nvarchar Provider
        nvarchar ProviderTxnId
        decimal Amount
        nvarchar Status
        datetime2 PaidAt
        datetime2 RefundedAt
        nvarchar FailureReason
        datetime2 CreatedAt
    }
    ord_FeeConfigs {
        int FeeConfigId PK
        nvarchar FeeType
        decimal Rate
        decimal FixedAmount
        int ScopeLabId FK
        date EffectiveFrom
        date EffectiveTo
        int CreatedBy FK
        datetime2 CreatedAt
    }
    ord_Reviews {
        int ReviewId PK
        int OrderId FK,UK
        int CustomerId FK
        int LabId FK
        tinyint RatingOverall
        tinyint RatingScanQuality
        tinyint RatingSpeed
        nvarchar Comment
        nvarchar LabReply
        datetime2 LabRepliedAt
        bit IsVisible
        int ModeratedBy FK
        datetime2 ModeratedAt
        nvarchar ModerationReason
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    ord_Complaints {
        int ComplaintId PK
        int OrderId FK
        int CustomerId FK
        int LabId FK
        nvarchar Category
        nvarchar Title
        nvarchar Description
        nvarchar Status
        nvarchar LabResponse
        int AssignedAdminId FK
        nvarchar ResolutionType
        nvarchar Resolution
        decimal RefundAmount
        datetime2 ResolvedAt
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    iam_Users {
        int UserId PK
    }
    lab_FilmLabs {
        int LabId PK
    }
    iam_Addresses {
        int AddressId PK
    }
    lab_LabServices {
        int LabServiceId PK
    }
    lab_FilmStocks {
        int StockId PK
    }
    iam_Users ||--o{ ord_Orders : "CustomerId"
    lab_FilmLabs ||--o{ ord_Orders : "LabId"
    ord_ProcessingStages ||--o{ ord_Orders : "StageId"
    iam_Addresses |o--o{ ord_Orders : "PickupAddressId"
    iam_Addresses |o--o{ ord_Orders : "ReturnAddressId"
    ord_Orders ||--o{ ord_OrderItems : "OrderId"
    lab_LabServices ||--o{ ord_OrderItems : "LabServiceId"
    lab_FilmStocks |o--o{ ord_OrderItems : "FilmStockId"
    ord_Orders ||--o{ ord_OrderStageLog : "OrderId"
    ord_ProcessingStages |o--o{ ord_OrderStageLog : "FromStageId"
    ord_ProcessingStages ||--o{ ord_OrderStageLog : "ToStageId"
    iam_Users |o--o{ ord_OrderStageLog : "ChangedBy"
    ord_Orders ||--o{ ord_Payments : "OrderId"
    lab_FilmLabs |o--o{ ord_FeeConfigs : "ScopeLabId"
    iam_Users ||--o{ ord_FeeConfigs : "CreatedBy"
    iam_Users |o--o{ ord_Reviews : "ModeratedBy"
    iam_Users |o--o{ ord_Complaints : "AssignedAdminId"
    ord_Orders ||--o| ord_Reviews : "OrderId,CustomerId,LabId"
    ord_Orders ||--o{ ord_Complaints : "OrderId,CustomerId,LabId"
```

Bảng ngoài module (chỉ hiện khóa chính): `iam.Users`, `lab.FilmLabs`, `iam.Addresses`, `lab.LabServices`, `lab.FilmStocks`.

- **FK ghép** `ord.Reviews(OrderId, CustomerId, LabId)` -> `ord.Orders(OrderId, CustomerId, LabId)`: FK ghép: bảo đảm khách và lab khớp với đơn.
- **FK ghép** `ord.Complaints(OrderId, CustomerId, LabId)` -> `ord.Orders(OrderId, CustomerId, LabId)`: FK ghép: bảo đảm khách và lab khớp với đơn.

## 6. Module `dlv`: M4 Delivery

```mermaid
erDiagram
    dlv_DeliveryRequests {
        int DeliveryRequestId PK
        int OrderId FK
        nvarchar Direction
        int CustomerAddressId FK
        int DeliveryPartnerId FK
        nvarchar Status
        decimal Fee
        decimal DistanceKm
        datetime2 ScheduledAt
        datetime2 PickedUpAt
        datetime2 DeliveredAt
        nvarchar ExternalTrackingCode
        nvarchar FailureReason
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    dlv_DeliveryStatusLog {
        int LogId PK
        int DeliveryRequestId FK
        nvarchar FromStatus
        nvarchar ToStatus
        int ChangedBy FK
        nvarchar Note
        datetime2 ChangedAt
    }
    ord_Orders {
        int OrderId PK
    }
    iam_Addresses {
        int AddressId PK
    }
    iam_DeliveryPartners {
        int DeliveryPartnerId PK
    }
    iam_Users {
        int UserId PK
    }
    ord_Orders ||--o{ dlv_DeliveryRequests : "OrderId"
    iam_Addresses ||--o{ dlv_DeliveryRequests : "CustomerAddressId"
    iam_DeliveryPartners |o--o{ dlv_DeliveryRequests : "DeliveryPartnerId"
    dlv_DeliveryRequests ||--o{ dlv_DeliveryStatusLog : "DeliveryRequestId"
    iam_Users |o--o{ dlv_DeliveryStatusLog : "ChangedBy"
```

Bảng ngoài module (chỉ hiện khóa chính): `ord.Orders`, `iam.Addresses`, `iam.DeliveryPartners`, `iam.Users`.

## 7. Module `arc`: M5 Digital Archive

```mermaid
erDiagram
    arc_ScanFiles {
        uniqueidentifier ScanFileId PK
        int OrderId FK
        int OrderItemId FK
        int OwnerUserId FK
        int UploadedBy FK
        smallint FrameNumber
        nvarchar FileName
        nvarchar StorageUrl
        nvarchar ContentType
        bigint FileSizeBytes
        int WidthPx
        int HeightPx
        char ChecksumSha256
        decimal QualityScore
        nvarchar QualityStatus
        datetime2 UploadedAt
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    arc_PhotoMetadata {
        uniqueidentifier ScanFileId PK,FK
        int FilmStockId FK
        nvarchar CameraModel
        nvarchar LensModel
        date ShootingDate
        smallint ExposedIso
        nvarchar ProcessMethod
        nvarchar ScannerModel
        int ScanResolutionDpi
        nvarchar ExtraJson
        datetime2 CreatedAt
        datetime2 UpdatedAt
    }
    arc_Albums {
        int AlbumId PK
        int OwnerUserId FK
        nvarchar Title
        nvarchar Description
        uniqueidentifier CoverScanFileId FK
        bit IsPublic
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    arc_AlbumPhotos {
        int AlbumId PK,FK
        uniqueidentifier ScanFileId PK,FK
        smallint SortOrder
        datetime2 AddedAt
    }
    arc_Notifications {
        int NotificationId PK
        int UserId FK
        nvarchar Type
        nvarchar Title
        nvarchar Body
        int OrderId FK
        bit IsRead
        datetime2 ReadAt
        datetime2 CreatedAt
    }
    ord_Orders {
        int OrderId PK
    }
    ord_OrderItems {
        int OrderItemId PK
    }
    iam_Users {
        int UserId PK
    }
    lab_FilmStocks {
        int StockId PK
    }
    ord_Orders ||--o{ arc_ScanFiles : "OrderId"
    ord_OrderItems |o--o{ arc_ScanFiles : "OrderItemId"
    iam_Users ||--o{ arc_ScanFiles : "OwnerUserId"
    iam_Users ||--o{ arc_ScanFiles : "UploadedBy"
    arc_ScanFiles ||--o| arc_PhotoMetadata : "ScanFileId"
    lab_FilmStocks |o--o{ arc_PhotoMetadata : "FilmStockId"
    iam_Users ||--o{ arc_Albums : "OwnerUserId"
    arc_ScanFiles |o--o{ arc_Albums : "CoverScanFileId"
    arc_Albums ||--o{ arc_AlbumPhotos : "AlbumId"
    arc_ScanFiles ||--o{ arc_AlbumPhotos : "ScanFileId"
    iam_Users ||--o{ arc_Notifications : "UserId"
    ord_Orders |o--o{ arc_Notifications : "OrderId"
```

Bảng ngoài module (chỉ hiện khóa chính): `ord.Orders`, `ord.OrderItems`, `iam.Users`, `lab.FilmStocks`.

## 8. Module `mkt`: M7 Marketplace

```mermaid
erDiagram
    mkt_ListingCategories {
        int CategoryId PK
        nvarchar CategoryCode UK
        nvarchar CategoryName
        bit IsActive
    }
    mkt_Listings {
        int ListingId PK
        int SellerId FK
        int CategoryId FK
        nvarchar ListingType
        nvarchar Title
        nvarchar Description
        nvarchar Brand
        nvarchar Model
        nvarchar Condition
        decimal Price
        nvarchar ExchangeWanted
        int Quantity
        nvarchar City
        nvarchar Status
        datetime2 ExpiresAt
        nvarchar ModerationReason
        int ModeratedBy FK
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    mkt_ListingImages {
        int ImageId PK
        int ListingId FK
        nvarchar ImageUrl
        tinyint SortOrder
        bit IsPrimary
        datetime2 CreatedAt
    }
    mkt_MarketTransactions {
        int TransactionId PK
        nvarchar TransactionCode UK
        int ListingId FK
        int SellerId FK
        int BuyerId FK
        int Quantity
        decimal UnitPrice
        decimal TotalAmount
        decimal PlatformFee
        nvarchar Status
        nvarchar Note
        datetime2 ConfirmedAt
        datetime2 ShippedAt
        datetime2 CompletedAt
        nvarchar CancelReason
        nvarchar DisputeReason
        datetime2 DisputedAt
        nvarchar DisputeResolution
        int ResolvedBy FK
        datetime2 ResolvedAt
        tinyint BuyerRating
        nvarchar BuyerComment
        datetime2 RatedAt
        datetime2 CreatedAt
        datetime2 UpdatedAt
    }
    mkt_Messages {
        int MessageId PK
        int ListingId FK
        int SenderId FK
        int ReceiverId FK
        nvarchar Body
        datetime2 SentAt
        datetime2 ReadAt
    }
    iam_Users {
        int UserId PK
    }
    iam_Users ||--o{ mkt_Listings : "SellerId"
    mkt_ListingCategories ||--o{ mkt_Listings : "CategoryId"
    iam_Users |o--o{ mkt_Listings : "ModeratedBy"
    mkt_Listings ||--o{ mkt_ListingImages : "ListingId"
    iam_Users ||--o{ mkt_MarketTransactions : "BuyerId"
    iam_Users |o--o{ mkt_MarketTransactions : "ResolvedBy"
    mkt_Listings ||--o{ mkt_Messages : "ListingId"
    iam_Users ||--o{ mkt_Messages : "SenderId"
    iam_Users ||--o{ mkt_Messages : "ReceiverId"
    mkt_Listings ||--o{ mkt_MarketTransactions : "ListingId,SellerId"
```

Bảng ngoài module (chỉ hiện khóa chính): `iam.Users`.

- **FK ghép** `mkt.MarketTransactions(ListingId, SellerId)` -> `mkt.Listings(ListingId, SellerId)`: FK ghép: bảo đảm người bán khớp với tin đăng.

## 9. Module `com`: M8 Community

```mermaid
erDiagram
    com_Articles {
        int ArticleId PK
        int AuthorId FK
        nvarchar ArticleType
        nvarchar Title
        nvarchar Slug
        nvarchar Summary
        nvarchar Body
        nvarchar Tags
        int RelatedLabId FK
        int RelatedStockId FK
        nvarchar Status
        datetime2 PublishedAt
        nvarchar ModerationReason
        int ModeratedBy FK
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    com_ArticleComments {
        int CommentId PK
        int ArticleId FK
        int UserId FK
        int ParentCommentId FK
        nvarchar Body
        bit IsAccepted
        bit IsVisible
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    com_Events {
        int EventId PK
        int OrganizerId FK
        int HostLabId FK
        nvarchar EventType
        nvarchar Title
        nvarchar Description
        datetime2 StartAt
        datetime2 EndAt
        datetime2 RegistrationDeadline
        nvarchar VenueName
        nvarchar AddressLine
        nvarchar City
        geography Location
        smallint Capacity
        decimal Fee
        nvarchar Status
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    com_EventRegistrations {
        int EventId PK,FK
        int UserId PK,FK
        nvarchar Status
        bit IsPaid
        datetime2 CancelledAt
        datetime2 CreatedAt
        datetime2 UpdatedAt
    }
    iam_Users {
        int UserId PK
    }
    lab_FilmLabs {
        int LabId PK
    }
    lab_FilmStocks {
        int StockId PK
    }
    iam_Users ||--o{ com_Articles : "AuthorId"
    lab_FilmLabs |o--o{ com_Articles : "RelatedLabId"
    lab_FilmStocks |o--o{ com_Articles : "RelatedStockId"
    iam_Users |o--o{ com_Articles : "ModeratedBy"
    com_Articles ||--o{ com_ArticleComments : "ArticleId"
    iam_Users ||--o{ com_ArticleComments : "UserId"
    com_ArticleComments |o--o{ com_ArticleComments : "ParentCommentId"
    iam_Users ||--o{ com_Events : "OrganizerId"
    lab_FilmLabs |o--o{ com_Events : "HostLabId"
    com_Events ||--o{ com_EventRegistrations : "EventId"
    iam_Users ||--o{ com_EventRegistrations : "UserId"
```

Bảng ngoài module (chỉ hiện khóa chính): `iam.Users`, `lab.FilmLabs`, `lab.FilmStocks`.

## 10. Module `ai`: M9 AI Support

```mermaid
erDiagram
    ai_UserPreferences {
        int UserId PK,FK
        int PreferredFormatId FK
        nvarchar PreferredFilmType
        nvarchar PreferredCity
        decimal MaxDistanceKm
        decimal MaxBudgetPerRoll
        bit PrioritizeQuality
        bit PrioritizeSpeed
        nvarchar Source
        nvarchar ExtraJson
        datetime2 CreatedAt
        datetime2 UpdatedAt
    }
    ai_AIChatLogs {
        bigint ChatLogId PK
        uniqueidentifier SessionId
        int UserId FK
        nvarchar Role
        nvarchar Message
        nvarchar ModelName
        int PromptTokens
        int CompletionTokens
        int LatencyMs
        nvarchar SourcesJson
        nvarchar Feedback
        datetime2 CreatedAt
    }
    ai_RecommendationLogs {
        bigint RecLogId PK
        int UserId FK
        nvarchar RecommendationType
        int ItemId
        tinyint Rank
        decimal Score
        nvarchar ModelVersion
        nvarchar ContextJson
        nvarchar Action
        datetime2 ActedAt
        datetime2 CreatedAt
    }
    ai_KnowledgeDocs {
        int KnowledgeDocId PK
        int SourceArticleId FK
        int ChunkIndex
        nvarchar Title
        nvarchar Topic
        nvarchar Content
        char ContentHash
        nvarchar EmbeddingJson
        nvarchar EmbeddingModel
        int ContributedBy FK
        bit IsApproved
        int ApprovedBy FK
        datetime2 ApprovedAt
        datetime2 CreatedAt
        datetime2 UpdatedAt
        bit IsDeleted
    }
    iam_Users {
        int UserId PK
    }
    lab_FilmFormats {
        int FormatId PK
    }
    com_Articles {
        int ArticleId PK
    }
    iam_Users ||--o| ai_UserPreferences : "UserId"
    lab_FilmFormats |o--o{ ai_UserPreferences : "PreferredFormatId"
    iam_Users ||--o{ ai_AIChatLogs : "UserId"
    iam_Users ||--o{ ai_RecommendationLogs : "UserId"
    com_Articles |o--o{ ai_KnowledgeDocs : "SourceArticleId"
    iam_Users ||--o{ ai_KnowledgeDocs : "ContributedBy"
    iam_Users |o--o{ ai_KnowledgeDocs : "ApprovedBy"
```

Bảng ngoài module (chỉ hiện khóa chính): `iam.Users`, `lab.FilmFormats`, `com.Articles`.

## 11. Module `audit`: M10 System/Audit

```mermaid
erDiagram
    audit_AuditLogs {
        bigint AuditLogId PK
        nvarchar TableSchema
        nvarchar TableName
        nvarchar PrimaryKeyValue
        nvarchar Action
        int ChangedBy
        nvarchar OldValues
        nvarchar NewValues
        nvarchar AppName
        nvarchar HostName
        datetime2 ChangedAt
    }
```
