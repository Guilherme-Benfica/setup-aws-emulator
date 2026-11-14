# Setup AWS Emulator

[![test](https://github.com/Guilherme-Benfica/setup-aws-emulator/actions/workflows/test.yml/badge.svg)](https://github.com/Guilherme-Benfica/setup-aws-emulator/actions/workflows/test.yml)

Run your AWS tests and Terraform in GitHub Actions against [AWS Emulator](https://aws.amazon.com/blogs/aws/test-your-applications-against-aws-locally-with-aws-emulator/), the official local emulator AWS launched on November 11, 2026. **One step, no AWS account, no secrets, no cost.**

```yaml
- uses: Guilherme-Benfica/setup-aws-emulator@v1
```

That step installs the emulator, starts it, waits until it is healthy, and points every later step at it: the AWS CLI, every AWS SDK, and Terraform.

## Quick start

```yaml
jobs:
  test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: Guilherme-Benfica/setup-aws-emulator@v1

      - run: aws s3 mb s3://my-bucket   # goes to the emulator, not to AWS
      - run: pytest -q tests            # boto3 picks up the emulator too
```

## Terraform

The AWS provider reads the same environment variables as the CLI and SDKs, so an empty `provider "aws" {}` block is enough. No endpoint list, no fake keys.

```yaml
      - uses: actions/checkout@v4
      - uses: Guilherme-Benfica/setup-aws-emulator@v1
      - uses: hashicorp/setup-terraform@v3
      - run: terraform init && terraform apply -auto-approve
```

A full example that creates an S3 bucket, an object and a DynamoDB table lives in [`examples/terraform`](examples/terraform). This repository's CI runs it on every push: `apply`, a clean `plan`, then `destroy`.

> [!IMPORTANT]
> **Pin the AWS provider below 6.23.0 for `aws_s3_bucket`.** From 6.23.0 the provider reads and writes bucket tags through Amazon S3 Control, and the SDK always sends S3 Control requests to `<account-id>.127.0.0.1`, a host that doesn't exist. AWS Emulator [documents this limitation](https://docs.aws.amazon.com/emulator/latest/userguide/point-sdk-to-emulator.html#point-sdk-host-names). The apply fails with `lookup 000000000000.127.0.0.1: no such host`. Until that changes, use:
>
> ```hcl
> aws = {
>   source  = "hashicorp/aws"
>   version = ">= 5.0, < 6.23.0"
> }
> ```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `port` | `9297` | Port the emulator listens on, bound to 127.0.0.1 only. |
| `region` | `us-east-1` | Exported to `AWS_REGION` and `AWS_DEFAULT_REGION`. |
| `telemetry` | `off` | Emulator telemetry, `on` or `off`. |
| `wait-timeout` | `60` | Seconds to wait for the health check before failing. |

## Outputs

| Output | Example |
| --- | --- |
| `endpoint` | `https://127.0.0.1:9297` |
| `ca-bundle` | Path to the emulator's `ca.pem` |
| `account-id` | `000000000000` |
| `log-file` | Path to the emulator log, handy in an `if: failure()` step |

## What the action exports

| Variable | Value |
| --- | --- |
| `AWS_ENDPOINT_URL` | `https://127.0.0.1:<port>` |
| `AWS_SHARED_CREDENTIALS_FILE` | `~/.aws/emulator/<port>/emulator_credentials` |
| `AWS_CONFIG_FILE` | `~/.aws/emulator/<port>/config` |
| `AWS_CA_BUNDLE` | `~/.aws/emulator/<port>/ca.pem` |
| `AWS_EC2_METADATA_DISABLED` | `true` |
| `AWS_DISABLE_HOST_PREFIX_INJECTION` | `true` |
| `AWS_REGION`, `AWS_DEFAULT_REGION` | the `region` input |

Before handing over, the action calls `sts get-caller-identity` and fails unless the answer is the emulator account `000000000000`, so a misconfigured job never silently reaches a real account.

## Good to know

- **Linux runners only** (x64 and arm64). On macOS and Windows, AWS Emulator runs through Docker.
- **Do not combine it with real credentials in the same job.** If `AWS_ACCESS_KEY_ID` or `AWS_PROFILE` is set, the action warns you, because those win over the emulator's credentials file.
- **IAM is not enforced.** AWS Emulator does not evaluate IAM policies the way AWS does, so test permissions on real AWS.
- **State is in memory** and disappears with the runner, so every job starts clean.
- Fidelity varies by service and operation, and unsupported operations return HTTP 501. See the [AWS Emulator User Guide](https://docs.aws.amazon.com/emulator/latest/userguide/what-is-service.html).

## Learn more

- Step-by-step tutorial: [AWS Emulator in practice](https://builder.aws.com/content/3M3qSo4KH3KNMJdJ6SExYVuylnA/aws-emulator-in-practice-test-aws-on-your-machine-with-no-account-and-no-cost) on AWS Builder Center
- Sample app with tests: [aws-emulator-notes-demo](https://github.com/Guilherme-Benfica/aws-emulator-notes-demo)

Issues and pull requests are welcome, especially results from other services.

This project is not affiliated with or endorsed by Amazon Web Services.

## License

[MIT](LICENSE) · Guilherme Benfica
