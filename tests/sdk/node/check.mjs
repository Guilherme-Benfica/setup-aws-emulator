// Calls STS through the AWS SDK for JavaScript v3 with no endpoint or credentials in code.
import { GetCallerIdentityCommand, STSClient } from "@aws-sdk/client-sts";

const { Account } = await new STSClient({}).send(new GetCallerIdentityCommand({}));
console.log("account", Account);
process.exit(Account === "000000000000" ? 0 : 1);
