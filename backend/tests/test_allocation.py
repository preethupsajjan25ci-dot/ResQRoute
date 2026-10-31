from dataclasses import dataclass

from app.allocation import filter_eligible_ambulances, sort_recommendations


@dataclass
class DemoAmbulance:
    id: int
    status: str
    capabilities: list[str]


def test_filter_excludes_busy_and_missing_capability():
    ambulances = [
        DemoAmbulance(1, "available", ["basic", "oxygen"]),
        DemoAmbulance(2, "dispatched", ["basic", "oxygen", "advanced_life_support"]),
        DemoAmbulance(3, "available", ["basic"]),
    ]
    eligible = filter_eligible_ambulances(ambulances, ["basic", "oxygen"])
    assert [item.id for item in eligible] == [1]


def test_ranking_uses_eta_then_distance():
    candidates = [
        {"ambulance_id": 1, "eta_seconds": 300, "distance_m": 2000},
        {"ambulance_id": 2, "eta_seconds": 240, "distance_m": 2500},
        {"ambulance_id": 3, "eta_seconds": 300, "distance_m": 1500},
    ]
    ranked = sort_recommendations(candidates)
    assert [item["ambulance_id"] for item in ranked] == [2, 3, 1]
