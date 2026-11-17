-- NaeemSoft-WMS migration: 003_inventory
BEGIN;
SET search_path TO naeemsoft_wms, public;

CREATE TABLE stock_movements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    warehouse_id uuid NOT NULL,
    product_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    movement_type varchar(30) NOT NULL,
    direction varchar(3) NOT NULL,
    quantity_base numeric(24,6) NOT NULL,
    source_document_type varchar(30) NOT NULL,
    source_document_id uuid NOT NULL,
    source_line_id uuid NOT NULL,
    created_by uuid NOT NULL REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    notes text,
    CONSTRAINT fk_movement_batch
        FOREIGN KEY (batch_id, product_id, warehouse_id)
        REFERENCES batches(id, product_id, warehouse_id),
    CONSTRAINT ck_movement_type CHECK (movement_type IN (
        'receipt', 'issue', 'sale', 'customer_return', 'supplier_return',
        'adjustment_in', 'adjustment_out', 'transfer_in', 'transfer_out'
    )),
    CONSTRAINT ck_movement_direction CHECK (direction IN ('IN', 'OUT')),
    CONSTRAINT ck_movement_type_direction CHECK (
        (movement_type IN ('receipt', 'customer_return', 'adjustment_in', 'transfer_in') AND direction = 'IN')
        OR
        (movement_type IN ('issue', 'sale', 'supplier_return', 'adjustment_out', 'transfer_out') AND direction = 'OUT')
    ),
    CONSTRAINT ck_movement_quantity_positive CHECK (quantity_base > 0),
    CONSTRAINT uq_movement_source_once
        UNIQUE (source_document_type, source_document_id, source_line_id, movement_type)
);

CREATE INDEX ix_stock_movements_product_date ON stock_movements(product_id, created_at DESC);
CREATE INDEX ix_stock_movements_warehouse_date ON stock_movements(warehouse_id, created_at DESC);

CREATE TABLE inventory_balances (
    warehouse_id uuid NOT NULL,
    product_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    quantity_on_hand_base numeric(24,6) NOT NULL DEFAULT 0,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (warehouse_id, product_id, batch_id),
    CONSTRAINT fk_balance_batch
        FOREIGN KEY (batch_id, product_id, warehouse_id)
        REFERENCES batches(id, product_id, warehouse_id),
    CONSTRAINT ck_balance_nonnegative CHECK (quantity_on_hand_base >= 0)
);

CREATE OR REPLACE VIEW v_inventory_on_hand AS
SELECT warehouse_id, product_id, SUM(quantity_on_hand_base) AS quantity_on_hand_base
FROM inventory_balances
GROUP BY warehouse_id, product_id;

-- The stock ledger is the source of truth. Every new movement updates the
-- balance in the same transaction. An insufficient OUT movement aborts it.
CREATE OR REPLACE FUNCTION apply_stock_movement_to_balance()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
BEGIN
    IF NEW.direction = 'IN' THEN
        INSERT INTO inventory_balances (
            warehouse_id, product_id, batch_id, quantity_on_hand_base, updated_at
        )
        VALUES (NEW.warehouse_id, NEW.product_id, NEW.batch_id, NEW.quantity_base, now())
        ON CONFLICT (warehouse_id, product_id, batch_id)
        DO UPDATE SET
            quantity_on_hand_base = inventory_balances.quantity_on_hand_base + EXCLUDED.quantity_on_hand_base,
            updated_at = now();
    ELSE
        UPDATE inventory_balances
           SET quantity_on_hand_base = quantity_on_hand_base - NEW.quantity_base,
               updated_at = now()
         WHERE warehouse_id = NEW.warehouse_id
           AND product_id = NEW.product_id
           AND batch_id = NEW.batch_id
           AND quantity_on_hand_base >= NEW.quantity_base;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Insufficient stock for product %, batch %, warehouse %',
                NEW.product_id, NEW.batch_id, NEW.warehouse_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_apply_stock_movement_to_balance
AFTER INSERT ON stock_movements
FOR EACH ROW EXECUTE FUNCTION apply_stock_movement_to_balance();

-- Shows every active product in every active warehouse, including zero stock.
CREATE OR REPLACE VIEW v_products_for_sales AS
SELECT
    w.id AS warehouse_id,
    p.id AS product_id,
    p.sku,
    p.name AS product_name,
    bu.id AS base_product_unit_id,
    u.name AS base_unit_name,
    COALESCE(ih.quantity_on_hand_base, 0) AS quantity_on_hand_base
FROM warehouses w
CROSS JOIN products p
JOIN product_units bu ON bu.product_id = p.id AND bu.is_base = true
JOIN units u ON u.id = bu.unit_id
LEFT JOIN v_inventory_on_hand ih
       ON ih.warehouse_id = w.id AND ih.product_id = p.id
WHERE p.is_active = true AND w.is_active = true;

COMMIT;
