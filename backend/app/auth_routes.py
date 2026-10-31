
"""Owner registration and login routes for ResQRoute."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from .database import get_db
from .models import Owner
from .schemas import OwnerRegister, OwnerLogin, AuthResponse
from .auth import (
    hash_password,
    verify_password,
    create_access_token,
)

router = APIRouter(
    prefix="/auth/owner",
    tags=["Owner Authentication"],
)


@router.post(
    "/register",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
)
def register_owner(
    payload: OwnerRegister,
    db: Session = Depends(get_db),
):
    email = payload.email.strip().lower()
    phone = payload.phone.strip()

    # Check whether the email or phone is already registered.
    existing_owner = db.scalar(
        select(Owner).where(
            (Owner.email == email) | (Owner.phone == phone)
        )
    )

    if existing_owner:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email or phone already exists.",
        )

    # Create the owner account.
    owner = Owner(
        full_name=payload.full_name.strip(),
        email=email,
        phone=phone,
        password_hash=hash_password(payload.password),
        is_verified=False,
    )

    db.add(owner)
    db.commit()
    db.refresh(owner)

    # Generate an access token.
    token = create_access_token(
        subject=str(owner.id),
        role="owner",
    )

    return AuthResponse(
        access_token=token,
        role="owner",
    )


@router.post(
    "/login",
    response_model=AuthResponse,
)
def login_owner(
    payload: OwnerLogin,
    db: Session = Depends(get_db),
):
    email = payload.email.strip().lower()

    # Find the owner by email.
    owner = db.scalar(
        select(Owner).where(Owner.email == email)
    )

    # Verify credentials.
    if (
        not owner
        or not verify_password(
            payload.password,
            owner.password_hash,
        )
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password.",
        )

    # Generate an access token.
    token = create_access_token(
        subject=str(owner.id),
        role="owner",
    )

    return AuthResponse(
        access_token=token,
        role="owner",
    )
