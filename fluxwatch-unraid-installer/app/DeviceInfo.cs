using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Globalization;

namespace DeviceMonitor
{
    public class DeviceInfo
    {
        private static readonly CultureInfo invariantCulture = CultureInfo.InvariantCulture;

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
                info["allIPs"] = GetAllIPAddresses();
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
                info["processCount"] = GetProcessCount();
                info["unraidVersion"] = GetUnraidVersion();
                info["dockerContainers"] = GetDockerContainerCount();
                info["arrayStatus"] = GetArrayStatus();
                info["online"] = true;
                info["timestamp"] = DateTime.Now.ToString("o");
                info["platform"] = "Linux/Unraid";
            }
            catch (Exception ex)
            {
                info["error"] = ex.Message;
                info["online"] = true;
            }

            return info;
        }

        private string GetOS()
        {
            try
            {
                if (File.Exists("/etc/unraid-version"))
                {
                    return $"Unraid {File.ReadAllText("/etc/unraid-version").Trim()}";
                }
                if (File.Exists("/etc/os-release"))
                {
                    var lines = File.ReadAllLines("/etc/os-release");
                    var prettyName = lines.FirstOrDefault(l => l.StartsWith("PRETTY_NAME="));
                    if (prettyName != null)
                        return prettyName.Split('=')[1].Trim('"');
                }
            }
            catch { }
            return Environment.OSVersion.ToString();
        }

        private string GetUnraidVersion()
        {
            try
            {
                if (File.Exists("/etc/unraid-version"))
                    return File.ReadAllText("/etc/unraid-version").Trim();
            }
            catch { }
            return "N/A";
        }

        private string GetLocalIPAddress()
        {
            try
            {
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
                                return addr.Address.ToString();
                        }
                    }
                }
                var host = Dns.GetHostEntry(Dns.GetHostName());
                foreach (var ip in host.AddressList)
                {
                    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                        return ip.ToString();
                }
            }
            catch { }
            return "127.0.0.1";
        }

        private List<string> GetAllIPAddresses()
        {
            var ips = new List<string>();
            try
            {
                var nics = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces();
                foreach (var nic in nics)
                {
                    if (nic.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
                        && nic.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback)
                    {
                        var props = nic.GetIPProperties();
                        foreach (var addr in props.UnicastAddresses)
                        {
                            if (addr.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                                ips.Add(addr.Address.ToString());
                        }
                    }
                }
            }
            catch { }
            return ips;
        }

        private string GetMACAddress()
        {
            try
            {
                var nics = System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces();
                var nic = nics.FirstOrDefault(n => 
                    n.OperationalStatus == System.Net.NetworkInformation.OperationalStatus.Up
                    && n.NetworkInterfaceType != System.Net.NetworkInformation.NetworkInterfaceType.Loopback
                    && !n.Name.StartsWith("docker")
                    && !n.Name.StartsWith("br-"));
                if (nic != null)
                    return nic.GetPhysicalAddress().ToString();
            }
            catch { }
            return "Unknown";
        }

        private double GetCpuUsage()
        {
            try
            {
                var loadAvg = File.ReadAllText("/proc/loadavg").Split(' ')[0];
                double load = double.Parse(loadAvg, invariantCulture);
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
                    return modelLine.Split(':')[1].Trim();
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
                double percent = total > 0 ? (used * 100.0) / total : 0;
                
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
                            double percent = total > 0 ? (used * 100.0) / total : 0;
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
                double seconds = double.Parse(uptime, invariantCulture);
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
            catch { return "0.00 0.00 0.00"; }
        }

        private int GetProcessCount()
        {
            try
            {
                return Directory.GetDirectories("/proc")
                    .Count(d => int.TryParse(Path.GetFileName(d), out _));
            }
            catch { return 0; }
        }

        private int GetDockerContainerCount()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "docker",
                    Arguments = "ps -q",
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (var process = Process.Start(psi))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    process.WaitForExit();
                    return output.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries).Length;
                }
            }
            catch { return 0; }
        }

        private string GetArrayStatus()
        {
            try
            {
                // Check Unraid array status
                if (File.Exists("/var/local/emhttp/var.ini"))
                {
                    var lines = File.ReadAllLines("/var/local/emhttp/var.ini");
                    var mdState = lines.FirstOrDefault(l => l.StartsWith("mdState="));
                    if (mdState != null)
                    {
                        string state = mdState.Split('=')[1].Trim('"');
                        return state;
                    }
                }
            }
            catch { }
            return "Unknown";
        }
    }
}
