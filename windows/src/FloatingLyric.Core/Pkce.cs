using System.Security.Cryptography;
using System.Text;

namespace FloatingLyric.Core;

/// <summary>
/// Proof Key for Code Exchange. There is no client secret to ship, so the
/// proof of identity is a verifier generated per login and revealed only when
/// the code is redeemed.
/// </summary>
public static class Pkce
{
    public sealed record Pair(string Verifier, string Challenge);

    public static Pair Generate()
    {
        var verifier = RandomUrlSafe(64);
        var hash = SHA256.HashData(Encoding.ASCII.GetBytes(verifier));
        return new Pair(verifier, Base64Url(hash));
    }

    public static string RandomState() => RandomUrlSafe(16);

    private static string RandomUrlSafe(int byteCount)
    {
        var bytes = RandomNumberGenerator.GetBytes(byteCount);
        return Base64Url(bytes);
    }

    private static string Base64Url(byte[] bytes) =>
        System.Convert.ToBase64String(bytes)
            .Replace('+', '-').Replace('/', '_').TrimEnd('=');
}
