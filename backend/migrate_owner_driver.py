
"""Safely add owner and driver support to the ResQRoute database."""

from sqlalchemy import inspect, text

from app.database import engine
from app.models import Owner, Driver


def migrate():
    with engine.begin() as connection:
        # Create the new tables without changing existing tables.
        Owner.__table__.create(connection, checkfirst=True)
        Driver.__table__.create(connection, checkfirst=True)

        # Find existing ambulance columns.
        existing_columns = {
            column["name"]
            for column in inspect(connection).get_columns("ambulances")
        }

        # Add new columns only if they do not already exist.
        if "owner_id" not in existing_columns:
            connection.execute(
                text(
                    "ALTER TABLE ambulances "
                    "ADD COLUMN owner_id INTEGER REFERENCES owners(id)"
                )
            )

        if "driver_id" not in existing_columns:
            connection.execute(
                text(
                    "ALTER TABLE ambulances "
                    "ADD COLUMN driver_id INTEGER REFERENCES drivers(id)"
                )
            )

        if "is_verified" not in existing_columns:
            connection.execute(
                text(
                    "ALTER TABLE ambulances "
                    "ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT 1"
                )
            )

    print("Migration completed successfully!")
    print("Owner and Driver tables created.")
    print("Ambulance table updated.")


if __name__ == "__main__":
    migrate()
