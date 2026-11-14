"""Tests for the demo pipeline. Run them with the AWS_* variables pointing at AWS Emulator."""
import base64
import json
import time

import boto3

from app.handler import handler

s3 = boto3.client("s3")
kinesis = boto3.client("kinesis")


def test_kinesis_records_reach_s3_through_firehose():
    kinesis.put_record(StreamName="demo-orders", Data=json.dumps({"id": 1, "amount": 10.5}), PartitionKey="1")

    deadline = time.time() + 180
    objects = []
    while time.time() < deadline and not objects:
        objects = s3.list_objects_v2(Bucket="demo-events", Prefix="orders/").get("Contents", [])
        time.sleep(2)

    assert objects, "Firehose did not deliver to S3 within 180 seconds"
    body = s3.get_object(Bucket="demo-events", Key=objects[0]["Key"])["Body"].read().decode()
    assert '"amount": 10.5' in body


def test_handler_writes_a_summary_to_s3():
    records = [
        {"kinesis": {"sequenceNumber": "42", "data": base64.b64encode(json.dumps(o).encode()).decode()}}
        for o in ({"id": 1, "amount": 10.5}, {"id": 2, "amount": 4.5})
    ]

    result = handler({"Records": records}, None)

    assert result == {"key": "summaries/42.json", "orders": 2, "total": 15.0}
    summary = json.loads(s3.get_object(Bucket="demo-events", Key="summaries/42.json")["Body"].read())
    assert summary == {"orders": 2, "total": 15.0}
