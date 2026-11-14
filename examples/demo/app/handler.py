"""A Lambda-style handler: reads Kinesis records and writes a summary to S3.

It is tested by calling handler() directly against AWS Emulator. The emulator does not
yet run a Lambda from a Kinesis trigger reliably, so the trigger itself is not part of
the demo.
"""
import base64
import json
import os

import boto3


def handler(event, context):
    orders = [json.loads(base64.b64decode(r["kinesis"]["data"])) for r in event["Records"]]
    summary = {"orders": len(orders), "total": round(sum(o["amount"] for o in orders), 2)}
    key = f"summaries/{event['Records'][0]['kinesis']['sequenceNumber']}.json"
    boto3.client("s3").put_object(
        Bucket=os.environ.get("DEMO_BUCKET", "demo-events"), Key=key, Body=json.dumps(summary)
    )
    return {"key": key, **summary}
