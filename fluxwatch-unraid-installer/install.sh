#!/bin/bash
#===============================================================================
#  FluxWatch Unraid Installer
#  Version: 1.0.1
#  
#  This script installs FluxWatch on Unraid with full cleanup of previous
#  installations, Docker container management, and automatic startup.
#
#  Usage: 
#    Local:  ./install.sh
#    Remote: curl -sSL https://raw.githubusercontent.com/YOUR_REPO/main/install.sh | bash
#
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
FLUXWATCH_VERSION="1.0.1"
CONTAINER_NAME="fluxwatch"
IMAGE_NAME="fluxwatch"
SHARE_NAME="fluxwatch"
SHARE_PATH="/mnt/user/${SHARE_NAME}"
APP_PORT=8080
LOG_FILE="/var/log/fluxwatch-install.log"

# GitHub repository (update this with your actual repo)
GITHUB_REPO="YOUR_USERNAME/fluxwatch-unraid"
GITHUB_BRANCH="main"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"

#===============================================================================
# Helper Functions
#===============================================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} - $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║     ███████╗██╗     ██╗   ██╗██╗  ██╗██╗    ██╗ █████╗ ████████╗ ║"
    echo "║     ██╔════╝██║     ██║   ██║╚██╗██╔╝██║    ██║██╔══██╗╚══██╔══╝ ║"
    echo "║     █████╗  ██║     ██║   ██║ ╚███╔╝ ██║ █╗ ██║███████║   ██║    ║"
    echo "║     ██╔══╝  ██║     ██║   ██║ ██╔██╗ ██║███╗██║██╔══██║   ██║    ║"
    echo "║     ██║     ███████╗╚██████╔╝██╔╝ ██╗╚███╔███╔╝██║  ██║   ██║    ║"
    echo "║     ╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝    ║"
    echo "║                                                                  ║"
    echo "║                    Unraid Installer v${FLUXWATCH_VERSION}                      ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}[STEP $1]${NC} $2"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "[STEP $1] $2"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log "ERROR: $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
    log "INFO: $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

check_unraid() {
    if [ ! -f /etc/unraid-version ]; then
        print_warning "This doesn't appear to be an Unraid system"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        UNRAID_VERSION=$(cat /etc/unraid-version)
        print_info "Detected Unraid version: $UNRAID_VERSION"
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    
    print_success "Docker is available"
}

#===============================================================================
# Step 1: Check for existing FluxWatch installations
#===============================================================================

check_existing_installations() {
    print_step "1/7" "Checking for existing FluxWatch installations"
    
    local found_existing=false
    
    # Check for running containers
    if docker ps -a --format '{{.Names}}' | grep -qi "fluxwatch\|devicemonitor"; then
        print_warning "Found existing FluxWatch/DeviceMonitor containers"
        found_existing=true
    fi
    
    # Check for existing share
    if [ -d "$SHARE_PATH" ]; then
        print_warning "Found existing FluxWatch share at $SHARE_PATH"
        found_existing=true
    fi
    
    # Check for processes using port 8080
    if netstat -tlnp 2>/dev/null | grep -q ":${APP_PORT}"; then
        print_warning "Port ${APP_PORT} is currently in use"
        found_existing=true
    fi
    
    # Check alternative paths
    for alt_path in "/mnt/user/appdata/fluxwatch" "/mnt/cache/appdata/fluxwatch"; do
        if [ -d "$alt_path" ]; then
            print_warning "Found FluxWatch data at $alt_path"
            found_existing=true
        fi
    done
    
    if [ "$found_existing" = true ]; then
        print_info "Existing installation(s) detected - will clean up"
    else
        print_success "No existing installations found"
    fi
}

#===============================================================================
# Step 2: Stop and remove existing FluxWatch containers
#===============================================================================

