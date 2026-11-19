"""NaeemSoft-WMS API v0.1 — first Android integration slice."""
import hmac
import os
from contextlib import contextmanager
from typing import Any
from uuid import UUID

import psycopg
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from psycopg.rows import dict_row

DATABASE_URL = os.environ.get("DATABASE_URL", "")
API_KEY = os.environ.get("WMS_API_KEY", "")
DEFAULT_CURRENCY = os.environ.get("WMS_BASE_CURRENCY", "").upper()

app = FastAPI(
    title="NaeemSoft-WMS API",
    version="0.1.0",
    description="Android application API for products, suppliers, receiving and stock.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
    allow_headers=["*"],
)


@contextmanager
def db():
    if not DATABASE_URL:
        raise HTTPException(status_code=503, detail="Database is not configured")
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        yield conn


def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    if not API_KEY or not x_api_key or not hmac.compare_digest(x_api_key, API_KEY):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")


def actor_id(conn) -> UUID:
    row = conn.execute(
        "SELECT id FROM naeemsoft_wms.users WHERE username = 'system' AND is_active = true"
    ).fetchone()
    if not row:
        raise HTTPException(status_code=503, detail="Run backend bootstrap before using the API")
    return row["id"]


def default_location(conn) -> tuple[UUID, UUID]:
    row = conn.execute(
        """
        SELECT b.id AS branch_id, w.id AS warehouse_id
        FROM naeemsoft_wms.branches b
        JOIN naeemsoft_wms.warehouses w ON w.branch_id = b.id
        WHERE b.code = 'MAIN' AND w.code = 'MAIN'
          AND b.is_active = true AND w.is_active = true
        LIMIT 1
        """
    ).fetchone()
    if not row:
        raise HTTPException(status_code=503, detail="Default branch/warehouse is missing")
    return row["branch_id"], row["warehouse_id"]


class UnitInput(BaseModel):
    code: str = Field(min_length=1, max_length=30)
    name: str = Field(min_length=1, max_length=100)
    factor_to_base: float = Field(gt=0)
    is_base: bool = False
    sale_price: float = Field(ge=0)
    purchase_allowed: bool = True
    sale_allowed: bool = True


class ProductCreate(BaseModel):
    sku: str = Field(min_length=1, max_length=60)
    name: str = Field(min_length=1, max_length=200)
    brand: str | None = None
    description: str | None = None
    currency_code: str = Field(min_length=3, max_length=3)
    units: list[UnitInput] = Field(min_length=1)


class SupplierCreate(BaseModel):
    name: str = Field(min_length=1, max_length=180)
    supplier_code: str | None = None
    phone: str | None = None
    email: str | None = None
    address: str | None = None


class ReceiptLineInput(BaseModel):
    product_unit_id: UUID
    quantity: float = Field(gt=0)
    unit_cost: float = Field(ge=0)
    batch_number: str | None = None
    expiry_date: str | None = None


class ReceiptCreate(BaseModel):
    supplier_id: UUID
    receipt_number: str = Field(min_length=1, max_length=60)
    currency_code: str = Field(min_length=3, max_length=3)
    exchange_rate: float = Field(default=1, gt=0)
    supplier_invoice_number: str | None = None
    notes: str | None = None
    items: list[ReceiptLineInput] = Field(min_length=1)


