# FluxWatch Unraid Installer

A complete installer package for deploying FluxWatch on Unraid NAS systems.

## Features

- ✅ Automatic cleanup of previous FluxWatch installations
- ✅ Removes old Docker containers and images
- ✅ Creates dedicated Unraid share for FluxWatch
- ✅ Builds optimized Docker container for Linux/Unraid
- ✅ Auto-starts on Unraid boot
- ✅ Web dashboard accessible on port 8080
- ✅ Device monitoring and registration
- ✅ Complete uninstaller included

## Quick Install

### Option 1: Install from GitHub (Recommended)

```bash
# One-line install
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/fluxwatch-unraid/main/install.sh | sudo bash
```

### Option 2: Manual Installation

1. Download the installer package:
```bash
wget https://github.com/YOUR_USERNAME/fluxwatch-unraid/archive/main.zip
unzip main.zip
cd fluxwatch-unraid-main
```

2. Make scripts executable:
```bash
chmod +x install.sh uninstall.sh
```

3. Run the installer:
```bash
sudo ./install.sh
```

### Option 3: Upload to Unraid Share

1. Create a new share on Unraid (e.g., `downloads`)
2. Upload all files from this package to that share
3. SSH into your Unraid server:
```bash
ssh root@your-unraid-ip
```
4. Navigate to the uploaded files:
```bash
cd /mnt/user/downloads/fluxwatch-unraid-installer
```
5. Run the installer:
```bash
chmod +x install.sh
./install.sh
```

## What Gets Installed

| Component | Location |
|-----------|----------|
| Application Files | `/mnt/user/fluxwatch/app/` |
| Data Directory | `/mnt/user/fluxwatch/data/` |
| Log Files | `/mnt/user/fluxwatch/logs/` |
| Config Files | `/mnt/user/fluxwatch/config/` |
| Docker Container | `fluxwatch` |

## Accessing FluxWatch

After installation, access the FluxWatch dashboard at:

- **Local Network**: `http://YOUR-UNRAID-IP:8080`
- **From Unraid Server**: `http://localhost:8080`

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `/` | Health check |
| `/health` | Health status |
| `/info` | Device information |
| `/api/info` | Full device info JSON |
| `/api/status` | Quick status check |

## Management Commands

### View Container Logs
```bash
docker logs -f fluxwatch
```

### Restart FluxWatch
```bash
docker restart fluxwatch
```

### Stop FluxWatch
```bash
docker stop fluxwatch
```

### Start FluxWatch
```bash
docker start fluxwatch
```

### Check Container Status
```bash
docker ps | grep fluxwatch
```

### View Resource Usage
```bash
docker stats fluxwatch
```

## Uninstallation

To completely remove FluxWatch:

```bash
# If you have the uninstall script
./uninstall.sh

# Or manually
docker stop fluxwatch
docker rm fluxwatch
docker rmi fluxwatch:latest
rm -rf /mnt/user/fluxwatch
```

## Troubleshooting

### Container won't start

1. Check Docker logs:
```bash
docker logs fluxwatch
```

2. Verify port 8080 is free:
```bash
netstat -tlnp | grep 8080
```

3. Check if container exists:
```bash
docker ps -a | grep fluxwatch
```

### Cannot access web interface

1. Check if container is running:
```bash
docker ps | grep fluxwatch
```

2. Test from Unraid console:
```bash
curl http://localhost:8080/health
```

3. Check firewall settings on Unraid

### Build fails

1. Ensure Docker is running:
```bash
docker info
```

2. Check disk space:
```bash
df -h
```

3. View build logs in `/var/log/fluxwatch-install.log`

## File Structure

```
fluxwatch-unraid-installer/
├── install.sh           # Main installation script
├── uninstall.sh         # Uninstallation script
├── README.md            # This file
└── app/                 # Application source files
    ├── Dockerfile       # Docker build configuration
    ├── FluxWatch.csproj # .NET project file
    ├── Program.cs       # Main entry point
    ├── ApiServer.cs     # HTTP API server
    └── DeviceInfo.cs    # System information collector
```

## Version History

### v1.0.1
- Initial Unraid release
- Linux/Docker optimized
- Full cleanup and installation automation
- Auto-start on boot

## Support

- GitHub Issues: https://github.com/YOUR_USERNAME/fluxwatch-unraid/issues
- FluxWatch Central: https://fw.nrdy.me

## License

MIT License - See LICENSE file for details.
