/* ============================================================
   File    : database/01_tables/ord_feedback.sql
   Module  : ord_feedback - M6 Review & Complaint
   Purpose : Tables của M6 Review & Complaint. Thứ tự CREATE TABLE: Reviews -> Complaints.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema: FK_Reviews_Orders, FK_Complaints_Orders.
   Owner   : C (xem docs/Phan-cong.md)
   Depends : iam, lab, ord (ord.sql chạy trước)
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Đánh giá lab sau khi đơn hoàn tất (mỗi đơn tối đa 1)
CREATE TABLE ord.Reviews
(
    ReviewId             INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Reviews PRIMARY KEY,
    OrderId              INT NOT NULL
                           CONSTRAINT UQ_Reviews_OrderId UNIQUE,
    CustomerId           INT NOT NULL,
    LabId                INT NOT NULL,
    RatingOverall        TINYINT NOT NULL
                           CONSTRAINT CK_Reviews_RatingOverall CHECK (RatingOverall BETWEEN 1 AND 5),
    RatingScanQuality    TINYINT NULL
                           CONSTRAINT CK_Reviews_RatingScanQuality CHECK (RatingScanQuality BETWEEN 1 AND 5),
    RatingSpeed          TINYINT NULL
                           CONSTRAINT CK_Reviews_RatingSpeed CHECK (RatingSpeed BETWEEN 1 AND 5),
    Comment              NVARCHAR(1000) NULL,
    LabReply             NVARCHAR(1000) NULL,
    LabRepliedAt         DATETIME2(0) NULL,
    IsVisible            BIT NOT NULL
                           CONSTRAINT DF_Reviews_IsVisible DEFAULT 1,
    ModeratedBy          INT NULL,
    ModeratedAt          DATETIME2(0) NULL,
    ModerationReason     NVARCHAR(255) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Reviews_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Reviews_IsDeleted DEFAULT 0,
    CONSTRAINT CK_Reviews_IsVisible_ModerationReason CHECK (IsVisible = 1 OR ModerationReason IS NOT NULL),
    CONSTRAINT CK_Reviews_LabReply_LabRepliedAt CHECK (LabReply IS NULL OR LabRepliedAt IS NOT NULL),
    CONSTRAINT FK_Reviews_Orders FOREIGN KEY (OrderId, CustomerId, LabId) REFERENCES ord.Orders(OrderId, CustomerId, LabId)
);
GO

-- Khiếu nại về đơn hàng và kết quả xử lý của Admin
CREATE TABLE ord.Complaints
(
    ComplaintId          INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Complaints PRIMARY KEY,
    OrderId              INT NOT NULL,
    CustomerId           INT NOT NULL,
    LabId                INT NOT NULL,
    Category             NVARCHAR(12) NOT NULL
                           CONSTRAINT CK_Complaints_Category CHECK (Category IN ('LostFilm','DamagedFilm','ScanQuality','Delay','Billing','Service','Other')),
    Title                NVARCHAR(150) NOT NULL,
    Description          NVARCHAR(2000) NOT NULL,
    Status               NVARCHAR(9) NOT NULL
                           CONSTRAINT DF_Complaints_Status DEFAULT 'Open'
                           CONSTRAINT CK_Complaints_Status CHECK (Status IN ('Open','InReview','Resolved','Rejected')),
    LabResponse          NVARCHAR(1000) NULL,
    AssignedAdminId      INT NULL,
    ResolutionType       NVARCHAR(12) NULL
                           CONSTRAINT CK_Complaints_ResolutionType CHECK (ResolutionType IN ('Refund','Redo','Compensation','NoAction')),
    Resolution           NVARCHAR(1000) NULL,
    RefundAmount         DECIMAL(18,0) NULL
                           CONSTRAINT CK_Complaints_RefundAmount CHECK (RefundAmount >= 0),
    ResolvedAt           DATETIME2(0) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Complaints_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Complaints_IsDeleted DEFAULT 0,
    CONSTRAINT CK_Complaints_Status_Resolution CHECK (Status NOT IN ('Resolved','Rejected') OR (Resolution IS NOT NULL AND ResolvedAt IS NOT NULL)),
    CONSTRAINT CK_Complaints_Status_AssignedAdminId CHECK (Status = 'Open' OR AssignedAdminId IS NOT NULL),
    CONSTRAINT CK_Complaints_RefundAmount_ResolutionType CHECK (RefundAmount IS NULL OR ResolutionType = 'Refund'),
    CONSTRAINT CK_Complaints_ResolutionType_Status CHECK (ResolutionType IS NULL OR Status = 'Resolved'),
    CONSTRAINT FK_Complaints_Orders FOREIGN KEY (OrderId, CustomerId, LabId) REFERENCES ord.Orders(OrderId, CustomerId, LabId)
);
GO
