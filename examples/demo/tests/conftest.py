"""Shared fixtures: resource names come from the Terraform outputs, not from the code."""
import json
import pathlib
import subprocess
import sys

import boto3
import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))


@pytest.fixture(scope="session")
def tf():
    out = subprocess.run(["terraform", f"-chdir={ROOT / 'infra'}", "output", "-json"],
                         capture_output=True, text=True, check=True).stdout
    return {name: item["value"] for name, item in json.loads(out).items()}


@pytest.fixture(scope="session")
def s3():
    return boto3.client("s3")


@pytest.fixture(scope="session")
def kinesis():
    return boto3.client("kinesis")
