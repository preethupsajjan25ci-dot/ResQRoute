
"""Admin verification routes for ResQRoute."""

import hmac
import os

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from .database import get_db
from .models import Owner, Ambulance


router = APIRouter(
    prefix="/admin",
    tags=["Admin Verification"],
)


def require_admin(
    x_admin_key: str | None = Header(default=None, alias="X-Admin-Key"),
):
    expected_key = os.getenv("ADMIN_API_KEY")

    if not expected_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin API key is not configured.",
        )

    if not x_admin_key or not hmac.compare_digest(
        x_admin_key,
        expected_key,
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid admin key.",
        )

    return True


@router.get("/owners/pending")
def list_pending_owners(
    _: bool = Depends(require_admin),
    db: Session = Depends(get_db),
):
    owners = db.scalars(
        select(Owner)
        .where(Owner.is_verified.is_(False))
        .order_by(Owner.created_at.desc())
    ).all()

    return [
        {
            "id": owner.id,
            "full_name": owner.full_name,
            "email": owner.email,
            "phone": owner.phone,
            "is_verified": owner.is_verified,
            "created_at": owner.created_at,
        }
        for owner in owners
    ]


@router.patch("/owners/{owner_id}/verify")
def verify_owner(
    owner_id: int,
    _: bool = Depends(require_admin),
    db: Session = Depends(get_db),
):
    owner = db.get(Owner, owner_id)

    if not owner:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Owner not found.",
        )

    owner.is_verified = True

    db.commit()
    db.refresh(owner)

    return {
        "message": "Owner verified successfully.",
        "owner_id": owner.id,
        "is_verified": owner.is_verified,
    }


@router.get("/ambulances/pending")
def list_pending_ambulances(
    _: bool = Depends(require_admin),
    db: Session = Depends(get_db),
):
    ambulances = db.scalars(
        select(Ambulance)
        .where(Ambulance.is_verified.is_(False))
        .order_by(Ambulance.created_at.desc())
    ).all()

    return [
        {
            "id": ambulance.id,
            "vehicle_code": ambulance.vehicle_code,
            "driver_name": ambulance.driver_name,
            "owner_id": ambulance.owner_id,
            "is_verified": ambulance.is_verified,
            "status": ambulance.status,
        }
        for ambulance in ambulances
    ]


@router.patch("/ambulances/{ambulance_id}/verify")
def verify_ambulance(
    ambulance_id: int,
    _: bool = Depends(require_admin),
    db: Session = Depends(get_db),
):
    ambulance = db.get(Ambulance, ambulance_id)

    if not ambulance:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ambulance not found.",
        )

    if not ambulance.owner_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This ambulance is not linked to an owner.",
        )

    owner = db.get(Owner, ambulance.owner_id)

    if not owner or not owner.is_verified:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The ambulance owner must be verified first.",
        )

    ambulance.is_verified = True
    ambulance.status = "available"

    db.commit()
    db.refresh(ambulance)

    return {
        "message": "Ambulance verified successfully.",
        "ambulance_id": ambulance.id,
        "is_verified": ambulance.is_verified,
        "status": ambulance.status,
    }
