/* ============================================================
   File    : database/01_tables/com.sql
   Module  : com - M8 Community & Knowledge
   Purpose : Tables của M8 Community & Knowledge. Thứ tự CREATE TABLE: Articles -> Events -> ArticleComments -> EventRegistrations.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema: FK_ArticleComments_Articles, FK_ArticleComments_ArticleComments, FK_EventRegistrations_Events.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam, lab
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Bài viết: hướng dẫn, review, kỹ thuật, kinh nghiệm, câu hỏi
CREATE TABLE com.Articles
(
    ArticleId            INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Articles PRIMARY KEY,
    AuthorId             INT NOT NULL,
    ArticleType          NVARCHAR(10) NOT NULL
                           CONSTRAINT CK_Articles_ArticleType CHECK (ArticleType IN ('Tutorial','Review','Technical','LabGuide','Experience','Question')),
    Title                NVARCHAR(200) NOT NULL,
    Slug                 NVARCHAR(220) NOT NULL,
    Summary              NVARCHAR(500) NULL,
    Body                 NVARCHAR(MAX) NOT NULL,
    Tags                 NVARCHAR(MAX) NULL
                           CONSTRAINT CK_Articles_Tags CHECK (ISJSON(Tags) = 1),
    RelatedLabId         INT NULL,
    RelatedStockId       INT NULL,
    Status               NVARCHAR(9) NOT NULL
                           CONSTRAINT DF_Articles_Status DEFAULT 'Draft'
                           CONSTRAINT CK_Articles_Status CHECK (Status IN ('Draft','Published','Hidden')),
    PublishedAt          DATETIME2(0) NULL,
    ModerationReason     NVARCHAR(255) NULL,
    ModeratedBy          INT NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Articles_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Articles_IsDeleted DEFAULT 0,
    CONSTRAINT CK_Articles_Status_PublishedAt CHECK (Status = 'Draft' OR PublishedAt IS NOT NULL),
    CONSTRAINT CK_Articles_Status_ModerationReason CHECK (Status <> 'Hidden' OR ModerationReason IS NOT NULL)
);
GO

-- Workshop và photowalk
CREATE TABLE com.Events
(
    EventId              INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_Events PRIMARY KEY,
    OrganizerId          INT NOT NULL,
    HostLabId            INT NULL,
    EventType            NVARCHAR(9) NOT NULL
                           CONSTRAINT CK_Events_EventType CHECK (EventType IN ('Workshop','Photowalk')),
    Title                NVARCHAR(200) NOT NULL,
    Description          NVARCHAR(2000) NULL,
    StartAt              DATETIME2(0) NOT NULL,
    EndAt                DATETIME2(0) NOT NULL,
    RegistrationDeadline DATETIME2(0) NULL,
    VenueName            NVARCHAR(200) NOT NULL,
    AddressLine          NVARCHAR(255) NOT NULL,
    City                 NVARCHAR(100) NOT NULL,
    Location             geography NULL,
    Capacity             SMALLINT NOT NULL
                           CONSTRAINT CK_Events_Capacity CHECK (Capacity > 0),
    Fee                  DECIMAL(18,0) NOT NULL
                           CONSTRAINT DF_Events_Fee DEFAULT 0
                           CONSTRAINT CK_Events_Fee CHECK (Fee >= 0),
    Status               NVARCHAR(9) NOT NULL
                           CONSTRAINT DF_Events_Status DEFAULT 'Draft'
                           CONSTRAINT CK_Events_Status CHECK (Status IN ('Draft','Open','Closed','Cancelled','Completed')),
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_Events_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_Events_IsDeleted DEFAULT 0,
    CONSTRAINT CK_Events_EndAt_StartAt CHECK (EndAt > StartAt),
    CONSTRAINT CK_Events_RegistrationDeadline_StartAt CHECK (RegistrationDeadline IS NULL OR RegistrationDeadline <= StartAt)
);
GO

-- Bình luận và trả lời (1 cấp) của bài viết
CREATE TABLE com.ArticleComments
(
    CommentId            INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_ArticleComments PRIMARY KEY,
    ArticleId            INT NOT NULL,
    UserId               INT NOT NULL,
    ParentCommentId      INT NULL,
    Body                 NVARCHAR(1000) NOT NULL,
    IsAccepted           BIT NOT NULL
                           CONSTRAINT DF_ArticleComments_IsAccepted DEFAULT 0,
    IsVisible            BIT NOT NULL
                           CONSTRAINT DF_ArticleComments_IsVisible DEFAULT 1,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_ArticleComments_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_ArticleComments_IsDeleted DEFAULT 0,
    CONSTRAINT FK_ArticleComments_Articles FOREIGN KEY (ArticleId) REFERENCES com.Articles(ArticleId),
    CONSTRAINT FK_ArticleComments_ArticleComments FOREIGN KEY (ParentCommentId) REFERENCES com.ArticleComments(CommentId)
);
GO

-- Đăng ký sự kiện, có hàng chờ (N-N Events-Users)
CREATE TABLE com.EventRegistrations
(
    EventId              INT NOT NULL,
    UserId               INT NOT NULL,
    Status               NVARCHAR(10) NOT NULL
                           CONSTRAINT DF_EventRegistrations_Status DEFAULT 'Registered'
                           CONSTRAINT CK_EventRegistrations_Status CHECK (Status IN ('Registered','Waitlisted','Cancelled','Attended')),
    IsPaid               BIT NOT NULL
                           CONSTRAINT DF_EventRegistrations_IsPaid DEFAULT 0,
    CancelledAt          DATETIME2(0) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_EventRegistrations_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    CONSTRAINT PK_EventRegistrations PRIMARY KEY (EventId, UserId),
    CONSTRAINT CK_EventRegistrations_Status_CancelledAt CHECK (Status <> 'Cancelled' OR CancelledAt IS NOT NULL),
    CONSTRAINT FK_EventRegistrations_Events FOREIGN KEY (EventId) REFERENCES com.Events(EventId)
);
GO
