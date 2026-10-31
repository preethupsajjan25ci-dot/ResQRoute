"""Create synthetic demonstration data; these are not live ambulance locations."""

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .models import Ambulance, EmergencyRequest


def seed_demo_data(db: Session) -> None:
    if (db.scalar(select(func.count()).select_from(Ambulance)) or 0) > 0:
        return

    # Synthetic sample coordinates around Bengaluru, solely to make the map demo useful.
    demo_ambulances = [
        Ambulance(vehicle_code="RQR-101", driver_name="Demo Driver A", latitude=12.9716, longitude=77.5946, status="available", capabilities=["basic", "oxygen"]),
        Ambulance(vehicle_code="RQR-102", driver_name="Demo Driver B", latitude=12.9250, longitude=77.5830, status="available", capabilities=["basic"]),
        Ambulance(vehicle_code="RQR-103", driver_name="Demo Driver C", latitude=13.0030, longitude=77.5700, status="available", capabilities=["basic", "oxygen", "advanced_life_support"]),
        Ambulance(vehicle_code="RQR-104", driver_name="Demo Driver D", latitude=12.9780, longitude=77.6400, status="offline", capabilities=["basic", "oxygen"]),
        Ambulance(vehicle_code="RQR-105", driver_name="Demo Driver E", latitude=13.0350, longitude=77.5970, status="available", capabilities=["basic", "oxygen"]),
    ]
    db.add_all(demo_ambulances)
    db.flush()

    demo_request = EmergencyRequest(
        emergency_type="Medical assistance (demo)",
        description="Synthetic example request for testing only. Not a real emergency.",
        priority="high",
        pickup_lat=12.9610,
        pickup_lng=77.6040,
        required_capabilities=["basic"],
        status="pending",
    )
    db.add(demo_request)
    db.commit()
