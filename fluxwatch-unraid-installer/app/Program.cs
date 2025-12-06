using System;
using System.IO;
using System.Threading;

namespace DeviceMonitor
{
    static class Program
    {
        private static ApiServer apiServer;
        private static string logPath = "/var/log/fluxwatch/startup.log";
        public static readonly string Version = "1.0.1";

        static void Main(string[] args)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath));
                Log($"\n========================================================");
                Log($"FluxWatch v{Version} starting on Linux/Unraid...");
                Log($"Arguments: {string.Join(" ", args)}");
                Log($"Working Directory: {Environment.CurrentDirectory}");
                Log($"Machine Name: {Environment.MachineName}");

                // Parse command line arguments
                foreach (var arg in args)
                {
                    string lowerArg = arg.ToLower();
                    
                    if (lowerArg == "/version" || lowerArg == "--version" || lowerArg == "-v")
                    {
                        Console.WriteLine($"FluxWatch v{Version}");
                        return;
                    }
                    
                    if (lowerArg == "/help" || lowerArg == "--help" || lowerArg == "-h")
                    {
                        PrintHelp();
                        return;
                    }
                }

                RunLinux();
            }
            catch (Exception ex)
            {
                Log($"FATAL: {ex.Message}\n{ex.StackTrace}");
                Console.WriteLine($"FATAL ERROR: {ex.Message}");
                Environment.Exit(1);
            }
        }

        static void PrintHelp()
        {
            Console.WriteLine($@"
FluxWatch v{Version} - Device Monitoring Agent

Usage: FluxWatch [options]

Options:
  --version, -v    Show version information
  --help, -h       Show this help message

Environment Variables:
  FLUXWATCH_PORT   HTTP server port (default: 8080)
  
Endpoints:
  /                Health check
  /health          Health status JSON
  /info            Device information
  /api/info        Full device info JSON
  /api/status      Quick status check

More info: https://fw.nrdy.me
");
        }

        static void Log(string message)
        {
            try
            {
                string logLine = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}";
                File.AppendAllText(logPath, logLine + "\n");
                Console.WriteLine(message);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Log error: {ex.Message}");
            }
        }

        static void RunLinux()
        {
            Log("Initializing API Server...");
            apiServer = new ApiServer();
            
            try
            {
                apiServer.Start();
                Log("API Server started successfully");
            }
            catch (Exception ex)
            {
                Log($"API Server failed to start: {ex.Message}");
                Log($"Stack trace: {ex.StackTrace}");
                throw;
            }

            Log($"FluxWatch v{Version} running at http://0.0.0.0:8080");
            Log("Press Ctrl+C to stop...");
            
            // Setup graceful shutdown
            var exitEvent = new ManualResetEvent(false);
            
            Console.CancelKeyPress += (sender, eventArgs) => 
            { 
                eventArgs.Cancel = true;
                Log("Received shutdown signal (Ctrl+C)...");
                exitEvent.Set(); 
            };

            AppDomain.CurrentDomain.ProcessExit += (sender, eventArgs) =>
            {
                Log("Process exit event received");
                Shutdown();
            };

            // Handle SIGTERM for Docker graceful shutdown
            AppDomain.CurrentDomain.UnhandledException += (sender, eventArgs) =>
            {
                Log($"Unhandled exception: {eventArgs.ExceptionObject}");
                Shutdown();
            };

            // Wait for exit signal
            exitEvent.WaitOne();
            
            Shutdown();
        }

        static void Shutdown()
        {
            Log("Initiating shutdown...");
            try
            {
                apiServer?.Stop();
                Log("API Server stopped");
            }
            catch (Exception ex)
            {
                Log($"Error during shutdown: {ex.Message}");
            }
            Log("FluxWatch shutdown complete");
        }
    }
}
