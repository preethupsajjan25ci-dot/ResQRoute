
"""Pydantic request and response schemas."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Priority = Literal["low", "medium", "high", "critical"]
AmbulanceStatus = Literal[
    "available", "dispatched", "on_scene", "transporting", "offline"
]
AssignmentStatus = Literal[
    "enroute", "on_scene", "transporting", "completed", "cancelled"
]


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class AmbulanceCreate(BaseModel):
    vehicle_code: str = Field(min_length=1, max_length=40)
    driver_name: str = Field(default="Demo Driver", max_length=120)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    capabilities: list[str] = Field(default_factory=lambda: ["basic"])


class AmbulanceRead(ORMModel):
    id: int
    vehicle_code: str
    driver_name: str
    latitude: float
    longitude: float
    status: str
    capabilities: list[str]
    last_location_at: datetime
    created_at: datetime


class EmergencyRequestCreate(BaseModel):
    emergency_type: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=1000)
    priority: Priority = "high"
    pickup_lat: float = Field(ge=-90, le=90)
    pickup_lng: float = Field(ge=-180, le=180)
    required_capabilities: list[str] = Field(
        default_factory=lambda: ["basic"]
    )


class EmergencyRequestRead(ORMModel):
    id: int
    emergency_type: str
    description: str | None
    priority: str
    pickup_lat: float
    pickup_lng: float
    required_capabilities: list[str]
    status: str
    created_at: datetime


class LocationUpdateCreate(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class AmbulanceStatusUpdate(BaseModel):
    status: Literal["available", "offline"]


class AssignmentCreate(BaseModel):
    ambulance_id: int


class AssignmentStatusUpdate(BaseModel):
    status: AssignmentStatus


class AssignmentRead(ORMModel):
    id: int
    request_id: int
    ambulance_id: int
    eta_seconds: float
    distance_m: float
    routing_source: str
    status: str
    assigned_at: datetime
    completed_at: datetime | None


# Owner authentication schemas

class OwnerRegister(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    email: str = Field(min_length=5, max_length=150)
    phone: str = Field(min_length=10, max_length=20)
    password: str = Field(min_length=8, max_length=128)


class OwnerLogin(BaseModel):
    email: str = Field(min_length=5, max_length=150)
    password: str = Field(min_length=8, max_length=128)


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
