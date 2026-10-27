namespace Api;

public class ContactMessage
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public required string Email { get; set; }
    public required string Message { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

// Validation rules live in a plain static class (no web dependencies),
// which keeps them easy to unit test.
public static class ContactRules
{
    public static bool IsValidName(string? name) =>
        !string.IsNullOrWhiteSpace(name) && name.Trim().Length <= 100;

    public static bool IsValidEmail(string? email) =>
        !string.IsNullOrWhiteSpace(email)
        && email.Trim().Length <= 200
        && email.Contains('@')
        && email.Trim().EndsWith(".", StringComparison.Ordinal) == false
        && email.Trim().Contains(' ') == false;

    public static bool IsValidMessage(string? message) =>
        !string.IsNullOrWhiteSpace(message) && message.Trim().Length <= 2000;
}
