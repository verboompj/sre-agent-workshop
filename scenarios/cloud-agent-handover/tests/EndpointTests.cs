using System.Net;
using System.Net.Http.Json;

namespace HandoverApp.Tests;

public sealed class EndpointTests(HandoverAppFactory factory)
    : IClassFixture<HandoverAppFactory>
{
    private readonly HttpClient client = factory.CreateClient();

    [Fact]
    public async Task Health_returns_ok()
    {
        var response = await client.GetAsync("/health");
        var payload = await response.Content.ReadFromJsonAsync<HealthResponse>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("healthy", payload?.Status);
    }

    [Fact]
    public async Task Feature_returns_completed_response()
    {
        var response = await client.PostAsync("/api/feature", content: null);
        var payload = await response.Content.ReadFromJsonAsync<FeatureResponse>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(
            new FeatureResponse(
                "completed",
                "The unfinished feature is now implemented."),
            payload);
    }

    [Fact]
    public async Task Home_renders_the_handover_button()
    {
        var html = await client.GetStringAsync("/");

        Assert.Contains("Run unfinished feature", html);
        Assert.Contains("SRE Agent to Copilot", html);
    }

    private sealed record HealthResponse(string Status);
    private sealed record FeatureResponse(string Status, string Message);
}
