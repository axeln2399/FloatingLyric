using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;

namespace FloatingLyric.Core;

public interface ITokenStore
{
    string? ReadRefreshToken();
    void WriteRefreshToken(string token);
    void DeleteRefreshToken();
}

/// <summary>
/// The refresh token, encrypted with DPAPI so only this Windows user account
/// can read it back. macOS keeps the equivalent in the Keychain; the shape of
/// the guarantee is the same.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class DpapiTokenStore : ITokenStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("com.floatinglyric.tokens");

    private readonly string _path;

    public DpapiTokenStore(string? path = null)
    {
        _path = path ?? Path.Combine(Settings.AppDataDirectory, "refresh.bin");
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
    }

    public string? ReadRefreshToken()
    {
        try
        {
            if (!File.Exists(_path)) return null;
            var plain = ProtectedData.Unprotect(
                File.ReadAllBytes(_path), Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plain);
        }
        catch
        {
            // A token encrypted by another account, or a corrupt file, is the
            // same thing as no token: ask the user to log in again.
            return null;
        }
    }

    public void WriteRefreshToken(string token)
    {
        var cipher = ProtectedData.Protect(
            Encoding.UTF8.GetBytes(token), Entropy, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(_path, cipher);
    }

    public void DeleteRefreshToken()
    {
        try { File.Delete(_path); } catch (IOException) { }
    }
}

public sealed class InMemoryTokenStore(string? token = null) : ITokenStore
{
    private string? _token = token;
    public string? ReadRefreshToken() => _token;
    public void WriteRefreshToken(string token) => _token = token;
    public void DeleteRefreshToken() => _token = null;
}
