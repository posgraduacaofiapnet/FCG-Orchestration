SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

USE FCGCatalogDb;
GO

IF OBJECT_ID(N'dbo.Games', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Games
    (
        Id uniqueidentifier NOT NULL,
        Title nvarchar(150) NOT NULL,
        Description nvarchar(500) NOT NULL,
        Price decimal(18,2) NOT NULL,
        IsActive bit NOT NULL,
        CONSTRAINT PK_Games PRIMARY KEY (Id)
    );
END;
GO

IF OBJECT_ID(N'dbo.Orders', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Orders
    (
        Id uniqueidentifier NOT NULL,
        UserId uniqueidentifier NOT NULL,
        GameId uniqueidentifier NOT NULL,
        GameTitle nvarchar(150) NOT NULL,
        UserEmail nvarchar(320) NOT NULL,
        Price decimal(18,2) NOT NULL,
        Status nvarchar(30) NOT NULL,
        CreatedAt datetime2 NOT NULL,
        CONSTRAINT PK_Orders PRIMARY KEY (Id)
    );
END;
GO

IF COL_LENGTH(N'dbo.Orders', N'UserEmail') IS NULL
BEGIN
    ALTER TABLE dbo.Orders ADD UserEmail nvarchar(320) NULL;
    UPDATE dbo.Orders SET UserEmail = N'unknown@invalid.local' WHERE UserEmail IS NULL;
    ALTER TABLE dbo.Orders ALTER COLUMN UserEmail nvarchar(320) NOT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Orders_UserId_GameId_Pending'
      AND object_id = OBJECT_ID(N'dbo.Orders')
)
BEGIN
    CREATE UNIQUE INDEX IX_Orders_UserId_GameId_Pending
        ON dbo.Orders (UserId, GameId)
        WHERE Status = N'Pending';
END;
GO

IF OBJECT_ID(N'dbo.LibraryItems', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.LibraryItems
    (
        Id uniqueidentifier NOT NULL,
        UserId uniqueidentifier NOT NULL,
        GameId uniqueidentifier NOT NULL,
        AcquiredAt datetime2 NOT NULL,
        CONSTRAINT PK_LibraryItems PRIMARY KEY (Id)
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_LibraryItems_UserId_GameId'
      AND object_id = OBJECT_ID(N'dbo.LibraryItems')
)
BEGIN
    CREATE UNIQUE INDEX IX_LibraryItems_UserId_GameId
        ON dbo.LibraryItems (UserId, GameId);
END;
GO

IF OBJECT_ID(N'dbo.OutboxMessages', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.OutboxMessages
    (
        Id uniqueidentifier NOT NULL,
        EventType nvarchar(100) NOT NULL,
        IsSuccessful bit NOT NULL CONSTRAINT DF_OutboxMessages_IsSuccessful DEFAULT (0),
        CreatedAt datetimeoffset NOT NULL,
        Payload nvarchar(max) NOT NULL,
        NextAttemptAt datetimeoffset NULL,
        Attempts int NOT NULL CONSTRAINT DF_OutboxMessages_Attempts DEFAULT (0),
        CONSTRAINT PK_OutboxMessages PRIMARY KEY (Id),
        CONSTRAINT CK_OutboxMessages_Attempts CHECK (Attempts >= 0),
        CONSTRAINT CK_OutboxMessages_Payload_IsJson CHECK (ISJSON(Payload) = 1),
        CONSTRAINT CK_OutboxMessages_EventType_NotEmpty CHECK (LEN(LTRIM(RTRIM(EventType))) > 0)
    );
END;
GO

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_OutboxMessages_Pending_NextAttemptAt_CreatedAt'
      AND object_id = OBJECT_ID(N'dbo.OutboxMessages')
      AND
      (
          filter_definition IS NULL
          OR filter_definition NOT LIKE N'%Attempts%10%'
      )
)
BEGIN
    DROP INDEX IX_OutboxMessages_Pending_NextAttemptAt_CreatedAt ON dbo.OutboxMessages;
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_OutboxMessages_Pending_NextAttemptAt_CreatedAt'
      AND object_id = OBJECT_ID(N'dbo.OutboxMessages')
)
BEGIN
    CREATE INDEX IX_OutboxMessages_Pending_NextAttemptAt_CreatedAt
        ON dbo.OutboxMessages (NextAttemptAt, CreatedAt, Id)
        INCLUDE (EventType, Payload, Attempts)
        WHERE IsSuccessful = 0 AND Attempts < 10;
END;
GO

IF SCHEMA_ID(N'messaging') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA messaging');
END;
GO

IF OBJECT_ID(N'messaging.InboxState', N'U') IS NULL
BEGIN
    CREATE TABLE messaging.InboxState
    (
        Id bigint NOT NULL IDENTITY,
        MessageId uniqueidentifier NOT NULL,
        ConsumerId uniqueidentifier NOT NULL,
        LockId uniqueidentifier NOT NULL,
        RowVersion rowversion NULL,
        Received datetime2 NOT NULL,
        ReceiveCount int NOT NULL,
        ExpirationTime datetime2 NULL,
        Consumed datetime2 NULL,
        Delivered datetime2 NULL,
        LastSequenceNumber bigint NULL,
        CONSTRAINT PK_InboxState PRIMARY KEY (Id),
        CONSTRAINT AK_InboxState_MessageId_ConsumerId UNIQUE (MessageId, ConsumerId)
    );
END;
GO

IF OBJECT_ID(N'messaging.OutboxState', N'U') IS NULL
BEGIN
    CREATE TABLE messaging.OutboxState
    (
        OutboxId uniqueidentifier NOT NULL,
        LockId uniqueidentifier NOT NULL,
        RowVersion rowversion NULL,
        Created datetime2 NOT NULL,
        Delivered datetime2 NULL,
        LastSequenceNumber bigint NULL,
        CONSTRAINT PK_OutboxState PRIMARY KEY (OutboxId)
    );
END;
GO

IF OBJECT_ID(N'messaging.OutboxMessage', N'U') IS NULL
BEGIN
    CREATE TABLE messaging.OutboxMessage
    (
        SequenceNumber bigint NOT NULL IDENTITY,
        EnqueueTime datetime2 NULL,
        SentTime datetime2 NOT NULL,
        Headers nvarchar(max) NULL,
        Properties nvarchar(max) NULL,
        InboxMessageId uniqueidentifier NULL,
        InboxConsumerId uniqueidentifier NULL,
        OutboxId uniqueidentifier NULL,
        MessageId uniqueidentifier NOT NULL,
        ContentType nvarchar(256) NOT NULL,
        MessageType nvarchar(max) NOT NULL,
        Body nvarchar(max) NOT NULL,
        ConversationId uniqueidentifier NULL,
        CorrelationId uniqueidentifier NULL,
        InitiatorId uniqueidentifier NULL,
        RequestId uniqueidentifier NULL,
        SourceAddress nvarchar(256) NULL,
        DestinationAddress nvarchar(256) NULL,
        ResponseAddress nvarchar(256) NULL,
        FaultAddress nvarchar(256) NULL,
        ExpirationTime datetime2 NULL,
        CONSTRAINT PK_OutboxMessage PRIMARY KEY (SequenceNumber),
        CONSTRAINT FK_OutboxMessage_InboxState_InboxMessageId_InboxConsumerId
            FOREIGN KEY (InboxMessageId, InboxConsumerId)
            REFERENCES messaging.InboxState (MessageId, ConsumerId),
        CONSTRAINT FK_OutboxMessage_OutboxState_OutboxId
            FOREIGN KEY (OutboxId)
            REFERENCES messaging.OutboxState (OutboxId)
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_InboxState_Delivered'
      AND object_id = OBJECT_ID(N'messaging.InboxState')
)
BEGIN
    CREATE INDEX IX_InboxState_Delivered ON messaging.InboxState (Delivered);
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_OutboxState_Created'
      AND object_id = OBJECT_ID(N'messaging.OutboxState')
)
BEGIN
    CREATE INDEX IX_OutboxState_Created ON messaging.OutboxState (Created);
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_OutboxMessage_EnqueueTime'
      AND object_id = OBJECT_ID(N'messaging.OutboxMessage')
)
BEGIN
    CREATE INDEX IX_OutboxMessage_EnqueueTime ON messaging.OutboxMessage (EnqueueTime);
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_OutboxMessage_ExpirationTime'
      AND object_id = OBJECT_ID(N'messaging.OutboxMessage')
)
BEGIN
    CREATE INDEX IX_OutboxMessage_ExpirationTime ON messaging.OutboxMessage (ExpirationTime);
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_OutboxMessage_InboxMessageId_InboxConsumerId_SequenceNumber'
      AND object_id = OBJECT_ID(N'messaging.OutboxMessage')
)
BEGIN
    CREATE UNIQUE INDEX IX_OutboxMessage_InboxMessageId_InboxConsumerId_SequenceNumber
        ON messaging.OutboxMessage (InboxMessageId, InboxConsumerId, SequenceNumber)
        WHERE InboxMessageId IS NOT NULL AND InboxConsumerId IS NOT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_OutboxMessage_OutboxId_SequenceNumber'
      AND object_id = OBJECT_ID(N'messaging.OutboxMessage')
)
BEGIN
    CREATE UNIQUE INDEX IX_OutboxMessage_OutboxId_SequenceNumber
        ON messaging.OutboxMessage (OutboxId, SequenceNumber)
        WHERE OutboxId IS NOT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_OutboxMessages_Successful_CreatedAt'
      AND object_id = OBJECT_ID(N'dbo.OutboxMessages')
)
BEGIN
    CREATE INDEX IX_OutboxMessages_Successful_CreatedAt
        ON dbo.OutboxMessages (CreatedAt, Id)
        WHERE IsSuccessful = 1;
END;
GO