remove_existing_containers() {
    print_step "2/7" "Stopping and removing existing FluxWatch containers"
    
    # Find all FluxWatch/DeviceMonitor related containers
    local containers=$(docker ps -a --format '{{.Names}}' | grep -Ei "fluxwatch|devicemonitor" || true)
    
    if [ -n "$containers" ]; then
        for container in $containers; do
            print_info "Stopping container: $container"
            docker stop "$container" 2>/dev/null || true
            
            print_info "Removing container: $container"
            docker rm -f "$container" 2>/dev/null || true
            
            print_success "Removed container: $container"
        done
    else
        print_info "No FluxWatch containers found"
    fi
    
    # Also check for containers by port
    local port_container=$(docker ps -a --filter "publish=${APP_PORT}" --format '{{.Names}}' | head -1)
    if [ -n "$port_container" ]; then
        print_warning "Found container using port ${APP_PORT}: $port_container"
        print_info "Stopping and removing..."
        docker stop "$port_container" 2>/dev/null || true
        docker rm -f "$port_container" 2>/dev/null || true
        print_success "Removed container using port ${APP_PORT}"
    fi
    
    # Remove old images
    local images=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -Ei "fluxwatch|devicemonitor" || true)
    if [ -n "$images" ]; then
        for image in $images; do
            print_info "Removing old image: $image"
            docker rmi -f "$image" 2>/dev/null || true
        done
        print_success "Removed old FluxWatch images"
    fi
}

#===============================================================================
# Step 3: Kill any processes using port 8080
#===============================================================================

kill_port_processes() {
    print_step "3/7" "Checking and freeing port ${APP_PORT}"
    
    # Check what's using the port
    local pid=$(lsof -ti:${APP_PORT} 2>/dev/null || true)
    
    if [ -n "$pid" ]; then
        print_warning "Found process(es) using port ${APP_PORT}: $pid"
        
        for p in $pid; do
            local proc_name=$(ps -p $p -o comm= 2>/dev/null || echo "unknown")
            print_info "Killing process $p ($proc_name)"
            kill -9 $p 2>/dev/null || true
        done
        
        sleep 2
        
        # Verify port is free
        if lsof -ti:${APP_PORT} &>/dev/null; then
            print_error "Failed to free port ${APP_PORT}"
            exit 1
        fi
        
        print_success "Port ${APP_PORT} is now free"
    else
        print_success "Port ${APP_PORT} is already free"
    fi
}

#===============================================================================
# Step 4: Remove old FluxWatch share and files
#===============================================================================

remove_old_files() {
    print_step "4/7" "Removing old FluxWatch files and shares"
    
    local paths_to_remove=(
        "$SHARE_PATH"
        "/mnt/user/appdata/fluxwatch"
        "/mnt/cache/appdata/fluxwatch"
        "/boot/config/plugins/fluxwatch"
        "/var/log/fluxwatch"
    )
    
    for path in "${paths_to_remove[@]}"; do
        if [ -d "$path" ] || [ -f "$path" ]; then
            print_info "Removing: $path"
            rm -rf "$path" 2>/dev/null || true
            print_success "Removed: $path"
        fi
    done
    
    # Remove any FluxWatch autostart entries
    if [ -f "/boot/config/go" ]; then
        if grep -q "fluxwatch" /boot/config/go 2>/dev/null; then
            print_info "Removing FluxWatch entries from /boot/config/go"
            sed -i '/fluxwatch/Id' /boot/config/go 2>/dev/null || true
            print_success "Cleaned up autostart entries"
        fi
    fi
    
    print_success "Old files cleanup complete"
}

#===============================================================================
# Step 5: Create new FluxWatch share
#===============================================================================

create_share() {
    print_step "5/7" "Creating FluxWatch share and directories"
    
    # Create the share directory
    mkdir -p "$SHARE_PATH"
    mkdir -p "$SHARE_PATH/app"
    mkdir -p "$SHARE_PATH/data"
    mkdir -p "$SHARE_PATH/logs"
    mkdir -p "$SHARE_PATH/config"
    
    # Set permissions
    chmod -R 755 "$SHARE_PATH"
    
    print_success "Created share structure at $SHARE_PATH"
    
    # Create log directory
    mkdir -p /var/log/fluxwatch
    chmod 755 /var/log/fluxwatch
    
    print_success "Created log directory"
}

#===============================================================================
# Step 6: Download and deploy FluxWatch files
#===============================================================================

