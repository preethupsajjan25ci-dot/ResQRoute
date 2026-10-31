"""SQLAlchemy models used by the ResQRoute prototype."""

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Ambulance(Base):
    __tablename__ = "ambulances"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    owner_id: Mapped[int | None] = mapped_column(
        ForeignKey("owners.id"), nullable=True, index=True
    )
    driver_id: Mapped[int | None] = mapped_column(
        ForeignKey("drivers.id"), nullable=True, index=True
    )
    is_verified: Mapped[bool] = mapped_column(Boolean, default=True)
    vehicle_code: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    driver_name: Mapped[str] = mapped_column(String(120), default="Demo Driver")
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(30), default="available", index=True)
    capabilities: Mapped[list[str]] = mapped_column(JSON, default=lambda: ["basic"])
    last_location_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    assignments: Mapped[list["Assignment"]] = relationship(back_populates="ambulance")
    location_updates: Mapped[list["LocationUpdate"]] = relationship(back_populates="ambulance")
    owner: Mapped["Owner | None"] = relationship(back_populates="ambulances")
    driver: Mapped["Driver | None"] = relationship()

class EmergencyRequest(Base):
    __tablename__ = "emergency_requests"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    emergency_type: Mapped[str] = mapped_column(String(100), index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    priority: Mapped[str] = mapped_column(String(20), default="high", index=True)
    pickup_lat: Mapped[float] = mapped_column(Float)
    pickup_lng: Mapped[float] = mapped_column(Float)
    required_capabilities: Mapped[list[str]] = mapped_column(JSON, default=lambda: ["basic"])
    status: Mapped[str] = mapped_column(String(30), default="pending", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    assignments: Mapped[list["Assignment"]] = relationship(back_populates="request")


class Assignment(Base):
    __tablename__ = "assignments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    request_id: Mapped[int] = mapped_column(ForeignKey("emergency_requests.id"), index=True)
    ambulance_id: Mapped[int] = mapped_column(ForeignKey("ambulances.id"), index=True)
    eta_seconds: Mapped[float] = mapped_column(Float)
    distance_m: Mapped[float] = mapped_column(Float)
    routing_source: Mapped[str] = mapped_column(String(40), default="approximate_fallback")
    status: Mapped[str] = mapped_column(String(30), default="accepted", index=True)
    assigned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    request: Mapped[EmergencyRequest] = relationship(back_populates="assignments")
    ambulance: Mapped[Ambulance] = relationship(back_populates="assignments")


class LocationUpdate(Base):
    __tablename__ = "location_updates"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    ambulance_id: Mapped[int] = mapped_column(ForeignKey("ambulances.id"), index=True)
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    ambulance: Mapped[Ambulance] = relationship(back_populates="location_updates")
class Owner(Base):
    __tablename__ = "owners"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    full_name: Mapped[str] = mapped_column(String(120))
    email: Mapped[str] = mapped_column(String(150), unique=True, index=True)
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    ambulances: Mapped[list["Ambulance"]] = relationship(back_populates="owner")


class Driver(Base):
    __tablename__ = "drivers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    owner_id: Mapped[int] = mapped_column(ForeignKey("owners.id"), index=True)
    full_name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)

    owner: Mapped["Owner"] = relationship()
