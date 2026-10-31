
"""ResQRoute API — educational prototype, not a real emergency dispatch service."""

from .admin_routes import router as admin_router
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, select
from sqlalchemy.orm import Session, joinedload

from .auth_routes import router as auth_router
from .auth import get_verified_owner
from .allocation import filter_eligible_ambulances, sort_recommendations
from .database import Base, engine, get_db
from .models import Ambulance, Assignment, EmergencyRequest, LocationUpdate
from .routing import (
    estimate_route_metrics,
    estimate_route_metrics_batch,
    get_route_geometry,
)
from .schemas import (
    AmbulanceCreate,
    AmbulanceRead,
    AmbulanceStatusUpdate,
    AssignmentCreate,
    AssignmentRead,
    AssignmentStatusUpdate,
    EmergencyRequestCreate,
    EmergencyRequestRead,
    LocationUpdateCreate,
)
from .seed import seed_demo_data


ACTIVE_ASSIGNMENT_STATUSES = {
    "accepted",
    "enroute",
    "on_scene",
    "transporting",
}


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)

    from .database import SessionLocal

    with SessionLocal() as db:
        seed_demo_data(db)

    yield


app = FastAPI(
    title="ResQRoute API",
    description=(
        "Educational prototype for ambulance allocation and route comparison. "
        "Uses synthetic demo records and is not intended for real emergency response."
    ),
    version="0.1.0",
    lifespan=lifespan,
)

# Register owner authentication and admin routes.
app.include_router(auth_router)
app.include_router(admin_router)


