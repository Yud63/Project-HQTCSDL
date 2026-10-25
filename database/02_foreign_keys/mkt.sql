/* ============================================================
   File    : database/02_foreign_keys/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : FK LIÊN MODULE (6): FK_Listings_Users_SellerId, FK_Listings_Users_ModeratedBy, FK_MarketTransactions_Users_BuyerId, FK_MarketTransactions_Users_ResolvedBy, FK_Messages_Users_SenderId, FK_Messages_Users_ReceiverId.
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

ALTER TABLE mkt.Listings WITH CHECK
    ADD CONSTRAINT FK_Listings_Users_SellerId FOREIGN KEY (SellerId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE mkt.Listings WITH CHECK
    ADD CONSTRAINT FK_Listings_Users_ModeratedBy FOREIGN KEY (ModeratedBy) REFERENCES iam.Users(UserId);
GO

ALTER TABLE mkt.MarketTransactions WITH CHECK
    ADD CONSTRAINT FK_MarketTransactions_Users_BuyerId FOREIGN KEY (BuyerId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE mkt.MarketTransactions WITH CHECK
    ADD CONSTRAINT FK_MarketTransactions_Users_ResolvedBy FOREIGN KEY (ResolvedBy) REFERENCES iam.Users(UserId);
GO

ALTER TABLE mkt.Messages WITH CHECK
    ADD CONSTRAINT FK_Messages_Users_SenderId FOREIGN KEY (SenderId) REFERENCES iam.Users(UserId);
GO

ALTER TABLE mkt.Messages WITH CHECK
    ADD CONSTRAINT FK_Messages_Users_ReceiverId FOREIGN KEY (ReceiverId) REFERENCES iam.Users(UserId);
GO
