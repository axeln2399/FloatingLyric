using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using FloatingLyric.Core;

namespace FloatingLyric.App;

/// <summary>
/// Three faces, because they are three different moments: a first run should
/// meet a button, not a walkthrough for registering a Spotify app.
/// </summary>
public sealed class LoginWindow : Window
{
    private readonly TextBox _clientId = new();
    private readonly StackPanel _clientIdRow = new();

    public LoginPrompt Prompt { get; }

    public LoginWindow(LoginPrompt prompt, string? currentClientId, Action<string> onSave)
    {
        Prompt = prompt;
        Title = prompt == LoginPrompt.Setup ? "Set up FloatingLyric" : "Log in to Spotify";
        Width = 520;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        CanResize = false;

        var stack = new StackPanel { Spacing = 14, Margin = new Avalonia.Thickness(20) };

        stack.Children.Add(new TextBlock
        {
            Text = prompt switch
            {
                LoginPrompt.Setup => "Connect your Spotify account",
                LoginPrompt.Welcome => "Welcome to FloatingLyric",
                _ => "You're logged out",
            },
            FontSize = 20,
            FontWeight = FontWeight.Bold,
        });

        stack.Children.Add(new TextBlock
        {
            Text = prompt switch
            {
                LoginPrompt.Setup =>
                    "1. Open developer.spotify.com/dashboard and click Create app.\n" +
                    "2. Name it anything, e.g. FloatingLyric.\n" +
                    "3. Add this Redirect URI exactly:\n" +
                    "       http://127.0.0.1:8888/callback\n" +
                    "4. Tick \"Web API\", save, then copy the Client ID below.",
                LoginPrompt.Welcome =>
                    "Log in with your Spotify account and lyrics will follow whatever you " +
                    "play — on this PC, your phone, or a speaker. Your browser opens " +
                    "Spotify's own page; your password never passes through FloatingLyric.",
                _ => "Log in again to start following what you're playing. Your browser " +
                     "opens Spotify's page — sign in and click Agree.",
            },
            TextWrapping = TextWrapping.Wrap,
            Foreground = Brushes.Gray,
        });

        _clientId.Text = currentClientId ?? "";
        _clientId.Watermark = "Client ID";
        _clientId.FontFamily = new FontFamily("Consolas, monospace");
        _clientIdRow.Children.Add(_clientId);
        _clientIdRow.IsVisible = prompt == LoginPrompt.Setup;
        stack.Children.Add(_clientIdRow);

        var useOwn = new Button
        {
            Content = "Use a different Client ID…",
            Background = Brushes.Transparent,
            BorderThickness = new Avalonia.Thickness(0),
            IsVisible = prompt != LoginPrompt.Setup,
        };
        useOwn.Click += (_, _) => { _clientIdRow.IsVisible = true; useOwn.IsVisible = false; };
        stack.Children.Add(useOwn);

        var logIn = new Button
        {
            Content = prompt == LoginPrompt.Setup ? "Save and Log In" : "Log In with Spotify",
            HorizontalAlignment = HorizontalAlignment.Right,
            IsDefault = true,
        };
        logIn.Click += (_, _) =>
        {
            onSave(_clientId.Text?.Trim() ?? "");
            Close();
        };
        stack.Children.Add(logIn);

        Content = stack;
    }
}
