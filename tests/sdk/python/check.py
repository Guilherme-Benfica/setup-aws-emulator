"""Calls STS through boto3 with no endpoint or credentials in code."""
import sys

import boto3

account = boto3.client("sts").get_caller_identity()["Account"]
print("account", account)
sys.exit(0 if account == "000000000000" else 1)
