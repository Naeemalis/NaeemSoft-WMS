# NaeemSoft-WMS — Database

The first database implementation is organized as ordered PostgreSQL migrations.

## Apply order

Run these files against a new PostgreSQL database, in order:

1. [001_core.sql](migrations/001_core.sql) — branches, warehouses, users, roles, currencies, categories, units, products, per-unit sale prices and price history.
2. [002_receiving.sql](migrations/002_receiving.sql) — suppliers, receipt headers and lines, supplier batch/expiry data.
3. [003_inventory.sql](migrations/003_inventory.sql) — immutable stock movement ledger, inventory balances and operational stock views.
4. [004_receipt_workflow_audit_views.sql](migrations/004_receipt_workflow_audit_views.sql) — receipt submission/approval functions, price completeness check, audit log and receipt totals.
5. [005_integrity_guards.sql](migrations/005_integrity_guards.sql) — receipt immutability, append-only ledgers and protection against direct balance edits.

The schema is created under `naeemsoft_wms`.

## Confirmed business rules represented

- A product is defined before its first receipt and can appear in the sales catalogue with zero stock.
- Each product has exactly one smallest/base unit; all other product units store their own conversion factor to that base unit.
- Every sale-enabled product unit must have its own manually entered sale price. Prices are not derived automatically from the base-unit price.
- Receipt quantities are converted and snapshotted in the smallest unit.
- Draft and pending-approval receipts do not affect stock.
- Receipt approval creates stock batches and stock movements exactly once.
- Inventory balances are maintained from the stock movement ledger; direct balance edits are rejected.
- A sale/issue movement that would make a batch balance negative is rejected.
- Product-unit prices, stock movements and audit history are append-only/history-preserving as appropriate.

## Example unit setup

For a pen product:

| Unit | factor_to_base | is_base |
|---|---:|---|
| Piece | 1 | true |
| Pack | 10 | false |
| Carton | 240 | false |

The database stores stock in pieces. The sales application decomposes a requested quantity into the largest applicable packs/cartons and the remainder, then uses each unit's independent sale price.

## Receipt workflow

1. Create a receipt in `draft`.
2. Add receipt lines while it remains a draft.
3. Call `submit_receipt_for_approval(receipt_id, user_id)`.
4. Call `approve_receipt(receipt_id, user_id)` after authorization.
5. Read available stock from `v_inventory_on_hand` or `v_products_for_sales`.

Calling `approve_receipt` again for an already approved receipt is a safe no-op.

## Not yet included

The database valuation method (FIFO vs weighted average), sales and quotation documents, customer/supplier account statements, return workflows, exchange-rate history, competitor intelligence, and branch-transfer workflow remain subsequent implementation stages. No valuation method has been silently selected.
