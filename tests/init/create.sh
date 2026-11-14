#!/usr/bin/env bash
# Used by the init test: creates resources the test checks afterwards.
set -euo pipefail
aws s3 mb s3://init-bucket
aws kinesis create-stream --stream-name init-stream --shard-count 1
aws kinesis wait stream-exists --stream-name init-stream
