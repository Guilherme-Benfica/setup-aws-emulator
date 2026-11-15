"""Integration: Kinesis -> Lambda -> S3 and API Gateway -> Lambda, against AWS Emulator."""
import json
import os
import ssl
import time
import urllib.error
import urllib.request

import boto3
import pytest

from test_pipeline import wait_for_keys


def get(url, headers=None):
    context = ssl.create_default_context(cafile=os.environ.get("AWS_CA_BUNDLE"))
    request = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(request, context=context, timeout=30) as response:
        return response.status, json.loads(response.read())


def test_kinesis_record_becomes_a_summary_through_lambda(tf, s3, kinesis):
    seq = kinesis.put_record(
        StreamName=tf["stream_name"], Data=json.dumps({"id": 7, "amount": 3.5}), PartitionKey="7"
    )["SequenceNumber"]

    key = f"summaries/{seq}.json"
    found = wait_for_keys(s3, tf["bucket_name"], key, timeout=90)

    assert found, f"the Kinesis-triggered Lambda did not write {key} within 90 seconds"
    summary = json.loads(s3.get_object(Bucket=tf["bucket_name"], Key=key)["Body"].read())
    assert summary == {"orders": 1, "total": 3.5}


def test_invalid_order_goes_to_the_dead_letter_queue(tf, kinesis):
    sqs = boto3.client("sqs")
    kinesis.put_record(StreamName=tf["stream_name"], Data=b"not json", PartitionKey="bad")

    deadline = time.time() + 90
    failures = []
    while time.time() < deadline and not failures:
        messages = sqs.receive_message(QueueUrl=tf["dlq_url"], WaitTimeSeconds=5).get("Messages", [])
        failures = [json.loads(m["Body"]) for m in messages]

    assert failures, "the invalid order did not reach the dead-letter queue within 90 seconds"
    assert failures[0]["requestContext"]["condition"] == "RetryAttemptsExhausted"


def test_api_lists_summaries_with_an_api_key(tf):
    url = os.environ["AWS_ENDPOINT_URL"].rstrip("/") + tf["api_path"] + "/summaries"

    status, body = get(url, headers={"x-api-key": tf["api_key"]})

    assert status == 200
    assert body["count"] == len(body["keys"])


def test_api_refuses_calls_without_an_api_key(tf):
    url = os.environ["AWS_ENDPOINT_URL"].rstrip("/") + tf["api_path"] + "/summaries"

    with pytest.raises(urllib.error.HTTPError) as refused:
        get(url)

    assert refused.value.code == 403
