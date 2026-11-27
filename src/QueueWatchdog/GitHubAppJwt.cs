using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace QueueWatchdog;

/// <summary>
/// A GitHub App's JSON Web Token (RS256), which GitHub exchanges for an installation token. Valid from 60 s ago, to
/// allow for clock drift, for 9 minutes: GitHub accepts at most 10.
/// </summary>
public static class GitHubAppJwt
{
    public static string Create(string appId, string privateKeyPem, DateTimeOffset now)
    {
        var header = Encode(new { alg = "RS256", typ = "JWT" });
        var payload = Encode(new
        {
            iat = now.AddSeconds(-60).ToUnixTimeSeconds(),
            exp = now.AddMinutes(9).ToUnixTimeSeconds(),
            iss = appId,
        });
        var signedPart = $"{header}.{payload}";

        using var key = RSA.Create();
        key.ImportFromPem(privateKeyPem);
        var signature = key.SignData(Encoding.ASCII.GetBytes(signedPart), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        return $"{signedPart}.{Base64Url.EncodeToString(signature)}";
    }

    private static string Encode(object value) => Base64Url.EncodeToString(JsonSerializer.SerializeToUtf8Bytes(value));
}
