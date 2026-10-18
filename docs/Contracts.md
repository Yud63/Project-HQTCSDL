# Contracts (hợp đồng giữa các module)

> **Đóng băng cuối tuần 1.** Sau đó, muốn đổi cột/bảng/chữ ký procedure phải sửa file này trong cùng Pull Request và báo cả nhóm.

## 1. Module, phụ thuộc, bảng sở hữu
| Schema | Module | Phụ thuộc | Bảng sở hữu (dự kiến) | Người phụ trách |
|---|---|---|---|---|
| `iam` | Identity & Access (M1) | (none - module gốc) | Users, Roles, UserRoles, Addresses, ExpertProfiles, DeliveryPartners | TBD |
| `lab` | Lab & Catalog (M2) | iam | FilmLabs, LabApprovals, FilmFormats, FilmStocks, ServiceTypes, LabServices | TBD |
| `ord` | Order, Processing, Payment, Review & Dispute (M3 + M6) | iam, lab | Orders, OrderItems, ProcessingStages, OrderStageLog, Payments, FeeConfigs, Reviews, Complaints | TBD |
| `dlv` | Delivery (M4) | iam, ord | DeliveryRequests, DeliveryStatusLog | TBD |
| `arc` | Digital Archive (M5) | iam, ord | ScanFiles, PhotoMetadata, Albums, AlbumPhotos, Notifications | TBD |
| `mkt` | Marketplace (M7) | iam | Listings, ListingCategories, ListingImages, MarketTransactions, Messages | TBD |
| `com` | Community & Knowledge (M8) | iam | Articles, ArticleComments, Events, EventRegistrations | TBD |
| `ai` | AI Support (M9) | iam, lab, ord | UserPreferences, AIChatLogs, RecommendationLogs, KnowledgeDocs | TBD |
| `audit` | System / Audit (M10) | tất cả module (chỉ ghi log) | AuditLogs | TBD |

## 2. Thứ tự dựng (đối tượng sau dùng đối tượng trước)
`Schema -> Tables -> Foreign Keys -> Indexes -> Seed reference -> Seed sample -> Functions -> Views -> Procedures -> Triggers -> Security -> Tests`

## 3. Procedure công bố (API của module) - dự kiến
| Module | Procedure | Việc | Trạng thái |
|---|---|---|---|
| `iam` | `iam.sp_RegisterUser` | Đăng ký tài khoản | Planned |
| `lab` | `lab.sp_ApproveLab` | Admin duyệt Film Lab | Planned |
| `lab` | `lab.sp_SearchLabs` | Tìm/so sánh lab | Planned |
| `ord` | `ord.sp_CreateOrder` | Tạo đơn (Transaction) | Planned |
| `ord` | `ord.sp_UpdateOrderStage` | Đổi giai đoạn xử lý | Planned |
| `ord` | `ord.sp_ProcessPayment` | Thanh toán | Planned |
| `ord` | `ord.sp_AddReview` | Đánh giá lab | Planned |
| `ord` | `ord.sp_FileComplaint` / `ord.sp_ResolveComplaint` | Khiếu nại | Planned |
| `dlv` | `dlv.sp_RequestDelivery` / `dlv.sp_UpdateDeliveryStatus` | Lấy/giao phim | Planned |
| `arc` | `arc.sp_UploadScan` | Lab upload file scan | Planned |
| `mkt` | `mkt.sp_CreateListing` / `mkt.sp_PlaceMarketOrder` | Marketplace | Planned |
| `com` | `com.sp_RegisterEvent` | Đăng ký workshop/photowalk | Planned |
| `ai` | `ai.sp_GetLabRecommendations` | Gợi ý lab | Planned |

## 4. Ai gọi ai (ví dụ `ord.sp_CreateOrder`)
| Bước | Thành phần | Module |
|---|---|---|
| 1 | Kiểm tra khách, lab còn hoạt động | `iam`, `lab` |
| 2 | Lấy giá `lab.LabServices`, tính tiền `ord.fn_CalcOrderTotal` | `lab`, `ord` |
| 3 | Thêm `ord.Orders`, `ord.OrderItems` trong một Transaction | `ord` |
| 4 | Trigger ghi `ord.OrderStageLog` và `audit.AuditLogs` | `ord`, `audit` |
| 5 | Nếu khách chọn lấy phim: `dlv.sp_RequestDelivery` | `dlv` |
| 6 | Tạo thông báo trong `arc.Notifications` | `arc` |

## 5. Nhật ký thay đổi hợp đồng
| Ngày | Người đổi | Thay đổi | Ảnh hưởng module |
|---|---|---|---|
| | | | |
