"""Lambda for the Kinesis trigger: summarizes a batch of orders into S3.

Invalid records are reported back (ReportBatchItemFailures), so only those are retried
and, if they keep failing, sent to the dead-letter queue. The valid ones are not lost.
"""
import json
import logging
import os

import boto3

from orders import InvalidOrder, parse_record, summarize

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
s3 = boto3.client("s3")
BUCKET = os.environ.get("DEMO_BUCKET", "demo-events")


def handler(event, context):
    orders, failures = [], []
    for record in event["Records"]:
        sequence = record["kinesis"]["sequenceNumber"]
        try:
            orders.append(parse_record(record))
        except InvalidOrder as error:
            logger.warning("invalid order", extra={"sequence": sequence, "error": str(error)})
            failures.append({"itemIdentifier": sequence})

    if orders:
        key = f"summaries/{event['Records'][0]['kinesis']['sequenceNumber']}.json"
        summary = summarize(orders)
        s3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(summary), ContentType="application/json")
        logger.info("summary written", extra={"key": key, **summary})

    return {"batchItemFailures": failures}
