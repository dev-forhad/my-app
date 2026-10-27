using Api;
using Xunit;

namespace Api.Tests;

public class ContactRulesTests
{
    [Theory]
    [InlineData("Forhad", true)]
    [InlineData("  ", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void IsValidName_ChecksBasics(string? name, bool expected)
    {
        Assert.Equal(expected, ContactRules.IsValidName(name));
    }

    [Theory]
    [InlineData("me@example.com", true)]
    [InlineData("missing-at.com", false)]
    [InlineData("has space@x.com", false)]
    [InlineData("user@x.com.", false)]
    [InlineData(null, false)]
    [InlineData("", false)]
    public void IsValidEmail_ChecksBasics(string? email, bool expected)
    {
        Assert.Equal(expected, ContactRules.IsValidEmail(email));
    }

    [Theory]
    [InlineData("hello there", true)]
    [InlineData("   ", false)]
    [InlineData(null, false)]
    public void IsValidMessage_ChecksBasics(string? message, bool expected)
    {
        Assert.Equal(expected, ContactRules.IsValidMessage(message));
    }

    [Fact]
    public void Limits_AreEnforced()
    {
        Assert.False(ContactRules.IsValidName(new string('a', 101)));
        Assert.False(ContactRules.IsValidMessage(new string('a', 2001)));
    }
}
