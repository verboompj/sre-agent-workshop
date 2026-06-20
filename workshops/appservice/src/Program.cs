using Microsoft.Data.SqlClient;
using Shop.Models;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();

var app = builder.Build();

var connectionString = Environment.GetEnvironmentVariable("AZURE_SQL_CONNECTIONSTRING") ?? "";

// Health check — intentionally does NOT verify DB connectivity (liveness only)
app.MapGet("/health", () => Results.Json(new { status = "healthy", timestamp = DateTime.UtcNow }));

// Landing page — shows SQL connectivity status
app.MapGet("/", async () =>
{
    string status;
    if (string.IsNullOrEmpty(connectionString))
    {
        status = "not configured (AZURE_SQL_CONNECTIONSTRING not set)";
    }
    else
    {
        try
        {
            await using var conn = new SqlConnection(connectionString);
            await conn.OpenAsync();
            status = "connected";
        }
        catch (Exception ex)
        {
            status = $"disconnected — {ex.Message}";
        }
    }

    var html = $"""
        <!DOCTYPE html>
        <html>
        <head><title>SRE Agent Workshop — Shop</title></head>
        <body>
          <h1>SRE Agent Workshop — Shop</h1>
          <table>
            <tr><td><strong>Azure SQL Status</strong></td><td>{status}</td></tr>
          </table>
        </body>
        </html>
        """;
    return Results.Content(html, "text/html");
});

// Catalog — reads Products from Azure SQL via the managed identity
app.MapGet("/products", async (ILogger<Program> logger) =>
{
    if (string.IsNullOrEmpty(connectionString))
    {
        return Results.Json(new { error = "AZURE_SQL_CONNECTIONSTRING is not set" }, statusCode: 500);
    }

    try
    {
        var products = new List<Product>();
        await using var conn = new SqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new SqlCommand("SELECT Id, Name, Price FROM dbo.Products ORDER BY Id", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            products.Add(new Product(reader.GetInt32(0), reader.GetString(1), reader.GetDecimal(2)));
        }
        return Results.Json(products);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to read products from Azure SQL");
        return Results.Json(new { error = $"Failed to connect to Azure SQL: {ex.Message}" }, statusCode: 500);
    }
});

app.Run();