@app.get("/health")
def health():
    try:
        with db() as conn:
            conn.execute("SELECT 1")
        return {"status": "ok", "service": "NaeemSoft-WMS API", "version": "0.1.0"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database unavailable: {exc}") from exc


@app.get("/api/dashboard", dependencies=[Depends(require_api_key)])
def dashboard():
    with db() as conn:
        _, warehouse_id = default_location(conn)
        products = conn.execute(
            "SELECT count(*) AS total FROM naeemsoft_wms.products WHERE is_active = true"
        ).fetchone()["total"]
        stock = conn.execute(
            """
            SELECT count(*) FILTER (WHERE quantity_on_hand_base > 0) AS stocked_products,
                   COALESCE(sum(quantity_on_hand_base), 0) AS total_base_units
            FROM naeemsoft_wms.v_inventory_on_hand
            WHERE warehouse_id = %s
            """,
            (warehouse_id,),
        ).fetchone()
        pending = conn.execute(
            "SELECT count(*) AS total FROM naeemsoft_wms.receipts WHERE status = 'pending_approval'"
        ).fetchone()["total"]
        return {
            "products_count": products,
            "stocked_products_count": stock["stocked_products"],
            "total_base_units": float(stock["total_base_units"]),
            "pending_receipts_count": pending,
        }


@app.get("/api/products", dependencies=[Depends(require_api_key)])
def list_products():
    with db() as conn:
        _, warehouse_id = default_location(conn)
        rows = conn.execute(
            """
            SELECT p.id, p.sku, p.name, p.brand, p.description,
                   buu.name AS base_unit_name,
                   COALESCE(ih.quantity_on_hand_base, 0) AS quantity_on_hand_base,
                   COALESCE(
                     jsonb_agg(
                       jsonb_build_object(
                         'product_unit_id', pu.id,
                         'unit_code', u.code,
                         'unit_name', u.name,
                         'factor_to_base', pu.factor_to_base,
                         'is_base', pu.is_base,
                         'purchase_allowed', pu.is_purchase_allowed,
                         'sale_allowed', pu.is_sale_allowed,
                         'sale_price', pup.sale_price,
                         'currency_code', pup.currency_code
                       ) ORDER BY pu.factor_to_base DESC
                     ) FILTER (WHERE pu.id IS NOT NULL), '[]'::jsonb
                   ) AS units
            FROM naeemsoft_wms.products p
            JOIN naeemsoft_wms.product_units bu
              ON bu.product_id = p.id AND bu.is_base = true
            JOIN naeemsoft_wms.units buu ON buu.id = bu.unit_id
            LEFT JOIN naeemsoft_wms.product_units pu ON pu.product_id = p.id AND pu.is_active = true
            LEFT JOIN naeemsoft_wms.units u ON u.id = pu.unit_id
            LEFT JOIN naeemsoft_wms.product_unit_prices pup ON pup.product_unit_id = pu.id
            LEFT JOIN naeemsoft_wms.v_inventory_on_hand ih
              ON ih.product_id = p.id AND ih.warehouse_id = %s
            WHERE p.is_active = true
            GROUP BY p.id, p.sku, p.name, p.brand, p.description,
                     buu.name, ih.quantity_on_hand_base
            ORDER BY p.name
            """,
            (warehouse_id,),
        ).fetchall()
        return [dict(row) for row in rows]


@app.get("/api/stock", dependencies=[Depends(require_api_key)])
def list_stock():
    with db() as conn:
        _, warehouse_id = default_location(conn)
        rows = conn.execute(
            """
            SELECT p.id AS product_id, p.sku, p.name AS product_name,
                   u.name AS base_unit_name,
                   COALESCE(ih.quantity_on_hand_base, 0) AS quantity_on_hand_base
            FROM naeemsoft_wms.products p
            JOIN naeemsoft_wms.product_units pu
              ON pu.product_id = p.id AND pu.is_base = true
            JOIN naeemsoft_wms.units u ON u.id = pu.unit_id
            LEFT JOIN naeemsoft_wms.v_inventory_on_hand ih
              ON ih.product_id = p.id AND ih.warehouse_id = %s
            WHERE p.is_active = true
            ORDER BY p.name
            """,
            (warehouse_id,),
        ).fetchall()
        return [dict(row) for row in rows]


@app.post("/api/products", status_code=201, dependencies=[Depends(require_api_key)])
def create_product(payload: ProductCreate):
    base_units = [unit for unit in payload.units if unit.is_base]
    codes = [unit.code.strip().lower() for unit in payload.units]
    if len(base_units) != 1 or base_units[0].factor_to_base != 1:
        raise HTTPException(422, "Exactly one base unit with conversion factor 1 is required")
    if len(codes) != len(set(codes)):
        raise HTTPException(422, "Unit codes must be unique within a product")
    if any(not unit.code.strip() or not unit.name.strip() for unit in payload.units):
        raise HTTPException(422, "Unit code and name are required")
    with db() as conn:
        user_id = actor_id(conn)
        with conn.transaction():
            product = conn.execute(
                """
                INSERT INTO naeemsoft_wms.products(sku, name, brand, description, created_by)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, sku, name
                """,
                (payload.sku.strip(), payload.name.strip(), payload.brand, payload.description, user_id),
            ).fetchone()
            for unit in payload.units:
                unit_id = conn.execute(
                    """
                    INSERT INTO naeemsoft_wms.units(code, name)
                    VALUES (%s, %s)
                    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name
                    RETURNING id
                    """,
                    (unit.code.strip().lower(), unit.name.strip()),
                ).fetchone()["id"]
                product_unit = conn.execute(
                    """
                    INSERT INTO naeemsoft_wms.product_units(
                        product_id, unit_id, factor_to_base, is_base,
                        is_purchase_allowed, is_sale_allowed
                    )
                    VALUES (%s, %s, %s, %s, %s, %s)
                    RETURNING id
                    """,
                    (
                        product["id"], unit_id, unit.factor_to_base, unit.is_base,
                        unit.purchase_allowed, unit.sale_allowed,
                    ),
                ).fetchone()
                if unit.sale_allowed:
                    conn.execute(
                        """
                        INSERT INTO naeemsoft_wms.product_unit_prices(
                            product_unit_id, sale_price, currency_code, updated_by
                        )
                        VALUES (%s, %s, %s, %s)
                        """,
                        (product_unit["id"], unit.sale_price, payload.currency_code.upper(), user_id),
                    )
        return {"id": str(product["id"]), "sku": product["sku"], "name": product["name"]}


@app.get("/api/suppliers", dependencies=[Depends(require_api_key)])
def list_suppliers():
    with db() as conn:
        rows = conn.execute(
            """
            SELECT id, supplier_code, name, phone, email, address
            FROM naeemsoft_wms.suppliers
            WHERE is_active = true
            ORDER BY name
            """
        ).fetchall()
        return [dict(row) for row in rows]


@app.post("/api/suppliers", status_code=201, dependencies=[Depends(require_api_key)])
def create_supplier(payload: SupplierCreate):
    with db() as conn:
        row = conn.execute(
            """
            INSERT INTO naeemsoft_wms.suppliers(supplier_code, name, phone, email, address)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id, supplier_code, name
            """,
            (payload.supplier_code, payload.name.strip(), payload.phone, payload.email, payload.address),
        ).fetchone()
        return dict(row)


@app.get("/api/receipts", dependencies=[Depends(require_api_key)])
def list_receipts():
    with db() as conn:
        rows = conn.execute(
            """
            SELECT r.id, r.receipt_number, r.status, r.receipt_date,
                   r.currency_code, s.name AS supplier_name,
                   COALESCE(sum(ri.line_total), 0) AS total
            FROM naeemsoft_wms.receipts r
            JOIN naeemsoft_wms.suppliers s ON s.id = r.supplier_id
            LEFT JOIN naeemsoft_wms.receipt_items ri ON ri.receipt_id = r.id
            GROUP BY r.id, s.name
            ORDER BY r.created_at DESC
            LIMIT 100
            """
        ).fetchall()
        return [dict(row) for row in rows]


@app.post("/api/receipts", status_code=201, dependencies=[Depends(require_api_key)])
def create_receipt(payload: ReceiptCreate):
    with db() as conn:
        user_id = actor_id(conn)
        branch_id, warehouse_id = default_location(conn)
        with conn.transaction():
            header = conn.execute(
                """
                INSERT INTO naeemsoft_wms.receipts(
                    branch_id, warehouse_id, supplier_id, receipt_number,
                    currency_code, exchange_rate, supplier_invoice_number,
                    notes, created_by
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id, receipt_number, status
                """,
                (
                    branch_id, warehouse_id, payload.supplier_id, payload.receipt_number,
                    payload.currency_code.upper(), payload.exchange_rate,
                    payload.supplier_invoice_number, payload.notes, user_id,
                ),
            ).fetchone()
            for index, line in enumerate(payload.items, start=1):
                product_unit = conn.execute(
                    """
                    SELECT product_id, factor_to_base, is_purchase_allowed
                    FROM naeemsoft_wms.product_units
                    WHERE id = %s AND is_active = true
                    """,
                    (line.product_unit_id,),
                ).fetchone()
                if not product_unit or not product_unit["is_purchase_allowed"]:
                    raise HTTPException(422, f"Purchase unit is invalid on line {index}")
                conn.execute(
                    """
                    INSERT INTO naeemsoft_wms.receipt_items(
                        receipt_id, line_number, product_id, product_unit_id,
                        quantity, conversion_factor_snapshot, unit_cost,
                        supplier_batch_number, expiry_date
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        header["id"], index, product_unit["product_id"], line.product_unit_id,
                        line.quantity, product_unit["factor_to_base"], line.unit_cost,
                        line.batch_number, line.expiry_date,
                    ),
                )
        return {"id": str(header["id"]), "receipt_number": header["receipt_number"], "status": header["status"]}


@app.post("/api/receipts/{receipt_id}/submit", dependencies=[Depends(require_api_key)])
def submit_receipt(receipt_id: UUID):
    with db() as conn:
        user_id = actor_id(conn)
        conn.execute(
            "SELECT naeemsoft_wms.submit_receipt_for_approval(%s, %s)",
            (receipt_id, user_id),
        )
        return {"id": str(receipt_id), "status": "pending_approval"}


@app.post("/api/receipts/{receipt_id}/approve", dependencies=[Depends(require_api_key)])
def approve_receipt(receipt_id: UUID):
    with db() as conn:
        user_id = actor_id(conn)
        conn.execute(
            "SELECT naeemsoft_wms.approve_receipt(%s, %s)",
            (receipt_id, user_id),
        )
        return {"id": str(receipt_id), "status": "approved"}


# ---- Issue cashier, account statements and stock availability (milestone 0.2) ----

class RecipientCreate(BaseModel):
    name: str = Field(min_length=1, max_length=180)
    recipient_code: str | None = None
    phone: str | None = None
    address: str | None = None
    notes: str | None = None


class IssueLineInput(BaseModel):
    product_unit_id: UUID
    quantity: float = Field(gt=0)
    unit_price: float | None = Field(default=None, ge=0)


class IssueCreate(BaseModel):
    recipient_id: UUID
    issue_number: str = Field(min_length=1, max_length=60)
    currency_code: str = Field(min_length=3, max_length=3)
    notes: str | None = None
    items: list[IssueLineInput] = Field(min_length=1)


class AccountPaymentCreate(BaseModel):
    payment_number: str = Field(min_length=1, max_length=60)
    currency_code: str = Field(min_length=3, max_length=3)
    amount: float = Field(gt=0)
    payment_date: str | None = None
    notes: str | None = None


@app.get("/api/recipients", dependencies=[Depends(require_api_key)])
def list_recipients():
    with db() as conn:
        rows = conn.execute(
            """SELECT id, recipient_code, name, phone, address, notes
               FROM naeemsoft_wms.recipients WHERE is_active=true ORDER BY name"""
        ).fetchall()
        return [dict(row) for row in rows]


@app.post("/api/recipients", status_code=201, dependencies=[Depends(require_api_key)])
def create_recipient(payload: RecipientCreate):
    with db() as conn:
        row = conn.execute(
            """INSERT INTO naeemsoft_wms.recipients(recipient_code,name,phone,address,notes)
               VALUES (%s,%s,%s,%s,%s) RETURNING id,recipient_code,name""",
            (payload.recipient_code, payload.name.strip(), payload.phone, payload.address, payload.notes),
        ).fetchone()
        return dict(row)


@app.get("/api/stock/available", dependencies=[Depends(require_api_key)])
def list_available_stock():
    with db() as conn:
        _, warehouse_id = default_location(conn)
        rows = conn.execute(
            """SELECT product_id, sku, product_name, product_unit_id, unit_code,
                      unit_name, factor_to_base, sale_price, currency_code,
                      quantity_on_hand_base
               FROM naeemsoft_wms.v_products_available_for_issue
               WHERE warehouse_id=%s ORDER BY product_name, factor_to_base DESC""",
            (warehouse_id,),
        ).fetchall()
        return [dict(row) for row in rows]


@app.get("/api/stock/expiry-alerts", dependencies=[Depends(require_api_key)])
def list_expiry_alerts():
    with db() as conn:
        _, warehouse_id = default_location(conn)
        rows = conn.execute(
            """SELECT product_id,sku,product_name,batch_id,batch_number,expiry_date,
                      quantity_on_hand_base,days_until_expiry
               FROM naeemsoft_wms.v_expiry_alerts
               WHERE warehouse_id=%s ORDER BY expiry_date,product_name""",
            (warehouse_id,),
        ).fetchall()
        return [dict(row) for row in rows]


@app.get("/api/issues", dependencies=[Depends(require_api_key)])
def list_issues():
    with db() as conn:
        rows = conn.execute(
            """SELECT i.id,i.issue_number,i.issue_date,i.status,i.currency_code,
                      r.name AS recipient_name,COALESCE(SUM(ii.line_total),0) AS total
               FROM naeemsoft_wms.issues i
               JOIN naeemsoft_wms.recipients r ON r.id=i.recipient_id
               LEFT JOIN naeemsoft_wms.issue_items ii ON ii.issue_id=i.id
               GROUP BY i.id,r.name ORDER BY i.created_at DESC LIMIT 100"""
        ).fetchall()
        return [dict(row) for row in rows]


@app.post("/api/issues", status_code=201, dependencies=[Depends(require_api_key)])
def create_issue(payload: IssueCreate):
    with db() as conn:
        user_id = actor_id(conn)
        branch_id, warehouse_id = default_location(conn)
        with conn.transaction():
            header = conn.execute(
                """INSERT INTO naeemsoft_wms.issues(
                       branch_id,warehouse_id,recipient_id,issue_number,currency_code,notes,created_by
                   ) VALUES (%s,%s,%s,%s,%s,%s,%s)
                   RETURNING id,issue_number,status""",
                (branch_id,warehouse_id,payload.recipient_id,payload.issue_number,
                 payload.currency_code.upper(),payload.notes,user_id),
            ).fetchone()
            for index,line in enumerate(payload.items,start=1):
                unit = conn.execute(
                    """SELECT pu.product_id,pu.factor_to_base,pu.is_sale_allowed,pup.sale_price
                       FROM naeemsoft_wms.product_units pu
                       LEFT JOIN naeemsoft_wms.product_unit_prices pup ON pup.product_unit_id=pu.id
                       WHERE pu.id=%s AND pu.is_active=true""",
                    (line.product_unit_id,),
                ).fetchone()
                if not unit or not unit["is_sale_allowed"]:
                    raise HTTPException(422, f"وحدة الصرف غير صالحة في السطر {index}")
                price = line.unit_price if line.unit_price is not None else unit["sale_price"]
                if price is None:
                    raise HTTPException(422, f"لا يوجد سعر بيع محدد لوحدة السطر {index}")
                conn.execute(
                    """INSERT INTO naeemsoft_wms.issue_items(
                           issue_id,line_number,product_id,product_unit_id,quantity,
                           conversion_factor_snapshot,unit_price
                       ) VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                    (header["id"],index,unit["product_id"],line.product_unit_id,
                     line.quantity,unit["factor_to_base"],price),
                )
        return {"id":str(header["id"]),"issue_number":header["issue_number"],"status":header["status"]}


@app.post("/api/issues/{issue_id}/submit", dependencies=[Depends(require_api_key)])
def submit_issue(issue_id: UUID):
    with db() as conn:
        conn.execute(
            "SELECT naeemsoft_wms.submit_issue_for_approval(%s,%s)",
            (issue_id,actor_id(conn)),
        )
        return {"id":str(issue_id),"status":"pending_approval"}


@app.post("/api/issues/{issue_id}/approve", dependencies=[Depends(require_api_key)])
def approve_issue(issue_id: UUID):
    with db() as conn:
        conn.execute(
            "SELECT naeemsoft_wms.approve_issue(%s,%s)",
            (issue_id,actor_id(conn)),
        )
        return {"id":str(issue_id),"status":"approved"}


def _statement_rows(conn, view_name: str, party_column: str, party_id: UUID):
    # view_name/party_column are fixed internal constants, never request values.
    rows = conn.execute(
        f"""SELECT entry_date,document_number,description,currency_code,debit,credit,
                    SUM(debit-credit) OVER (
                      PARTITION BY currency_code
                      ORDER BY entry_date,document_number,document_id
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                    ) AS running_balance
             FROM naeemsoft_wms.{view_name}
             WHERE {party_column}=%s
             ORDER BY currency_code,entry_date,document_number,document_id""",
        (party_id,),
    ).fetchall()
    return [
        {**dict(row),"debit":float(row["debit"]),"credit":float(row["credit"]),
         "running_balance":float(row["running_balance"])}
        for row in rows
    ]


@app.get("/api/suppliers/{supplier_id}/statement", dependencies=[Depends(require_api_key)])
def supplier_statement(supplier_id: UUID):
    with db() as conn:
        supplier = conn.execute(
            "SELECT id,name FROM naeemsoft_wms.suppliers WHERE id=%s",(supplier_id,)
        ).fetchone()
        if not supplier: raise HTTPException(404,"المورد غير موجود")
        entries = _statement_rows(conn,"v_supplier_statement_entries","supplier_id",supplier_id)
        return {"party":dict(supplier),"entries":entries}


@app.post("/api/suppliers/{supplier_id}/payments", status_code=201, dependencies=[Depends(require_api_key)])
def create_supplier_payment(supplier_id: UUID, payload: AccountPaymentCreate):
    with db() as conn:
        user_id=actor_id(conn)
        row=conn.execute(
            """INSERT INTO naeemsoft_wms.supplier_payments(
                   supplier_id,payment_number,payment_date,currency_code,amount,notes,created_by
               ) VALUES (%s,%s,COALESCE(%s::date,current_date),%s,%s,%s,%s)
               RETURNING id,payment_number,amount,currency_code,payment_date""",
            (supplier_id,payload.payment_number,payload.payment_date,payload.currency_code.upper(),
             payload.amount,payload.notes,user_id),
        ).fetchone()
        return dict(row)


@app.get("/api/recipients/{recipient_id}/statement", dependencies=[Depends(require_api_key)])
def recipient_statement(recipient_id: UUID):
    with db() as conn:
        recipient=conn.execute(
            "SELECT id,name FROM naeemsoft_wms.recipients WHERE id=%s",(recipient_id,)
        ).fetchone()
        if not recipient: raise HTTPException(404,"المستلم غير موجود")
        entries=_statement_rows(conn,"v_recipient_statement_entries","recipient_id",recipient_id)
        return {"party":dict(recipient),"entries":entries}


@app.post("/api/recipients/{recipient_id}/payments", status_code=201, dependencies=[Depends(require_api_key)])
def create_recipient_payment(recipient_id: UUID, payload: AccountPaymentCreate):
    with db() as conn:
        user_id=actor_id(conn)
        row=conn.execute(
            """INSERT INTO naeemsoft_wms.recipient_payments(
                   recipient_id,payment_number,payment_date,currency_code,amount,notes,created_by
               ) VALUES (%s,%s,COALESCE(%s::date,current_date),%s,%s,%s,%s)
               RETURNING id,payment_number,amount,currency_code,payment_date""",
            (recipient_id,payload.payment_number,payload.payment_date,payload.currency_code.upper(),
             payload.amount,payload.notes,user_id),
        ).fetchone()
        return dict(row)
