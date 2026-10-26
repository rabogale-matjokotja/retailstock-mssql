/* ============================================================
   RetailStock: Inventory & Sales Database (MS SQL Server)
   Problem: a retailer loses money on stockouts and overstock.
   This schema tracks stock, sales and supplier orders so that
   reorder needs and slow-moving stock are visible automatically.
   ============================================================ */

IF DB_ID('RetailStock') IS NULL CREATE DATABASE RetailStock;
GO
USE RetailStock;
GO

/* ---------- Tables ---------- */

CREATE TABLE dbo.Categories (
    CategoryID   INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE dbo.Suppliers (
    SupplierID   INT IDENTITY(1,1) PRIMARY KEY,
    SupplierName NVARCHAR(150) NOT NULL,
    Email        NVARCHAR(150) NULL,
    Phone        NVARCHAR(30)  NULL,
    LeadTimeDays INT NOT NULL CONSTRAINT DF_Suppliers_Lead DEFAULT 7
        CONSTRAINT CK_Suppliers_Lead CHECK (LeadTimeDays >= 0)
);

CREATE TABLE dbo.Products (
    ProductID    INT IDENTITY(1,1) PRIMARY KEY,
    SKU          NVARCHAR(30)  NOT NULL UNIQUE,
    ProductName  NVARCHAR(150) NOT NULL,
    CategoryID   INT NOT NULL REFERENCES dbo.Categories(CategoryID),
    SupplierID   INT NOT NULL REFERENCES dbo.Suppliers(SupplierID),
    CostPrice    DECIMAL(10,2) NOT NULL CHECK (CostPrice >= 0),
    SellPrice    DECIMAL(10,2) NOT NULL CHECK (SellPrice >= 0),
    ReorderLevel INT NOT NULL CONSTRAINT DF_Products_RL DEFAULT 10 CHECK (ReorderLevel >= 0),
    ReorderQty   INT NOT NULL CONSTRAINT DF_Products_RQ DEFAULT 50 CHECK (ReorderQty > 0),
    IsActive     BIT NOT NULL CONSTRAINT DF_Products_Active DEFAULT 1
);

CREATE TABLE dbo.Inventory (
    ProductID    INT PRIMARY KEY REFERENCES dbo.Products(ProductID),
    QtyOnHand    INT NOT NULL CONSTRAINT DF_Inv_Qty DEFAULT 0 CHECK (QtyOnHand >= 0),
    LastUpdated  DATETIME2 NOT NULL CONSTRAINT DF_Inv_Upd DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FullName   NVARCHAR(150) NOT NULL,
    Email      NVARCHAR(150) NULL,
    City       NVARCHAR(80)  NULL
);

CREATE TABLE dbo.Orders (
    OrderID    INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES dbo.Customers(CustomerID),
    OrderDate  DATETIME2 NOT NULL CONSTRAINT DF_Orders_Date DEFAULT SYSDATETIME(),
    Status     NVARCHAR(20) NOT NULL CONSTRAINT DF_Orders_Status DEFAULT 'Completed'
        CONSTRAINT CK_Orders_Status CHECK (Status IN ('Completed','Cancelled','Refunded'))
);

CREATE TABLE dbo.OrderItems (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID     INT NOT NULL REFERENCES dbo.Orders(OrderID),
    ProductID   INT NOT NULL REFERENCES dbo.Products(ProductID),
    Quantity    INT NOT NULL CHECK (Quantity > 0),
    UnitPrice   DECIMAL(10,2) NOT NULL CHECK (UnitPrice >= 0),  -- price at time of sale
    CONSTRAINT UQ_OrderItems UNIQUE (OrderID, ProductID)
);

CREATE TABLE dbo.PurchaseOrders (
    PurchaseOrderID INT IDENTITY(1,1) PRIMARY KEY,
    SupplierID      INT NOT NULL REFERENCES dbo.Suppliers(SupplierID),
    OrderedOn       DATETIME2 NOT NULL CONSTRAINT DF_PO_Date DEFAULT SYSDATETIME(),
    Status          NVARCHAR(20) NOT NULL CONSTRAINT DF_PO_Status DEFAULT 'Pending'
        CONSTRAINT CK_PO_Status CHECK (Status IN ('Pending','Received','Cancelled'))
);

CREATE TABLE dbo.PurchaseOrderItems (
    PurchaseOrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    PurchaseOrderID INT NOT NULL REFERENCES dbo.PurchaseOrders(PurchaseOrderID),
    ProductID       INT NOT NULL REFERENCES dbo.Products(ProductID),
    Quantity        INT NOT NULL CHECK (Quantity > 0),
    UnitCost        DECIMAL(10,2) NOT NULL CHECK (UnitCost >= 0)
);

CREATE TABLE dbo.StockMovements (
    MovementID   BIGINT IDENTITY(1,1) PRIMARY KEY,
    ProductID    INT NOT NULL REFERENCES dbo.Products(ProductID),
    QtyChange    INT NOT NULL,                       -- negative = sale, positive = restock
    Reason       NVARCHAR(30) NOT NULL,              -- 'Sale','Restock','Adjustment'
    MovedAt      DATETIME2 NOT NULL CONSTRAINT DF_SM_At DEFAULT SYSDATETIME()
);
GO

/* ---------- Indexes (each one has a reason) ---------- */

-- Sales reports filter and group by date constantly
CREATE INDEX IX_Orders_OrderDate ON dbo.Orders(OrderDate) INCLUDE (CustomerID, Status);
-- Joining items back to products for revenue-per-product queries
CREATE INDEX IX_OrderItems_ProductID ON dbo.OrderItems(ProductID) INCLUDE (Quantity, UnitPrice);
-- Movement history is queried per product over time
CREATE INDEX IX_StockMovements_Product_Date ON dbo.StockMovements(ProductID, MovedAt);
GO

/* ---------- Trigger: keep stock in sync with sales ---------- */

CREATE OR ALTER TRIGGER dbo.trg_OrderItems_AfterInsert
ON dbo.OrderItems
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE inv
       SET inv.QtyOnHand   = inv.QtyOnHand - s.TotalQty,
           inv.LastUpdated = SYSDATETIME()
      FROM dbo.Inventory inv
      JOIN (SELECT ProductID, SUM(Quantity) AS TotalQty
              FROM inserted GROUP BY ProductID) s
        ON s.ProductID = inv.ProductID;

    INSERT dbo.StockMovements (ProductID, QtyChange, Reason)
    SELECT ProductID, -SUM(Quantity), 'Sale'
      FROM inserted GROUP BY ProductID;
    -- If stock would go below zero, the CHECK on QtyOnHand fails
    -- and the whole sale is rolled back (no overselling).
END;
GO

/* ---------- View: products that need reordering ---------- */

CREATE OR ALTER VIEW dbo.vw_ReorderNeeded AS
SELECT p.ProductID, p.SKU, p.ProductName, s.SupplierName,
       i.QtyOnHand, p.ReorderLevel, p.ReorderQty, s.LeadTimeDays
  FROM dbo.Products p
  JOIN dbo.Inventory i ON i.ProductID = p.ProductID
  JOIN dbo.Suppliers s ON s.SupplierID = p.SupplierID
 WHERE p.IsActive = 1
   AND i.QtyOnHand <= p.ReorderLevel;
GO

/* ---------- View: slow-moving stock (no sales in 90 days) ---------- */

CREATE OR ALTER VIEW dbo.vw_SlowMovers AS
SELECT p.ProductID, p.SKU, p.ProductName, i.QtyOnHand,
       i.QtyOnHand * p.CostPrice AS CapitalTiedUp,
       MAX(o.OrderDate) AS LastSoldOn
  FROM dbo.Products p
  JOIN dbo.Inventory i ON i.ProductID = p.ProductID
  LEFT JOIN dbo.OrderItems oi ON oi.ProductID = p.ProductID
  LEFT JOIN dbo.Orders o ON o.OrderID = oi.OrderID AND o.Status = 'Completed'
 WHERE p.IsActive = 1 AND i.QtyOnHand > 0
 GROUP BY p.ProductID, p.SKU, p.ProductName, i.QtyOnHand, p.CostPrice
HAVING MAX(o.OrderDate) IS NULL
    OR MAX(o.OrderDate) < DATEADD(DAY, -90, SYSDATETIME());
GO

/* ---------- Procedure: create purchase orders for low stock ---------- */

CREATE OR ALTER PROCEDURE dbo.usp_GenerateReorders
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @Created TABLE (PurchaseOrderID INT, SupplierID INT);

        -- One purchase order per supplier that has products to reorder
        INSERT dbo.PurchaseOrders (SupplierID)
        OUTPUT inserted.PurchaseOrderID, inserted.SupplierID INTO @Created
        SELECT DISTINCT p.SupplierID
          FROM dbo.vw_ReorderNeeded r
          JOIN dbo.Products p ON p.ProductID = r.ProductID
         WHERE NOT EXISTS (   -- skip products already on a pending PO
               SELECT 1 FROM dbo.PurchaseOrderItems poi
                 JOIN dbo.PurchaseOrders po ON po.PurchaseOrderID = poi.PurchaseOrderID
                WHERE poi.ProductID = r.ProductID AND po.Status = 'Pending');

        INSERT dbo.PurchaseOrderItems (PurchaseOrderID, ProductID, Quantity, UnitCost)
        SELECT c.PurchaseOrderID, p.ProductID, p.ReorderQty, p.CostPrice
          FROM @Created c
          JOIN dbo.Products p ON p.SupplierID = c.SupplierID
          JOIN dbo.vw_ReorderNeeded r ON r.ProductID = p.ProductID
         WHERE NOT EXISTS (
               SELECT 1 FROM dbo.PurchaseOrderItems poi
                 JOIN dbo.PurchaseOrders po ON po.PurchaseOrderID = poi.PurchaseOrderID
                WHERE poi.ProductID = p.ProductID AND po.Status = 'Pending'
                  AND po.PurchaseOrderID <> c.PurchaseOrderID);

        -- Remove any PO that ended up with no items
        DELETE po FROM dbo.PurchaseOrders po
         WHERE po.PurchaseOrderID IN (SELECT PurchaseOrderID FROM @Created)
           AND NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrderItems
                            WHERE PurchaseOrderID = po.PurchaseOrderID);

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
