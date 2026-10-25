/* ============================================================
   File    : database/01_tables/ai.sql
   Module  : ai - M9 AI Support
   Purpose : Tables của M9 AI Support. Thứ tự CREATE TABLE: UserPreferences -> AIChatLogs -> RecommendationLogs -> KnowledgeDocs.
             Gồm PK, CHECK, UNIQUE, DEFAULT và FK TRONG CÙNG schema (không có).
   Owner   : E (xem docs/Phan-cong.md)
   Depends : iam, lab, com
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

-- Sở thích dùng cho gợi ý cá nhân hóa (1-1 với Users)
CREATE TABLE ai.UserPreferences
(
    UserId               INT NOT NULL
                           CONSTRAINT PK_UserPreferences PRIMARY KEY,
    PreferredFormatId    INT NULL,
    PreferredFilmType    NVARCHAR(15) NULL
                           CONSTRAINT CK_UserPreferences_PreferredFilmType CHECK (PreferredFilmType IN ('ColorNegative','BlackWhite','ColorSlide')),
    PreferredCity        NVARCHAR(100) NULL,
    MaxDistanceKm        DECIMAL(6,2) NULL
                           CONSTRAINT CK_UserPreferences_MaxDistanceKm CHECK (MaxDistanceKm > 0),
    MaxBudgetPerRoll     DECIMAL(18,0) NULL
                           CONSTRAINT CK_UserPreferences_MaxBudgetPerRoll CHECK (MaxBudgetPerRoll >= 0),
    PrioritizeQuality    BIT NOT NULL
                           CONSTRAINT DF_UserPreferences_PrioritizeQuality DEFAULT 0,
    PrioritizeSpeed      BIT NOT NULL
                           CONSTRAINT DF_UserPreferences_PrioritizeSpeed DEFAULT 0,
    Source               NVARCHAR(8) NOT NULL
                           CONSTRAINT DF_UserPreferences_Source DEFAULT 'UserSet'
                           CONSTRAINT CK_UserPreferences_Source CHECK (Source IN ('UserSet','Inferred')),
    ExtraJson            NVARCHAR(MAX) NULL
                           CONSTRAINT CK_UserPreferences_ExtraJson CHECK (ISJSON(ExtraJson) = 1),
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_UserPreferences_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL
);
GO

-- Nhật ký hội thoại với AI Assistant (chỉ thêm)
CREATE TABLE ai.AIChatLogs
(
    ChatLogId            BIGINT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_AIChatLogs PRIMARY KEY,
    SessionId            UNIQUEIDENTIFIER NOT NULL,
    UserId               INT NOT NULL,
    Role                 NVARCHAR(9) NOT NULL
                           CONSTRAINT CK_AIChatLogs_Role CHECK (Role IN ('User','Assistant','System')),
    Message              NVARCHAR(MAX) NOT NULL,
    ModelName            NVARCHAR(50) NULL,
    PromptTokens         INT NULL
                           CONSTRAINT CK_AIChatLogs_PromptTokens CHECK (PromptTokens >= 0),
    CompletionTokens     INT NULL
                           CONSTRAINT CK_AIChatLogs_CompletionTokens CHECK (CompletionTokens >= 0),
    LatencyMs            INT NULL
                           CONSTRAINT CK_AIChatLogs_LatencyMs CHECK (LatencyMs >= 0),
    SourcesJson          NVARCHAR(MAX) NULL
                           CONSTRAINT CK_AIChatLogs_SourcesJson CHECK (ISJSON(SourcesJson) = 1),
    Feedback             NVARCHAR(10) NULL
                           CONSTRAINT CK_AIChatLogs_Feedback CHECK (Feedback IN ('Helpful','NotHelpful')),
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_AIChatLogs_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_AIChatLogs_Role_ModelName CHECK (Role <> 'Assistant' OR ModelName IS NOT NULL),
    CONSTRAINT CK_AIChatLogs_Feedback_Role CHECK (Feedback IS NULL OR Role = 'Assistant')
);
GO

-- Nhật ký gợi ý và phản ứng người dùng (dữ liệu đánh giá mô hình)
CREATE TABLE ai.RecommendationLogs
(
    RecLogId             BIGINT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_RecommendationLogs PRIMARY KEY,
    UserId               INT NOT NULL,
    RecommendationType   NVARCHAR(9) NOT NULL
                           CONSTRAINT CK_RecommendationLogs_RecommendationType CHECK (RecommendationType IN ('Lab','FilmStock','Article','Event','Listing')),
    ItemId               INT NOT NULL,
    Rank                 TINYINT NOT NULL
                           CONSTRAINT CK_RecommendationLogs_Rank CHECK (Rank >= 1),
    Score                DECIMAL(6,4) NOT NULL
                           CONSTRAINT CK_RecommendationLogs_Score CHECK (Score BETWEEN 0 AND 1),
    ModelVersion         NVARCHAR(30) NOT NULL,
    ContextJson          NVARCHAR(MAX) NULL
                           CONSTRAINT CK_RecommendationLogs_ContextJson CHECK (ISJSON(ContextJson) = 1),
    Action               NVARCHAR(9) NULL
                           CONSTRAINT CK_RecommendationLogs_Action CHECK (Action IN ('Clicked','Ordered','Dismissed')),
    ActedAt              DATETIME2(0) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_RecommendationLogs_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_RecommendationLogs_Action_ActedAt CHECK (Action IS NULL OR ActedAt IS NOT NULL)
);
GO

-- Đoạn tri thức (chunk) cho Retrieval-Augmented Generation
CREATE TABLE ai.KnowledgeDocs
(
    KnowledgeDocId       INT IDENTITY(1,1) NOT NULL
                           CONSTRAINT PK_KnowledgeDocs PRIMARY KEY,
    SourceArticleId      INT NULL,
    ChunkIndex           INT NOT NULL
                           CONSTRAINT DF_KnowledgeDocs_ChunkIndex DEFAULT 0
                           CONSTRAINT CK_KnowledgeDocs_ChunkIndex CHECK (ChunkIndex >= 0),
    Title                NVARCHAR(200) NOT NULL,
    Topic                NVARCHAR(50) NULL,
    Content              NVARCHAR(4000) NOT NULL
                           CONSTRAINT CK_KnowledgeDocs_Content CHECK (LEN(Content) > 0),
    ContentHash          CHAR(64) NULL,
    EmbeddingJson        NVARCHAR(MAX) NULL
                           CONSTRAINT CK_KnowledgeDocs_EmbeddingJson CHECK (ISJSON(EmbeddingJson) = 1),
    EmbeddingModel       NVARCHAR(50) NULL,
    ContributedBy        INT NOT NULL,
    IsApproved           BIT NOT NULL
                           CONSTRAINT DF_KnowledgeDocs_IsApproved DEFAULT 0,
    ApprovedBy           INT NULL,
    ApprovedAt           DATETIME2(0) NULL,
    CreatedAt            DATETIME2(0) NOT NULL
                           CONSTRAINT DF_KnowledgeDocs_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt            DATETIME2(0) NULL,
    IsDeleted            BIT NOT NULL
                           CONSTRAINT DF_KnowledgeDocs_IsDeleted DEFAULT 0,
    CONSTRAINT CK_KnowledgeDocs_IsApproved_ApprovedBy CHECK (IsApproved = 0 OR (ApprovedBy IS NOT NULL AND ApprovedAt IS NOT NULL))
);
GO
