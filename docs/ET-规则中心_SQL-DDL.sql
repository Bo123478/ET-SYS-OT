-- ET 规则中心建库脚本（SQL Server）
-- 对齐：docs/ET-规则中心_建库清单.md

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'et_rule')
BEGIN
    EXEC('CREATE SCHEMA et_rule');
END
GO

IF OBJECT_ID('et_rule.RuleSet', 'U') IS NULL
BEGIN
CREATE TABLE et_rule.RuleSet (
    RuleSetId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    Environment NVARCHAR(20) NOT NULL,
    Status NVARCHAR(20) NOT NULL,
    Version NVARCHAR(50) NOT NULL,
    EffectiveFrom DATETIME2(0) NULL,
    Description NVARCHAR(MAX) NULL,
    CreatedByName NVARCHAR(100) NULL,
    ApprovedByName NVARCHAR(100) NULL,
    PublishedByName NVARCHAR(100) NULL,
    CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT CK_RuleSet_Environment CHECK (Environment IN ('Dev','Test','Prod')),
    CONSTRAINT CK_RuleSet_Status CHECK (Status IN ('Draft','Submitted','Approved','Published','Archived')),
    CONSTRAINT UQ_RuleSet_Env_Version UNIQUE(Environment, Version)
);
END
GO

IF OBJECT_ID('et_rule.RuleScope', 'U') IS NULL
BEGIN
CREATE TABLE et_rule.RuleScope (
    RuleScopeId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    RuleSetId UNIQUEIDENTIFIER NOT NULL,
    ProjectCode NVARCHAR(50) NULL,
    EquipmentType NVARCHAR(50) NULL,
    PlantCode NVARCHAR(50) NULL,
    AppGroup NVARCHAR(50) NULL,
    Priority INT NOT NULL DEFAULT 100,
    Enabled BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_RuleScope_RuleSet FOREIGN KEY (RuleSetId) REFERENCES et_rule.RuleSet(RuleSetId)
);
END
GO

IF OBJECT_ID('et_rule.RuleItem', 'U') IS NULL
BEGIN
CREATE TABLE et_rule.RuleItem (
    RuleItemId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    RuleSetId UNIQUEIDENTIFIER NOT NULL,
    RuleScopeId UNIQUEIDENTIFIER NULL,
    RuleCode NVARCHAR(80) NOT NULL,
    Category NVARCHAR(30) NOT NULL,
    Severity NVARCHAR(20) NOT NULL,
    Enabled BIT NOT NULL DEFAULT 1,
    MatcherJson NVARCHAR(MAX) NOT NULL,
    ExpectJson NVARCHAR(MAX) NOT NULL,
    [Operator] NVARCHAR(30) NOT NULL,
    UnknownPolicy NVARCHAR(30) NOT NULL,
    MessageTemplate NVARCHAR(MAX) NULL,
    SortOrder INT NULL,
    CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_RuleItem_RuleSet FOREIGN KEY (RuleSetId) REFERENCES et_rule.RuleSet(RuleSetId),
    CONSTRAINT FK_RuleItem_RuleScope FOREIGN KEY (RuleScopeId) REFERENCES et_rule.RuleScope(RuleScopeId),
    CONSTRAINT CK_RuleItem_Category CHECK (Category IN ('AppVersion','WindowsService','ComPort','HostMapping')),
    CONSTRAINT CK_RuleItem_Severity CHECK (Severity IN ('Info','Warn','Alarm')),
    CONSTRAINT CK_RuleItem_UnknownPolicy CHECK (UnknownPolicy IN ('UnknownAsAlarm','UnknownAsWarn','Ignore')),
    CONSTRAINT UQ_RuleItem_RuleCode UNIQUE(RuleCode),
    CONSTRAINT CK_RuleItem_MatcherJson_IsJson CHECK (ISJSON(MatcherJson) = 1),
    CONSTRAINT CK_RuleItem_ExpectJson_IsJson CHECK (ISJSON(ExpectJson) = 1)
);
END
GO

IF OBJECT_ID('et_rule.PublishRecord', 'U') IS NULL
BEGIN
CREATE TABLE et_rule.PublishRecord (
    PublishRecordId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    RuleSetId UNIQUEIDENTIFIER NOT NULL,
    Version NVARCHAR(50) NOT NULL,
    ArtifactPath NVARCHAR(500) NOT NULL,
    ArtifactHash NVARCHAR(128) NOT NULL,
    PreviousVersion NVARCHAR(50) NULL,
    PublishedByName NVARCHAR(100) NOT NULL,
    PublishedAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    Status NVARCHAR(20) NOT NULL,
    ErrorMessage NVARCHAR(MAX) NULL,
    CONSTRAINT FK_PublishRecord_RuleSet FOREIGN KEY (RuleSetId) REFERENCES et_rule.RuleSet(RuleSetId),
    CONSTRAINT CK_PublishRecord_Status CHECK (Status IN ('Success','Failed','RolledBack'))
);
END
GO

IF OBJECT_ID('et_rule.ChangeLog', 'U') IS NULL
BEGIN
CREATE TABLE et_rule.ChangeLog (
    ChangeLogId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
    EntityName NVARCHAR(80) NOT NULL,
    EntityId NVARCHAR(64) NOT NULL,
    [Action] NVARCHAR(30) NOT NULL,
    BeforeJson NVARCHAR(MAX) NULL,
    AfterJson NVARCHAR(MAX) NULL,
    Actor NVARCHAR(100) NOT NULL,
    OccurredAt DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT CK_ChangeLog_Action CHECK ([Action] IN ('Create','Update','Delete','Submit','Approve','Publish','Rollback')),
    CONSTRAINT CK_ChangeLog_BeforeJson_IsJson CHECK (BeforeJson IS NULL OR ISJSON(BeforeJson) = 1),
    CONSTRAINT CK_ChangeLog_AfterJson_IsJson CHECK (AfterJson IS NULL OR ISJSON(AfterJson) = 1)
);
END
GO

-- 索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RuleSet_Env_Status_Version' AND object_id = OBJECT_ID('et_rule.RuleSet'))
CREATE INDEX IX_RuleSet_Env_Status_Version ON et_rule.RuleSet(Environment, Status, Version);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RuleScope_Query' AND object_id = OBJECT_ID('et_rule.RuleScope'))
CREATE INDEX IX_RuleScope_Query ON et_rule.RuleScope(RuleSetId, ProjectCode, EquipmentType, Priority);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RuleItem_Query' AND object_id = OBJECT_ID('et_rule.RuleItem'))
CREATE INDEX IX_RuleItem_Query ON et_rule.RuleItem(RuleSetId, Category, Enabled, SortOrder);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PublishRecord_RuleSet_PublishedAt' AND object_id = OBJECT_ID('et_rule.PublishRecord'))
CREATE INDEX IX_PublishRecord_RuleSet_PublishedAt ON et_rule.PublishRecord(RuleSetId, PublishedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ChangeLog_Entity' AND object_id = OBJECT_ID('et_rule.ChangeLog'))
CREATE INDEX IX_ChangeLog_Entity ON et_rule.ChangeLog(EntityName, EntityId, OccurredAt DESC);
GO
