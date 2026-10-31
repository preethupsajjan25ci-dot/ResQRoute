"""Road-routing adapter with a clearly labelled offline estimate fallback."""

import math
import os
from typing import Any

import httpx

OSRM_BASE_URL = os.getenv("OSRM_BASE_URL", "https://router.project-osrm.org").rstrip("/")
OSRM_TIMEOUT_SECONDS = 4.0


def haversine_metres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Return straight-line distance between two WGS84 coordinates in metres."""
    radius = 6_371_000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * radius * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1 - a)))



def _approximate_metrics(start_lat: float, start_lng: float, end_lat: float, end_lng: float) -> dict[str, Any]:
    """Approximate-only fallback; never label this as a road route."""
    straight_distance = haversine_metres(start_lat, start_lng, end_lat, end_lng)
    estimated_road_distance = straight_distance * 1.25
    estimated_speed_mps = 22_000 / 3600  # assumed 22 km/h, for a demo only
    return {
        "eta_seconds": estimated_road_distance / estimated_speed_mps,
        "distance_m": estimated_road_distance,
        "routing_source": "approximate_fallback",
    }


def estimate_route_metrics_batch(
    origins: list[tuple[float, float]], destination: tuple[float, float]
) -> list[dict[str, Any]]:
    """Estimate all origin-to-destination metrics using one OSRM table request when possible.

    `origins` and `destination` are (latitude, longitude). This reduces network round trips
    for a dispatcher screen showing several candidate ambulances.
    """
    if not origins:
        return []
    all_points = [*origins, destination]
    coordinates = ";".join(f"{lng},{lat}" for lat, lng in all_points)
    source_indices = ";".join(str(index) for index in range(len(origins)))
    destination_index = str(len(origins))
    url = f"{OSRM_BASE_URL}/table/v1/driving/{coordinates}"
    try:
        response = httpx.get(
            url,
            params={"sources": source_indices, "destinations": destination_index, "annotations": "duration,distance"},
            timeout=OSRM_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        data = response.json()
        if data.get("code") == "Ok":
            durations = (data.get("durations") or [])
            distances = (data.get("distances") or [])
            metrics: list[dict[str, Any]] = []
            for index, (lat, lng) in enumerate(origins):
                duration_row = durations[index] if index < len(durations) else []
                distance_row = distances[index] if index < len(distances) else []
                duration = duration_row[0] if duration_row else None
                distance = distance_row[0] if distance_row else None
                if duration is None or distance is None:
                    metrics.append(_approximate_metrics(lat, lng, destination[0], destination[1]))
                else:
                    metrics.append({
                        "eta_seconds": float(duration),
                        "distance_m": float(distance),
                        "routing_source": "osrm_road_route",
                    })
            return metrics
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        pass
    return [
        _approximate_metrics(lat, lng, destination[0], destination[1])
        for lat, lng in origins
    ]

def estimate_route_metrics(start_lat: float, start_lng: float, end_lat: float, end_lng: float) -> dict[str, Any]:
    """Fetch road metrics from OSRM. On failure, return an explicitly approximate estimate."""
    url = (
        f"{OSRM_BASE_URL}/route/v1/driving/"
        f"{start_lng},{start_lat};{end_lng},{end_lat}"
    )
    try:
        response = httpx.get(url, params={"overview": "false", "steps": "false"}, timeout=OSRM_TIMEOUT_SECONDS)
        response.raise_for_status()
        data = response.json()
        route = (data.get("routes") or [None])[0]
        if route and route.get("duration") is not None and route.get("distance") is not None:
            return {
                "eta_seconds": float(route["duration"]),
                "distance_m": float(route["distance"]),
                "routing_source": "osrm_road_route",
            }
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        pass

    # Demo fallback only: never present this as a road-derived estimate.
    return _approximate_metrics(start_lat, start_lng, end_lat, end_lng)


def get_route_geometry(start_lat: float, start_lng: float, end_lat: float, end_lng: float) -> dict[str, Any]:
    """Return route points as {lat, lng}; use a two-point line if OSRM is unavailable."""
    url = (
        f"{OSRM_BASE_URL}/route/v1/driving/"
        f"{start_lng},{start_lat};{end_lng},{end_lat}"
    )
    try:
        response = httpx.get(
            url,
            params={"overview": "full", "geometries": "geojson", "steps": "false"},
            timeout=OSRM_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        data = response.json()
        route = (data.get("routes") or [None])[0]
        coordinates = route.get("geometry", {}).get("coordinates", []) if route else []
        if coordinates:
            # GeoJSON coordinate order is [longitude, latitude].
            points = [{"lat": float(lat), "lng": float(lng)} for lng, lat in coordinates]
            return {
                "geometry": points,
                "distance_m": float(route.get("distance", 0)),
                "eta_seconds": float(route.get("duration", 0)),
                "routing_source": "osrm_road_route",
            }
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        pass

    metrics = estimate_route_metrics(start_lat, start_lng, end_lat, end_lng)
    return {
        "geometry": [
            {"lat": start_lat, "lng": start_lng},
            {"lat": end_lat, "lng": end_lng},
        ],
        **metrics,
    }
