# RetailStock: Inventory & Sales Database (MS SQL Server)

## The problem
A small retailer loses money in two ways: **stockouts** (lost sales) and **overstock** (cash tied up in products that don't sell). This database tracks products, stock levels, sales and supplier orders so that:

- low stock is flagged automatically and purchase orders can be generated,
- stock updates itself whenever a sale is recorded (and overselling is blocked),
- slow-moving products and the capital tied up in them are easy to find,
- sales trends and best sellers can be reported with plain SQL.

## Tech
Microsoft SQL Server (T-SQL), SSMS / Azure Data Studio.

## Entity relationship diagram

```mermaid
erDiagram
    Categories ||--o{ Products : classifies
    Suppliers  ||--o{ Products : supplies
    Products   ||--|| Inventory : "stock level"
    Products   ||--o{ StockMovements : logs
    Customers  ||--o{ Orders : places
    Orders     ||--|{ OrderItems : contains
    Products   ||--o{ OrderItems : "sold as"
    Suppliers  ||--o{ PurchaseOrders : receives
    PurchaseOrders ||--|{ PurchaseOrderItems : contains
    Products   ||--o{ PurchaseOrderItems : "ordered as"

    Products {
        int ProductID PK
        string SKU
        string ProductName
        decimal CostPrice
        decimal SellPrice
        int ReorderLevel
        int ReorderQty
    }
    Inventory {
        int ProductID PK
        int QtyOnHand
        datetime LastUpdated
    }
    Orders {
        int OrderID PK
        int CustomerID FK
        datetime OrderDate
        string Status
    }
    OrderItems {
        int OrderItemID PK
        int OrderID FK
        int ProductID FK
        int Quantity
        decimal UnitPrice
    }
```

## Design decisions
- **3NF schema**: categories, suppliers and customers live in their own tables.
- **`UnitPrice` stored on `OrderItems`**: historical sales keep the price at the time of sale even if the product price changes.
- **`Inventory` separate from `Products`**: stock changes constantly, product details rarely.
- **`StockMovements` audit log**: every change in stock is traceable.
- **CHECK constraints** enforce business rules (no negative stock, valid statuses, positive quantities).
- **Trigger `trg_OrderItems_AfterInsert`** deducts stock on sale; the `QtyOnHand >= 0` check rolls back sales that would oversell.
- **Indexes** are on the columns that reports filter and join on (see comments in `schema.sql`).

## What's inside
| File | Purpose |
|---|---|
| `schema.sql` | Tables, constraints, indexes, trigger, views, stored procedure |
| `seed_data.sql` | Sample data: 36 products, 40 customers, ~640 orders over 13 weeks |
| `queries/dashboard_queries.sql` | The queries behind every dashboard panel, plus window-function examples |
| `docs/index.html` | Static dashboard, published with GitHub Pages |
| `gen.py` | Script that generated the sample data and dashboard figures |

## Live dashboard
**[View the dashboard](https://YOUR-USERNAME.github.io/YOUR-REPO/)** (replace with your GitHub Pages link; setup steps below)

It shows revenue KPIs, weekly revenue, revenue by category, top products, items that need reordering and slow-moving stock.

## Key objects
- `vw_ReorderNeeded`: products at or below their reorder level
- `vw_SlowMovers`: products with no sales in 90 days, with capital tied up
- `usp_GenerateReorders`: creates one purchase order per supplier for low-stock items, skipping products already on order

## How to run
1. Open SSMS and run `schema.sql`.
2. Run `seed_data.sql`.
3. Try `SELECT * FROM dbo.vw_ReorderNeeded;` then `EXEC dbo.usp_GenerateReorders;`
4. Run the queries in `queries/dashboard_queries.sql` to reproduce each dashboard panel.

## Publishing the dashboard (GitHub Pages)
1. Push this repo to GitHub.
2. Repo **Settings > Pages > Build and deployment**: Source = *Deploy from a branch*, Branch = `main`, folder = `/docs`.
3. After a minute the dashboard is live at `https://<your-username>.github.io/<repo-name>/`.

## Sample results
_Add screenshots of query outputs here once seed data is loaded._
