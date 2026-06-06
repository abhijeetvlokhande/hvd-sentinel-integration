import hmac
import json
import os

import azure.functions as func
import requests
from azure.identity import ManagedIdentityCredential

credential = ManagedIdentityCredential()
MAX_PAYLOAD_BYTES = 900000


def _normalize(record):
    auth = record.get("auth") or {}
    req = record.get("request") or {}
    return {
        "eventTime": record.get("time"),
        "eventType": record.get("type"),
        "operation": req.get("operation"),
        "path": req.get("path"),
        "authDisplayName": auth.get("display_name"),
        "clientIp": req.get("remote_address"),
        "requestId": req.get("id"),
        "errorMessage": record.get("error"),
        "rawData": json.dumps(record, separators=(",", ":")),
    }


def _post_batches(endpoint, dcr_id, stream, rows):
    url = f"{endpoint}/dataCollectionRules/{dcr_id}/streams/{stream}?api-version=2023-01-01"
    token = credential.get_token("https://monitor.azure.com/.default").token
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    batch, batch_bytes = [], 2
    for row in rows:
        row_bytes = len(json.dumps(row, separators=(",", ":")).encode("utf-8"))
        if batch and batch_bytes + 1 + row_bytes > MAX_PAYLOAD_BYTES:
            requests.post(
                url,
                headers=headers,
                data=json.dumps(batch, separators=(",", ":")),
                timeout=30,
            ).raise_for_status()
            batch, batch_bytes = [], 2
        batch.append(row)
        batch_bytes += (1 if len(batch) > 1 else 0) + row_bytes

    if batch:
        requests.post(
            url,
            headers=headers,
            data=json.dumps(batch, separators=(",", ":")),
            timeout=30,
        ).raise_for_status()


def main(req: func.HttpRequest) -> func.HttpResponse:
    expected = os.environ["HCP_BEARER_TOKEN"].strip()
    incoming = req.headers.get("Authorization", "").replace("Bearer ", "", 1).strip()
    if not hmac.compare_digest(incoming, expected):
        return func.HttpResponse("unauthorized", status_code=401)

    payload = req.get_json()
    records = payload if isinstance(payload, list) else [payload]
    out = [_normalize(record) for record in records]

    endpoint = os.environ.get("DCR_ENDPOINT_URI") or os.environ.get("DCE_URI")
    if not endpoint:
        return func.HttpResponse("missing ingestion endpoint", status_code=500)

    try:
        _post_batches(endpoint, os.environ["DCR_IMMUTABLE_ID"], os.environ["STREAM_NAME"], out)
    except requests.HTTPError as err:
        return func.HttpResponse(f"ingestion failed: {err}", status_code=500)

    return func.HttpResponse("ok", status_code=200)
