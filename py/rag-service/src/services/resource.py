"""Resource Service."""

from libs.db import get_db_connection
from models.resource import Resource


class ResourceService:
    """Resource Service."""

    def add_resource_to_db(self, resource: Resource) -> None:
        """Add a resource to the database."""
        with get_db_connection() as conn:
            conn.execute(
                """
              INSERT INTO resources (name, uri, type, status, indexing_status, created_at)
              VALUES (?, ?, ?, ?, ?, ?)
              """,
                (
                    resource.name,
                    resource.uri,
                    resource.type,
                    resource.status,
                    resource.indexing_status,
                    resource.created_at,
                ),
            )
            conn.commit()

    def update_resource_indexing_status(self, uri: str, indexing_status: str, indexing_status_message: str) -> None:
        """Update resource indexing status in the database."""
        with get_db_connection() as conn:
            if indexing_status == "indexing":
                conn.execute(
                    """
                  UPDATE resources
                  SET indexing_status = ?, indexing_status_message = ?, indexing_started_at = CURRENT_TIMESTAMP
                  WHERE uri = ?
                  """,
                    (indexing_status, indexing_status_message, uri),
                )
            else:
                conn.execute(
                    """
                  UPDATE resources
                  SET indexing_status = ?, indexing_status_message = ?, last_indexed_at = CURRENT_TIMESTAMP
                  WHERE uri = ?
                  """,
                    (indexing_status, indexing_status_message, uri),
                )
            conn.commit()

    def update_resource_status(self, uri: str, status: str, error: str | None = None) -> None:
        """Update resource status in the database."""
        with get_db_connection() as conn:
            if status == "active":
                conn.execute(
                    """
                  UPDATE resources
                  SET status = ?, last_indexed_at = CURRENT_TIMESTAMP, last_error = ?
                  WHERE uri = ?
                  """,
                    (status, error, uri),
                )
            else:
                conn.execute(
                    """
                  UPDATE resources
                  SET status = ?, last_error = ?
                  WHERE uri = ?
                  """,
                    (status, error, uri),
                )
            conn.commit()

    def get_resource(self, uri: str) -> Resource | None:
        """Get resource from the database."""
        with get_db_connection() as conn:
            row = conn.execute(
                "SELECT * FROM resources WHERE uri = ?",
                (uri,),
            ).fetchone()
            if row:
                return Resource(**dict(row))
            return None

    def get_resource_by_name(self, name: str) -> Resource | None:
        """Get resource by name from the database."""
        with get_db_connection() as conn:
            row = conn.execute(
                "SELECT * FROM resources WHERE name = ?",
                (name,),
            ).fetchone()
            if row:
                return Resource(**dict(row))
            return None

    def get_all_resources(self) -> list[Resource]:
        """Get all resources from the database."""
        with get_db_connection() as conn:
            rows = conn.execute("SELECT * FROM resources ORDER BY created_at DESC").fetchall()
            return [Resource(**dict(row)) for row in rows]


resource_service = ResourceService()
