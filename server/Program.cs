using Api;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

// Connection string precedence:
//   1. Environment variable ConnectionStrings__DefaultConnection (set by docker-compose in production)
//   2. appsettings.json (local development)
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
    ?? "Host=localhost;Port=5432;Database=appdb;Username=app;Password=devpassword";

// Admin credentials + JWT signing key come from the environment in production
// (Elastic Beanstalk properties). The fallbacks below exist ONLY for local dev.
var adminUsername = builder.Configuration["ADMIN_USERNAME"] ?? "admin";
var adminPassword = builder.Configuration["ADMIN_PASSWORD"] ?? "admin123";
var jwtKey = builder.Configuration["Jwt:Key"] ?? "dev-only-signing-key-not-used-in-production";
var jwtIssuer = "my-app-api";

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtIssuer,
            ValidateAudience = true,
            ValidAudience = jwtIssuer,
            ValidateLifetime = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
        };
    });
builder.Services.AddAuthorization();

// Rate limiting: fixed windows partitioned by client IP.
//   login        — 5 attempts/minute  (brute-force shield)
//   public-write — 20 posts/minute    (spam shield on the contact form)
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("login", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 5, Window = TimeSpan.FromMinutes(1) }));
    options.AddPolicy("public-write", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 20, Window = TimeSpan.FromMinutes(1) }));
});

// Swagger/OpenAPI — interactive docs at /swagger. The security definition
// adds an "Authorize" button to the UI: paste a JWT from /api/auth/login and
// you can call the protected inbox endpoints right from the browser.
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Portfolio API",
        Version = "v1",
        Description = "Public contact form + JWT-protected admin inbox. " +
                      "POST /api/auth/login to get a token, then Authorize.",
    });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Paste the JWT returned by POST /api/auth/login",
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            },
            Array.Empty<string>()
        }
    });
});

builder.Services.AddDbContext<AppDb>(options => options.UseNpgsql(connectionString));

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

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

// Swagger UI — interactive documentation.
app.UseSwagger();
app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "Portfolio API v1"));

// Login: exchange admin credentials for a short-lived JWT. The credentials
// themselves never leave the server; the client only receives a signed token.
// Rate-limited to 5 attempts/minute per IP.
app.MapPost("/api/auth/login", (LoginDto dto) =>
{
    if (dto.Username != adminUsername || dto.Password != adminPassword)
        return Results.Unauthorized();

    var claims = new[]
    {
        new Claim(ClaimTypes.Name, dto.Username),
        new Claim(ClaimTypes.Role, "admin"),
    };
    var token = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
    {
        Subject = new ClaimsIdentity(claims),
        Issuer = jwtIssuer,
        Audience = jwtIssuer,
        Expires = DateTime.UtcNow.AddHours(8),
        SigningCredentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            SecurityAlgorithms.HmacSha256),
    });
    return Results.Ok(new { token });
})
.RequireRateLimiting("login");

// Who am I? lets the admin page verify a stored token is still valid.
app.MapGet("/api/auth/me", (ClaimsPrincipal user) =>
    Results.Ok(new { user = user.Identity?.Name ?? "unknown" }))
    .RequireAuthorization();

// Contact form: anyone may SUBMIT a message (public form), but only a valid
// admin token may READ the inbox.
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
})
.RequireRateLimiting("public-write");

app.MapGet("/api/contact", async (AppDb db) =>
    await db.Contacts.OrderByDescending(c => c.CreatedAtUtc).ToListAsync())
    .RequireAuthorization();

app.Run();

public class AppDb(DbContextOptions<AppDb> options) : DbContext(options)
{
    public DbSet<ContactMessage> Contacts => Set<ContactMessage>();
}

public record ContactDto(string Name, string Email, string Message);
public record LoginDto(string Username, string Password);
