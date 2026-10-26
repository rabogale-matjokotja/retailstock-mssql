/* ============================================================
   Queries behind each panel of the dashboard (docs/index.html)
   ============================================================ */
USE RetailStock;
GO

-- 1. KPI cards
SELECT SUM(oi.Quantity * oi.UnitPrice)                         AS Revenue,
       COUNT(DISTINCT o.OrderID)                               AS Orders,
       SUM(oi.Quantity)                                        AS UnitsSold,
       SUM(oi.Quantity * oi.UnitPrice) / COUNT(DISTINCT o.OrderID) AS AvgOrderValue,
       SUM(oi.Quantity * (oi.UnitPrice - p.CostPrice))         AS GrossProfit
  FROM dbo.Orders o
  JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
  JOIN dbo.Products p    ON p.ProductID = oi.ProductID
 WHERE o.Status = 'Completed';

-- 2. Weekly revenue (weeks start on Monday; independent of @@DATEFIRST)
SELECT DATEADD(DAY, -(DATEDIFF(DAY, '19000101', CAST(o.OrderDate AS DATE)) % 7),
               CAST(o.OrderDate AS DATE))     AS WeekStart,
       SUM(oi.Quantity * oi.UnitPrice)        AS Revenue
  FROM dbo.Orders o
  JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
 WHERE o.Status = 'Completed'
 GROUP BY DATEADD(DAY, -(DATEDIFF(DAY, '19000101', CAST(o.OrderDate AS DATE)) % 7),
                  CAST(o.OrderDate AS DATE))
 ORDER BY WeekStart;

-- 3. Revenue by category
SELECT c.CategoryName, SUM(oi.Quantity * oi.UnitPrice) AS Revenue
  FROM dbo.OrderItems oi
  JOIN dbo.Orders o     ON o.OrderID = oi.OrderID AND o.Status = 'Completed'
  JOIN dbo.Products p   ON p.ProductID = oi.ProductID
  JOIN dbo.Categories c ON c.CategoryID = p.CategoryID
 GROUP BY c.CategoryName
 ORDER BY Revenue DESC;

-- 4. Top 10 products by revenue
SELECT TOP 10 p.ProductName, SUM(oi.Quantity * oi.UnitPrice) AS Revenue
  FROM dbo.OrderItems oi
  JOIN dbo.Orders o   ON o.OrderID = oi.OrderID AND o.Status = 'Completed'
  JOIN dbo.Products p ON p.ProductID = oi.ProductID
 GROUP BY p.ProductName
 ORDER BY Revenue DESC;

-- 5. Products that need reordering
SELECT ProductName, SupplierName, QtyOnHand, ReorderLevel, LeadTimeDays
  FROM dbo.vw_ReorderNeeded
 ORDER BY QtyOnHand - ReorderLevel;

-- 6. Slow movers and the capital tied up in them
SELECT ProductName, QtyOnHand, CapitalTiedUp, LastSoldOn
  FROM dbo.vw_SlowMovers
 ORDER BY CapitalTiedUp DESC;

/* ---------- Bonus: window functions ---------- */

-- 7. Rank products within their category
SELECT c.CategoryName, p.ProductName,
       SUM(oi.Quantity * oi.UnitPrice) AS Revenue,
       RANK() OVER (PARTITION BY c.CategoryName
                    ORDER BY SUM(oi.Quantity * oi.UnitPrice) DESC) AS RankInCategory
  FROM dbo.OrderItems oi
  JOIN dbo.Orders o     ON o.OrderID = oi.OrderID AND o.Status = 'Completed'
  JOIN dbo.Products p   ON p.ProductID = oi.ProductID
  JOIN dbo.Categories c ON c.CategoryID = p.CategoryID
 GROUP BY c.CategoryName, p.ProductName;

-- 8. Daily revenue with a running total and 7-day moving average
WITH Daily AS (
    SELECT CAST(o.OrderDate AS DATE) AS Day, SUM(oi.Quantity * oi.UnitPrice) AS Revenue
      FROM dbo.Orders o
      JOIN dbo.OrderItems oi ON oi.OrderID = o.OrderID
     WHERE o.Status = 'Completed'
     GROUP BY CAST(o.OrderDate AS DATE)
)
SELECT Day, Revenue,
       SUM(Revenue) OVER (ORDER BY Day ROWS UNBOUNDED PRECEDING) AS RunningTotal,
       AVG(Revenue) OVER (ORDER BY Day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS MovingAvg7Day
  FROM Daily
 ORDER BY Day;
