"""Lambda behind API Gateway (proxy integration): lists the order summaries in S3."""
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
s3 = boto3.client("s3")
BUCKET = os.environ.get("DEMO_BUCKET", "demo-events")


def handler(event, context):
    # list_objects_v2 returns at most 1,000 keys per call: the paginator reads them all.
    pages = s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix="summaries/")
    keys = [obj["Key"] for page in pages for obj in page.get("Contents", [])]
    logger.info("summaries listed", extra={"count": len(keys)})
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"count": len(keys), "keys": keys}),
    }
