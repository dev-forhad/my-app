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

// Create the schema on startup. Acceptable for a demo app; in a production
// pipeline you would apply EF Core migrations as an explicit deploy step instead.
using (var scope = app.Services.CreateScope())
{
    scope.ServiceProvider.GetRequiredService<AppDb>().Database.EnsureCreated();
}

// Status endpoint — a simple target for health checks and smoke tests.
app.MapGet("/", () => Results.Json(new
{
    status = "ok",
    service = "my-app-api",
    timeUtc = DateTime.UtcNow
}));

// A tiny CRUD API over PostgreSQL.
app.MapGet("/api/items", async (AppDb db) =>
    await db.Todos.OrderByDescending(t => t.CreatedAtUtc).ToListAsync());

app.MapPost("/api/items", async (TodoItemDto dto, AppDb db) =>
{
    if (!TodoRules.IsValidTitle(dto.Title))
        return Results.BadRequest(new { error = "Title is required (max 200 characters)." });

    var todo = new TodoItem { Title = dto.Title.Trim() };
    db.Todos.Add(todo);
    await db.SaveChangesAsync();
    return Results.Created($"/api/items/{todo.Id}", todo);
});

app.MapPost("/api/items/{id}/toggle", async (int id, AppDb db) =>
{
    var todo = await db.Todos.FindAsync(id);
    if (todo is null) return Results.NotFound();
    todo.IsDone = !todo.IsDone;
    await db.SaveChangesAsync();
    return Results.Ok(todo);
});

app.MapDelete("/api/items/{id}", async (int id, AppDb db) =>
{
    var todo = await db.Todos.FindAsync(id);
    if (todo is null) return Results.NotFound();
    db.Todos.Remove(todo);
    await db.SaveChangesAsync();
    return Results.NoContent();
});

app.Run();

public class AppDb(DbContextOptions<AppDb> options) : DbContext(options)
{
    public DbSet<TodoItem> Todos => Set<TodoItem>();
}

public record TodoItemDto(string Title);
