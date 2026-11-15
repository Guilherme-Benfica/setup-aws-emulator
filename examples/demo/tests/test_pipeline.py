"""Integration: Kinesis -> Firehose -> S3, against AWS Emulator (or a real account)."""
import json
import time


def wait_for_keys(s3, bucket, prefix, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        found = s3.list_objects_v2(Bucket=bucket, Prefix=prefix).get("Contents", [])
        if found:
            return found
        time.sleep(2)
    return []


def test_kinesis_records_reach_s3_through_firehose(tf, s3, kinesis):
    kinesis.put_record(StreamName=tf["stream_name"], Data=json.dumps({"id": 1, "amount": 10.5}), PartitionKey="1")

    objects = wait_for_keys(s3, tf["bucket_name"], "orders/", timeout=180)

    assert objects, "Firehose did not deliver to S3 within 180 seconds"
    body = s3.get_object(Bucket=tf["bucket_name"], Key=objects[0]["Key"])["Body"].read().decode()
    assert '"amount": 10.5' in body


def test_bucket_is_private_encrypted_and_versioned(tf, s3):
    bucket = tf["bucket_name"]
    block = s3.get_public_access_block(Bucket=bucket)["PublicAccessBlockConfiguration"]
    assert all(block.values())
    rule = s3.get_bucket_encryption(Bucket=bucket)["ServerSideEncryptionConfiguration"]["Rules"][0]
    assert rule["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"] == "AES256"
    assert s3.get_bucket_versioning(Bucket=bucket)["Status"] == "Enabled"
