# syntax=docker/dockerfile:1
# Multi-stage build: compile with the SDK image, ship only binaries in a small
# runtime image. To move to .NET 10 later, change DOTNET_VERSION to 10.0 —
# that is the only edit needed.
ARG DOTNET_VERSION=8.0

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION}-alpine AS build
WORKDIR /src

# Restore dependencies as their own layer so Docker's layer cache skips the
# NuGet download on every code change.
COPY Api.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-alpine AS final
WORKDIR /app
COPY --from=build /app .

# .NET 8+ runtime images ship a built-in unprivileged user 'app' (uid 1654).
USER app

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# Docker-level health check used by orchestration tools.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/ >/dev/null || exit 1

ENTRYPOINT ["dotnet", "Api.dll"]
