namespace Api;

public class TodoItem
{
    public int Id { get; set; }
    public required string Title { get; set; }
    public bool IsDone { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

// Validation rules live in a plain static class (no web dependencies),
// which keeps them easy to unit test.
public static class TodoRules
{
    public static bool IsValidTitle(string? title) =>
        !string.IsNullOrWhiteSpace(title) && title.Trim().Length <= 200;
}
