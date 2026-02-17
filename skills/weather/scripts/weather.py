#!/usr/bin/env python3
"""Open-Meteo weather helper for OpenClawKit skills."""

from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request


def _http_get_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=10) as response:
        payload = response.read().decode("utf-8")
        return json.loads(payload)


def _resolve_coords(payload: dict) -> tuple[float, float, str]:
    if "latitude" in payload and "longitude" in payload:
        latitude = float(payload["latitude"])
        longitude = float(payload["longitude"])
        name = payload.get("location") or f"{latitude:.4f},{longitude:.4f}"
        return latitude, longitude, str(name)

    location = str(payload.get("location", "")).strip()
    if not location:
        raise ValueError("Input must include `location` or (`latitude`, `longitude`).")

    query = urllib.parse.urlencode({"name": location, "count": 1, "language": "en", "format": "json"})
    geo_url = f"https://geocoding-api.open-meteo.com/v1/search?{query}"
    geo_data = _http_get_json(geo_url)
    results = geo_data.get("results") or []
    if not results:
        raise ValueError(f"No geocoding result for location: {location}")

    top = results[0]
    latitude = float(top["latitude"])
    longitude = float(top["longitude"])
    country = top.get("country_code") or top.get("country") or ""
    resolved = f"{top.get('name', location)}, {country}".strip(", ")
    return latitude, longitude, resolved


def _read_input() -> dict:
    raw = ""
    if len(sys.argv) > 1:
        raw = sys.argv[1]
    else:
        raw = sys.stdin.read().strip()
    if not raw:
        return {}
    return json.loads(raw)


def main() -> int:
    try:
        user_input = _read_input()
        latitude, longitude, resolved_name = _resolve_coords(user_input)

        forecast_query = urllib.parse.urlencode(
            {
                "latitude": latitude,
                "longitude": longitude,
                "current": "temperature_2m,weather_code,wind_speed_10m",
                "daily": "temperature_2m_max,temperature_2m_min,weather_code",
                "timezone": "auto",
                "forecast_days": 1,
            }
        )
        forecast_url = f"https://api.open-meteo.com/v1/forecast?{forecast_query}"
        forecast = _http_get_json(forecast_url)

        current = forecast.get("current", {})
        daily = forecast.get("daily", {})
        output = {
            "resolved_location": resolved_name,
            "latitude": latitude,
            "longitude": longitude,
            "current": {
                "temperature_c": current.get("temperature_2m"),
                "weather_code": current.get("weather_code"),
                "wind_kmh": current.get("wind_speed_10m"),
            },
            "today": {
                "temp_max_c": (daily.get("temperature_2m_max") or [None])[0],
                "temp_min_c": (daily.get("temperature_2m_min") or [None])[0],
                "weather_code": (daily.get("weather_code") or [None])[0],
            },
        }
        print(json.dumps(output, separators=(",", ":")))
        return 0
    except Exception as error:  # noqa: BLE001
        print(json.dumps({"error": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
