"""Unit tests: business rules only, no AWS and no emulator."""
import base64
import json

import pytest

from orders import InvalidOrder, parse_record, summarize


def record(payload) -> dict:
    data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
    return {"kinesis": {"sequenceNumber": "1", "data": base64.b64encode(data).decode()}}


def test_summarize_counts_and_adds_with_cents():
    assert summarize([{"amount": 0.1}, {"amount": 0.2}, {"amount": 10}]) == {"orders": 3, "total": 10.3}


def test_summarize_empty_batch():
    assert summarize([]) == {"orders": 0, "total": 0.0}


def test_parse_record_decodes_the_order():
    assert parse_record(record({"id": 7, "amount": 3.5})) == {"id": 7, "amount": 3.5}


@pytest.mark.parametrize("payload", [b"not json", {"id": 1}, {"id": 1, "amount": "abc"}])
def test_parse_record_rejects_invalid_orders(payload):
    with pytest.raises(InvalidOrder):
        parse_record(record(payload))
