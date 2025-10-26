"""Lambda handler for retrieving stored document summaries.

This function is invoked by API Gateway and expects the request to
include tenant and document identifiers in the path parameters. It
looks up the corresponding summary object in the tenant-specific
summary bucket and returns its JSON payload. Responses are formatted
for API Gateway proxy integration.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError


LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(logging.INFO)

S3_CLIENT = boto3.client("s3")

REGION = os.getenv("REGION", "us-east-1")
ENV = os.getenv("ENV", "dev")
SUMMARY_BUCKET_SUFFIX = os.getenv("SUMMARY_BUCKET_SUFFIX", "summaries")


def _build_bucket_name(tenant_slug: str) -> str:
    """Return the expected S3 bucket for summaries for this tenant."""
    return f"cloudable-{SUMMARY_BUCKET_SUFFIX}-{ENV}-{REGION}-{tenant_slug}"


def _response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    LOGGER.debug("Received event: %s", json.dumps(event))

    path_params = event.get("pathParameters") or {}
    tenant = path_params.get("tenant")
    document_id = path_params.get("document_id") or path_params.get("documentId")

    if not tenant or not document_id:
        return _response(400, {"error": "Missing tenant or document identifier"})

    bucket = _build_bucket_name(tenant)
    # Store summaries using document_id.json; adjust if schema differs
    key = f"{document_id}.json"

    try:
        obj = S3_CLIENT.get_object(Bucket=bucket, Key=key)
    except ClientError as exc:  # pragma: no cover - network call
        code = exc.response.get("Error", {}).get("Code")
        if code == "NoSuchKey":
            LOGGER.info("Summary not found for tenant=%s document=%s", tenant, document_id)
            return _response(404, {"error": "Summary not found"})
        if code in {"AccessDenied", "403"}:
            LOGGER.warning("Access denied fetching summary: %s", exc, exc_info=True)
            return _response(403, {"error": "Access denied fetching summary"})

        LOGGER.error("Unexpected S3 error: %s", exc, exc_info=True)
        return _response(502, {"error": "Unable to retrieve summary"})

    try:
        payload = obj["Body"].read().decode("utf-8")
        # Return parsed JSON if possible, otherwise raw text
        try:
            data = json.loads(payload)
        except json.JSONDecodeError:
            data = {"summary": payload}
    except Exception as exc:  # pragma: no cover - network call
        LOGGER.error("Failed to read summary body: %s", exc, exc_info=True)
        return _response(502, {"error": "Failed to read summary content"})

    return _response(200, {"tenant": tenant, "document_id": document_id, "data": data})
