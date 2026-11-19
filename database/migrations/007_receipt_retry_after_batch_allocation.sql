-- NaeemSoft-WMS migration: 007_receipt_retry_after_batch_allocation
BEGIN;
SET search_path TO naeemsoft_wms, public;

-- Migration 006 changes movement idempotency to include batch_id so one issue
-- line can be allocated across several batches. Keep receipt posting idempotent
-- with a generic conflict target after that index change.
CREATE OR REPLACE FUNCTION approve_receipt(p_receipt_id uuid,p_user_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path = naeemsoft_wms, public AS $$
DECLARE
    v_receipt receipts%ROWTYPE;
    v_line receipt_items%ROWTYPE;
    v_batch_id uuid;
BEGIN
    SELECT * INTO v_receipt FROM receipts WHERE id=p_receipt_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Receipt % not found',p_receipt_id; END IF;
    IF v_receipt.status='approved' THEN RETURN; END IF;
    IF v_receipt.status<>'pending_approval' THEN
        RAISE EXCEPTION 'Only pending receipts can be approved; current status: %',v_receipt.status;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM receipt_items WHERE receipt_id=p_receipt_id) THEN
        RAISE EXCEPTION 'Cannot approve an empty receipt';
    END IF;

    FOR v_line IN SELECT * FROM receipt_items WHERE receipt_id=p_receipt_id ORDER BY line_number LOOP
        INSERT INTO batches(receipt_item_id,product_id,warehouse_id,batch_number,expiry_date,received_qty_base)
        VALUES(v_line.id,v_line.product_id,v_receipt.warehouse_id,
               v_line.supplier_batch_number,v_line.expiry_date,v_line.quantity_base)
        ON CONFLICT(receipt_item_id) DO NOTHING
        RETURNING id INTO v_batch_id;
        IF v_batch_id IS NULL THEN
            SELECT id INTO v_batch_id FROM batches WHERE receipt_item_id=v_line.id;
        END IF;

        INSERT INTO stock_movements(
            warehouse_id,product_id,batch_id,movement_type,direction,quantity_base,
            source_document_type,source_document_id,source_line_id,created_by,notes
        ) VALUES (
            v_receipt.warehouse_id,v_line.product_id,v_batch_id,'receipt','IN',v_line.quantity_base,
            'receipt',v_receipt.id,v_line.id,p_user_id,'Posted by receipt approval'
        ) ON CONFLICT DO NOTHING;
        v_batch_id:=NULL;
    END LOOP;

    UPDATE receipts SET status='approved',approved_by=p_user_id,approved_at=now()
    WHERE id=p_receipt_id;
END; $$;

COMMIT;
