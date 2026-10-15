#!/usr/bin/env python3
"""
build_food_db.py — Convert a foods JSON file into an SQLite database with FTS5.

Usage:
    python3 scripts/build_food_db.py foods.json foods.db

Input JSON format (array of objects):
    [
      {
        "name": "Chicken Breast",
        "category": "Protein",
        "kcal": 165,
        "protein": 31,
        "carbs": 0,
        "fat": 3.6,
        "fiber": 0,          // optional
        "sugar": 0,          // optional
        "saturatedFat": 0,   // optional
        "sodium": 74,        // optional, mg per 100g
        "cholesterol": 85,   // optional, mg per 100g
        "defaultServingG": 150,
        "servingLabel": "150g breast"  // optional
      },
      ...
    ]

Valid category values (case-sensitive):
    "Protein", "Carbs & Grains", "Dairy", "Fruit", "Vegetables",
    "Fats & Oils", "Condiments & Extras", "Meals & Prepared Foods",
    "Supplements", "Restaurants"

The output .db file can be:
  1. Imported directly via FoodStore.importJSON(from:) in the app (preferred)
  2. Used as the bundled foods.db if you want to ship it inside the app bundle
"""

import json
import sqlite3
import sys
from pathlib import Path


VALID_CATEGORIES = {
    "Protein",
    "Carbs & Grains",
    "Dairy",
    "Fruit",
    "Vegetables",
    "Fats & Oils",
    "Condiments & Extras",
    "Meals & Prepared Foods",
    "Supplements",
    "Restaurants",
}


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript("""
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;

        CREATE TABLE IF NOT EXISTS foods (
            rowid       INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT    NOT NULL,
            category    TEXT    NOT NULL,
            kcal        REAL    NOT NULL DEFAULT 0,
            protein     REAL    NOT NULL DEFAULT 0,
            carbs       REAL    NOT NULL DEFAULT 0,
            fat         REAL    NOT NULL DEFAULT 0,
            fiber       REAL    NOT NULL DEFAULT 0,
            sugar       REAL    NOT NULL DEFAULT 0,
            sat_fat     REAL    NOT NULL DEFAULT 0,
            sodium      REAL    NOT NULL DEFAULT 0,
            cholesterol REAL    NOT NULL DEFAULT 0,
            serving_g   INTEGER NOT NULL DEFAULT 100,
            serving_label TEXT,
            UNIQUE(name)
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS foods_fts USING fts5(
            name,
            content=foods,
            content_rowid=rowid,
            tokenize='unicode61'
        );

        CREATE TRIGGER IF NOT EXISTS foods_ai AFTER INSERT ON foods BEGIN
            INSERT INTO foods_fts(rowid, name) VALUES (new.rowid, new.name);
        END;

        CREATE TRIGGER IF NOT EXISTS foods_ad AFTER DELETE ON foods BEGIN
            INSERT INTO foods_fts(foods_fts, rowid, name)
            VALUES ('delete', old.rowid, old.name);
        END;

        CREATE TRIGGER IF NOT EXISTS foods_au AFTER UPDATE ON foods BEGIN
            INSERT INTO foods_fts(foods_fts, rowid, name)
            VALUES ('delete', old.rowid, old.name);
            INSERT INTO foods_fts(rowid, name) VALUES (new.rowid, new.name);
        END;
    """)


def insert_foods(conn: sqlite3.Connection, items: list[dict]) -> tuple[int, int]:
    sql = """
        INSERT OR REPLACE INTO foods
          (name, category, kcal, protein, carbs, fat,
           fiber, sugar, sat_fat, sodium, cholesterol,
           serving_g, serving_label)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
    """
    inserted = 0
    skipped = 0
    rows = []
    for item in items:
        name = item.get("name", "").strip()
        if not name:
            skipped += 1
            continue
        cat = item.get("category", "Meals & Prepared Foods")
        if cat not in VALID_CATEGORIES:
            print(f"  Warning: unknown category '{cat}' for '{name}' — defaulting to 'Meals & Prepared Foods'")
            cat = "Meals & Prepared Foods"
        rows.append((
            name,
            cat,
            float(item.get("kcal", 0)),
            float(item.get("protein", 0)),
            float(item.get("carbs", 0)),
            float(item.get("fat", 0)),
            float(item.get("fiber") or 0),
            float(item.get("sugar") or 0),
            float(item.get("saturatedFat") or 0),
            float(item.get("sodium") or 0),
            float(item.get("cholesterol") or 0),
            int(item.get("defaultServingG", 100)),
            item.get("servingLabel"),
        ))

    conn.executemany(sql, rows)
    inserted = len(rows)
    return inserted, skipped


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: python3 build_food_db.py <input.json> <output.db>")
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    if not input_path.exists():
        print(f"Error: input file not found: {input_path}")
        sys.exit(1)

    print(f"Reading {input_path}…")
    with open(input_path, encoding="utf-8") as f:
        items = json.load(f)

    if not isinstance(items, list):
        print("Error: JSON root must be an array of food objects")
        sys.exit(1)

    print(f"Loaded {len(items):,} items")

    if output_path.exists():
        output_path.unlink()

    conn = sqlite3.connect(str(output_path))
    try:
        create_schema(conn)
        with conn:
            inserted, skipped = insert_foods(conn, items)

        row_count = conn.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
        # Checkpoint the WAL so all rows are in the main .db file before it is
        # copied into the Xcode project.  Without this, rows written in WAL mode
        # stay in the sidecar .db-wal file which is not included in the app bundle.
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        print(f"Done: {inserted:,} rows inserted, {skipped} skipped")
        print(f"Database: {output_path} ({output_path.stat().st_size / 1024 / 1024:.1f} MB, {row_count:,} foods)")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
