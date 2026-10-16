# DailyFitness

A native iOS app for strength training, nutrition logging, and health tracking. Built with SwiftUI, no third-party dependencies.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Xcode | 16+ | Mac App Store |
| Git LFS | any | `brew install git-lfs` |

Git LFS is required because `foods.db` (101 MB) and `scripts/foods_import.json` (113 MB) are stored as LFS objects.

## Setup

```bash
# 1. Install Git LFS (if not already)
brew install git-lfs
git lfs install

# 2. Clone the repo (LFS objects download automatically)
git clone https://github.com/arakipovic/daily-fitness.git
cd daily-fitness

# If you already cloned without LFS, pull the large files manually:
git lfs pull
```

## Running in Xcode

1. Open `DailyFitness.xcodeproj`
2. Select the **DailyFitness** target → **Signing & Capabilities**
3. Set a unique **Bundle Identifier** (e.g. `com.yourname.dailyfitness`)
4. Select your **Apple Developer Team**
5. Choose a simulator or connected device, then **⌘R**

## Running Tests

```
⌘U  (Product → Test)
```

Tests use isolated in-memory stores — no device or simulator needed.

## Rebuilding the Food Database

`foods.db` is pre-built and committed via LFS. Only rebuild if you've changed `scripts/foods_import.json`:

```bash
python3 scripts/build_food_db.py scripts/foods_import.json foods.db
```

Requires Python 3 (stdlib only, no pip installs).

## Analytics

User events are logged on-device to `Documents/analytics.jsonl` (JSON Lines, capped at 5 000 entries). Access them via:

```swift
Analytics.shared.allEvents()
```

No data leaves the device. The file is ready to ship to any backend when needed.

## Project Structure

| Path | Purpose |
|---|---|
| `DailyFitness/` | Xcode target — views, logic, models |
| `DailyFitness/DailyFitnessTests/` | Unit tests |
| `foods.db` | Bundled food catalog (SQLite + FTS5) |
| `scripts/` | Python tooling to regenerate `foods.db` |
