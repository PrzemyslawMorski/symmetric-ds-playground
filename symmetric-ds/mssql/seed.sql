IF DB_ID('SuppliersDb') IS NULL
BEGIN
    CREATE DATABASE SuppliersDb;
END
GO
USE SuppliersDb;
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
-- Seed a couple of demo rows if table is empty
IF NOT EXISTS (SELECT 1 FROM dbo.Suppliers)
BEGIN
    INSERT INTO dbo.Suppliers (Id, Name, Active)
    VALUES (NEWID(), N'Acme Air', 1);

    INSERT INTO dbo.Suppliers (Id, Name, Active)
    VALUES (NEWID(), N'Contoso Travel', 1);
END
GO

