-- NaeemSoft-WMS
-- PostgreSQL schema, phase 1: core organization, products, units and prices.
-- Version: 0.1

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS naeemsoft_wms;
SET search_path TO naeemsoft_wms, public;

CREATE TABLE branches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(30) NOT NULL UNIQUE,
    name varchar(150) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE warehouses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id uuid NOT NULL REFERENCES branches(id),
    code varchar(30) NOT NULL,
    name varchar(150) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_warehouses_branch_code UNIQUE (branch_id, code),
    CONSTRAINT uq_warehouses_id_branch UNIQUE (id, branch_id)
);

CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    username varchar(80) NOT NULL,
    password_hash text NOT NULL,
    full_name varchar(180) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_users_username_ci ON users (lower(username));

CREATE TABLE employees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid UNIQUE REFERENCES users(id),
    branch_id uuid NOT NULL REFERENCES branches(id),
    employee_no varchar(40) NOT NULL UNIQUE,
    full_name varchar(180) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    hired_at date,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    role_code varchar(50) NOT NULL UNIQUE,
    role_name varchar(120) NOT NULL,
    description text,
    is_system_role boolean NOT NULL DEFAULT false
);

CREATE TABLE permissions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    permission_code varchar(100) NOT NULL UNIQUE,
    description text NOT NULL
);

CREATE TABLE user_roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    branch_id uuid REFERENCES branches(id)
);
CREATE UNIQUE INDEX uq_user_roles_global ON user_roles(user_id, role_id) WHERE branch_id IS NULL;
CREATE UNIQUE INDEX uq_user_roles_branch ON user_roles(user_id, role_id, branch_id) WHERE branch_id IS NOT NULL;

CREATE TABLE role_permissions (
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE currencies (
    code varchar(3) PRIMARY KEY,
    name varchar(80) NOT NULL,
    symbol varchar(12),
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_currency_code_upper CHECK (code = upper(code))
);

CREATE TABLE categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id uuid REFERENCES categories(id),
    code varchar(40) UNIQUE,
    name varchar(150) NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_category_not_own_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE TABLE units (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code varchar(30) NOT NULL UNIQUE,
    name varchar(100) NOT NULL,
    symbol varchar(20),
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sku varchar(60) NOT NULL UNIQUE,
    name varchar(200) NOT NULL,
    category_id uuid REFERENCES categories(id),
    brand varchar(120),
    description text,
    image_reference text,
    is_active boolean NOT NULL DEFAULT true,
    created_by uuid REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- factor_to_base = number of smallest units represented by one product unit.
CREATE TABLE product_units (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    unit_id uuid NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
    factor_to_base numeric(20,6) NOT NULL,
    is_base boolean NOT NULL DEFAULT false,
    is_purchase_allowed boolean NOT NULL DEFAULT true,
    is_sale_allowed boolean NOT NULL DEFAULT true,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_product_unit_factor_positive CHECK (factor_to_base > 0),
    CONSTRAINT ck_base_unit_factor_one CHECK (NOT is_base OR factor_to_base = 1),
    CONSTRAINT uq_product_unit UNIQUE (product_id, unit_id),
    CONSTRAINT uq_product_unit_id_pair UNIQUE (product_id, id)
);
CREATE UNIQUE INDEX uq_product_one_base_unit ON product_units(product_id) WHERE is_base = true;
CREATE INDEX ix_product_units_product ON product_units(product_id);

CREATE TABLE product_unit_prices (
    product_unit_id uuid PRIMARY KEY REFERENCES product_units(id) ON DELETE RESTRICT,
    sale_price numeric(20,6) NOT NULL,
    currency_code varchar(3) NOT NULL REFERENCES currencies(code),
    updated_by uuid NOT NULL REFERENCES users(id),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sale_price_nonnegative CHECK (sale_price >= 0)
);

CREATE TABLE price_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_unit_id uuid NOT NULL REFERENCES product_units(id) ON DELETE RESTRICT,
    old_price numeric(20,6),
    new_price numeric(20,6) NOT NULL,
    currency_code varchar(3) NOT NULL REFERENCES currencies(code),
    changed_by uuid NOT NULL REFERENCES users(id),
    changed_at timestamptz NOT NULL DEFAULT now(),
    change_reason text,
    CONSTRAINT ck_price_history_new_nonnegative CHECK (new_price >= 0),
    CONSTRAINT ck_price_history_old_nonnegative CHECK (old_price IS NULL OR old_price >= 0)
);

CREATE OR REPLACE FUNCTION log_product_unit_price_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO price_history(product_unit_id, old_price, new_price, currency_code, changed_by, changed_at)
        VALUES (NEW.product_unit_id, NULL, NEW.sale_price, NEW.currency_code, NEW.updated_by, COALESCE(NEW.updated_at, now()));
    ELSIF OLD.sale_price IS DISTINCT FROM NEW.sale_price
       OR OLD.currency_code IS DISTINCT FROM NEW.currency_code THEN
        INSERT INTO price_history(product_unit_id, old_price, new_price, currency_code, changed_by, changed_at)
        VALUES (NEW.product_unit_id, OLD.sale_price, NEW.sale_price, NEW.currency_code, NEW.updated_by, COALESCE(NEW.updated_at, now()));
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_product_unit_price_history
AFTER INSERT OR UPDATE ON product_unit_prices
FOR EACH ROW EXECUTE FUNCTION log_product_unit_price_change();

CREATE OR REPLACE FUNCTION check_product_has_one_base_unit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
DECLARE
    v_product_id uuid;
    v_base_count integer;
    v_bad_factor integer;
BEGIN
    IF TG_TABLE_NAME = 'products' THEN
        v_product_id := NEW.id;
    ELSIF TG_OP = 'DELETE' THEN
        v_product_id := OLD.product_id;
    ELSE
        v_product_id := NEW.product_id;
    END IF;

    SELECT count(*), count(*) FILTER (WHERE factor_to_base <> 1)
      INTO v_base_count, v_bad_factor
      FROM product_units
     WHERE product_id = v_product_id AND is_base = true;

    IF EXISTS (SELECT 1 FROM products WHERE id = v_product_id)
       AND (v_base_count <> 1 OR v_bad_factor <> 0) THEN
        RAISE EXCEPTION 'Product % must have exactly one base unit with factor_to_base = 1', v_product_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER ct_product_base_unit_on_product
AFTER INSERT OR UPDATE ON products
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_product_has_one_base_unit();

CREATE CONSTRAINT TRIGGER ct_product_base_unit_on_units
AFTER INSERT OR UPDATE OR DELETE ON product_units
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_product_has_one_base_unit();

COMMIT;
