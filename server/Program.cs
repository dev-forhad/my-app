using Api;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// Connection string precedence:
//   1. Environment variable ConnectionStrings__DefaultConnection (set by docker-compose in production)
//   2. appsettings.json (local development)
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
    ?? "Host=localhost;Port=5432;Database=appdb;Username=app;Password=devpassword";

builder.Services.AddDbContext<AppDb>(options => options.UseNpgsql(connectionString));

var app = builder.Build();

// EnsureCreated creates the schema when the database is empty but never
// evolves an existing one — so table changes ship as explicit idempotent SQL
// here. Acceptable for a demo app; a production pipeline would apply EF Core
// migrations as a deploy step instead.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDb>();
    db.Database.EnsureCreated();
    db.Database.ExecuteSqlRaw(
        "DROP TABLE IF EXISTS \"Todos\";" +
        "CREATE TABLE IF NOT EXISTS \"Contacts\" (" +
        "  \"Id\" serial PRIMARY KEY," +
        "  \"Name\" text NOT NULL," +
        "  \"Email\" text NOT NULL," +
        "  \"Message\" text NOT NULL," +
        "  \"CreatedAtUtc\" timestamp NOT NULL)");
}

// Status endpoint — a simple target for health checks and smoke tests.
app.MapGet("/", () => Results.Json(new
{
    status = "ok",
    service = "my-app-api",
    timeUtc = DateTime.UtcNow
}));

// Contact form endpoints. POST is what the portfolio's contact form calls;
// GET lists received messages (note: publicly readable for now — locking it
// down behind auth is a documented upgrade path in the README).
app.MapGet("/api/contact", async (AppDb db) =>
    await db.Contacts.OrderByDescending(c => c.CreatedAtUtc).ToListAsync());

app.MapPost("/api/contact", async (ContactDto dto, AppDb db) =>
{
    if (!ContactRules.IsValidName(dto.Name))
        return Results.BadRequest(new { error = "Name is required (max 100 characters)." });
    if (!ContactRules.IsValidEmail(dto.Email))
        return Results.BadRequest(new { error = "A valid email is required." });
    if (!ContactRules.IsValidMessage(dto.Message))
        return Results.BadRequest(new { error = "Message is required (max 2000 characters)." });

    var contact = new ContactMessage
    {
        Name = dto.Name.Trim(),
        Email = dto.Email.Trim(),
        Message = dto.Message.Trim(),
    };
    db.Contacts.Add(contact);
    await db.SaveChangesAsync();
    return Results.Created($"/api/contact/{contact.Id}", contact);
});

app.Run();

public class AppDb(DbContextOptions<AppDb> options) : DbContext(options)
{
    public DbSet<ContactMessage> Contacts => Set<ContactMessage>();
}

public record ContactDto(string Name, string Email, string Message);
