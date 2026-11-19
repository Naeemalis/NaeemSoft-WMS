# NaeemSoft-WMS — Database

PostgreSQL schema migrations are applied in numeric order.

## Apply order

1. `001_core.sql` — organization, products, units and prices.
2. `002_receiving.sql` — suppliers, receipt headers/lines and expiry batches.
3. `003_inventory.sql` — immutable stock movement ledger, balances and stock views.
4. `004_receipt_workflow_audit_views.sql` — receipt submission/approval, audit and totals.
5. `005_integrity_guards.sql` — receipt immutability, append-only ledgers and balance guards.
6. `006_issue_accounts_and_availability.sql` — recipients, wholesale issues, payment entries, account statement views, available-stock catalogue and expiry alerts.
7. `007_receipt_retry_after_batch_allocation.sql` — preserves safe receipt retries after allowing issue lines to consume multiple batches.

The schema is `naeemsoft_wms`.

## Confirmed rules

- Products are defined before receiving. Each has exactly one base unit.
- Unit conversion factors are product-specific. Stock is held in the smallest/base unit.
- Each sale-enabled unit has its own manually entered price.
- Receipt drafts and pending approvals do not affect stock. Approval posts each receipt once and creates a traceable batch.
- Issue drafts and pending approvals do not affect stock. Approval posts OUT movements, allocates batches by earliest expiry date first and fails atomically if stock is insufficient.
- The wholesale issue catalogue includes only product units belonging to products with positive available stock.
- Expiry alert view reports batches with stock and expiry dates within the next 30 days.
- Supplier statements include approved receipt debits and supplier settlement credits.
- Recipient statements include approved issue debits and recipient collection credits.
- Statement balances are partitioned by currency; different currencies are never added together.
- Inventory balances are a projection of the append-only stock movement ledger.

## Important limitations

The current statement views do not yet include supplier returns or recipient returns. Payment workflows record account entries but are not yet connected to a cash/bank register. Minimum-stock thresholds have not been configured because the per-product threshold policy is still undecided. Stock valuation (FIFO vs weighted average), stock counts, transfers and full role-based authorization remain subsequent work.
