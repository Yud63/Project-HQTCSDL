/* ============================================================
   File    : database/05_functions/mkt.sql
   Module  : mkt - M7 Marketplace
   Purpose : Function: fn_CalcMarketplaceFee, fn_SellerRating.
   Owner   : D (xem docs/Phan-cong.md)
   Depends : iam
   Re-run  : CREATE OR ALTER - chạy lại bao nhiêu lần cũng được.
   Ref     : docs/Conventions.md, docs/Contracts.md, docs/DataDictionary.xlsx
   ============================================================ */
USE FilmLabDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = N'seq_TransactionCode' AND schema_id = SCHEMA_ID(N'mkt'))
    CREATE SEQUENCE mkt.seq_TransactionCode AS BIGINT START WITH 5 INCREMENT BY 1;
GO

CREATE OR ALTER FUNCTION mkt.fn_CalcMarketplaceFee (@Amount DECIMAL(18,0), @OnDate DATE)
RETURNS DECIMAL(18,0)
AS
BEGIN
    DECLARE @Rate DECIMAL(5,4), @Fixed DECIMAL(18,0), @Found BIT = 0, @Fee DECIMAL(18,0);

    SELECT TOP 1 @Rate = Rate, @Fixed = FixedAmount, @Found = 1
    FROM ord.FeeConfigs
    WHERE FeeType = N'MarketplaceFee'
      AND ScopeLabId IS NULL
      AND EffectiveFrom <= @OnDate
      AND (EffectiveTo IS NULL OR EffectiveTo >= @OnDate)
    ORDER BY EffectiveFrom DESC, FeeConfigId DESC;

    IF @Found = 0 SET @Rate = 0.05;

    SET @Amount = ISNULL(@Amount, 0);
    SET @Fee = ROUND(@Amount * ISNULL(@Rate, 0), 0) + ISNULL(@Fixed, 0);
    IF @Fee > @Amount SET @Fee = @Amount;
    RETURN @Fee;
END
GO

CREATE OR ALTER FUNCTION mkt.fn_SellerRating (@SellerId INT)
RETURNS DECIMAL(3,2)
AS
BEGIN
    DECLARE @r DECIMAL(3,2);
    SELECT @r = CAST(AVG(CAST(BuyerRating AS DECIMAL(5,2))) AS DECIMAL(3,2))
    FROM mkt.MarketTransactions
    WHERE SellerId = @SellerId AND BuyerRating IS NOT NULL;
    RETURN @r;
END
GO
