# NaeemSoft-WMS — architecture baseline

## Deployment boundary
- One Android device, one warehouse, one local SQLite database.
- No backend, API, PostgreSQL, cloud dependency, or mandatory internet connection.
- Database file: app-private SQLite storage, with foreign keys and WAL enabled.

## Application layers
1. Presentation: responsive Flutter screens, Arabic/English/French, RTL for Arabic.
2. Application services: receiving, issuing, approvals, returns, stocktaking, statements, reporting.
3. Domain: stock rules, FEFO, unit conversion, status calculation, validation.
4. Data: SQLite repositories, migrations, transaction boundaries, backup/restore.

## Inventory invariants
- Draft and pending documents do not affect available stock.
- Only approved receipts create inventory batches and inbound ledger entries.
- Only approved issues allocate from batches and create outbound ledger entries.
- Issue allocation follows FEFO and rejects expired or insufficient stock.
- Supplier returns reference the original receipt line and batch and cannot exceed the remaining received quantity.
- Customer returns reference the original issue line and require inspection before becoming available.
- A stock count freezes all stock movements until approval or cancellation; approval posts variance movements.
- Stock movements are append-only; corrections use reversal/adjustment records.
- Issue documents identify a recipient and every issue line stores its own unit price.
- Purchase requests are not receipts and never increase stock.

## Product status
- Out of stock: available quantity is zero.
- Low stock: available quantity is at or below the product reorder threshold.
- Stagnant: no qualifying movement for the configured period.
- Expired / near expiry: calculated per batch, not only per product.
- A product can have multiple simultaneous status flags; expiry and availability must be evaluated at batch level.

## Responsive requirements
- Support portrait and landscape.
- Adapt product-grid columns to available width.
- Use bottom navigation on compact screens and a navigation rail on wide screens.
- No clipped controls or horizontal overflow in normal workflows.
