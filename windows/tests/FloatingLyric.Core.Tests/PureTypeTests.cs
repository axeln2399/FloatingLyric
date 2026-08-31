using FloatingLyric.Core;
using Xunit;

namespace FloatingLyric.Core.Tests;

public class LrcParserTests
{
    [Fact]
    public void ParsesMinutesSecondsAndHundredths()
    {
        var lines = LrcParser.Parse("[00:12.34]Hello");
        Assert.Single(lines);
        Assert.Equal(12_340, lines[0].TimeMs);
        Assert.Equal("Hello", lines[0].Text);
    }

    [Theory]
    [InlineData("[00:01.5]x", 1_500)]
    [InlineData("[00:01.50]x", 1_500)]
    [InlineData("[00:01.500]x", 1_500)]
    [InlineData("[00:01]x", 1_000)]
    [InlineData("[00:01:50]x", 1_500)]
    public void FractionsAreLeftAligned(string raw, int expected) =>
        Assert.Equal(expected, LrcParser.Parse(raw)[0].TimeMs);

    [Fact]
    public void OneLineMayCarrySeveralTimestamps()
    {
        var lines = LrcParser.Parse("[00:10.00][00:20.00]Chorus");
        Assert.Equal(2, lines.Count);
        Assert.All(lines, l => Assert.Equal("Chorus", l.Text));
        Assert.Equal([10_000, 20_000], lines.Select(l => l.TimeMs));
    }

    [Fact]
    public void OffsetTagShiftsEveryLineAndClampsAtZero()
    {
        var lines = LrcParser.Parse("[offset:+500]\n[00:10.00]a\n[00:00.10]b");
        Assert.Equal(10_500, lines.Single(l => l.Text == "a").TimeMs);
        Assert.Equal(600, lines.Single(l => l.Text == "b").TimeMs);

        var negative = LrcParser.Parse("[offset:-5000]\n[00:01.00]early");
        Assert.Equal(0, negative[0].TimeMs);
    }

    [Fact]
    public void MetadataAndUntimedLinesAreIgnored()
    {
        var lines = LrcParser.Parse("[ar:Artist]\n[ti:Title]\nplain text\n[00:05.00]real");
        Assert.Single(lines);
        Assert.Equal("real", lines[0].Text);
    }

    [Fact]
    public void OutOfOrderFilesAreSorted()
    {
        var lines = LrcParser.Parse("[00:30.00]third\n[00:10.00]first\n[00:20.00]second");
        Assert.Equal(["first", "second", "third"], lines.Select(l => l.Text));
    }

    [Fact]
    public void EmptyTextIsKeptAsAGap() =>
        Assert.Equal("", LrcParser.Parse("[00:10.00]")[0].Text);

    [Fact]
    public void HandlesWindowsLineEndings() =>
        Assert.Equal(2, LrcParser.Parse("[00:01.00]a\r\n[00:02.00]b").Count);
}

public class LyricsDocumentTests
{
    private static readonly LyricsDocument Doc = new([
        new LyricLine(0, "zero"), new LyricLine(10_000, "ten"), new LyricLine(20_000, "twenty"),
    ]);

    [Fact]
    public void FindsTheLastLineAtOrBeforeThePosition()
    {
        Assert.Equal(0, Doc.IndexAt(0, 0));
        Assert.Equal(0, Doc.IndexAt(9_999, 0));
        Assert.Equal(1, Doc.IndexAt(10_000, 0));
        Assert.Equal(2, Doc.IndexAt(999_999, 0));
    }

    [Fact]
    public void ReturnsNullBeforeTheFirstLine() => Assert.Null(Doc.IndexAt(-1, 0));

    [Fact]
    public void OffsetShiftsTheLookup()
    {
        Assert.Equal(1, Doc.IndexAt(9_000, 1_000));
        Assert.Null(Doc.IndexAt(500, -1_000));
    }

    [Fact]
    public void AnEmptyDocumentHasNoCurrentLine() =>
        Assert.Null(new LyricsDocument([]).IndexAt(1_000, 0));

    [Fact]
    public void EveryNonLatinLineGetsAReading()
    {
        var doc = new LyricsDocument([
            new LyricLine(0, "こんにちは"), new LyricLine(1_000, "hello there"),
        ]);
        Assert.NotNull(doc.RomanizationAt(0));
        Assert.Null(doc.RomanizationAt(1));
        Assert.True(doc.HasRomanizations);
    }

    [Fact]
    public void AnEnglishSongHasNoReadingsAtAll() =>
        Assert.False(new LyricsDocument([new LyricLine(0, "Blinding lights")]).HasRomanizations);

