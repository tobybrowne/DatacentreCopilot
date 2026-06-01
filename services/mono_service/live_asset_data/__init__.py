"""
Publishes live asset data to asset_live_data every INTERVAL seconds.
Each tick inserts a new row (append-only); the latest_asset_live_data view
surfaces the most recent row per asset.

Currently generates simulated data - intended to be replaced with a real
BMS integration per asset type.

Started automatically as part of the mono service (see app.py lifespan).
Requires SUPABASE_URL and SUPABASE_KEY in environment.
Uses the service key so it bypasses RLS.
"""

import asyncio
import math
import os
import random

from supabase import create_client

INTERVAL = 5  # seconds between inserts

POWER_TYPES   = {"ups", "generator", "ats", "sts", "mts", "pdu", "rpp", "transformer", "vfd"}
COOLING_TYPES = {"ahu", "acch", "crah", "cooling_tower", "dry_cooler", "heat_exchanger"}


def _make_power_data(t: float) -> dict:
    load  = 55 + 20 * math.sin(t / 30)  + random.gauss(0, 2)
    v_in  = 230 + 5  * math.sin(t / 47) + random.gauss(0, 1)
    v_out = 226 + 4  * math.sin(t / 53) + random.gauss(0, 1)
    return {
        "load_percent": round(max(0, min(100, load)), 1),
        "input_volt":   round(v_in, 1),
        "output_volt":  round(v_out, 1),
    }


def _make_cooling_data(t: float) -> dict:
    temp = 18 + 4  * math.sin(t / 40) + random.gauss(0, 0.5)
    load = 45 + 15 * math.sin(t / 35) + random.gauss(0, 2)
    return {
        "temperature":  round(max(0, temp), 1),
        "load_percent": round(max(0, min(100, load)), 1),
    }


def _should_alarm(data: dict, asset_type: str) -> bool:
    return True
    if asset_type in POWER_TYPES:
        return data["load_percent"] > 90 or not (210 <= data["input_volt"] <= 250)
    if asset_type in COOLING_TYPES:
        return data["temperature"] > 28 or data["load_percent"] > 90
    return False


async def run() -> None:
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")
    if not url or not key:
        print("live_asset_data: SUPABASE_URL / SUPABASE_KEY not set - skipping.")
        return

    sb = create_client(url, key)

    assets = sb.table("assets").select("id, asset_type, anchors(space_id)").execute().data
    live_assets = [a for a in assets if a["asset_type"] in POWER_TYPES | COOLING_TYPES]

    if not live_assets:
        print("live_asset_data: no power/cooling assets found - skipping.")
        return

    print(f"live_asset_data: publishing data for {len(live_assets)} assets every {INTERVAL}s.")

    t = 0.0
    while True:
        rows = []
        for asset in live_assets:
            asset_type = asset["asset_type"]
            data = _make_power_data(t) if asset_type in POWER_TYPES else _make_cooling_data(t)
            rows.append({
                "asset_id": asset["id"],
                "space_id": (asset.get("anchors") or {}).get("space_id"),
                "data":     data,
                "alarm":    _should_alarm(data, asset_type),
            })

        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, lambda: sb.table("asset_live_data").insert(rows).execute())

        alarms = sum(1 for r in rows if r["alarm"])
        print(f"live_asset_data: t={t:.0f}s  {len(rows)} rows  ({alarms} alarms)")

        t += INTERVAL
        await asyncio.sleep(INTERVAL)