deploy_files() {
    print_step "6/7" "Deploying FluxWatch application files"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check if we're running from local files or need to download
    if [ -f "$script_dir/app/Dockerfile" ]; then
        print_info "Using local installation files"
        
        # Copy app files
        cp -r "$script_dir/app/"* "$SHARE_PATH/app/" 2>/dev/null || true
        
    else
        print_info "Downloading files from GitHub..."
        
        # Download files from GitHub
        local files=(
            "app/Dockerfile"
            "app/FluxWatch.csproj"
            "app/Program.cs"
            "app/ApiServer.cs"
            "app/DeviceInfo.cs"
        )
        
        for file in "${files[@]}"; do
            local url="${GITHUB_RAW_BASE}/${file}"
            local dest="${SHARE_PATH}/${file}"
            local dest_dir=$(dirname "$dest")
            
            mkdir -p "$dest_dir"
            
            print_info "Downloading: $file"
            if curl -sSL "$url" -o "$dest" 2>/dev/null; then
                print_success "Downloaded: $file"
            else
                print_warning "Failed to download: $file (will use embedded)"
            fi
        done
    fi
    
    # Create Dockerfile if not exists
    if [ ! -f "$SHARE_PATH/app/Dockerfile" ]; then
        print_info "Creating Dockerfile from embedded template"
        create_dockerfile
    fi
    
    # Create project file if not exists
    if [ ! -f "$SHARE_PATH/app/FluxWatch.csproj" ]; then
        print_info "Creating project file from embedded template"
        create_project_file
    fi
    
    # Create source files if not exists
    if [ ! -f "$SHARE_PATH/app/Program.cs" ]; then
        print_info "Creating source files from embedded templates"
        create_source_files
    fi
    
    print_success "Application files deployed"
}

#===============================================================================
# Create Dockerfile
#===============================================================================

