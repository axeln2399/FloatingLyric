using Avalonia;

namespace FloatingLyric.App;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args) =>
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);

    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<FloatingLyricApp>()
        .UsePlatformDetect()
        .WithInterFont()
        .LogToTrace();
}
