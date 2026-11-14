"""Lambda triggers in AWS Emulator: Kinesis -> Lambda -> S3, and API Gateway -> Lambda."""
import json
import os
import ssl
import time
import urllib.request

import boto3

s3 = boto3.client("s3")
kinesis = boto3.client("kinesis")


def test_kinesis_record_becomes_a_summary_through_lambda():
    seq = kinesis.put_record(
        StreamName="demo-orders", Data=json.dumps({"id": 7, "amount": 3.5}), PartitionKey="7"
    )["SequenceNumber"]

    key = f"summaries/{seq}.json"
    deadline = time.time() + 90
    while time.time() < deadline:
        found = s3.list_objects_v2(Bucket="demo-events", Prefix=key).get("Contents", [])
        if found:
            break
        time.sleep(2)

    assert found, f"the Kinesis-triggered Lambda did not write {key} within 90 seconds"
    summary = json.loads(s3.get_object(Bucket="demo-events", Key=key)["Body"].read())
    assert summary == {"orders": 1, "total": 3.5}


def test_api_gateway_lists_summaries_through_lambda():
    url = os.environ["AWS_ENDPOINT_URL"].rstrip("/") + "/dev/summaries"
    context = ssl.create_default_context(cafile=os.environ["AWS_CA_BUNDLE"])

    with urllib.request.urlopen(url, context=context, timeout=30) as response:
        assert response.status == 200
        body = json.loads(response.read())

    assert isinstance(body["count"], int)
    assert body["count"] == len(body["keys"])
