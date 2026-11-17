"""Create the first local WMS service account, branch, warehouse and currency."""
import os
import sys
import psycopg

DATABASE_URL = os.environ.get("DATABASE_URL")
CURRENCY = os.environ.get("WMS_BASE_CURRENCY", "").strip().upper()
CURRENCY_NAME = os.environ.get("WMS_BASE_CURRENCY_NAME", CURRENCY).strip()

if not DATABASE_URL:
    raise SystemExit("DATABASE_URL is required")
if len(CURRENCY) != 3 or not CURRENCY.isalpha():
    raise SystemExit("Set WMS_BASE_CURRENCY to the chosen 3-letter currency code in .env")

with psycopg.connect(DATABASE_URL) as conn:
    conn.execute(
        """
        INSERT INTO naeemsoft_wms.currencies(code, name, symbol)
        VALUES (%s, %s, %s)
        ON CONFLICT (code) DO NOTHING
        """,
        (CURRENCY, CURRENCY_NAME or CURRENCY, CURRENCY),
    )
    conn.execute(
        """
        INSERT INTO naeemsoft_wms.branches(code, name)
        VALUES ('MAIN', 'Main branch')
        ON CONFLICT (code) DO NOTHING
        """
    )
    branch_id = conn.execute(
        "SELECT id FROM naeemsoft_wms.branches WHERE code = 'MAIN'"
    ).fetchone()[0]
    conn.execute(
        """
        INSERT INTO naeemsoft_wms.warehouses(branch_id, code, name)
        VALUES (%s, 'MAIN', 'Main warehouse')
        ON CONFLICT (branch_id, code) DO NOTHING
        """,
        (branch_id,),
    )
    conn.execute(
        """
        INSERT INTO naeemsoft_wms.users(username, password_hash, full_name)
        VALUES ('system', '!service-account-no-login!', 'WMS Service Account')
        ON CONFLICT DO NOTHING
        """
    )

print("NaeemSoft-WMS bootstrap completed.")
