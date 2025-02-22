"""Resource Model."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class Resource(BaseModel):
    """Model for resource record."""

    id: int | None = Field(None, description="Resource ID")
    name: str = Field(..., description="Name of the resource")
    uri: str = Field(..., description="URI of the resource")
    type: Literal["local", "remote"] = Field(..., description="Type of resource (path/https)")
    status: str = Field("active", description="Status of resource (active/inactive)")
    indexing_status: Literal["pending", "indexing", "indexed", "failed"] = Field(
        "pending",
        description="Indexing status (pending/indexing/indexed/failed)",
    )
    indexing_status_message: str | None = Field(None, description="Indexing status message")
    created_at: datetime = Field(default_factory=datetime.now, description="Creation timestamp")
    indexing_started_at: datetime | None = Field(None, description="Indexing start timestamp")
    last_indexed_at: datetime | None = Field(None, description="Last indexing timestamp")
    last_error: str | None = Field(None, description="Last error message if any")
