USE FCGUsersDb;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users
    (
        Id uniqueidentifier NOT NULL,
        Name nvarchar(150) NOT NULL,
        Email nvarchar(150) NOT NULL,
        PasswordHash nvarchar(max) NOT NULL,
        Role nvarchar(30) NOT NULL,
        CreatedAt datetime2 NOT NULL,
        CONSTRAINT PK_Users PRIMARY KEY (Id)
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Users_Email' AND object_id = OBJECT_ID(N'dbo.Users')
)
BEGIN
    CREATE UNIQUE INDEX IX_Users_Email ON dbo.Users (Email);
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
