# Server Transcode

![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)
![Go](https://img.shields.io/badge/Go-1.24-blue.svg)

Worker service สำหรับ transcode วิดีโอเป็น HLS (multi-bitrate), สร้าง thumbnail sprites, และอัพโหลดไฟล์ไปยัง storage server ผ่าน SCP

## ✨ Features

- Transcode วิดีโอเป็น HLS (adaptive bitrate streaming)
- รองรับ GPU encoding (NVIDIA NVENC) พร้อม CPU fallback
- สร้าง thumbnail sprite sheets + VTT
- ดาวน์โหลดไฟล์ต้นฉบับจาก storage ผ่าน SCP
- อัพโหลดผลลัพธ์กลับ storage ผ่าน SCP
- รองรับหลาย workers พร้อมกัน (systemd template)
- Auto-retry เมื่อ transcode ล้มเหลว
- Per-job logging พร้อม auto cleanup
- รองรับ x86_64 และ ARM64

## 📋 Requirements

- Linux (Ubuntu/Debian recommended)
- FFmpeg (with NVENC support for GPU encoding)
- Node.js (ติดตั้งอัตโนมัติผ่าน NVM)
- MongoDB
- NVIDIA GPU + drivers (optional, สำหรับ GPU encoding)

## 🚀 Quick Install (One-line)

```bash
curl -fsSL https://raw.githubusercontent.com/zergolf1994/server-transcode-releases/main/install.sh | sudo -E bash -s -- \
    --mongodb-uri "mongodb+srv://user:pass@host/dbname" \
    --storage-id "storage1" \
    -n 2
```

## 🛠️ Manual Installation

```bash
# Download install script
curl -fsSL https://raw.githubusercontent.com/zergolf1994/server-transcode-releases/main/install.sh -o install.sh
chmod +x install.sh

# Install with default settings (1 worker)
sudo ./install.sh --mongodb-uri "mongodb+srv://user:pass@host/dbname"

# Install with 2 workers
sudo ./install.sh \
    --mongodb-uri "mongodb+srv://user:pass@host/dbname" \
    --storage-id "storage1" \
    --storage-path "/home/files" \
    -n 2
```

## 🗑️ Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/zergolf1994/server-transcode-releases/main/install.sh | sudo -E bash -s -- \
    --uninstall
```

## ⚙️ Service Management

```bash
# Status (worker 1)
systemctl status server-transcode@1

# Logs (all workers)
journalctl -u "server-transcode@*" -f

# Logs (worker 1 only)
journalctl -u "server-transcode@1" -f

# Restart all workers (2 workers example)
for i in $(seq 1 2); do sudo systemctl restart server-transcode@$i; done

# Stop all workers
for i in $(seq 1 2); do sudo systemctl stop server-transcode@$i; done
```

## 📂 File Structure

```
/opt/server-transcode/
├── server-transcode          # Main binary (Go)
├── .env                      # Environment config
└── scripts/
    ├── package.json          # npm dependencies
    ├── node_modules/         # npm packages (node-scp)
    ├── scp-download.js       # SCP download script
    └── scp-upload.js         # SCP upload script
```

## 🔧 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MONGODB_URI` | — | MongoDB connection string |
| `STORAGE_ID` | — | Storage server identifier |
| `STORAGE_PATH` | `/home/files` | Remote storage path for files |
| `WORKER_ID` | `hostname-transcode-N` | Unique worker identifier (auto-set) |

## 📋 Install Options

| Option | Default | Description |
|--------|---------|-------------|
| `-n, --count` | `1` | จำนวน worker instances |
| `--mongodb-uri` | — | MongoDB connection string |
| `--storage-id` | — | Storage ID |
| `--storage-path` | `/home/files` | Remote storage path |
| `--node-version` | `22` | Node.js version |
| `--uninstall` | — | ลบทั้งหมด (binary, service, config) |
| `-h, --help` | — | แสดง help |

## 🔄 Update

```bash
# Re-run install script (will download latest binary & restart workers)
curl -fsSL https://raw.githubusercontent.com/zergolf1994/server-transcode-releases/main/install.sh | sudo -E bash -s -- \
    --mongodb-uri "mongodb+srv://user:pass@host/dbname" \
    -n 2
```
