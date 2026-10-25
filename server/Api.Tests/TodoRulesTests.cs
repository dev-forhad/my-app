using Api;
using Xunit;

namespace Api.Tests;

public class TodoRulesTests
{
    [Theory]
    [InlineData("buy milk", true)]
    [InlineData("  ", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    [InlineData("x", true)]
    public void IsValidTitle_ChecksBasicRules(string? title, bool expected)
    {
        Assert.Equal(expected, TodoRules.IsValidTitle(title));
    }

    [Fact]
    public void IsValidTitle_RejectsTitlesLongerThan200Characters()
    {
        var tooLong = new string('a', 201);
        Assert.False(TodoRules.IsValidTitle(tooLong));
        Assert.True(TodoRules.IsValidTitle(tooLong[..200]));
    }
}
