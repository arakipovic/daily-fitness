#!/usr/bin/env python3
"""
import_fdc.py — Converts USDA FoodData Central CSVs into the DailyFitness food JSON format.

Usage:
    python3 scripts/import_fdc.py \
        data/FoodData_Central_csv_2026-04-30 \
        --out scripts/foods_import.json

Then import into the app (once):
    Settings → Import Food Database → pick foods_import.json
    (or call FoodStore.shared.importJSON(from: url) in code)

What gets included:
    - Foundation foods (~2 400): highest quality USDA lab data
    - SR Legacy foods (~8 900): classic USDA standard reference
    - Survey / FNDDS foods (~7 800): NHANES prepared food data
    - Branded foods (~1.9 M): manufacturer submissions, US market only, not discontinued

Nutrient amounts in the FDC are all expressed per 100 g of edible portion.
"""

import csv
import json
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Nutrient IDs (from nutrient.csv, nutrient_nbr column)
# ---------------------------------------------------------------------------
TARGET_NUTRIENT_NBR_TO_KEY = {
    208: "kcal",         # Energy
    203: "protein",
    205: "carbs",        # Carbohydrate, by difference
    204: "fat",          # Total lipid
    291: "fiber",        # Fiber, total dietary
    269: "sugar",        # Total Sugars
    606: "saturatedFat", # Fatty acids, total saturated
    307: "sodium",       # Sodium, Na (mg per 100 g)
    601: "cholesterol",  # Cholesterol (mg per 100 g)
}

# ---------------------------------------------------------------------------
# Category mapping: USDA food_category.id → app category string
# ---------------------------------------------------------------------------
USDA_CAT = {
    1:  "Dairy",                    # Dairy and Egg Products
    2:  "Condiments & Extras",      # Spices and Herbs
    3:  "Meals & Prepared Foods",   # Baby Foods
    4:  "Fats & Oils",              # Fats and Oils
    5:  "Protein",                  # Poultry Products
    6:  "Condiments & Extras",      # Soups, Sauces, and Gravies
    7:  "Protein",                  # Sausages and Luncheon Meats
    8:  "Carbs & Grains",           # Breakfast Cereals
    9:  "Fruit",                    # Fruits and Fruit Juices
    10: "Protein",                  # Pork Products
    11: "Vegetables",               # Vegetables and Vegetable Products
    12: "Fats & Oils",              # Nut and Seed Products
    13: "Protein",                  # Beef Products
    14: "Condiments & Extras",      # Beverages
    15: "Protein",                  # Finfish and Shellfish Products
    16: "Protein",                  # Legumes and Legume Products
    17: "Protein",                  # Lamb, Veal, and Game Products
    18: "Carbs & Grains",           # Baked Products
    19: "Condiments & Extras",      # Sweets
    20: "Carbs & Grains",           # Cereal Grains and Pasta
    21: "Meals & Prepared Foods",   # Fast Foods
    22: "Meals & Prepared Foods",   # Meals, Entrees, and Side Dishes
    23: "Condiments & Extras",      # Snacks
    24: "Meals & Prepared Foods",   # American Indian/Alaska Native Foods
    25: "Restaurants",              # Restaurant Foods
    26: "Meals & Prepared Foods",   # Branded Food Products Database
    27: "Meals & Prepared Foods",   # Quality Control Materials
    28: "Condiments & Extras",      # Alcoholic Beverages
}

# Keywords for branded food category strings (case-insensitive substring match)
BRANDED_CAT_KEYWORDS = [
    ("dairy",       "Dairy"),
    ("cheese",      "Dairy"),
    ("milk",        "Dairy"),
    ("yogurt",      "Dairy"),
    ("meat",        "Protein"),
    ("poultry",     "Protein"),
    ("seafood",     "Protein"),
    ("fish",        "Protein"),
    ("egg",         "Protein"),
    ("legume",      "Protein"),
    ("bean",        "Protein"),
    ("protein",     "Protein"),
    ("fruit",       "Fruit"),
    ("vegetable",   "Vegetables"),
    ("produce",     "Vegetables"),
    ("grain",       "Carbs & Grains"),
    ("bread",       "Carbs & Grains"),
    ("pasta",       "Carbs & Grains"),
    ("cereal",      "Carbs & Grains"),
    ("baked",       "Carbs & Grains"),
    ("oil",         "Fats & Oils"),
    ("nut",         "Fats & Oils"),
    ("seed",        "Fats & Oils"),
    ("supplement",  "Supplements"),
    ("vitamin",     "Supplements"),
    ("protein powder", "Supplements"),
    ("restaurant",  "Restaurants"),
    ("fast food",   "Restaurants"),
    ("beverage",    "Condiments & Extras"),
    ("drink",       "Condiments & Extras"),
    ("juice",       "Condiments & Extras"),
    ("snack",       "Condiments & Extras"),
    ("sauce",       "Condiments & Extras"),
    ("condiment",   "Condiments & Extras"),
    ("sweet",       "Condiments & Extras"),
    ("candy",       "Condiments & Extras"),
    ("chocolate",   "Condiments & Extras"),
    ("spice",       "Condiments & Extras"),
]