create_dockerfile() {
    cat > "$SHARE_PATH/app/Dockerfile" << 'DOCKERFILE'
# FluxWatch Dockerfile for Linux/Unraid
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
    && rm -rf /var/lib/apt/lists/*

# Copy published app
COPY --from=build /app .

# Create directories for logs and data
RUN mkdir -p /var/log/fluxwatch /app/data

# Set environment variables
ENV ASPNETCORE_URLS=http://+:8080
ENV DOTNET_RUNNING_IN_CONTAINER=true

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the application
ENTRYPOINT ["dotnet", "FluxWatch.dll"]
DOCKERFILE
    
    print_success "Created Dockerfile"
}

#===============================================================================
# Create Project File
#===============================================================================

create_project_file() {
    cat > "$SHARE_PATH/app/FluxWatch.csproj" << 'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <RootNamespace>DeviceMonitor</RootNamespace>
    <AssemblyName>FluxWatch</AssemblyName>
    <Version>1.0.1</Version>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>disable</Nullable>
    <PublishSingleFile>false</PublishSingleFile>
    <SelfContained>false</SelfContained>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="System.Text.Json" Version="8.0.0" />
  </ItemGroup>
</Project>
CSPROJ
    
    print_success "Created FluxWatch.csproj"
}

#===============================================================================
# Create Source Files
#===============================================================================

create_source_files() {
    # Program.cs - Linux-optimized version
    cat > "$SHARE_PATH/app/Program.cs" << 'PROGRAMCS'
using System;
using System.IO;
using System.Threading;

namespace DeviceMonitor
{
    static class Program
    {
        private static ApiServer apiServer;
        private static string logPath = "/var/log/fluxwatch/startup.log";

        static void Main(string[] args)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath));
                Log($"\n========================================================");
                Log($"FluxWatch v1.0.1 starting on Linux/Unraid...");
                Log($"Arguments: {string.Join(" ", args)}");

                // Parse command line arguments
                foreach (var arg in args)
                {
                    if (arg.ToLower() == "/version")
                    {
                        Console.WriteLine("FluxWatch v1.0.1");
                        return;
                    }
                }

                RunLinux();
            }
            catch (Exception ex)
            {
                Log($"FATAL: {ex.Message}\n{ex.StackTrace}");
                Console.WriteLine($"FATAL ERROR: {ex.Message}");
            }
        }

        static void Log(string message)
        {
            try
            {
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss}] {message}\n");
                Console.WriteLine(message);
            }
            catch { }
        }

        static void RunLinux()
        {
            Log("Starting API Server...");
            apiServer = new ApiServer();
            
            try
            {
                apiServer.Start();
                Log("API Server started successfully");
            }
            catch (Exception ex)
            {
                Log($"API Server failed: {ex.Message}");
                return;
            }

            Log("FluxWatch running at http://localhost:8080");
            
            var exitEvent = new ManualResetEvent(false);
            
            Console.CancelKeyPress += (s, e) => 
            { 
                e.Cancel = true;
                Log("Shutdown signal received...");
                exitEvent.Set(); 
            };

            AppDomain.CurrentDomain.ProcessExit += (s, e) =>
            {
                Log("Process exit event received");
                apiServer?.Stop();
            };

            exitEvent.WaitOne();
            
            Log("Shutting down...");
            apiServer.Stop();
            Log("Exiting");
        }
    }
}
PROGRAMCS

    # ApiServer.cs - Linux-optimized version
    cat > "$SHARE_PATH/app/ApiServer.cs" << 'APISERVERCS'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace DeviceMonitor
{
    public class ApiServer
    {
        private HttpListener listener;
        private DeviceInfo deviceInfo;
        private bool running;
        private static readonly HttpClient httpClient = new HttpClient();
        private const string CENTRAL_SERVER = "https://fw.nrdy.me/register.php";
        private const string COMMAND_CHECK_URL = "https://fw.nrdy.me/check_command.php";
        private const string COMMAND_RESPONSE_URL = "https://fw.nrdy.me/command_response.php";
        private Timer registrationTimer;
        private Timer commandCheckTimer;
        private string deviceId;
        private string logPath = "/var/log/fluxwatch/apiserver.log";

        public ApiServer()
        {
            deviceInfo = new DeviceInfo();
            listener = new HttpListener();
            deviceId = GetDeviceId();

            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath));
            }
            catch { }
        }

        private void LogInfo(string message)
        {
            try
            {
                var line = $"[{DateTime.Now}] {message}";
                File.AppendAllText(logPath, line + "\n");
                Console.WriteLine(line);
            }
            catch { }
        }

        private void LogError(string message)
        {
            try
            {
                var line = $"[{DateTime.Now}] ERROR: {message}";
                File.AppendAllText(logPath, line + "\n");
                Console.WriteLine(line);
            }
            catch { }
        }

        private string GetDeviceId()
        {
            string hostname = Environment.MachineName;
            string macAddress = "";

            try
            {
                var nics = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces();
                var nic = nics.FirstOrDefault(n => 
                    n.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
                    && n.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback);
                if (nic != null)
                {
                    macAddress = nic.GetPhysicalAddress().ToString();
                }
            }
            catch { }

            return $"{hostname}_{macAddress}";
        }

        private async Task<string> GetPublicIP()
        {
            try
            {
                var response = await httpClient.GetStringAsync("https://api.ipify.org");
                return response.Trim();
            }
            catch
            {
                try
                {
                    var response = await httpClient.GetStringAsync("https://icanhazip.com");
                    return response.Trim();
                }
                catch { return "Unknown"; }
            }
        }

        private string GetLocalIPAddress()
        {
            try
            {
                var host = Dns.GetHostEntry(Dns.GetHostName());
                foreach (var ip in host.AddressList)
                {
                    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    {
                        return ip.ToString();
                    }
                }
            }
            catch { }
            return "127.0.0.1";
        }

        public void Start()
        {
            try
            {
                LogInfo("Starting API Server...");
                listener.Prefixes.Add("http://*:8080/");
                listener.Start();
                running = true;
                LogInfo("HttpListener started successfully");

                Thread listenerThread = new Thread(HandleRequests);
                listenerThread.IsBackground = true;
                listenerThread.Start();
                LogInfo("Request handler thread started");

                registrationTimer = new Timer(RegisterDevice, null, 0, 30000);
                LogInfo("Device registration timer started (30s interval)");

                commandCheckTimer = new Timer(CheckForCommands, null, 2000, 5000);
                LogInfo("Command check timer started (5s interval)");

                LogInfo($"API Server is running on http://localhost:8080");
                LogInfo($"Device ID: {deviceId}");
            }
            catch (Exception ex)
            {
                LogError($"Failed to start API Server: {ex.Message}");
                throw;
            }
        }

        private async void RegisterDevice(object state)
        {
            try
            {
                var info = deviceInfo.GetInfo();
                string publicIP = await GetPublicIP();
                string localIP = GetLocalIPAddress();
                long lastSeen = DateTimeOffset.Now.ToUnixTimeSeconds();

                var registrationData = new Dictionary<string, object>
                {
                    { "deviceId", deviceId },
                    { "hostname", Environment.MachineName },
                    { "publicIP", publicIP },
                    { "localIP", localIP },
                    { "lastSeen", lastSeen },
                    { "version", "1.0.1" },
                    { "platform", "Linux/Unraid" },
                    { "info", info }
                };

                var json = JsonSerializer.Serialize(registrationData);
                var content = new StringContent(json, Encoding.UTF8, "application/json");
                
                var response = await httpClient.PostAsync(CENTRAL_SERVER, content);
                if (response.IsSuccessStatusCode)
                {
                    LogInfo("Device registered successfully");
                }
            }
            catch (Exception ex)
            {
                LogError($"Registration failed: {ex.Message}");
            }
        }

        private async void CheckForCommands(object state)
        {
            try
            {
                var response = await httpClient.GetStringAsync($"{COMMAND_CHECK_URL}?deviceId={Uri.EscapeDataString(deviceId)}");
                if (!string.IsNullOrEmpty(response) && response != "null")
                {
                    LogInfo($"Received command: {response}");
                    await ProcessCommand(response);
                }
            }
            catch { }
        }

        private async Task ProcessCommand(string commandJson)
        {
            try
            {
                var command = JsonSerializer.Deserialize<Dictionary<string, object>>(commandJson);
                if (command == null) return;

                string commandId = command.ContainsKey("commandId") ? command["commandId"].ToString() : "";
                string action = command.ContainsKey("action") ? command["action"].ToString() : "";

                LogInfo($"Processing command: {action}");

                string result = "completed";
                string message = "";

                switch (action.ToLower())
                {
                    case "ping":
                        message = "pong";
                        break;
                    case "reboot":
                        message = "Reboot initiated";
                        Process.Start("reboot");
                        break;
                    case "shutdown":
                        message = "Shutdown initiated";
                        Process.Start("poweroff");
                        break;
                    default:
                        result = "unknown";
                        message = $"Unknown command: {action}";
                        break;
                }

                // Send response
                var responseData = new Dictionary<string, object>
                {
                    { "commandId", commandId },
                    { "deviceId", deviceId },
                    { "result", result },
                    { "message", message },
                    { "timestamp", DateTimeOffset.Now.ToUnixTimeSeconds() }
                };

                var json = JsonSerializer.Serialize(responseData);
                var content = new StringContent(json, Encoding.UTF8, "application/json");
                await httpClient.PostAsync(COMMAND_RESPONSE_URL, content);
            }
            catch (Exception ex)
            {
                LogError($"Command processing error: {ex.Message}");
            }
        }

        private void HandleRequests()
        {
            while (running)
            {
                try
                {
                    var context = listener.GetContext();
                    ThreadPool.QueueUserWorkItem(_ => ProcessRequest(context));
                }
                catch (Exception ex)
                {
                    if (running) LogError($"Request error: {ex.Message}");
                }
            }
        }

        private void ProcessRequest(HttpListenerContext context)
        {
            try
            {
                var request = context.Request;
                var response = context.Response;
                
                // Add CORS headers
                response.Headers.Add("Access-Control-Allow-Origin", "*");
                response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
                response.Headers.Add("Access-Control-Allow-Headers", "Content-Type");

                if (request.HttpMethod == "OPTIONS")
                {
                    response.StatusCode = 200;
                    response.Close();
                    return;
                }

                string path = request.Url.AbsolutePath.ToLower();
                string responseString = "";
                string contentType = "application/json";

                switch (path)
                {
                    case "/":
                    case "/health":
                        responseString = JsonSerializer.Serialize(new { status = "healthy", version = "1.0.1", platform = "Linux/Unraid" });
                        break;

                    case "/info":
                    case "/api/info":
                        var info = deviceInfo.GetInfo();
                        info["deviceId"] = deviceId;
                        info["version"] = "1.0.1";
                        responseString = JsonSerializer.Serialize(info);
                        break;

                    case "/api/status":
                        responseString = JsonSerializer.Serialize(new {
                            online = true,
                            deviceId = deviceId,
                            hostname = Environment.MachineName,
                            localIP = GetLocalIPAddress(),
                            uptime = GetUptime(),
                            version = "1.0.1"
                        });
                        break;

                    default:
                        response.StatusCode = 404;
                        responseString = JsonSerializer.Serialize(new { error = "Not found" });
                        break;
                }

                response.ContentType = contentType;
                byte[] buffer = Encoding.UTF8.GetBytes(responseString);
                response.ContentLength64 = buffer.Length;
                response.OutputStream.Write(buffer, 0, buffer.Length);
                response.Close();
            }
            catch (Exception ex)
            {
                LogError($"Process request error: {ex.Message}");
            }
        }

        private string GetUptime()
        {
            try
            {
                string uptime = File.ReadAllText("/proc/uptime").Split(' ')[0];
                double seconds = double.Parse(uptime);
                TimeSpan ts = TimeSpan.FromSeconds(seconds);
                return $"{(int)ts.TotalDays}d {ts.Hours}h {ts.Minutes}m";
            }
            catch { return "Unknown"; }
        }

        public void Stop()
        {
            LogInfo("Stopping API Server...");
            running = false;
            registrationTimer?.Dispose();
            commandCheckTimer?.Dispose();
            try { listener.Stop(); } catch { }
            LogInfo("API Server stopped");
        }
    }
}
APISERVERCS

    # DeviceInfo.cs - Linux-optimized version
    cat > "$SHARE_PATH/app/DeviceInfo.cs" << 'DEVICEINFOCS'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;

namespace DeviceMonitor
{
    public class DeviceInfo
    {
        public Dictionary<string, object> GetInfo()
        {
            return GetLinuxInfo();
        }

        private Dictionary<string, object> GetLinuxInfo()
        {
            var info = new Dictionary<string, object>();

            try
            {
                info["os"] = GetOS();
                info["hostname"] = Environment.MachineName;
                info["ipAddress"] = GetLocalIPAddress();
                info["macAddress"] = GetMACAddress();
                info["cpu"] = GetCpuUsage();
                info["cpuModel"] = GetCpuModel();
                info["cpuCores"] = Environment.ProcessorCount;
                
                var memory = GetMemoryInfo();
                info["ramUsed"] = memory.used;
                info["ramTotal"] = memory.total;
                info["ramPercent"] = memory.percent;
                
                var disk = GetDiskInfo();
                info["diskUsed"] = disk.used;
                info["diskTotal"] = disk.total;
                info["diskPercent"] = disk.percent;
                
                info["uptime"] = GetUptime();
                info["loadAverage"] = GetLoadAverage();
                info["online"] = true;
                info["timestamp"] = DateTime.Now.ToString("o");
                info["platform"] = "Linux/Unraid";
            }
            catch (Exception ex)
            {
                info["error"] = ex.Message;
            }

            return info;
        }

        private string GetOS()
        {
            try
            {
                if (File.Exists("/etc/unraid-version"))
                {
                    var version = File.ReadAllText("/etc/unraid-version").Trim();
                    return $"Unraid {version}";
                }
                if (File.Exists("/etc/os-release"))
                {
                    var lines = File.ReadAllLines("/etc/os-release");
                    var prettyName = lines.FirstOrDefault(l => l.StartsWith("PRETTY_NAME="));
                    if (prettyName != null)
                    {
                        return prettyName.Split('=')[1].Trim('"');
                    }
                }
            }
            catch { }
            return Environment.OSVersion.ToString();
        }

        private string GetLocalIPAddress()
        {
            try
            {
                var host = Dns.GetHostEntry(Dns.GetHostName());
                foreach (var ip in host.AddressList)
                {
                    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    {
                        return ip.ToString();
                    }
                }
            }
            catch { }
            return "127.0.0.1";
        }

        private string GetMACAddress()
        {
            try
            {
                var nics = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces();
                var nic = nics.FirstOrDefault(n => 
                    n.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
                    && n.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback);
                if (nic != null)
                {
                    return nic.GetPhysicalAddress().ToString();
                }
            }
            catch { }
            return "Unknown";
        }

        private double GetCpuUsage()
        {
            try
            {
                var loadAvg = File.ReadAllText("/proc/loadavg").Split(' ')[0];
                double load = double.Parse(loadAvg);
                int cores = Environment.ProcessorCount;
                return Math.Round((load / cores) * 100, 2);
            }
            catch { return 0; }
        }

        private string GetCpuModel()
        {
            try
            {
                var cpuinfo = File.ReadAllLines("/proc/cpuinfo");
                var modelLine = cpuinfo.FirstOrDefault(l => l.StartsWith("model name"));
                if (modelLine != null)
                {
                    return modelLine.Split(':')[1].Trim();
                }
            }
            catch { }
            return "Unknown";
        }

        private (double used, double total, double percent) GetMemoryInfo()
        {
            try
            {
                var meminfo = File.ReadAllLines("/proc/meminfo");
                long total = 0, available = 0;
                
                foreach (var line in meminfo)
                {
                    if (line.StartsWith("MemTotal:"))
                        total = long.Parse(line.Split(':')[1].Trim().Split(' ')[0]) * 1024;
                    else if (line.StartsWith("MemAvailable:"))
                        available = long.Parse(line.Split(':')[1].Trim().Split(' ')[0]) * 1024;
                }
                
                long used = total - available;
                double totalGB = total / (1024.0 * 1024.0 * 1024.0);
                double usedGB = used / (1024.0 * 1024.0 * 1024.0);
                double percent = (used * 100.0) / total;
                
                return (Math.Round(usedGB, 2), Math.Round(totalGB, 2), Math.Round(percent, 2));
            }
            catch { return (0, 0, 0); }
        }

        private (double used, double total, double percent) GetDiskInfo()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "df",
                    Arguments = "-B1 /",
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (var process = Process.Start(psi))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit();

                    var lines = output.Split('\n');
                    if (lines.Length > 1)
                    {
                        var parts = lines[1].Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                        if (parts.Length >= 4)
                        {
                            long total = long.Parse(parts[1]);
                            long used = long.Parse(parts[2]);
                            double totalGB = total / (1024.0 * 1024.0 * 1024.0);
                            double usedGB = used / (1024.0 * 1024.0 * 1024.0);
                            double percent = (used * 100.0) / total;
                            return (Math.Round(usedGB, 2), Math.Round(totalGB, 2), Math.Round(percent, 2));
                        }
                    }
                }
            }
            catch { }
            return (0, 0, 0);
        }

        private string GetUptime()
        {
            try
            {
                string uptime = File.ReadAllText("/proc/uptime").Split(' ')[0];
                double seconds = double.Parse(uptime);
                TimeSpan ts = TimeSpan.FromSeconds(seconds);
                return $"{(int)ts.TotalDays}d {ts.Hours}h {ts.Minutes}m";
            }
            catch { return "Unknown"; }
        }

        private string GetLoadAverage()
        {
            try
            {
                return File.ReadAllText("/proc/loadavg").Split('\n')[0].Trim();
            }
            catch { return "Unknown"; }
        }
    }
}
DEVICEINFOCS

    print_success "Created source files"
}

#===============================================================================
# Step 7: Build and start Docker container
#===============================================================================

build_and_start_container() {
    print_step "7/7" "Building and starting FluxWatch container"
    
    cd "$SHARE_PATH/app"
    
    # Build the Docker image
    print_info "Building Docker image (this may take a few minutes)..."
    
    if docker build -t "${IMAGE_NAME}:${FLUXWATCH_VERSION}" -t "${IMAGE_NAME}:latest" . 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Docker image built successfully"
    else
        print_error "Failed to build Docker image"
        exit 1
    fi
    
    # Create and start the container
    print_info "Creating and starting container..."
    
    docker run -d \
        --name "${CONTAINER_NAME}" \
        --restart unless-stopped \
        -p ${APP_PORT}:8080 \
        -v "${SHARE_PATH}/data:/app/data" \
        -v "${SHARE_PATH}/logs:/var/log/fluxwatch" \
        -v "${SHARE_PATH}/config:/app/config" \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -e TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC") \
        --hostname "$(hostname)-fluxwatch" \
        "${IMAGE_NAME}:latest"
    
    if [ $? -eq 0 ]; then
        print_success "Container started successfully"
    else
        print_error "Failed to start container"
        exit 1
    fi
    
    # Wait for container to be healthy
    print_info "Waiting for FluxWatch to start..."
    sleep 5
    
    # Check if container is running
    if docker ps | grep -q "${CONTAINER_NAME}"; then
        print_success "FluxWatch container is running"
    else
        print_error "Container failed to start"
        docker logs "${CONTAINER_NAME}" 2>&1 | tail -20
        exit 1
    fi
    
    # Test health endpoint
    local max_attempts=10
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:${APP_PORT}/health" | grep -q "healthy"; then
            print_success "FluxWatch is responding to health checks"
            break
        fi
        print_info "Waiting for FluxWatch to be ready (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_warning "Health check timed out, but container is running"
    fi
}

#===============================================================================
# Setup autostart on Unraid boot
#===============================================================================

setup_autostart() {
    print_info "Setting up autostart..."
    
    # Create autostart script
    cat > "/boot/config/plugins/fluxwatch/start.sh" << 'STARTSH'
#!/bin/bash
# FluxWatch autostart script
docker start fluxwatch 2>/dev/null || echo "FluxWatch container not found"
STARTSH
    
    mkdir -p /boot/config/plugins/fluxwatch
    chmod +x /boot/config/plugins/fluxwatch/start.sh
    
    # Add to go file if not already present
    if ! grep -q "fluxwatch" /boot/config/go 2>/dev/null; then
        echo "" >> /boot/config/go
        echo "# FluxWatch autostart" >> /boot/config/go
        echo "/boot/config/plugins/fluxwatch/start.sh &" >> /boot/config/go
    fi
    
    print_success "Autostart configured"
}

#===============================================================================
# Print final summary
#===============================================================================

print_summary() {
    local container_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null || echo "N/A")
    local host_ip=$(hostname -I | awk '{print $1}')
    
    echo -e "\n${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║              FluxWatch Installation Complete!                    ║"
    echo "║                                                                  ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                  ║"
    echo "║  Version: ${FLUXWATCH_VERSION}                                              ║"
    echo "║  Container: ${CONTAINER_NAME}                                          ║"
    echo "║  Port: ${APP_PORT}                                                    ║"
    echo "║                                                                  ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                  ║"
    echo "║  Access FluxWatch:                                               ║"
    echo "║    http://${host_ip}:${APP_PORT}                                       ║"
    echo "║    http://localhost:${APP_PORT}                                        ║"
    echo "║                                                                  ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                  ║"
    echo "║  File Locations:                                                 ║"
    echo "║    Share: ${SHARE_PATH}                                ║"
    echo "║    Logs:  ${SHARE_PATH}/logs                           ║"
    echo "║    Data:  ${SHARE_PATH}/data                           ║"
    echo "║                                                                  ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                  ║"
    echo "║  Useful Commands:                                                ║"
    echo "║    View logs:     docker logs -f ${CONTAINER_NAME}                     ║"
    echo "║    Restart:       docker restart ${CONTAINER_NAME}                     ║"
    echo "║    Stop:          docker stop ${CONTAINER_NAME}                        ║"
    echo "║    Uninstall:     ./uninstall.sh                                 ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

#===============================================================================
# Main installation flow
#===============================================================================

main() {
    print_header
    
    log "=========================================="
    log "FluxWatch Installation Started"
    log "=========================================="
    
    check_root
    check_unraid
    check_docker
    
    check_existing_installations
    remove_existing_containers
    kill_port_processes
    remove_old_files
    create_share
    deploy_files
    build_and_start_container
    setup_autostart
    
    print_summary
    
    log "=========================================="
    log "FluxWatch Installation Completed"
    log "=========================================="
}

# Run main function
main "$@"