    [Fact]
    public void IndexesOutsideTheDocumentReturnNoReading()
    {
        var doc = new LyricsDocument([new LyricLine(0, "こんにちは")]);
        Assert.Null(doc.RomanizationAt(-1));
        Assert.Null(doc.RomanizationAt(99));
    }
}

public class PlayheadClockTests
{
    [Fact]
    public void ReportsZeroBeforeAnyAnchor() =>
        Assert.Equal(0, new PlayheadClock().PositionMs(100));

    [Fact]
    public void ExtrapolatesWhilePlaying()
    {
        var clock = new PlayheadClock();
        clock.Anchor(10_000, true, 100);
        Assert.Equal(10_000, clock.PositionMs(100));
        Assert.Equal(12_500, clock.PositionMs(102.5));
    }

    [Fact]
    public void FreezesWhilePaused()
    {
        var clock = new PlayheadClock();
        clock.Anchor(10_000, false, 100);
        Assert.Equal(10_000, clock.PositionMs(200));
    }

    [Fact]
    public void NeverGoesNegative()
    {
        var clock = new PlayheadClock();
        clock.Anchor(-5_000, true, 100);
        Assert.Equal(0, clock.PositionMs(100));
    }

    [Fact]
    public void DriftIsNotASeekButAJumpIs()
    {
        var clock = new PlayheadClock();
        clock.Anchor(10_000, true, 100);
        Assert.False(clock.IsSeek(11_200, 101));   // 200 ms of drift
        Assert.True(clock.IsSeek(60_000, 101));    // the user dragged
    }

    [Fact]
    public void NothingIsASeekBeforeTheFirstAnchor() =>
        Assert.False(new PlayheadClock().IsSeek(50_000, 100));
}

public class ChromeVisibilityTests
{
    [Fact]
    public void TimeoutIsThreeSeconds() => Assert.Equal(3.0, ChromeVisibility.IdleTimeoutSeconds);

    [Fact]
    public void VisibleImmediatelyAfterActivity() =>
        Assert.True(ChromeVisibility.IsVisible(100, 100, false));

    [Fact]
    public void StaysVisibleJustBeforeTheTimeout() =>
        Assert.True(ChromeVisibility.IsVisible(102.9, 100, false));

    [Fact]
    public void HidesOnceTheTimeoutIsReached()
    {
        Assert.False(ChromeVisibility.IsVisible(103.0, 100, false));
        Assert.False(ChromeVisibility.IsVisible(999, 100, false));
    }

    [Fact]
    public void HoveringKeepsItVisibleIndefinitely() =>
        Assert.True(ChromeVisibility.IsVisible(999, 100, true));

    [Fact]
    public void ClockGoingBackwardsDoesNotHideIt() =>
        Assert.True(ChromeVisibility.IsVisible(90, 100, false));
}

public class PanelOpacityTests
{
    [Fact]
    public void TheRangeIsTheWholeZeroToOneHundredPercent()
    {
        Assert.Equal(0, PanelOpacity.MinimumPercent);
        Assert.Equal(100, PanelOpacity.MaximumPercent);
        Assert.Equal(60, PanelOpacity.DefaultPercent);
    }

    [Theory]
    [InlineData(-40, 0)]
    [InlineData(0, 0)]
    [InlineData(73, 73)]
    [InlineData(101, 100)]
    [InlineData(999, 100)]
    public void ValuesOutsideTheRangeAreClamped(int input, int expected) =>
        Assert.Equal(expected, PanelOpacity.Clamped(input));

    [Fact]
    public void HoveringLiftsAnInvisibleWindowBackIntoView()
    {
        Assert.Equal(0.0, PanelOpacity.Alpha(0, false), 4);
        Assert.Equal(PanelOpacity.HoverFloorPercent / 100.0, PanelOpacity.Alpha(0, true), 4);
    }

    [Theory]
    [InlineData(40)]
    [InlineData(60)]
    [InlineData(100)]
    public void HoveringNeverMakesAWindowMoreTransparent(int percent) =>
        Assert.Equal(PanelOpacity.Alpha(percent), PanelOpacity.Alpha(percent, true), 4);

    [Fact]
    public void SteppingStopsAtBothEnds()
    {
        Assert.Equal(65, PanelOpacity.Stepped(60, 5));
        Assert.Equal(55, PanelOpacity.Stepped(60, -5));
        Assert.Equal(100, PanelOpacity.Stepped(98, 5));
        Assert.Equal(0, PanelOpacity.Stepped(2, -5));
    }
}