# Data quality priority: lower = higher priority; wins name conflicts
DATA_TYPE_PRIORITY = {
    "foundation_food":   0,
    "sr_legacy_food":    1,
    "survey_fndds_food": 2,
    "branded_food":      3,
}

INCLUDE_TYPES = set(DATA_TYPE_PRIORITY.keys())


def guess_branded_category(cat_str: str) -> str:
    if not cat_str:
        return "Meals & Prepared Foods"
    lower = cat_str.lower()
    for keyword, app_cat in BRANDED_CAT_KEYWORDS:
        if keyword in lower:
            return app_cat
    return "Meals & Prepared Foods"


def load_nutrients(data_dir: Path) -> tuple[dict, dict]:
    """
    Returns:
        target_id_to_key: {nutrient_id: field_name}  (only the 9 we want)
        nutrients: {fdc_id: {field_name: float}}
    """
    # Pass 1: find nutrient IDs for the nutrient numbers we want
    target_id_to_key = {}
    with open(data_dir / "nutrient.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                nbr = int(float(row["nutrient_nbr"]))
            except (ValueError, TypeError):
                continue
            if nbr in TARGET_NUTRIENT_NBR_TO_KEY:
                nid = int(row["id"])
                target_id_to_key[nid] = TARGET_NUTRIENT_NBR_TO_KEY[nbr]

    print(f"  Target nutrient IDs: {target_id_to_key}")

    # Pass 2: stream food_nutrient.csv (27M rows), keep only target nutrient IDs
    nutrients: dict[int, dict[str, float]] = {}
    path = data_dir / "food_nutrient.csv"
    total = 0
    kept = 0
    t0 = time.time()
    with open(path, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            total += 1
            if total % 2_000_000 == 0:
                elapsed = time.time() - t0
                print(f"  {total/1_000_000:.0f}M rows scanned, {kept:,} kept  ({elapsed:.0f}s)…")
            try:
                nid = int(row["nutrient_id"])
            except (ValueError, TypeError):
                continue
            if nid not in target_id_to_key:
                continue
            try:
                fdc_id = int(row["fdc_id"])
                amount = float(row["amount"]) if row["amount"] else 0.0
            except (ValueError, TypeError):
                continue
            key = target_id_to_key[nid]
            if fdc_id not in nutrients:
                nutrients[fdc_id] = {}
            if key not in nutrients[fdc_id]:   # first value wins per (food, nutrient)
                nutrients[fdc_id][key] = amount
            kept += 1

    elapsed = time.time() - t0
    print(f"  Done: {total/1_000_000:.1f}M rows in {elapsed:.0f}s → {len(nutrients):,} foods with nutrients")
    return target_id_to_key, nutrients


def load_portions(data_dir: Path) -> dict:
    """Returns {fdc_id: (gram_weight_int, label_or_None)}  — first portion only."""
    portions: dict[int, tuple[int, str | None]] = {}
    with open(data_dir / "food_portion.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                fdc_id = int(row["fdc_id"])
            except (ValueError, TypeError):
                continue
            if fdc_id in portions:
                continue   # Already have first portion
            try:
                gw = float(row["gram_weight"])
            except (ValueError, TypeError):
                continue
            if gw <= 0:
                continue
            desc = (row.get("portion_description") or "").strip()
            mod  = (row.get("modifier") or "").strip()
            label = " ".join(x for x in [desc, mod] if x) or None
            portions[fdc_id] = (max(5, min(1000, int(round(gw)))), label)
    return portions


def load_branded(data_dir: Path) -> dict:
    """Returns {fdc_id: dict} with serving and metadata fields."""
    branded: dict[int, dict] = {}
    with open(data_dir / "branded_food.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                fdc_id = int(row["fdc_id"])
            except (ValueError, TypeError):
                continue
            branded[fdc_id] = {
                "size":         row.get("serving_size") or "",
                "unit":         (row.get("serving_size_unit") or "").strip().lower(),
                "label":        (row.get("household_serving_fulltext") or "").strip() or None,
                "cat":          (row.get("branded_food_category") or "").strip(),
                "market":       (row.get("market_country") or "").strip(),
                "discontinued": (row.get("discontinued_date") or "").strip(),
            }
    return branded


def get_serving(fdc_id: int, data_type: str, branded: dict, portions: dict) -> tuple[int, str | None]:
    if data_type == "branded_food":
        b = branded.get(fdc_id)
        if b:
            try:
                size = float(b["size"])
                if size > 0 and b["unit"] in ("g", "ml", "mls", "g.", "gr"):
                    return max(5, min(1000, int(round(size)))), b["label"]
            except (ValueError, TypeError):
                pass
    if fdc_id in portions:
        return portions[fdc_id]
    return 100, None


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Convert USDA FDC CSVs → DailyFitness food JSON")
    parser.add_argument("data_dir", help="Path to the FoodData Central CSV folder")
    parser.add_argument("--out", default="scripts/foods_import.json", help="Output JSON path")
    parser.add_argument(
        "--types", nargs="+",
        default=["foundation_food", "sr_legacy_food", "survey_fndds_food", "branded_food"],
        help="Data types to include"
    )
    parser.add_argument("--min-kcal", type=float, default=1.0, help="Skip foods below this kcal (per 100g)")
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    if not data_dir.is_dir():
        print(f"Error: not a directory: {data_dir}")
        sys.exit(1)

    include_types = set(args.types)

    # ── Step 1: Nutrients ──────────────────────────────────────────────────
    print("\n[1/4] Loading nutrient data (scanning 27M rows)…")
    _, nutrients = load_nutrients(data_dir)

    # ── Step 2: Portions ──────────────────────────────────────────────────
    print("\n[2/4] Loading portion data…")
    portions = load_portions(data_dir)
    print(f"  {len(portions):,} foods with serving data")

    # ── Step 3: Branded metadata ──────────────────────────────────────────
    print("\n[3/4] Loading branded food metadata…")
    branded = load_branded(data_dir)
    print(f"  {len(branded):,} branded foods")

    # ── Step 4: Process food.csv ──────────────────────────────────────────
    print("\n[4/4] Processing foods…")

    # best_by_name: normalized_name → (priority, item_dict)
    best_by_name: dict[str, tuple[int, dict]] = {}

    # Load category mapping
    cat_map: dict[int, str] = {}
    with open(data_dir / "food_category.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                cat_map[int(row["id"])] = USDA_CAT.get(int(row["id"]), "Meals & Prepared Foods")
            except (ValueError, TypeError):
                pass

    skipped_type = skipped_kcal = skipped_market = 0
    processed = 0

    with open(data_dir / "food.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            dt = row.get("data_type", "")
            if dt not in include_types:
                skipped_type += 1
                continue

            try:
                fdc_id = int(row["fdc_id"])
            except (ValueError, TypeError):
                continue

            name = (row.get("description") or "").strip()
            if len(name) < 2:
                continue

            n = nutrients.get(fdc_id, {})
            kcal = n.get("kcal", 0.0)
            if kcal < args.min_kcal:
                skipped_kcal += 1
                continue

            # Filter branded foods
            if dt == "branded_food":
                b = branded.get(fdc_id, {})
                market = b.get("market", "")
                if market and market.strip() not in ("", "United States"):
                    skipped_market += 1
                    continue
                if b.get("discontinued"):
                    skipped_market += 1
                    continue

            # Category
            cat_raw = row.get("food_category_id", "")
            try:
                category = cat_map.get(int(cat_raw), "Meals & Prepared Foods")
            except (ValueError, TypeError):
                # Branded foods often store a text label in this field
                if dt == "branded_food":
                    b = branded.get(fdc_id, {})
                    category = guess_branded_category(b.get("cat") or cat_raw)
                else:
                    category = "Meals & Prepared Foods"

            serving_g, serving_label = get_serving(fdc_id, dt, branded, portions)

            item: dict = {
                "name": name,
                "category": category,
                "kcal": round(kcal, 1),
                "protein": round(n.get("protein", 0.0), 2),
                "carbs": round(n.get("carbs", 0.0), 2),
                "fat": round(n.get("fat", 0.0), 2),
                "fiber": round(n.get("fiber", 0.0), 2),
                "sugar": round(n.get("sugar", 0.0), 2),
                "saturatedFat": round(n.get("saturatedFat", 0.0), 2),
                "sodium": round(n.get("sodium", 0.0), 1),
                "cholesterol": round(n.get("cholesterol", 0.0), 1),
                "defaultServingG": serving_g,
            }
            if serving_label and len(serving_label) < 80:
                item["servingLabel"] = serving_label

            # Dedup by normalized name; keep highest-quality data type
            norm = name.lower().strip()
            prio = DATA_TYPE_PRIORITY.get(dt, 99)
            existing = best_by_name.get(norm)
            if existing is None or prio < existing[0]:
                best_by_name[norm] = (prio, item)

            processed += 1
            if processed % 200_000 == 0:
                print(f"  {processed:,} foods processed, {len(best_by_name):,} unique names so far…")

    out_items = [item for _, item in best_by_name.values()]

    print(f"\n  Processed: {processed:,}")
    print(f"  Unique names (after dedup): {len(out_items):,}")
    print(f"  Skipped (wrong type): {skipped_type:,}")
    print(f"  Skipped (< {args.min_kcal} kcal): {skipped_kcal:,}")
    print(f"  Skipped (non-US/discontinued): {skipped_market:,}")

    # ── Write output ──────────────────────────────────────────────────────
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"\nWriting {out_path}…")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out_items, f, ensure_ascii=False, separators=(",", ":"))

    size_mb = out_path.stat().st_size / 1024 / 1024
    print(f"Done: {out_path}  ({size_mb:.0f} MB, {len(out_items):,} foods)")
    print("""
Next steps:
  1. In the app: Settings → Import Food Database → select this JSON file
     (or call: try await FoodStore.shared.importJSON(from: url) in code)
  2. The app stores everything in SQLite with FTS5 search.
  3. Search is now instant even with 1M+ foods.
""")


if __name__ == "__main__":
    main()
