using System.Text.Json;

namespace FloatingLyric.Core;

/// <summary>
/// Everything the app remembers between runs. macOS has UserDefaults; Windows
/// gets a JSON file in %APPDATA%, which is the same idea with fewer surprises
/// than the registry.
/// </summary>
public sealed class Settings
{
    public static string AppDataDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "FloatingLyric");

    private static string FilePath => Path.Combine(AppDataDirectory, "settings.json");

    public string? ClientIdOverride { get; set; }
    public int SyncOffsetMs { get; set; }
    public int FontSize { get; set; } = 18;
    public int OpacityPercent { get; set; } = PanelOpacity.DefaultPercent;
    public bool ClickThrough { get; set; }
    public bool LockPosition { get; set; }
    public bool ShowRomaji { get; set; } = true;
    public bool AutoHideChrome { get; set; } = true;
    public bool HasSignedInBefore { get; set; }
    public double? WindowX { get; set; }
    public double? WindowY { get; set; }
    public double WindowWidth { get; set; } = 420;
    public double WindowHeight { get; set; } = 210;

    /// <summary>The Client ID to authenticate with: the user's own if they set
    /// one, otherwise the app's.</summary>
    public string? ClientId => string.IsNullOrWhiteSpace(ClientIdOverride)
        ? (AppCredentials.HasBuiltInClientId ? AppCredentials.BuiltInClientId : null)
        : ClientIdOverride;

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllBytes(FilePath))
                       ?? new Settings();
        }
        catch (Exception e) when (e is IOException or JsonException) { }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(AppDataDirectory);
            File.WriteAllBytes(FilePath, JsonSerializer.SerializeToUtf8Bytes(this,
                new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (IOException) { }
    }

    public void ClampForStorage()
    {
        SyncOffsetMs = Math.Clamp(SyncOffsetMs, -2000, 2000);
        OpacityPercent = PanelOpacity.Clamped(OpacityPercent);
    }
}
