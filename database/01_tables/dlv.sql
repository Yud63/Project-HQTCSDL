/* ============================================================
   File    : database/01_tables/dlv.sql
   Module  : dlv - M4 Delivery
   Purpose : Tables của M4 Delivery. Thứ tự CREATE TABLE: DeliveryRequests -> DeliveryStatusLog.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema: FK_DeliveryStatusLog_DeliveryRequests.
   Owner   : A (xem docs/Phan-cong.md)
   Depends : iam, ord
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Chặng lấy phim (Pickup) hoặc trả phim (Return) của đơn
CREATE TABLE dlv.DeliveryRequests
(
    DeliveryRequestId    INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_DeliveryRequests PRIMARY KEY,
    OrderId              INT NOT NULL,
    Direction            NVARCHAR(6) NOT NULL
                           CONSTRAINT CK_DeliveryRequests_Direction CHECK (Direction IN ('Pickup','Return')),
    CustomerAddressId    INT NOT NULL,
    DeliveryPartnerId    INT NULL,
    Status               NVARCHAR(10) NOT NULL
                           CONSTRAINT DF_DeliveryRequests_Status DEFAULT 'Requested'
                           CONSTRAINT CK_DeliveryRequests_Status CHECK (Status IN ('Requested','Assigned','PickedUp','Delivered','Failed','Cancelled')),
    Fee                  DECIMAL(18,0) NOT NULL
                           CONSTRAINT CK_DeliveryRequests_Fee CHECK (Fee >= 0),
    DistanceKm           DECIMAL(6,2) NULL
                           CONSTRAINT CK_DeliveryRequests_DistanceKm CHECK (DistanceKm >= 0),
    ScheduledAt          DATETIME2(0) NULL,
    PickedUpAt           DATETIME2(0) NULL,
    DeliveredAt          DATETIME2(0) NULL,
    ExternalTrackingCode NVARCHAR(50) NULL,
    FailureReason        NVARCHAR(255) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_DeliveryRequests_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_DeliveryRequests_IsDeleted DEFAULT 0,
    CONSTRAINT CK_DeliveryRequests_Status_FailureReason CHECK (Status <> 'Failed' OR FailureReason IS NOT NULL),
    CONSTRAINT CK_DeliveryRequests_Status_DeliveryPartnerId CHECK (Status NOT IN ('Assigned','PickedUp','Delivered') OR DeliveryPartnerId IS NOT NULL),
    CONSTRAINT CK_DeliveryRequests_PickedUpAt_Status CHECK (PickedUpAt IS NULL OR Status IN ('PickedUp','Delivered','Failed')),
    CONSTRAINT CK_DeliveryRequests_DeliveredAt_Status CHECK (DeliveredAt IS NULL OR Status = 'Delivered')
);
GO

-- Nhật ký đổi trạng thái chặng giao (bất biến, do trigger ghi)
CREATE TABLE dlv.DeliveryStatusLog
(
    LogId                INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_DeliveryStatusLog PRIMARY KEY,
    DeliveryRequestId    INT NOT NULL,
    FromStatus           NVARCHAR(10) NULL,
    ToStatus             NVARCHAR(10) NOT NULL,
    ChangedBy            INT NULL,
    Note                 NVARCHAR(255) NULL,
    ChangedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_DeliveryStatusLog_ChangedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_DeliveryStatusLog_DeliveryRequests FOREIGN KEY (DeliveryRequestId) REFERENCES dlv.DeliveryRequests(DeliveryRequestId)
);
GO
