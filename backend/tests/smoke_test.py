import json
import os
import urllib.request

BASE = os.environ.get("WMS_TEST_URL", "http://127.0.0.1:8000")
API_KEY = os.environ["WMS_API_KEY"]


def call(method, path, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(
        BASE + path,
        data=body,
        method=method,
        headers={
            "Content-Type": "application/json",
            "X-API-Key": API_KEY,
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        raw = response.read()
        return json.loads(raw) if raw else {}


health = call("GET", "/health")
assert health["status"] == "ok", health

product = call(
    "POST",
    "/api/products",
    {
        "sku": "PEN-SMOKE-001",
        "name": "Smoke Test Pens",
        "currency_code": "USD",
        "units": [
            {
                "code": "piece",
                "name": "Piece",
                "factor_to_base": 1,
                "is_base": True,
                "sale_price": 10,
            },
            {
                "code": "pack",
                "name": "Pack",
                "factor_to_base": 10,
                "is_base": False,
                "sale_price": 80,
            },
            {
                "code": "carton",
                "name": "Carton",
                "factor_to_base": 240,
                "is_base": False,
                "sale_price": 1500,
            },
        ],
    },
)
product_id = product["id"]

products = call("GET", "/api/products")
found = next(item for item in products if item["id"] == product_id)
carton = next(unit for unit in found["units"] if unit["unit_code"] == "carton")

supplier = call(
    "POST",
    "/api/suppliers",
    {"name": "Smoke Test Supplier", "supplier_code": "SUP-SMOKE-001"},
)

receipt = call(
    "POST",
    "/api/receipts",
    {
        "supplier_id": supplier["id"],
        "receipt_number": "RCV-SMOKE-001",
        "currency_code": "USD",
        "exchange_rate": 1,
        "items": [
            {
                "product_unit_id": carton["product_unit_id"],
                "quantity": 5,
                "unit_cost": 1200,
            }
        ],
    },
)
receipt_id = receipt["id"]


def stock_quantity():
    rows = call("GET", "/api/stock")
    row = next(item for item in rows if item["product_id"] == product_id)
    return float(row["quantity_on_hand_base"])


assert stock_quantity() == 0, "Draft receipt must not increase stock"
call("POST", f"/api/receipts/{receipt_id}/submit")
assert stock_quantity() == 0, "Pending receipt must not increase stock"
call("POST", f"/api/receipts/{receipt_id}/approve")
assert stock_quantity() == 1200, "Five cartons must post as 1,200 base units"
call("POST", f"/api/receipts/{receipt_id}/approve")
assert stock_quantity() == 1200, "Retrying approval must not double-post stock"


recipient = call("POST", "/api/recipients", {"name": "Smoke Test Recipient", "recipient_code": "REC-SMOKE-001"})
issue = call(
    "POST",
    "/api/issues",
    {
        "recipient_id": recipient["id"],
        "issue_number": "ISS-SMOKE-001",
        "currency_code": "USD",
        "items": [{"product_unit_id": carton["product_unit_id"], "quantity": 1}],
    },
)
issue_id = issue["id"]
call("POST", f"/api/issues/{issue_id}/submit")
assert stock_quantity() == 1200, "Pending issue must not reduce stock"
call("POST", f"/api/issues/{issue_id}/approve")
assert stock_quantity() == 960, "One carton issue must reduce stock by 240 base units"
call("POST", f"/api/issues/{issue_id}/approve")
assert stock_quantity() == 960, "Retrying issue approval must not double-post"

supplier_statement = call("GET", f"/api/suppliers/{supplier['id']}/statement")
assert supplier_statement["entries"], "Supplier statement should include the approved receipt"
recipient_statement = call("GET", f"/api/recipients/{recipient['id']}/statement")
assert recipient_statement["entries"], "Recipient statement should include the approved issue"
available = call("GET", "/api/stock/available")
assert available, "Products with positive stock should appear in issue catalogue"

print("API smoke test passed: receipt and issue approvals, stock balances, and account statements.")

