# System Health Monitor 🛠️

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platforms: Linux](https://img.shields.io/badge/Platform-Linux-green.svg)](https://www.linux.org/)

A comprehensive system health monitoring and maintenance tool for Linux. This script provides real-time information about your system's health, including CPU/GPU temperatures, disk usage, memory usage, error logs, and more. It can also automatically fix common issues.

<div align="center">
  <img src="https://github.com/acn3to/system-health-monitor/raw/main/screenshots/dashboard.png" alt="System Health Monitor Dashboard" style="max-width: 100%;">
</div>

## 📋 Table of Contents

- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Usage](#-usage)
- [Oh-My-Zsh Integration](#-oh-my-zsh-integration)
- [Customization](#-customization)
- [Compatibility](#-compatibility)
- [Troubleshooting](#-troubleshooting)
- [License](#-license)
- [Contributing](#-contributing)

## ✨ Features

- 📊 **System Dashboard**: Quick overview of critical system metrics
- 🌡️ **Temperature Monitoring**: CPU, GPU (NVIDIA, AMD, Intel), and storage device temperatures
- 💾 **Disk Health**: SMART status, usage, and I/O statistics
- 🧠 **Memory Analysis**: RAM and swap usage monitoring
- 🔍 **Error Detection**: System logs and kernel messages analysis
- 🔄 **Automatic Fixes**: Package manager issues, updates, and maintenance
- 🐳 **Container Status**: Docker and Podman container monitoring
- 🖥️ **Hardware Support**: Auto-detection of NVIDIA, AMD, and Intel GPUs
- 🖧 **Network Statistics**: Interface info, connections, and traffic
- 👁️ **Visual Indicators**: Color-coded status markers for quick assessment
- 🔧 **Multi-Distro Support**: Works on Debian, Ubuntu, Fedora, RHEL, Arch, and more

## 🔧 Requirements

- Linux distribution (supports multiple package managers)
- `sudo` privileges for system-wide monitoring and fixes
- Basic utilities: `bc`, `grep`, `awk`, `sed` (pre-installed on most systems)

## 📥 Installation

### Option 1: Quick Install (Recommended)

```bash
git clone https://github.com/acn3to/system-health-monitor.git
cd system-health-monitor
sudo ./install.sh
```

The installer will:
- Detect your package manager
- Install required dependencies
- Add the command to your system PATH
- Offer to set up convenient aliases

### Option 2: Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/acn3to/system-health-monitor.git
   cd system-health-monitor
   ```

2. Make the script executable:
   ```bash
   chmod +x system-health.sh
   ```

3. Move it to a system path (optional):
   ```bash
   sudo cp system-health.sh /usr/local/bin/system-health
   sudo chmod +x /usr/local/bin/system-health
   ```

### Dependencies

The installer will detect and install missing dependencies automatically. If you prefer to install them manually:

#### Debian/Ubuntu
```bash
sudo apt install bc smartmontools lm-sensors sysstat
```

#### Fedora/RHEL/CentOS
```bash
sudo dnf install bc smartmontools lm_sensors sysstat
```

#### Arch Linux
```bash
sudo pacman -S bc smartmontools lm_sensors sysstat
```

## 🚀 Usage

### Basic Health Check
Performs a system health scan without making any changes:

```bash
sudo system-health
```

### Health Check with Automatic Fixes
Scans your system and automatically fixes detected issues:

```bash
sudo system-health --fix
```

### Get Help
View all available options and usage information:

```bash
system-health --help
```

### What It Checks

The script monitors and provides information on:
- CPU and memory usage
- Temperature of CPU, GPU, and storage devices
- Disk health and usage
- Package manager status and pending updates
- Running containers
- Network status
- System errors

### What It Can Fix

When run with the `--fix` flag, the script can:
- Clear package manager locks
- Update system packages
- Handle kept-back packages
- Install missing monitoring tools
- Suggest system reboots when needed

## 💻 Oh-My-Zsh Integration

Add convenient aliases to your shell for quick access:

### For Oh-My-Zsh Users

1. Edit your `.zshrc` file:
   ```bash
   nano ~/.zshrc
   ```

2. Add these lines:
   ```bash
   # System Health Monitor aliases
   alias health='sudo system-health'
   alias health-fix='sudo system-health --fix'
   ```

3. Apply the changes:
   ```bash
   source ~/.zshrc
   ```

Now you can simply type `health` or `health-fix` in your terminal!

### For Bash Users

1. Edit your `.bashrc` file:
   ```bash
   nano ~/.bashrc
   ```

2. Add these lines:
   ```bash
   # System Health Monitor aliases
   alias health='sudo system-health'
   alias health-fix='sudo system-health --fix'
   ```

3. Apply the changes:
   ```bash
   source ~/.bashrc
   ```

## ⚙️ Customization

You can customize thresholds and behavior by editing the script file:

1. Open the script:
   ```bash
   sudo nano /usr/local/bin/system-health
   ```

2. Find the "Define threshold values" section (around line 500):
   ```bash
   # Define threshold values (adjust as needed)
   cpu_threshold=80.0      # degrees Celsius for CPU cores
   gpu_threshold=80        # degrees Celsius for GPU
   nvme_threshold=70       # degrees Celsius for NVMe drive
   error_threshold=1       # more than 1 error log line triggers warning
   mem_threshold=90        # memory usage percentage
   disk_threshold=90       # disk usage percentage
   ```

3. Adjust the values to suit your needs and save the file

## 🧩 Compatibility

The script automatically detects your hardware and package manager, adjusting functionality accordingly:

### Fully Supported Systems
- 🟢 Ubuntu and derivatives (Linux Mint, Pop!_OS, etc.)
- 🟢 Debian and derivatives
- 🟢 Fedora, RHEL, and CentOS
- 🟢 Arch Linux and derivatives

### Package Managers
- 🟢 apt (Debian/Ubuntu)
- 🟢 dnf (Fedora/RHEL 8+)
- 🟢 yum (CentOS/RHEL 7)
- 🟢 pacman (Arch Linux)

### GPU Support
- 🟢 NVIDIA GPUs (using nvidia-smi)
- 🟢 AMD GPUs (using rocm-smi)
- 🟢 Intel integrated graphics (limited functionality)

## ❓ Troubleshooting

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| **"Permission denied" errors** | Run the script with `sudo`: `sudo system-health` |
| **Missing temperature data** | Some systems have limited sensor access. This is normal. |
| **"Command not found" error** | Ensure the script is installed correctly in your PATH |
| **Script shows package locks** | Run with fix mode: `sudo system-health --fix` |
| **Dependencies not installing** | Install them manually using your package manager |

### For Advanced Issues

1. Run the script with full details: `sudo system-health`
2. Look for warning or error messages
3. Check if any recommended tools are missing
4. Ensure your system's sensors are properly configured

If problems persist, please [open an issue](https://github.com/acn3to/system-health-monitor/issues) with:
- Your distribution name and version
- Complete output from the script
- Any error messages you received

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👥 Contributing

Contributions are welcome! Please feel free to:

1. Fork the repository
2. Create a feature branch: `git checkout -b new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin new-feature`
5. Submit a pull request

For major changes, please open an issue first to discuss what you would like to change.