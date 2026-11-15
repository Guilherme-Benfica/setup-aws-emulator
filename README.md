# Setup AWS Emulator

[![test](https://github.com/Guilherme-Benfica/setup-aws-emulator/actions/workflows/test.yml/badge.svg)](https://github.com/Guilherme-Benfica/setup-aws-emulator/actions/workflows/test.yml)

Run your AWS tests and Terraform in GitHub Actions against [AWS Emulator](https://aws.amazon.com/blogs/aws/test-your-applications-against-aws-locally-with-aws-emulator/), the official local emulator AWS launched on November 11, 2026. **One step, no AWS account, no secrets, no cost.**

```yaml
- uses: Guilherme-Benfica/setup-aws-emulator@v1
```

That step installs the emulator, starts it, waits until it is healthy, and points every later step at it: the AWS CLI, the AWS SDKs for Python, Go, JavaScript, .NET and Java, and Terraform. It can also create your test resources first (`init`).

The same scripts run on your own machine as the [`awsemu`](#use-it-on-your-machine) command.

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

## Create resources before the tests (`init`)

List `.sh` scripts and Terraform directories, one per line. They run in order, after the emulator is up and the variables are set:

```yaml
      - uses: hashicorp/setup-terraform@v3   # only needed for Terraform directories
      - uses: Guilherme-Benfica/setup-aws-emulator@v1
        with:
          init: |
            scripts/create-queues.sh
            infra/
```

If a step fails, the action fails and prints the emulator log.

## SDKs

| SDK | What the action sets up |
| --- | --- |
| AWS CLI, Python (boto3), Go | Nothing extra: they read `AWS_CA_BUNDLE` and the emulator config |
| JavaScript v3 (Node.js) | `NODE_EXTRA_CA_CERTS` (added to Node's own roots) |
| .NET and Rust on Linux | `SSL_CERT_FILE`: the system CA certificates **plus** the emulator CA, so `npm`, `dotnet restore` and `curl` keep working |
| Java 2.x | A trust store with the JDK roots plus the emulator CA, in `AWS_EMULATOR_JAVA_OPTS` |

Pass `AWS_EMULATOR_JAVA_OPTS` to the JVM that runs your tests:

```yaml
      - run: mvn -B test "-DargLine=$AWS_EMULATOR_JAVA_OPTS"           # Maven Surefire
      - run: ./gradlew test                                            # Gradle: test { jvmArgs(System.getenv("AWS_EMULATOR_JAVA_OPTS").split(" ")) }
```

Or set `java-tool-options: true` and every JVM in the job trusts the emulator (the trust store keeps the JDK roots, so Maven and Gradle downloads still work).

**.NET on Windows** ignores `SSL_CERT_FILE` and trusts only the Windows certificate store. Rather than adding the emulator CA to the machine, give the client an `HttpClientFactory` that trusts it ([full file](tests/sdk/dotnet/Program.cs)):

```csharp
var config = new AmazonSecurityTokenServiceConfig();
if (OperatingSystem.IsWindows())
    config.HttpClientFactory = new EmulatorHttpClientFactory(Environment.GetEnvironmentVariable("AWS_CA_BUNDLE")!);

sealed class EmulatorHttpClientFactory(string caBundlePath) : HttpClientFactory
{
    private readonly X509Certificate2 _emulatorCa = X509Certificate2.CreateFromPem(File.ReadAllText(caBundlePath));

    public override HttpClient CreateHttpClient(IClientConfig clientConfig) => new(new HttpClientHandler
    {
        ServerCertificateCustomValidationCallback = (_, certificate, chain, errors) =>
        {
            if (errors == SslPolicyErrors.None) return true;
            if (errors != SslPolicyErrors.RemoteCertificateChainErrors || certificate is null || chain is null) return false;
            chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
            chain.ChainPolicy.CustomTrustStore.Add(_emulatorCa);
            chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
            return chain.Build(certificate);
        },
    });
}
```

Each of these is tested in CI on Linux and on Windows (Java on Linux).

## Windows

The same step works on `windows-2022` and `windows-2025`:

```yaml
    runs-on: windows-2025
    steps:
      - uses: actions/checkout@v4
      - uses: Guilherme-Benfica/setup-aws-emulator@v1
      - run: aws s3 mb s3://my-bucket   # PowerShell, cmd or Git Bash
```

AWS Emulator runs natively only on Linux, and Docker on GitHub-hosted Windows runners only runs Windows containers. So on Windows the action installs Ubuntu in WSL 1 with [`Vampire/setup-wsl`](https://github.com/Vampire/setup-wsl) and runs the emulator there. WSL 1 shares the network with Windows, so the emulator is at `https://127.0.0.1:9297` for every Windows program, and the action exports Windows paths (`C:\Users\...\.aws\emulator\9297\...`) in the same variables as on Linux. Setting up WSL adds about two minutes to the job.

## Lambda triggers

AWS Emulator runs Lambda functions and their triggers. The [demo](examples/demo) covers Kinesis → Firehose → S3, Kinesis → Lambda → S3 and API Gateway → Lambda, created with Terraform following the AWS Well-Architected pillars (private encrypted bucket, encrypted stream, least-privilege roles, dead-letter queue with partial batch failures, log groups with retention, API key with throttling) and checked by unit and integration tests in CI. What we learned building it:

- **The function role must be able to read the stream** (`kinesis:GetRecords`, `GetShardIterator`, `DescribeStream`, `DescribeStreamSummary`, `ListShards`, `ListStreams`). Like AWS, the emulator refuses the event source mapping otherwise, even though it does not evaluate IAM policies elsewhere.
- **REST API stages answer at `https://127.0.0.1:<port>/<stage>/<path>`**, for example `https://127.0.0.1:9297/dev/summaries`. The proxy event has the v1 structure.
- **Each Kinesis record arrives in its own invocation**: the emulator does not batch. Test batching, batching windows, tumbling windows and event filters on AWS. The official fidelity report shows those details fail today, while the basic trigger works.
- **Functions run isolated**: they cannot open files on your machine.
- **Failed records reach the dead-letter queue**: with `ReportBatchItemFailures`, retries and an `on_failure` destination, an invalid record lands in SQS after the retries (`RetryAttemptsExhausted`), as on AWS.
- **`log_format = "JSON"` is ignored**: logs reach CloudWatch as plain text. Check structured logging on AWS.
- **API keys need an explicit value**: AWS generates one when you omit it; the emulator asks for 20+ characters, so generate it (for example with `random_password`). The emulator does enforce the key: calls without it get 403.
- **A versioned bucket with objects cannot be deleted**, as on AWS: the demo sets `force_destroy` outside production so `terraform destroy` works.

## Report at the end of the job

```yaml
      - uses: Guilherme-Benfica/setup-aws-emulator/report@v1
        if: always()
```

It uploads the emulator log as an artifact and adds a section to the job summary. When a test fails with `NotImplemented` (HTTP 501, "scaffolded but not implemented in this emulator"), the operation is not in AWS Emulator yet: an emulator limitation, not a bug in your code. The emulator does not log each request, so the report cannot list those calls for you.

## Apps in containers

On Linux, a container started with `network_mode: host` reaches the emulator at `127.0.0.1`, so its certificate stays valid. Mount the emulator folder and pass the variables, as in [`examples/compose/compose.yml`](examples/compose/compose.yml):

```yaml
      - run: EMULATOR_DIR="$(dirname "$AWS_CA_BUNDLE")" docker compose -f examples/compose/compose.yml run --rm aws
```

## Use it on your machine

`awsemu` runs the emulator locally with the same scripts, on Linux and on Windows (through WSL).

**Windows (PowerShell)** — needs WSL with a Linux distribution (`wsl --install -d Ubuntu-24.04`):

```powershell
irm https://raw.githubusercontent.com/Guilherme-Benfica/setup-aws-emulator/v1/install.ps1 | iex
# open a new terminal
awsemu up
awsemu env | Out-String | Invoke-Expression
aws s3 mb s3://my-bucket
awsemu down
```

**Linux (bash)**:

```bash
curl -fsSL https://raw.githubusercontent.com/Guilherme-Benfica/setup-aws-emulator/v1/install.sh | bash
awsemu up
eval "$(awsemu env)"
aws s3 mb s3://my-bucket
awsemu down
```

Prefer to read the installer first? Download [`install.sh`](install.sh) or [`install.ps1`](install.ps1), read it, then run it. It only copies files to `~/.awsemu/app` and adds `awsemu` to your user PATH; nothing needs admin.

| Command | What it does |
| --- | --- |
| `awsemu up [--port N] [--region R] [--init PATH]... [--telemetry on]` | Installs the emulator if needed, starts it, runs init steps (`.sh` or Terraform on Linux, `.ps1` or Terraform on Windows) |
| `awsemu env [--port N] [--shell bash\|pwsh]` | Prints the variables, and removes real AWS credentials from that shell |
| `awsemu status`, `awsemu logs [-f]`, `awsemu down` | Health and account, the log, stop and clean up |

In Git Bash on Windows, `awsemu` hands off to the Windows version; use `eval "$(awsemu env)"` there. Telemetry is off unless you pass `--telemetry on`. On Windows the emulator writes its files under `%USERPROFILE%\.aws\emulator\<port>`, so Windows programs read the same config and certificate.

## Other CI systems

`awsemu` works in any Linux job. These examples are **untested**; issues and fixes are welcome.

```yaml
# GitLab CI
test:
  image: ubuntu:24.04
  before_script:
    - apt-get update && apt-get install -y curl ca-certificates awscli
    - curl -fsSL https://raw.githubusercontent.com/Guilherme-Benfica/setup-aws-emulator/v1/install.sh | bash
    - export PATH="$HOME/.local/bin:$PATH"
    - awsemu up
    - eval "$(awsemu env)"
  script:
    - pytest -q tests
```

```yaml
# Azure Pipelines
pool:
  vmImage: ubuntu-24.04
steps:
  - bash: |
      curl -fsSL https://raw.githubusercontent.com/Guilherme-Benfica/setup-aws-emulator/v1/install.sh | bash
      export PATH="$HOME/.local/bin:$PATH"
      awsemu up
      eval "$(awsemu env)"
      pytest -q tests
```

```groovy
// Jenkins (Linux agent)
sh '''
  curl -fsSL https://raw.githubusercontent.com/Guilherme-Benfica/setup-aws-emulator/v1/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
  awsemu up
  eval "$(awsemu env)"
  pytest -q tests
  awsemu down
'''
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `version` | `latest` | Emulator version to install: `latest`, or a version such as `1.0.351` from [`versions.json`](https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/versions.json) (`1.0.351.1` works too). Pin it when you want the same emulator on every run. |
| `port` | `9297` | Port the emulator listens on, bound to 127.0.0.1 only. |
| `region` | `us-east-1` | Exported to `AWS_REGION` and `AWS_DEFAULT_REGION`. |
| `telemetry` | `off` | Emulator telemetry, `on` or `off`. |
| `init` | | `.sh` scripts and Terraform directories to run after start, one per line. |
| `java-tool-options` | `false` | Also export `JAVA_TOOL_OPTIONS` with the emulator trust store. |
| `wait-timeout` | `60` | Seconds to wait for the health check before failing. |

## Outputs

| Output | Example |
| --- | --- |
| `version` | Version printed by `aws-emulator -v` |
| `endpoint` | `https://127.0.0.1:9297` |
| `ca-bundle` | Path to the emulator's `ca.pem` |
| `account-id` | `000000000000` |
| `ca-bundle-combined` | System CAs plus the emulator CA (Linux), also in `SSL_CERT_FILE` |
| `java-truststore` | PKCS12 trust store with the JDK roots plus the emulator CA (password `changeit`) |
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
| `NODE_EXTRA_CA_CERTS` | the emulator `ca.pem` |
| `SSL_CERT_FILE` | system CAs plus the emulator CA (Linux only) |
| `AWS_EMULATOR_JAVA_OPTS` | trust store options for your test JVM (when `keytool` is available) |
| `JAVA_TOOL_OPTIONS` | the same, only with `java-tool-options: true` |

Before handing over, the action calls `sts get-caller-identity` and fails unless the answer is the emulator account `000000000000`, so a misconfigured job never silently reaches a real account.

## Good to know

- **Runs on Linux (x64, arm64) and Windows (x64) runners.** macOS runners aren't supported, because GitHub-hosted macOS runners have no Docker. On a self-hosted macOS runner, use the [Docker setup](https://docs.aws.amazon.com/emulator/latest/userguide/getting-started-docker.html).
- **Do not combine it with real credentials in the same job.** If `AWS_ACCESS_KEY_ID` or `AWS_PROFILE` is set, the action warns you, because those win over the emulator's credentials file.
- **Use a recent AWS SDK.** The action points SDKs at the emulator through `AWS_ENDPOINT_URL`. An SDK too old to read it calls real AWS instead, where the emulator keys are rejected (`The security token included in the request is invalid`) and nothing is created. We saw this with the AWS SDK for Java 2.28.0; the CI here uses 2.55.0. The `account-id` check only covers the AWS CLI.
- **IAM is not enforced.** AWS Emulator does not evaluate IAM policies the way AWS does, so test permissions on real AWS.
- **State is in memory** and disappears with the runner, so every job starts clean.
- Fidelity varies by service and operation, and unsupported operations return HTTP 501. See the [AWS Emulator User Guide](https://docs.aws.amazon.com/emulator/latest/userguide/what-is-service.html).

## Versioning

Releases follow `vMAJOR.MINOR.PATCH`. The major tag (`v1`) always points at the latest `v1.x.y`, so `@v1` picks up fixes without breaking changes. Pin a full version (`@v1.0.0`) or a commit SHA if you want nothing to move.

To release, either publish a release such as `v1.2.3` in the GitHub UI, or run the [`release`](.github/workflows/release.yml) workflow by hand with that version. Both move the major tag to the new release.

## Learn more

- Step-by-step tutorial: [AWS Emulator in practice](https://builder.aws.com/content/3M3qSo4KH3KNMJdJ6SExYVuylnA/aws-emulator-in-practice-test-aws-on-your-machine-with-no-account-and-no-cost) on AWS Builder Center
- Sample app with tests: [aws-emulator-notes-demo](https://github.com/Guilherme-Benfica/aws-emulator-notes-demo)

Issues and pull requests are welcome, especially results from other services.

This project is not affiliated with or endorsed by Amazon Web Services.

## License

[MIT](LICENSE) · Guilherme Benfica
