-- Create and seed the product catalog. Idempotent: safe to re-run on every deploy.
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Products' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.Products (
        Id    INT IDENTITY(1,1) PRIMARY KEY,
        Name  NVARCHAR(200)  NOT NULL,
        Price DECIMAL(10, 2) NOT NULL
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Products)
BEGIN
    INSERT INTO dbo.Products (Name, Price) VALUES
        (N'Quantum Widget',       19.99),
        (N'Hyperflux Capacitor',  49.50),
        (N'Nano Sprocket',         7.25),
        (N'Plasma Coil',          89.00);
END;
GO
