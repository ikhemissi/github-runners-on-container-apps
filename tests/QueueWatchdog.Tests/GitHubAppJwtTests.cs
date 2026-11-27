using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace QueueWatchdog.Tests;

public class GitHubAppJwtTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 27, 18, 0, 0, TimeSpan.Zero);

    [Fact]
    public void The_token_is_signed_with_the_apps_key_and_carries_the_claims_GitHub_requires()
    {
        using var key = RSA.Create(2048);
        var jwt = GitHubAppJwt.Create("123456", key.ExportRSAPrivateKeyPem(), Now);

        var parts = jwt.Split('.');
        var header = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[0])).RootElement;
        var claims = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[1])).RootElement;
        var signatureVerifies = key.VerifyData(
            Encoding.ASCII.GetBytes($"{parts[0]}.{parts[1]}"), Base64Url.DecodeFromChars(parts[2]),
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);

        Assert.True(signatureVerifies);
        Assert.Equal("RS256", header.GetProperty("alg").GetString());
        Assert.Equal("123456", claims.GetProperty("iss").GetString());
        Assert.Equal(Now.AddSeconds(-60).ToUnixTimeSeconds(), claims.GetProperty("iat").GetInt64());
        Assert.True(claims.GetProperty("exp").GetInt64() <= Now.AddMinutes(10).ToUnixTimeSeconds());
    }
}
