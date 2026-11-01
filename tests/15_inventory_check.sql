USE FilmLabDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Danh mục chuẩn: Contracts mục 8 + ord.fn_IsValidComplaintTransition (function thứ 15, được nhóm thêm)
CREATE TABLE #exp (SchemaName SYSNAME COLLATE DATABASE_DEFAULT,
                   ObjName    SYSNAME COLLATE DATABASE_DEFAULT,
                   Kind       CHAR(1) COLLATE DATABASE_DEFAULT);
INSERT #exp VALUES

 -- Procedure (51)
 (N'iam',N'sp_RegisterUser','P'),
 (N'lab',N'sp_ApproveLab','P'),(N'lab',N'sp_SearchLabs','P'),(N'lab',N'sp_RecalcLabRating','P'),
 (N'ord',N'sp_CreateOrder','P'),(N'ord',N'sp_UpdateOrderStage','P'),(N'ord',N'sp_CancelOrder','P'),(N'ord',N'sp_ProcessPayment','P'),
 (N'ord',N'sp_AddReview','P'),(N'ord',N'sp_FileComplaint','P'),(N'ord',N'sp_ResolveComplaint','P'),(N'ord',N'sp_ReplyReview','P'),(N'ord',N'sp_ModerateReview','P'),
 (N'dlv',N'sp_UpdateDeliveryStatus','P'),(N'dlv',N'sp_RequestDelivery','P'),(N'dlv',N'sp_AssignPartner','P'),
 (N'arc',N'sp_UploadScan','P'),(N'arc',N'sp_SetScanQuality','P'),(N'arc',N'sp_CreateNotification','P'),(N'arc',N'sp_MarkNotificationRead','P'),
 (N'mkt',N'sp_CreateListing','P'),(N'mkt',N'sp_PlaceMarketOrder','P'),(N'mkt',N'sp_SearchListings','P'),(N'mkt',N'sp_UpdateMarketTransaction','P'),
 (N'mkt',N'sp_ResolveDispute','P'),(N'mkt',N'sp_RateSeller','P'),(N'mkt',N'sp_SendMessage','P'),(N'mkt',N'sp_ModerateListing','P'),(N'mkt',N'sp_RunMaintenance','P'),
 (N'com',N'sp_RegisterEvent','P'),(N'com',N'sp_PublishArticle','P'),(N'com',N'sp_ModerateArticle','P'),(N'com',N'sp_AddComment','P'),(N'com',N'sp_AcceptAnswer','P'),(N'com',N'sp_CancelEventRegistration','P'),
 (N'ai',N'sp_GetLabRecommendations','P'),(N'ai',N'sp_SaveUserPreferences','P'),(N'ai',N'sp_LogChatMessage','P'),(N'ai',N'sp_RecordRecommendationAction','P'),(N'ai',N'sp_ApproveKnowledgeDoc','P'),(N'ai',N'sp_PurgeOldLogs','P'),
 (N'audit',N'sp_WriteAudit','P'),
 (N'iam',N'sp_SaveAddress','P'),(N'iam',N'sp_SetUserStatus','P'),(N'iam',N'sp_AssignRole','P'),
 (N'lab',N'sp_SaveLabProfile','P'),(N'lab',N'sp_SaveLabService','P'),
 (N'ord',N'sp_SetFeeConfig','P'),
 (N'arc',N'sp_SaveAlbum','P'),(N'arc',N'sp_SetAlbumPhoto','P'),
 (N'com',N'sp_SaveEvent','P'),
 -- Function (14 + 1)
 (N'lab',N'fn_LabCapacityLeft','F'),(N'lab',N'fn_DistanceKm','F'),
 (N'ord',N'fn_CalcOrderTotal','F'),(N'ord',N'fn_CalcPlatformFee','F'),(N'ord',N'fn_NextStage','F'),(N'ord',N'fn_IsValidTransition','F'),(N'ord',N'fn_CalcDeliveryFee','F'),(N'ord',N'fn_LabAvgRating','F'),
 (N'ord',N'fn_IsValidComplaintTransition','F'),
 (N'dlv',N'fn_IsValidDeliveryTransition','F'),(N'arc',N'fn_GetPhotoMetadata','F'),
 (N'mkt',N'fn_CalcMarketplaceFee','F'),(N'mkt',N'fn_SellerRating','F'),
 (N'com',N'fn_EventSeatsLeft','F'),(N'ai',N'fn_LabScores','F'),
 -- View (14)
 (N'lab',N'vw_TopLabs','V'),
 (N'ord',N'vw_LabRevenue','V'),(N'ord',N'vw_OrdersInProgress','V'),(N'ord',N'vw_LabReviews','V'),(N'ord',N'vw_OpenComplaints','V'),
 (N'dlv',N'vw_DeliveryBoard','V'),(N'arc',N'vw_CustomerArchive','V'),
 (N'mkt',N'vw_MarketActive','V'),(N'mkt',N'vw_SellerStats','V'),
 (N'com',N'vw_ExpertContributions','V'),(N'com',N'vw_UpcomingEvents','V'),
 (N'ai',N'vw_RecommendationMetrics','V'),
 (N'audit',N'vw_RecentChanges','V'),(N'audit',N'vw_AdminDashboard','V'),
 -- Trigger (28)
 (N'iam',N'trg_Users_Audit','T'),
 (N'lab',N'trg_LabServices_CheckScan','T'),(N'lab',N'trg_FilmLabs_Audit','T'),
 (N'ord',N'trg_Orders_LogStage','T'),(N'ord',N'trg_Orders_PreventInvalidStage','T'),(N'ord',N'trg_Payments_UpdateOrder','T'),(N'ord',N'trg_FeeConfigs_NoOverlap','T'),(N'ord',N'trg_Payments_Audit','T'),
 (N'ord',N'trg_Reviews_CheckEligible','T'),(N'ord',N'trg_Reviews_UpdateRating','T'),(N'ord',N'trg_Complaints_Guard','T'),(N'ord',N'trg_Complaints_Notify','T'),(N'ord',N'trg_Complaints_Audit','T'),
 (N'dlv',N'trg_DeliveryRequests_LogStatus','T'),(N'dlv',N'trg_DeliveryRequests_Guard','T'),
 (N'arc',N'trg_ScanFiles_Notify','T'),(N'arc',N'trg_ScanFiles_CheckOwner','T'),(N'arc',N'trg_AlbumPhotos_CheckOwner','T'),
 (N'mkt',N'trg_Listings_Guard','T'),(N'mkt',N'trg_ListingImages_Limit','T'),(N'mkt',N'trg_MarketTransactions_Guard','T'),(N'mkt',N'trg_Messages_CheckParties','T'),(N'mkt',N'trg_Listings_Audit','T'),(N'mkt',N'trg_MarketTransactions_Audit','T'),
 (N'com',N'trg_Articles_CheckAuthorRole','T'),(N'com',N'trg_ArticleComments_CheckLevel','T'),(N'com',N'trg_EventRegistrations_CheckSeats','T'),
 (N'ai',N'trg_KnowledgeDocs_Guard','T'),
 -- Sequence (2)
 (N'ord',N'seq_OrderCode','S'),(N'mkt',N'seq_TransactionCode','S');

