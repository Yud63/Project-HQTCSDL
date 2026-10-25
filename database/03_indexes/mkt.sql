/* ============================================================
   File    : database/03_indexes/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : Index của M7 Marketplace (chi tiết trong docs/Requirements.md, mục Index dự kiến). Đặt tên IX_/UX_/SIX_<Bang>_<Cot>. Full-Text bọc IF SERVERPROPERTY('IsFullTextInstalled') = 1.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : Chạy lại bằng REBUILD=1 (DB tạo mới). Không DROP TABLE thủ công.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;  -- bắt buộc cho filtered index, spatial index, computed column
SET ANSI_NULLS ON;
GO

CREATE UNIQUE NONCLUSTERED INDEX UX_ListingImages_Primary
    ON mkt.ListingImages (ListingId)
    WHERE IsPrimary = 1;
GO

CREATE NONCLUSTERED INDEX IX_Listings_Browse
    ON mkt.Listings (Status, CategoryId, Price)
    INCLUDE (Title, City);
GO

CREATE NONCLUSTERED INDEX IX_MktTxn_Buyer
    ON mkt.MarketTransactions (BuyerId, CreatedAt DESC);
GO

CREATE NONCLUSTERED INDEX IX_MktTxn_Seller_Status
    ON mkt.MarketTransactions (SellerId, Status);
GO

CREATE NONCLUSTERED INDEX IX_Messages_Thread
    ON mkt.Messages (ListingId, SentAt);
GO

-- Full-Text (D-20): chỉ tạo khi instance có cài Full-Text (image Linux của CI không có)
IF SERVERPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'ftc_FilmLabDB')
        EXEC(N'CREATE FULLTEXT CATALOG ftc_FilmLabDB;');
    EXEC(N'CREATE FULLTEXT INDEX ON mkt.Listings (Title LANGUAGE 0, Description LANGUAGE 0) KEY INDEX PK_Listings ON ftc_FilmLabDB WITH CHANGE_TRACKING AUTO;');
END
GO
