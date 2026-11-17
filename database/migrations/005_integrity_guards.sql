-- NaeemSoft-WMS migration: 005_integrity_guards
BEGIN;
SET search_path TO naeemsoft_wms, public;

-- Once a receipt leaves draft, its business data is frozen. Only workflow
-- metadata/status can change while pending; approved receipts are immutable.
CREATE OR REPLACE FUNCTION guard_receipt_header_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
BEGIN
    IF OLD.status = 'approved' THEN
        RAISE EXCEPTION 'Approved receipts are immutable; create a reversal document instead';
    END IF;

    IF OLD.status = 'pending_approval' THEN
        IF (to_jsonb(NEW) - ARRAY['status', 'approved_by', 'approved_at', 'cancelled_by', 'cancelled_at'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['status', 'approved_by', 'approved_at', 'cancelled_by', 'cancelled_at']) THEN
            RAISE EXCEPTION 'A pending receipt cannot have its business data edited';
        END IF;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (
            (OLD.status = 'draft' AND NEW.status IN ('pending_approval', 'cancelled'))
            OR
            (OLD.status = 'pending_approval' AND NEW.status IN ('approved', 'cancelled'))
        ) THEN
            RAISE EXCEPTION 'Invalid receipt status transition: % -> %', OLD.status, NEW.status;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_receipt_status_transition ON receipts;
CREATE TRIGGER trg_guard_receipt_header_update
BEFORE UPDATE ON receipts
FOR EACH ROW EXECUTE FUNCTION guard_receipt_header_update();

-- Inventory balances are a projection of the immutable movement ledger.
-- Direct writes are rejected; only the stock-movement trigger may maintain them.
CREATE OR REPLACE FUNCTION guard_direct_inventory_balance_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
BEGIN
    IF pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'Do not edit inventory_balances directly; post a stock movement';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_inventory_balance_write
BEFORE INSERT OR UPDATE OR DELETE ON inventory_balances
FOR EACH ROW EXECUTE FUNCTION guard_direct_inventory_balance_write();

-- Movement and history tables are append-only.
CREATE OR REPLACE FUNCTION reject_ledger_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'This ledger/history table is append-only';
END;
$$;

CREATE TRIGGER trg_stock_movements_append_only
BEFORE UPDATE OR DELETE ON stock_movements
FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();

CREATE TRIGGER trg_price_history_append_only
BEFORE UPDATE OR DELETE ON price_history
FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();

CREATE TRIGGER trg_audit_logs_append_only
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();

COMMIT;