CREATE TABLE #act (SchemaName SYSNAME COLLATE DATABASE_DEFAULT,
                   ObjName    SYSNAME COLLATE DATABASE_DEFAULT,
                   Kind       CHAR(1) COLLATE DATABASE_DEFAULT);
INSERT #act (SchemaName, ObjName, Kind)
SELECT SCHEMA_NAME(o.schema_id), o.name,
       CASE WHEN o.type = 'P' THEN 'P'
            WHEN o.type IN ('FN','IF','TF') THEN 'F'
            WHEN o.type = 'V' THEN 'V'
            WHEN o.type = 'TR' THEN 'T'
            WHEN o.type = 'SO' THEN 'S' END
FROM sys.objects o
WHERE o.is_ms_shipped = 0
  AND o.type IN ('P','FN','IF','TF','V','TR','SO')
  AND SCHEMA_NAME(o.schema_id) IN (N'iam',N'lab',N'ord',N'dlv',N'arc',N'mkt',N'com',N'ai',N'audit');

-- Chi tiết thiếu / thừa (rỗng nghĩa là khớp)
SELECT N'MISSING' AS Tag, e.Kind, e.SchemaName, e.ObjName FROM #exp e
WHERE NOT EXISTS (SELECT 1 FROM #act a WHERE a.Kind = e.Kind AND a.SchemaName = e.SchemaName AND a.ObjName = e.ObjName)
UNION ALL
SELECT N'EXTRA', a.Kind, a.SchemaName, a.ObjName FROM #act a
WHERE NOT EXISTS (SELECT 1 FROM #exp e WHERE a.Kind = e.Kind AND a.SchemaName = e.SchemaName AND a.ObjName = e.ObjName);

SELECT k.Kind,
       (SELECT COUNT(*) FROM #exp WHERE Kind = k.Kind) AS Expected,
       (SELECT COUNT(*) FROM #act WHERE Kind = k.Kind) AS Actual,
       (SELECT COUNT(*) FROM #exp e WHERE e.Kind = k.Kind AND NOT EXISTS
          (SELECT 1 FROM #act a WHERE a.Kind = e.Kind AND a.SchemaName = e.SchemaName AND a.ObjName = e.ObjName)) AS Missing,
       (SELECT COUNT(*) FROM #act a WHERE a.Kind = k.Kind AND NOT EXISTS
          (SELECT 1 FROM #exp e WHERE e.Kind = a.Kind AND e.SchemaName = a.SchemaName AND e.ObjName = a.ObjName)) AS Extra
INTO #res
FROM (VALUES ('P'),('F'),('V'),('T'),('S')) k(Kind);

DECLARE @Kind CHAR(1), @Exp INT, @Act INT, @Mis INT, @Ext INT, @Label NVARCHAR(20);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Kind, Expected, Actual, Missing, Extra FROM #res ORDER BY Kind;
OPEN c;
FETCH NEXT FROM c INTO @Kind, @Exp, @Act, @Mis, @Ext;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Label = CASE @Kind WHEN 'P' THEN N'Procedure' WHEN 'F' THEN N'Function' WHEN 'V' THEN N'View'
                            WHEN 'T' THEN N'Trigger' ELSE N'Sequence' END;
    PRINT CASE WHEN @Mis = 0 AND @Ext = 0
               THEN N'PASS: ' + @Label + N' khớp danh mục (' + CAST(@Act AS NVARCHAR(10)) + N')'
               ELSE N'FAIL: ' + @Label + N' thiếu ' + CAST(@Mis AS NVARCHAR(10)) + N', thừa ' + CAST(@Ext AS NVARCHAR(10))
                    + N' (mong đợi ' + CAST(@Exp AS NVARCHAR(10)) + N', thực tế ' + CAST(@Act AS NVARCHAR(10)) + N')' END;
    FETCH NEXT FROM c INTO @Kind, @Exp, @Act, @Mis, @Ext;
END;
CLOSE c;
DEALLOCATE c;

-- Trigger bị tắt (test ép giai đoạn có DISABLE rồi ROLLBACK; không được để sót)
DECLARE @Dis INT = (SELECT COUNT(*) FROM sys.triggers WHERE is_disabled = 1 AND is_ms_shipped = 0 AND parent_class = 1);
PRINT CASE WHEN @Dis = 0 THEN N'PASS: không có trigger nào bị tắt'
           ELSE N'FAIL: có ' + CAST(@Dis AS NVARCHAR(10)) + N' trigger bị tắt' END;

-- Tham chiếu chưa resolve sau khi build xong
SELECT OBJECT_SCHEMA_NAME(d.referencing_id) AS RefSchema, OBJECT_NAME(d.referencing_id) AS RefObj,
       d.referenced_schema_name AS MissingSchema, d.referenced_entity_name AS MissingObj
INTO #unres
FROM sys.sql_expression_dependencies d
WHERE d.referenced_id IS NULL AND d.referenced_database_name IS NULL AND d.referenced_server_name IS NULL
    AND d.is_ambiguous = 0 AND d.referenced_entity_name NOT IN (N'sp_set_session_context', N'inserted', N'deleted');
SELECT * FROM #unres;
DECLARE @Un INT = (SELECT COUNT(*) FROM #unres);
PRINT CASE WHEN @Un = 0 THEN N'PASS: mọi module resolve đủ tham chiếu'
           ELSE N'FAIL: ' + CAST(@Un AS NVARCHAR(10)) + N' tham chiếu chưa resolve (xem bảng trên)' END;

-- Số bảng và FK theo thiết kế
DECLARE @Tb INT = (SELECT COUNT(*) FROM sys.tables t
                   WHERE t.is_ms_shipped = 0 AND t.temporal_type <> 1
                     AND SCHEMA_NAME(t.schema_id) IN (N'iam',N'lab',N'ord',N'dlv',N'arc',N'mkt',N'com',N'ai',N'audit'));
DECLARE @Fk INT = (SELECT COUNT(*) FROM sys.foreign_keys);
PRINT CASE WHEN @Tb = 41 THEN N'PASS: 41 bảng' ELSE N'FAIL: số bảng = ' + CAST(@Tb AS NVARCHAR(10)) + N' (mong đợi 41)' END;
PRINT CASE WHEN @Fk = 77 THEN N'PASS: 77 FK' ELSE N'FAIL: số FK = ' + CAST(@Fk AS NVARCHAR(10)) + N' (mong đợi 77)' END;
GO