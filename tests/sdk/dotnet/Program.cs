// Calls STS through the AWS SDK for .NET with no endpoint or credentials in code.
// On Linux, the SSL_CERT_FILE that setup-aws-emulator exports is enough. .NET on Windows
// only trusts the Windows certificate store, so there the client gets an HttpClientFactory
// that trusts the emulator certificate (AWS_CA_BUNDLE) and nothing else extra.
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using Amazon.Runtime;
using Amazon.SecurityToken;
using Amazon.SecurityToken.Model;

var config = new AmazonSecurityTokenServiceConfig();
if (OperatingSystem.IsWindows())
{
    config.HttpClientFactory = new EmulatorHttpClientFactory(Environment.GetEnvironmentVariable("AWS_CA_BUNDLE")!);
}

var identity = await new AmazonSecurityTokenServiceClient(config).GetCallerIdentityAsync(new GetCallerIdentityRequest());
Console.WriteLine($"account {identity.Account}");
return identity.Account == "000000000000" ? 0 : 1;

// Trusts the system roots plus the emulator CA. Host name checks stay on.
sealed class EmulatorHttpClientFactory(string caBundlePath) : HttpClientFactory
{
    private readonly X509Certificate2 _emulatorCa = X509Certificate2.CreateFromPem(File.ReadAllText(caBundlePath));

    public override HttpClient CreateHttpClient(IClientConfig clientConfig)
    {
        var handler = new HttpClientHandler
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
        };
        return new HttpClient(handler);
    }
}
