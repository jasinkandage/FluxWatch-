# FluxWatch Dockerfile for Linux/Unraid
# Version: 1.0.1

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project file and restore dependencies
COPY *.csproj ./
RUN dotnet restore

# Copy source files and build
COPY *.cs ./
RUN dotnet publish -c Release -o /app --self-contained false

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0-jammy
WORKDIR /app

# Install additional dependencies for system monitoring
RUN apt-get update && apt-get install -y \
    procps \
    lsof \
    net-tools \
    iproute2 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy published app
COPY --from=build /app .

# Create directories for logs and data
RUN mkdir -p /var/log/fluxwatch /app/data /app/config

# Set environment variables
ENV ASPNETCORE_URLS=http://+:8080
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:8080/health || exit 1

# Run the application
ENTRYPOINT ["dotnet", "FluxWatch.dll"]
