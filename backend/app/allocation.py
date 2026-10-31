"""Simple, testable ambulance eligibility and ranking logic."""

from typing import Any, Iterable


def filter_eligible_ambulances(
    ambulances: Iterable[Any], required_capabilities: Iterable[str]
) -> list[Any]:
    """Keep available vehicles whose capabilities cover the request requirements."""
    required = set(required_capabilities or ["basic"])
    eligible = []
    for ambulance in ambulances:
        if ambulance.status != "available":
            continue
        capabilities = set(ambulance.capabilities or [])
        if required.issubset(capabilities):
            eligible.append(ambulance)
    return eligible


def sort_recommendations(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Rank candidates by estimated road ETA, breaking ties by route distance."""
    return sorted(candidates, key=lambda item: (item["eta_seconds"], item["distance_m"]))
