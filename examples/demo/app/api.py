"""Lambda behind API Gateway (proxy integration): lists the order summaries in S3."""
import json
import os

import boto3


def handler(event, context):
    listing = boto3.client("s3").list_objects_v2(
        Bucket=os.environ.get("DEMO_BUCKET", "demo-events"), Prefix="summaries/"
    )
    keys = [o["Key"] for o in listing.get("Contents", [])]
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"count": len(keys), "keys": keys}),
    }