# Development CORS settings.
# Restrict origins before deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def root() -> dict[str, str]:
    return {
        "name": "ResQRoute API",
        "docs": "/docs",
        "mode": "educational prototype only",
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


# --------------------------------------------------
# AMBULANCE ENDPOINTS
# --------------------------------------------------

@app.get("/ambulances", response_model=list[AmbulanceRead])
def list_ambulances(
    db: Session = Depends(get_db),
) -> list[Ambulance]:
    return list(
        db.scalars(
            select(Ambulance).order_by(Ambulance.vehicle_code)
        ).all()
    )


@app.post(
    "/ambulances",
    response_model=AmbulanceRead,
    status_code=201,
)
def create_ambulance(
    payload: AmbulanceCreate,
    db: Session = Depends(get_db),
    owner=Depends(get_verified_owner),
) -> Ambulance:

    if db.scalar(
        select(Ambulance).where(
            Ambulance.vehicle_code == payload.vehicle_code
        )
    ):
        raise HTTPException(
            status_code=409,
            detail="That vehicle_code already exists.",
        )

    ambulance = Ambulance(
        **payload.model_dump(),
        owner_id=owner.id,
        status="offline",
        is_verified=False,
    )

    db.add(ambulance)
    db.commit()
    db.refresh(ambulance)

    return ambulance


@app.patch(
    "/ambulances/{ambulance_id}/status",
    response_model=AmbulanceRead,
)
def update_ambulance_status(
    ambulance_id: int,
    payload: AmbulanceStatusUpdate,
    db: Session = Depends(get_db),
    owner=Depends(get_verified_owner),
) -> Ambulance:

    ambulance = db.get(Ambulance, ambulance_id)

    if not ambulance:
        raise HTTPException(
            status_code=404,
            detail="Ambulance not found.",
        )

    if ambulance.owner_id != owner.id:
        raise HTTPException(
            status_code=403,
            detail="You can only update your own ambulance.",
        )

    if not ambulance.is_verified:
        raise HTTPException(
            status_code=403,
            detail="Your ambulance must be verified before changing its status.",
        )

    active_assignment = db.scalar(
        select(Assignment).where(
            Assignment.ambulance_id == ambulance_id,
            Assignment.status.in_(ACTIVE_ASSIGNMENT_STATUSES),
        )
    )

    if active_assignment:
        raise HTTPException(
            status_code=409,
            detail=(
                "This ambulance has an active assignment; "
                "update the assignment instead."
            ),
        )

    ambulance.status = payload.status

    db.commit()
    db.refresh(ambulance)

    return ambulance


@app.post(
    "/ambulances/{ambulance_id}/location",
    response_model=AmbulanceRead,
)
def update_ambulance_location(
    ambulance_id: int,
    payload: LocationUpdateCreate,
    db: Session = Depends(get_db),
    owner=Depends(get_verified_owner),
) -> Ambulance:

    ambulance = db.get(Ambulance, ambulance_id)

    if not ambulance:
        raise HTTPException(
            status_code=404,
            detail="Ambulance not found.",
        )

    if ambulance.owner_id != owner.id:
        raise HTTPException(
            status_code=403,
            detail="You can only update the location of your own ambulance.",
        )

    ambulance.latitude = payload.latitude
    ambulance.longitude = payload.longitude
    ambulance.last_location_at = datetime.now(timezone.utc)

    db.add(
        LocationUpdate(
            ambulance_id=ambulance.id,
            latitude=payload.latitude,
            longitude=payload.longitude,
        )
    )

    db.commit()
    db.refresh(ambulance)

    return ambulance


# --------------------------------------------------
# EMERGENCY REQUEST ENDPOINTS
# --------------------------------------------------

@app.post(
    "/requests",
    response_model=EmergencyRequestRead,
    status_code=201,
)
def create_request(
    payload: EmergencyRequestCreate,
    db: Session = Depends(get_db),
) -> EmergencyRequest:

    required = list(
        dict.fromkeys(payload.required_capabilities or ["basic"])
    )

    if "basic" not in required:
        required.insert(0, "basic")

    request = EmergencyRequest(
        **payload.model_dump(exclude={"required_capabilities"}),
        required_capabilities=required,
        status="pending",
    )

    db.add(request)
    db.commit()
    db.refresh(request)

    return request


@app.get(
    "/requests",
    response_model=list[EmergencyRequestRead],
)
def list_requests(
    status: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
) -> list[EmergencyRequest]:

    stmt = (
        select(EmergencyRequest)
        .order_by(EmergencyRequest.created_at.desc())
        .limit(limit)
    )

    if status:
        stmt = stmt.where(EmergencyRequest.status == status)

    return list(db.scalars(stmt).all())


@app.get(
    "/requests/{request_id}",
    response_model=EmergencyRequestRead,
)
def get_request(
    request_id: int,
    db: Session = Depends(get_db),
) -> EmergencyRequest:

    request = db.get(EmergencyRequest, request_id)

    if not request:
        raise HTTPException(
            status_code=404,
            detail="Emergency request not found.",
        )

    return request


@app.get("/requests/{request_id}/recommendations")
def recommend_ambulances(
    request_id: int,
    db: Session = Depends(get_db),
) -> dict[str, Any]:

    request = db.get(EmergencyRequest, request_id)

    if not request:
        raise HTTPException(
            status_code=404,
            detail="Emergency request not found.",
        )

    if request.status != "pending":
        return {
            "request_id": request.id,
            "recommendations": [],
            "message": (
                f"Request is {request.status}, not pending."
            ),
        }

    # Only admin-verified ambulances can be recommended.
    all_ambulances = list(
        db.scalars(
            select(Ambulance).where(
                Ambulance.is_verified.is_(True)
            )
        ).all()
    )

    eligible = filter_eligible_ambulances(
        all_ambulances,
        request.required_capabilities,
    )

    candidates: list[dict[str, Any]] = []

    metrics_batch = estimate_route_metrics_batch(
        [
            (ambulance.latitude, ambulance.longitude)
            for ambulance in eligible
        ],
        (request.pickup_lat, request.pickup_lng),
    )

    for ambulance, metrics in zip(eligible, metrics_batch):
        candidates.append(
            {
                "ambulance_id": ambulance.id,
                "vehicle_code": ambulance.vehicle_code,
                "driver_name": ambulance.driver_name,
                "latitude": ambulance.latitude,
                "longitude": ambulance.longitude,
                "capabilities": ambulance.capabilities,
                **metrics,
                "eta_minutes": round(
                    metrics["eta_seconds"] / 60,
                    1,
                ),
                "distance_km": round(
                    metrics["distance_m"] / 1000,
                    2,
                ),
                "last_location_at": ambulance.last_location_at,
            }
        )

    ranked = sort_recommendations(candidates)

    return {
        "request_id": request.id,
        "recommendations": ranked,
        "message": (
            "Recommendations are suggestions for dispatcher review, "
            "not an autonomous medical decision."
        ),
    }


# --------------------------------------------------
# ROUTE ENDPOINT
# --------------------------------------------------

@app.get("/routes")
def get_route(
    request_id: int,
    ambulance_id: int,
    db: Session = Depends(get_db),
) -> dict[str, Any]:

    request = db.get(EmergencyRequest, request_id)
    ambulance = db.get(Ambulance, ambulance_id)

    if not request:
        raise HTTPException(
            status_code=404,
            detail="Emergency request not found.",
        )

    if not ambulance:
        raise HTTPException(
            status_code=404,
            detail="Ambulance not found.",
        )

    route = get_route_geometry(
        ambulance.latitude,
        ambulance.longitude,
        request.pickup_lat,
        request.pickup_lng,
    )

    return {
        "request_id": request.id,
        "ambulance_id": ambulance.id,
        "start": {
            "lat": ambulance.latitude,
            "lng": ambulance.longitude,
        },
        "end": {
            "lat": request.pickup_lat,
            "lng": request.pickup_lng,
        },
        **route,
    }


# --------------------------------------------------
# ASSIGNMENT ENDPOINTS
# --------------------------------------------------

@app.post(
    "/requests/{request_id}/assign",
    response_model=AssignmentRead,
    status_code=201,
)
def assign_ambulance(
    request_id: int,
    payload: AssignmentCreate,
    db: Session = Depends(get_db),
) -> Assignment:

    request = db.get(EmergencyRequest, request_id)

    if not request:
        raise HTTPException(
            status_code=404,
            detail="Emergency request not found.",
        )

    if request.status != "pending":
        raise HTTPException(
            status_code=409,
            detail="Only pending requests can be assigned.",
        )

    ambulance = db.get(Ambulance, payload.ambulance_id)

    if not ambulance:
        raise HTTPException(
            status_code=404,
            detail="Ambulance not found.",
        )

    if not ambulance.is_verified:
        raise HTTPException(
            status_code=403,
            detail="This ambulance has not been verified by an admin.",
        )

    if ambulance.status != "available":
        raise HTTPException(
            status_code=409,
            detail="The selected ambulance is no longer available.",
        )

    required = set(request.required_capabilities or ["basic"])

    if not required.issubset(set(ambulance.capabilities or [])):
        raise HTTPException(
            status_code=409,
            detail=(
                "The ambulance does not meet the request's "
                "required capabilities."
            ),
        )

    # Re-check availability because recommendations may be stale.
    metrics = estimate_route_metrics(
        ambulance.latitude,
        ambulance.longitude,
        request.pickup_lat,
        request.pickup_lng,
    )

    assignment = Assignment(
        request_id=request.id,
        ambulance_id=ambulance.id,
        eta_seconds=metrics["eta_seconds"],
        distance_m=metrics["distance_m"],
        routing_source=metrics["routing_source"],
        status="accepted",
    )

    ambulance.status = "dispatched"
    request.status = "allocated"

    db.add(assignment)
    db.commit()
    db.refresh(assignment)

    return assignment


@app.get(
    "/assignments",
    response_model=list[AssignmentRead],
)
def list_assignments(
    active_only: bool = True,
    db: Session = Depends(get_db),
) -> list[Assignment]:

    stmt = select(Assignment).order_by(
        Assignment.assigned_at.desc()
    )

    if active_only:
        stmt = stmt.where(
            Assignment.status.in_(ACTIVE_ASSIGNMENT_STATUSES)
        )

    return list(db.scalars(stmt).all())


@app.patch(
    "/assignments/{assignment_id}/status",
    response_model=AssignmentRead,
)
def update_assignment_status(
    assignment_id: int,
    payload: AssignmentStatusUpdate,
    db: Session = Depends(get_db),
) -> Assignment:

    assignment = db.scalar(
        select(Assignment)
        .options(
            joinedload(Assignment.request),
            joinedload(Assignment.ambulance),
        )
        .where(Assignment.id == assignment_id)
    )

    if not assignment:
        raise HTTPException(
            status_code=404,
            detail="Assignment not found.",
        )

    if assignment.status in {"completed", "cancelled"}:
        raise HTTPException(
            status_code=409,
            detail="This assignment is already closed.",
        )

    requested_status = payload.status

    allowed_transitions = {
        "accepted": {"enroute", "on_scene", "cancelled"},
        "enroute": {"on_scene", "cancelled"},
        "on_scene": {"transporting", "completed", "cancelled"},
        "transporting": {"completed", "cancelled"},
    }

    if requested_status not in allowed_transitions.get(
        assignment.status,
        set(),
    ):
        raise HTTPException(
            status_code=409,
            detail=(
                f"Invalid status transition from "
                f"{assignment.status} to {requested_status}."
            ),
        )

    assignment.status = requested_status

    if requested_status == "cancelled":
        assignment.request.status = "pending"
        assignment.ambulance.status = "available"

    elif requested_status == "enroute":
        assignment.request.status = "allocated"
        assignment.ambulance.status = "dispatched"

    elif requested_status == "on_scene":
        assignment.request.status = "in_progress"
        assignment.ambulance.status = "on_scene"

    elif requested_status == "transporting":
        assignment.request.status = "in_progress"
        assignment.ambulance.status = "transporting"

    elif requested_status == "completed":
        assignment.request.status = "completed"
        assignment.ambulance.status = "available"
        assignment.completed_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(assignment)

    return assignment


# --------------------------------------------------
# DASHBOARD SUMMARY
# --------------------------------------------------

@app.get("/dashboard/summary")
def dashboard_summary(
    db: Session = Depends(get_db),
) -> dict[str, int]:

    total_ambulances = (
        db.scalar(
            select(func.count()).select_from(Ambulance)
        )
        or 0
    )

    available_ambulances = (
        db.scalar(
            select(func.count())
            .select_from(Ambulance)
            .where(Ambulance.status == "available")
        )
        or 0
    )

    open_requests = (
        db.scalar(
            select(func.count())
            .select_from(EmergencyRequest)
            .where(
                EmergencyRequest.status.in_(
                    ["pending", "allocated", "in_progress"]
                )
            )
        )
        or 0
    )

    active_assignments = (
        db.scalar(
            select(func.count())
            .select_from(Assignment)
            .where(
                Assignment.status.in_(ACTIVE_ASSIGNMENT_STATUSES)
            )
        )
        or 0
    )

    completed_requests = (
        db.scalar(
            select(func.count())
            .select_from(EmergencyRequest)
            .where(EmergencyRequest.status == "completed")
        )
        or 0
    )

    return {
        "ambulances_total": int(total_ambulances),
        "ambulances_available": int(available_ambulances),
        "requests_open": int(open_requests),
        "assignments_active": int(active_assignments),
        "requests_completed": int(completed_requests),
    }