public class PanelToggleTests
{
    [Fact]
    public void MinimizedIsCheckedBeforeVisible()
    {
        Assert.Equal(PanelAction.Restore, PanelToggle.Action(true, true));
        Assert.Equal(PanelAction.Hide, PanelToggle.Action(false, true));
        Assert.Equal(PanelAction.Show, PanelToggle.Action(false, false));
    }
}

public class LoginPromptTests
{
    [Fact]
    public void AFirstRunWithABuiltInClientIdIsJustAButton() =>
        Assert.Equal(LoginPrompt.Welcome, LoginPrompts.Required("CID", false, false));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void TheWalkthroughOnlyAppearsWithNoClientIdAtAll(string? clientId) =>
        Assert.Equal(LoginPrompt.Setup, LoginPrompts.Required(clientId, false, false));

    [Fact]
    public void SigningOutAfterSigningInAsksToLogBackIn() =>
        Assert.Equal(LoginPrompt.LogIn, LoginPrompts.Required("CID", false, true));

    [Fact]
    public void ALoggedInSessionIsNeverInterrupted() =>
        Assert.Null(LoginPrompts.Required("CID", true, true));

    [Fact]
    public void SetupWinsOverAStoredSessionWithNoClientId() =>
        Assert.Equal(LoginPrompt.Setup, LoginPrompts.Required(null, true, true));

    [Fact]
    public void TheAppShipsWithAClientId()
    {
        Assert.True(AppCredentials.HasBuiltInClientId);
        Assert.Equal(32, AppCredentials.BuiltInClientId.Length);
    }
}

public class SpotifyCallbackTests
{
    private static SpotifyCallback.Result Read(string url, string state = "ST") =>
        SpotifyCallback.Code(new Uri(url), state);

    [Fact]
    public void ReadsTheCodeWhenTheStateMatches() =>
        Assert.Equal("ABC123", Read("http://127.0.0.1:8888/callback?code=ABC123&state=ST").Value);

    [Fact]
    public void RejectsAStateFromSomewhereElse() =>
        Assert.IsType<AppError.AuthStateMismatch>(
            Read("http://127.0.0.1:8888/callback?code=ABC&state=OTHER").Error);

    [Fact]
    public void RejectsAResponseCarryingNoStateAtAll() =>
        Assert.IsType<AppError.AuthStateMismatch>(
            Read("http://127.0.0.1:8888/callback?code=ABC").Error);

    [Fact]
    public void UserRefusalIsReportedAsCancelled() =>
        Assert.IsType<AppError.AuthCancelled>(
            Read("http://127.0.0.1:8888/callback?error=access_denied&state=ST").Error);

    /// <summary>An error wins: Spotify sends no code with one, so reading the
    /// state first would report the wrong reason.</summary>
    [Fact]
    public void AnErrorWinsOverAMismatchedState() =>
        Assert.IsType<AppError.AuthCancelled>(
            Read("http://127.0.0.1:8888/callback?error=access_denied&state=OTHER").Error);

    [Fact]
    public void AnEmptyCodeIsNotACode() =>
        Assert.IsType<AppError.AuthCancelled>(
            Read("http://127.0.0.1:8888/callback?code=&state=ST").Error);

    [Fact]
    public void PercentEncodedValuesAreDecoded() =>
        Assert.Equal("A/B+C", Read("http://127.0.0.1:8888/callback?code=A%2FB%2BC&state=ST").Value);

    [Fact]
    public void PortsAreTriedInOrder()
    {
        Assert.Equal([8888, 8889, 8890], SpotifyCallback.CandidatePorts);
        Assert.Equal("http://127.0.0.1:8888/callback", SpotifyCallback.RedirectUri(8888));
    }
}

public class PkceTests
{
    [Fact]
    public void VerifierAndChallengeDifferAndAreUrlSafe()
    {
        var pair = Pkce.Generate();
        Assert.NotEqual(pair.Verifier, pair.Challenge);
        Assert.DoesNotContain('+', pair.Challenge);
        Assert.DoesNotContain('/', pair.Challenge);
        Assert.DoesNotContain('=', pair.Challenge);
        Assert.InRange(pair.Verifier.Length, 43, 128);   // RFC 7636
    }

    [Fact]
    public void EveryLoginGetsItsOwnVerifier() =>
        Assert.NotEqual(Pkce.Generate().Verifier, Pkce.Generate().Verifier);

    [Fact]
    public void StatesAreUnique() => Assert.NotEqual(Pkce.RandomState(), Pkce.RandomState());
}
