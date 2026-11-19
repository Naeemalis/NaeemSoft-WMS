-- NaeemSoft-WMS migration: 008_issue_catalogue_base_unit_display
BEGIN;
SET search_path TO naeemsoft_wms, public;

DROP VIEW IF EXISTS v_products_available_for_issue;
CREATE VIEW v_products_available_for_issue AS
SELECT w.id AS warehouse_id,
       p.id AS product_id,
       p.sku,
       p.name AS product_name,
       pu.id AS product_unit_id,
       u.code AS unit_code,
       u.name AS unit_name,
       buu.name AS base_unit_name,
       pu.factor_to_base,
       pup.sale_price,
       pup.currency_code,
       COALESCE(v.quantity_on_hand_base,0) AS quantity_on_hand_base
FROM warehouses w
JOIN v_products_for_sales v ON v.warehouse_id=w.id
JOIN products p ON p.id=v.product_id
JOIN product_units pu ON pu.product_id=p.id AND pu.is_active AND pu.is_sale_allowed
JOIN units u ON u.id=pu.unit_id
JOIN product_units bu ON bu.product_id=p.id AND bu.is_base=true
JOIN units buu ON buu.id=bu.unit_id
LEFT JOIN product_unit_prices pup ON pup.product_unit_id=pu.id
WHERE w.is_active AND COALESCE(v.quantity_on_hand_base,0)>0
  AND (lower(u.code) IN ('carton','pack','piece','كرتون','باكت','حبة','حبه')
       OR lower(u.name) IN ('carton','pack','piece','كرتون','باكت','حبة','حبه'));

COMMIT;
