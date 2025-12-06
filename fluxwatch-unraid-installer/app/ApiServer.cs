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
        
        // Central server endpoints
        private const string CENTRAL_SERVER = "https://fw.nrdy.me/register.php";
        private const string COMMAND_CHECK_URL = "https://fw.nrdy.me/check_command.php";
        private const string COMMAND_RESPONSE_URL = "https://fw.nrdy.me/command_response.php";
        
        private Timer registrationTimer;
        private Timer commandCheckTimer;
        private string deviceId;
        private string logPath = "/var/log/fluxwatch/apiserver.log";
        private int port = 8080;

        public ApiServer()
        {
            deviceInfo = new DeviceInfo();
            listener = new HttpListener();
            deviceId = GetDeviceId();

            // Check for port override
            string portEnv = Environment.GetEnvironmentVariable("FLUXWATCH_PORT");
            if (!string.IsNullOrEmpty(portEnv) && int.TryParse(portEnv, out int customPort))
            {
                port = customPort;
            }

            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath));
            }
            catch { }

            // Set HttpClient timeout
            httpClient.Timeout = TimeSpan.FromSeconds(30);
        }

        private void LogInfo(string message)
        {
            try
            {
                var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] INFO: {message}";
                File.AppendAllText(logPath, line + "\n");
                Console.WriteLine(line);
            }
            catch { }
        }

        private void LogError(string message)
        {
            try
            {
                var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] ERROR: {message}";
                File.AppendAllText(logPath, line + "\n");
                Console.WriteLine(line);
            }
            catch { }
        }

        private void LogDebug(string message)
        {
            try
            {
                var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] DEBUG: {message}";
                File.AppendAllText(logPath, line + "\n");
            }
            catch { }
        }

        private string GetDeviceId()
        {
            string hostname = Environment.MachineName;
            string macAddress = "000000000000";

            try
            {
                var nics = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces();
                var nic = nics.FirstOrDefault(n => 
                    n.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
                    && n.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback
                    && !n.Name.StartsWith("docker")
                    && !n.Name.StartsWith("br-")
                    && !n.Name.StartsWith("veth"));
                
                if (nic != null)
                {
                    macAddress = nic.GetPhysicalAddress().ToString();
                }
            }
            catch (Exception ex)
            {
                LogError($"Error getting MAC address: {ex.Message}");
            }

            return $"{hostname}_{macAddress}";
        }

        private async Task<string> GetPublicIP()
        {
            string[] ipServices = {
                "https://api.ipify.org",
                "https://icanhazip.com",
                "https://ifconfig.me/ip",
                "https://ipecho.net/plain"
            };

            foreach (var service in ipServices)
            {
                try
                {
                    var response = await httpClient.GetStringAsync(service);
                    string ip = response.Trim();
                    if (!string.IsNullOrEmpty(ip) && ip.Contains('.'))
                    {
                        return ip;
                    }
                }
                catch { }
            }
            
            return "Unknown";
        }

        private string GetLocalIPAddress()
        {
            try
            {
                // First try to get IP from network interfaces
                var nics = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces();
                foreach (var nic in nics)
                {
                    if (nic.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
                        && nic.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback
                        && !nic.Name.StartsWith("docker")
                        && !nic.Name.StartsWith("br-")
                        && !nic.Name.StartsWith("veth"))
                    {
                        var props = nic.GetIPProperties();
                        foreach (var addr in props.UnicastAddresses)
                        {
                            if (addr.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork
                                && !IPAddress.IsLoopback(addr.Address))
                            {
                                return addr.Address.ToString();
                            }
                        }
                    }
                }

                // Fallback to DNS resolution
                var host = Dns.GetHostEntry(Dns.GetHostName());
                foreach (var ip in host.AddressList)
                {
                    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    {
                        return ip.ToString();
                    }
                }
            }
            catch (Exception ex)
            {
                LogError($"Error getting local IP: {ex.Message}");
            }
            
            return "127.0.0.1";
        }

        public void Start()
        {
            try
            {
                LogInfo("Starting API Server...");
                LogInfo($"Device ID: {deviceId}");
                LogInfo($"Port: {port}");
                
                // Add URL prefix
                listener.Prefixes.Add($"http://*:{port}/");
                LogInfo($"Added URL prefix: http://*:{port}/");

                // Start listener
                listener.Start();
                running = true;
                LogInfo("HttpListener started successfully");

                // Start request handler thread
                Thread listenerThread = new Thread(HandleRequests);
                listenerThread.IsBackground = true;
                listenerThread.Name = "HttpListener Thread";
                listenerThread.Start();
                LogInfo("Request handler thread started");

                // Register device every 30 seconds
                registrationTimer = new Timer(RegisterDeviceCallback, null, TimeSpan.Zero, TimeSpan.FromSeconds(30));
                LogInfo("Device registration timer started (30s interval)");

                // Check for commands every 5 seconds
                commandCheckTimer = new Timer(CheckForCommandsCallback, null, TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(5));
                LogInfo("Command check timer started (5s interval)");

                LogInfo($"API Server is running on http://0.0.0.0:{port}");
            }
            catch (HttpListenerException ex)
            {
                LogError($"HttpListener failed to start: {ex.Message} (ErrorCode: {ex.ErrorCode})");
                throw new Exception($"Failed to start HTTP server on port {port}: {ex.Message}", ex);
            }
            catch (Exception ex)
            {
                LogError($"Failed to start API Server: {ex.Message}\n{ex.StackTrace}");
                throw;
            }
        }

        private void RegisterDeviceCallback(object state) => Task.Run(() => RegisterDevice());
        private void CheckForCommandsCallback(object state) => Task.Run(() => CheckForCommands());

        private async Task RegisterDevice()
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
                    { "lastSeenFormatted", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") },
                    { "version", Program.Version },
                    { "platform", info.ContainsKey("os") ? info["os"].ToString() : "Linux/Unraid" },
                    { "agentType", "unraid" },
                    { "info", info }
                };

                var json = JsonSerializer.Serialize(registrationData);
                var content = new StringContent(json, Encoding.UTF8, "application/json");
                
                var response = await httpClient.PostAsync(CENTRAL_SERVER, content);
                if (response.IsSuccessStatusCode)
                {
                    LogDebug("Device registered successfully");
                }
                else
                {
                    LogDebug($"Registration response: {response.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                LogDebug($"Registration failed: {ex.Message}");
            }
        }

        private async Task CheckForCommands()
        {
            try
            {
                var response = await httpClient.GetStringAsync($"{COMMAND_CHECK_URL}?deviceId={Uri.EscapeDataString(deviceId)}");
                if (!string.IsNullOrEmpty(response) && response != "null" && response != "{}")
                {
                    LogInfo($"Received command: {response}");
                    await ProcessCommand(response);
                }
            }
            catch (Exception ex)
            {
                LogDebug($"Command check error: {ex.Message}");
            }
        }

        private async Task ProcessCommand(string commandJson)
        {
            try
            {
                var command = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(commandJson);
                if (command == null) return;

                string commandId = command.ContainsKey("commandId") ? command["commandId"].GetString() : "";
                string action = command.ContainsKey("action") ? command["action"].GetString() : "";

                LogInfo($"Processing command: {action} (ID: {commandId})");

                string result = "completed";
                string message = "";

                switch (action.ToLower())
                {
                    case "ping":
                        message = "pong";
                        break;
                        
                    case "reboot":
                        message = "Reboot initiated";
                        _ = Task.Run(async () => {
                            await Task.Delay(2000);
                            ExecuteCommand("reboot", "");
                        });
                        break;
                        
                    case "shutdown":
                        message = "Shutdown initiated";
                        _ = Task.Run(async () => {
                            await Task.Delay(2000);
                            ExecuteCommand("poweroff", "");
                        });
                        break;
                        
                    case "update":
                        message = "Update check initiated";
                        // Placeholder for update logic
                        break;
                        
                    default:
                        result = "unknown";
                        message = $"Unknown command: {action}";
                        LogInfo($"Unknown command received: {action}");
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
                
                LogInfo($"Command response sent: {result} - {message}");
            }
            catch (Exception ex)
            {
                LogError($"Command processing error: {ex.Message}");
            }
        }

        private void ExecuteCommand(string fileName, string arguments)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = fileName,
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                LogError($"Execute command error: {ex.Message}");
            }
        }

        private void HandleRequests()
        {
            LogInfo("Request handler started, waiting for connections...");
            
            while (running)
            {
                try
                {
                    var context = listener.GetContext();
                    ThreadPool.QueueUserWorkItem(_ => ProcessRequest(context));
                }
                catch (HttpListenerException ex) when (!running)
                {
                    LogDebug($"Listener stopped: {ex.Message}");
                    break;
                }
                catch (Exception ex)
                {
                    if (running)
                    {
                        LogError($"Request handling error: {ex.Message}");
                    }
                }
            }
            
            LogInfo("Request handler stopped");
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
                response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, Authorization");

                // Handle preflight
                if (request.HttpMethod == "OPTIONS")
                {
                    response.StatusCode = 200;
                    response.Close();
                    return;
                }

                string path = request.Url.AbsolutePath.ToLower().TrimEnd('/');
                if (string.IsNullOrEmpty(path)) path = "/";
                
                string responseString = "";
                string contentType = "application/json";
                int statusCode = 200;

                LogDebug($"Request: {request.HttpMethod} {path}");

                switch (path)
                {
                    case "/":
                    case "/health":
                        responseString = JsonSerializer.Serialize(new { 
                            status = "healthy", 
                            version = Program.Version, 
                            platform = "Linux/Unraid",
                            deviceId = deviceId,
                            timestamp = DateTime.UtcNow.ToString("o")
                        });
                        break;

                    case "/info":
                    case "/api/info":
                        var info = deviceInfo.GetInfo();
                        info["deviceId"] = deviceId;
                        info["version"] = Program.Version;
                        info["agentType"] = "unraid";
                        responseString = JsonSerializer.Serialize(info);
                        break;

                    case "/api/status":
                        responseString = JsonSerializer.Serialize(new {
                            online = true,
                            deviceId = deviceId,
                            hostname = Environment.MachineName,
                            localIP = GetLocalIPAddress(),
                            uptime = GetUptime(),
                            version = Program.Version,
                            platform = "Linux/Unraid"
                        });
                        break;

                    case "/api/metrics":
                        var metrics = deviceInfo.GetInfo();
                        responseString = JsonSerializer.Serialize(new {
                            cpu = metrics.ContainsKey("cpu") ? metrics["cpu"] : 0,
                            ramPercent = metrics.ContainsKey("ramPercent") ? metrics["ramPercent"] : 0,
                            diskPercent = metrics.ContainsKey("diskPercent") ? metrics["diskPercent"] : 0,
                            loadAverage = metrics.ContainsKey("loadAverage") ? metrics["loadAverage"] : "0 0 0",
                            timestamp = DateTime.UtcNow.ToString("o")
                        });
                        break;

                    default:
                        statusCode = 404;
                        responseString = JsonSerializer.Serialize(new { 
                            error = "Not found", 
                            path = path,
                            availableEndpoints = new[] { "/", "/health", "/info", "/api/info", "/api/status", "/api/metrics" }
                        });
                        break;
                }

                response.StatusCode = statusCode;
                response.ContentType = contentType;
                byte[] buffer = Encoding.UTF8.GetBytes(responseString);
                response.ContentLength64 = buffer.Length;
                response.OutputStream.Write(buffer, 0, buffer.Length);
                response.Close();
            }
            catch (Exception ex)
            {
                LogError($"Process request error: {ex.Message}");
                try
                {
                    context.Response.StatusCode = 500;
                    context.Response.Close();
                }
                catch { }
            }
        }

        private string GetUptime()
        {
            try
            {
                if (File.Exists("/proc/uptime"))
                {
                    string uptime = File.ReadAllText("/proc/uptime").Split(' ')[0];
                    double seconds = double.Parse(uptime, System.Globalization.CultureInfo.InvariantCulture);
                    TimeSpan ts = TimeSpan.FromSeconds(seconds);
                    return $"{(int)ts.TotalDays}d {ts.Hours}h {ts.Minutes}m";
                }
            }
            catch { }
            return "Unknown";
        }

        public void Stop()
        {
            LogInfo("Stopping API Server...");
            running = false;
            
            registrationTimer?.Dispose();
            commandCheckTimer?.Dispose();
            
            try
            {
                listener.Stop();
                listener.Close();
            }
            catch (Exception ex)
            {
                LogError($"Error stopping listener: {ex.Message}");
            }
            
            LogInfo("API Server stopped");
        }
    }
}
