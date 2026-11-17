-- NaeemSoft-WMS smoke test: product -> draft receipt -> pending -> approved.
-- Run after migrations 001 through 005. All test rows are rolled back.

BEGIN;
SET search_path TO naeemsoft_wms, public;

DO $$
DECLARE
    v_branch_id uuid;
    v_warehouse_id uuid;
    v_user_id uuid;
    v_supplier_id uuid;
    v_product_id uuid;
    v_piece_unit_id uuid;
    v_pack_unit_id uuid;
    v_carton_unit_id uuid;
    v_receipt_id uuid;
    v_on_hand numeric(24,6);
    v_movement_count integer;
BEGIN
    INSERT INTO branches(code, name)
    VALUES ('TEST-BR', 'Test Branch')
    RETURNING id INTO v_branch_id;

    INSERT INTO warehouses(branch_id, code, name)
    VALUES (v_branch_id, 'TEST-WH', 'Test Warehouse')
    RETURNING id INTO v_warehouse_id;

    INSERT INTO users(username, password_hash, full_name)
    VALUES ('wms_smoke_test', 'not-a-real-password-hash', 'WMS Smoke Test')
    RETURNING id INTO v_user_id;

    INSERT INTO currencies(code, name, symbol)
    VALUES ('TST', 'Test Currency', 'T');

    INSERT INTO units(code, name) VALUES
        ('piece', 'Piece'),
        ('pack', 'Pack'),
        ('carton', 'Carton');

    INSERT INTO products(sku, name, created_by)
    VALUES ('PEN-SMOKE-001', 'Test Pens', v_user_id)
    RETURNING id INTO v_product_id;

    SELECT id INTO v_piece_unit_id FROM units WHERE code = 'piece';
    SELECT id INTO v_pack_unit_id FROM units WHERE code = 'pack';
    SELECT id INTO v_carton_unit_id FROM units WHERE code = 'carton';

    INSERT INTO product_units(product_id, unit_id, factor_to_base, is_base)
    VALUES
        (v_product_id, v_piece_unit_id, 1, true),
        (v_product_id, v_pack_unit_id, 10, false),
        (v_product_id, v_carton_unit_id, 240, false);

    INSERT INTO product_unit_prices(product_unit_id, sale_price, currency_code, updated_by)
    SELECT pu.id,
           CASE u.code WHEN 'piece' THEN 10 WHEN 'pack' THEN 80 ELSE 1500 END,
           'TST',
           v_user_id
      FROM product_units pu
      JOIN units u ON u.id = pu.unit_id
     WHERE pu.product_id = v_product_id;

    SET CONSTRAINTS ALL IMMEDIATE;

    INSERT INTO suppliers(name)
    VALUES ('Test Supplier')
    RETURNING id INTO v_supplier_id;

    INSERT INTO receipts(
        branch_id, warehouse_id, supplier_id, receipt_number,
        currency_code, created_by
    )
    VALUES (
        v_branch_id, v_warehouse_id, v_supplier_id, 'TEST-REC-001',
        'TST', v_user_id
    )
    RETURNING id INTO v_receipt_id;

    INSERT INTO receipt_items(
        receipt_id, line_number, product_id, product_unit_id,
        quantity, conversion_factor_snapshot, unit_cost
    )
    VALUES (
        v_receipt_id, 1, v_product_id, v_carton_unit_id,
        5, 240, 1000
    );

    SELECT quantity_on_hand_base INTO v_on_hand
      FROM v_inventory_on_hand
     WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;
    IF COALESCE(v_on_hand, 0) <> 0 THEN
        RAISE EXCEPTION 'Draft receipt changed stock; expected 0, got %', v_on_hand;
    END IF;

    PERFORM submit_receipt_for_approval(v_receipt_id, v_user_id);

    SELECT quantity_on_hand_base INTO v_on_hand
      FROM v_inventory_on_hand
     WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;
    IF COALESCE(v_on_hand, 0) <> 0 THEN
        RAISE EXCEPTION 'Pending receipt changed stock; expected 0, got %', v_on_hand;
    END IF;

    PERFORM approve_receipt(v_receipt_id, v_user_id);

    SELECT quantity_on_hand_base INTO v_on_hand
      FROM v_inventory_on_hand
     WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;
    IF v_on_hand <> 1200 THEN
        RAISE EXCEPTION 'Approved receipt stock mismatch; expected 1200, got %', v_on_hand;
    END IF;

    -- Retry approval: quantity and movement count must remain unchanged.
    PERFORM approve_receipt(v_receipt_id, v_user_id);

    SELECT quantity_on_hand_base INTO v_on_hand
      FROM v_inventory_on_hand
     WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;

    SELECT count(*) INTO v_movement_count
      FROM stock_movements
     WHERE source_document_type = 'receipt'
       AND source_document_id = v_receipt_id;

    IF v_on_hand <> 1200 OR v_movement_count <> 1 THEN
        RAISE EXCEPTION
            'Duplicate approval detected; expected stock 1200 and 1 movement, got stock % and movements %',
            v_on_hand, v_movement_count;
    END IF;

    RAISE NOTICE 'PASS: 5 cartons x 240 = 1200 pieces; draft/pending stock stayed zero; approval posted once.';
END;
$$;

ROLLBACK;
