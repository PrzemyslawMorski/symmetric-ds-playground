IF DB_ID('SuppliersDb') IS NULL
BEGIN
    CREATE DATABASE SuppliersDb;
END
GO
USE master;

-- Create dedicated Debezium login (idempotent)
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = N'debezium')
BEGIN
    CREATE LOGIN [debezium] WITH PASSWORD = 'Debezium!Passw0rd', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
END
GO

-- Grant server-level permission required by Debezium
IF NOT EXISTS (
    SELECT 1 FROM sys.server_permissions p
    JOIN sys.server_principals sp ON p.grantee_principal_id = sp.principal_id
    WHERE sp.name = N'debezium' AND p.permission_name = 'VIEW SERVER STATE'
)
BEGIN
    GRANT VIEW SERVER STATE TO [debezium];
END
GO

USE SuppliersDb;

-- Map login to database user and grant db_owner (idempotent)
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'debezium')
BEGIN
    CREATE USER [debezium] FOR LOGIN [debezium];
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.database_role_members drm
    JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id AND r.name = N'db_owner'
    JOIN sys.database_principals u ON u.principal_id = drm.member_principal_id AND u.name = N'debezium'
)
BEGIN
    EXEC sp_addrolemember @rolename = N'db_owner', @membername = N'debezium';
END
GO

-- Allow Debezium to read CDC objects and general tables (idempotent schema grant)
BEGIN TRY
    GRANT SELECT ON SCHEMA::cdc TO [debezium];
END TRY
BEGIN CATCH
    -- Schema may not exist yet before sp_cdc_enable_db; safe to ignore
END CATCH
GO

IF OBJECT_ID('dbo.Suppliers','U') IS NULL
BEGIN
    CREATE TABLE dbo.Suppliers (
        Id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        Name NVARCHAR(200) NOT NULL,
        Active BIT NOT NULL DEFAULT(1),
        UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
GO

-- Enable CDC at the database level (idempotent)
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_cdc_enabled = 0)
BEGIN
    EXEC sys.sp_cdc_enable_db;
END
GO

-- Now that CDC is enabled, the cdc schema exists; grant explicit read access
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'cdc')
BEGIN
    BEGIN TRY
        GRANT SELECT ON SCHEMA::cdc TO [debezium];
    END TRY
    BEGIN CATCH
        -- ignore if already granted
    END CATCH
END
GO

-- Also grant EXECUTE on CDC schema procs/functions and SELECT on dbo
USE SuppliersDb;
GO

BEGIN TRY
    GRANT EXECUTE ON SCHEMA::cdc TO [debezium];
END TRY
BEGIN CATCH
END CATCH
GO

BEGIN TRY
    GRANT SELECT ON SCHEMA::dbo TO [debezium];
END TRY
BEGIN CATCH
END CATCH
GO

-- Debezium may require VIEW DATABASE STATE at DB scope for CDC metadata
BEGIN TRY
    GRANT VIEW DATABASE STATE TO [debezium];
END TRY
BEGIN CATCH
END CATCH
GO

-- Enable CDC for dbo.Suppliers (idempotent; use cdc.change_tables to determine status)
IF NOT EXISTS (
    SELECT 1 FROM cdc.change_tables WHERE source_object_id = OBJECT_ID('dbo.Suppliers')
)
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name   = N'Suppliers',
        @role_name     = NULL,
        @supports_net_changes = 0;
END
GO

-- Debezium Signals table (as configured via signal.data.collection = dbo.DebeziumSignals)
IF OBJECT_ID('dbo.DebeziumSignals','U') IS NULL
BEGIN
    CREATE TABLE dbo.DebeziumSignals (
        id        NVARCHAR(64)    NOT NULL,
        type      NVARCHAR(32)    NOT NULL,
        data      NVARCHAR(MAX)   NULL,
        PRIMARY KEY (id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers)
BEGIN
    INSERT INTO dbo.Suppliers (Id, Name, Active)
    VALUES (NEWID(), N'Acme Air', 1),
           (NEWID(), N'Contoso Travel', 1);
END
GO

