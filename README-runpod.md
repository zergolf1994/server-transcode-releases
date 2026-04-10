# Server Transcode — RunPod Deployment Guide

Video transcoding worker ที่รันบน RunPod GPU Pod — ใช้ NVENC (GPU) สำหรับ encode video หลาย resolution

## Requirements

| Item | Requirement |
|------|-------------|
| **RunPod Template** | Ubuntu-based image ที่มี CUDA (เช่น `runpod/ubuntu:22.04-cuda12.1`) |
| **GPU** | NVIDIA RTX 4090, L4, A40, RTX A4000+ |
| **Container Disk** | 50 GB |
| **Volume Disk** | 0 GB (ไม่จำเป็น) |
| **SSH** | ✅ เปิด |
| **Jupyter** | ❌ ไม่ต้อง |
| **Environment Variables** | `NVIDIA_DRIVER_CAPABILITIES=all` **(จำเป็น!)** |

## Quick Start

### 1. สร้าง RunPod GPU Pod

1. ไปที่ [RunPod Console](https://www.runpod.io/console/pods) → **+ GPU Pod**
2. เลือก GPU: **RTX 4090** หรือ **L4** (24 GB VRAM)
3. เลือก Template: Ubuntu-based ที่มี CUDA
4. ⚠️ **กดปุ่ม Customize Deployment** → ใส่ Environment Variables:
   ```
   NVIDIA_DRIVER_CAPABILITIES = all
   ```
   > **สำคัญมาก!** ถ้าไม่ใส่ GPU จะ encode ไม่ได้ (NVENC blocked)
5. ตั้งค่า:
   - ☑ **SSH terminal access**
   - Container Disk: **50 GB**
6. กด **Deploy**

### 2. SSH เข้า Pod

```bash
# ใช้ SSH command จาก RunPod Console → Connect → SSH
ssh root@<pod-ip> -p <port> -i ~/.ssh/id_rsa
```

### 3. ติดตั้ง

```bash
# Clone repository
git clone https://github.com/zergolf1994/server-transcode-releases.git /workspace/server-transcode
cd /workspace/server-transcode

# รัน installer
chmod +x install-runpod.sh
./install-runpod.sh --mongodb-uri "mongodb+srv://user:pass@host/dbname"
```

### 4. เสร็จ! ✅

Worker จะเริ่มทำงานอัตโนมัติ — poll หา transcode jobs ทุก 5 วินาที

---

## Installation Options

```bash
# 1 worker (default)
./install-runpod.sh --mongodb-uri "mongodb+srv://..."

# 2 workers
./install-runpod.sh --mongodb-uri "mongodb+srv://..." -n 2

# กำหนด Storage ID/Path (local storage mode)
./install-runpod.sh \
  --mongodb-uri "mongodb+srv://..." \
  --storage-id "storage1" \
  --storage-path "/workspace/files"

# ข้าม FFmpeg installation (ถ้าลงเองแล้ว)
./install-runpod.sh --mongodb-uri "mongodb+srv://..." --skip-ffmpeg
```

## Management Commands

### ดู Status

```bash
# ดู log worker 1
tail -f /workspace/server-transcode/log/worker-1.log

# ดู log ทุก worker
tail -f /workspace/server-transcode/log/worker-*.log

# ดู PID ที่กำลังรัน
cat /workspace/server-transcode/pids/*.pid

# เช็คว่า process ยังรันอยู่
ps aux | grep server-transcode
```

### Stop / Start / Restart

```bash
# Stop ทุก worker
/workspace/server-transcode/stop.sh

# Start ทุก worker
/workspace/server-transcode/start.sh

# Restart
/workspace/server-transcode/stop.sh && /workspace/server-transcode/start.sh

# Stop ผ่าน installer
./install-runpod.sh --stop
```

### อัปเดต Binary

```bash
cd /workspace/server-transcode
./install-runpod.sh --mongodb-uri "mongodb+srv://..."
# installer จะ download binary ใหม่ + restart workers
```

## Pod Restart / Auto-Start

เมื่อ pod restart (เช่น interruptible ถูกเตะแล้วกลับมา) ต้อง start workers ใหม่:

### วิธี 1: Manual

```bash
/workspace/server-transcode/start.sh
```

### วิธี 2: Auto-start ผ่าน RunPod Settings

1. ไปที่ RunPod Console → Pod Settings → **Edit Pod**
2. ใส่ **Docker Command**:
   ```
   bash -c "sleep 5 && /workspace/server-transcode/start.sh && sleep infinity"
   ```
3. Save — ทุกครั้งที่ pod start จะรัน workers อัตโนมัติ

> ⚠️ **หมายเหตุ**: ถ้าใช้ **Container Disk** (ไม่ใช่ Network Volume) ข้อมูลจะหายเมื่อ pod ถูก **terminate** (ไม่ใช่ restart) — ต้อง install ใหม่

## Architecture

```
RunPod GPU Pod
├── /workspace/server-transcode/       # App directory
│   ├── server-transcode               # Go binary
│   ├── .env                           # Environment config
│   ├── install-runpod.sh              # Installer
│   ├── start.sh                       # Start workers
│   ├── stop.sh                        # Stop workers
│   ├── scripts/                       # SCP upload/download scripts
│   │   ├── scp-upload.js
│   │   ├── scp-upload-dir.js          # Directory upload (sprite/)
│   │   ├── scp-download.js
│   │   └── node_modules/
│   ├── pids/                          # PID files
│   │   ├── worker-1.pid
│   │   └── worker-2.pid
│   ├── log/                           # Worker logs
│   │   ├── worker-1.log
│   │   └── worker-2.log
│   └── download/                      # Temp files (auto-cleanup)
│       └── {slug}/
│           ├── file_original.mp4
│           ├── file_360.mp4
│           └── ...
```

## Flow (Remote Mode)

RunPod ไม่มี local storage → ใช้ **Remote Mode** (SCP upload/download):

```
1. Poll MongoDB → หา file ที่ต้อง transcode
2. SCP Download → ดาวน์โหลด file_original.mp4 จาก storage server
3. FFmpeg NVENC → encode 360p, 480p, 720p, 1080p (GPU accelerated)
4. SCP Upload → upload แต่ละ resolution กลับไป storage server
5. Sprite → สร้าง thumbnail sprite sheet + VTT (upload ทั้ง folder ทีเดียว)
6. Cloudflare Purge → ล้าง cache playlist.m3u8 (original + cloned files)
7. Cleanup → ลบ temp files
```

## ☁️ Cloudflare Cache Purge

หลัง transcode เสร็จ จะ purge cache `playlist.m3u8` อัตโนมัติ (ทั้ง original + cloned files)

### Settings ที่ต้องเพิ่มใน MongoDB (collection: `settings`)

| name | value | คำอธิบาย |
|------|-------|----------|
| `domain_content` | `cdn.vdohls.com` | Domain ของ content CDN (ไม่ต้องใส่ https://) |
| `cf_zone_id` | `be3d1b73...` | Cloudflare Zone ID (หาได้ที่ Dashboard → Overview) |
| `cf_api_token` | `cfut_ED4p...` | Cloudflare API Token (ต้องมี permission: Zone → Cache Purge → Purge) |

> ถ้าไม่ได้ตั้ง settings → จะ skip purge เงียบๆ ไม่ error

### URL ที่จะถูก purge

```
https://cdn.vdohls.com/{originalSlug}/playlist.m3u8
https://cdn.vdohls.com/{clonedSlug1}/playlist.m3u8
https://cdn.vdohls.com/{clonedSlug2}/playlist.m3u8
...
```

## Disk Usage

| ส่วน | ขนาด |
|------|------|
| OS + CUDA + PyTorch (base image) | ~20 GB |
| FFmpeg + Node.js + binary | ~1 GB |
| **Temp per job** (original + encode) | **ขึ้นอยู่กับขนาดวิดีโอ** |

### ตัวอย่าง Temp Disk ต่อ 1 job

| วิดีโอ | Original | Peak temp | 50 GB Container พอ? |
|--------|----------|-----------|---------------------|
| 5 นาที 1080p | ~500 MB | ~1 GB | ✅ |
| 30 นาที 1080p | ~2 GB | ~3 GB | ✅ |
| 1 ชม. 1080p | ~5 GB | ~8 GB | ✅ |
| 2 ชม. 1080p | ~10 GB | ~15 GB | ⚠️ ตึง |

> **หมายเหตุ**: Worker encode ทีละ resolution แล้วลบ temp ทันที ไม่เก็บทุก resolution พร้อมกัน

## GPU Performance

| GPU | H.264 NVENC 1080p | ราคา RunPod/hr |
|-----|-------------------|----------------|
| **L4** | ~300-500 fps | $0.22-0.39 |
| A40 | ~300-400 fps | $0.29-0.44 |
| RTX 4090 | ~400-600 fps | $0.34-0.69 |
| A100 | ~300-500 fps | $0.99+ |

> **L4 แนะนำ** — NVENC performance ใกล้เคียง A100 แต่ราคาถูกกว่ามาก

## Troubleshooting

### Worker ไม่ start

```bash
# เช็ค log
cat /workspace/server-transcode/log/worker-1.log

# ปัญหาที่พบบ่อย:
# - MONGODB_URI ผิด
# - Network ไม่สามารถเชื่อมต่อ MongoDB
```

### FFmpeg NVENC ไม่ทำงาน

```bash
# เช็คว่ามี NVENC
ffmpeg -encoders 2>/dev/null | grep nvenc

# เช็ค GPU
nvidia-smi

# ทดสอบ NVENC จริงๆ
ffmpeg -v error -f lavfi -i "color=c=black:s=256x256:d=1:r=25" \
  -pix_fmt yuv420p -c:v h264_nvenc -frames:v 1 -f null -
```

**ถ้าเจอ `OpenEncodeSessionEx failed: unsupported device`:**

→ Pod ไม่ได้ตั้ง `NVIDIA_DRIVER_CAPABILITIES=all`

1. ไปที่ RunPod Dashboard → Stop Pod
2. Edit Pod → Environment Variables → เพิ่ม `NVIDIA_DRIVER_CAPABILITIES=all`
3. Start Pod ใหม่

> ⚠️ ต้อง set env var **ตอนสร้าง Pod** หรือ **ก่อน Start** — ใช้ `export` ใน shell ไม่ช่วย

### Disk เต็ม

```bash
# เช็ค disk usage
df -h /workspace

# ลบ temp files ที่ค้าง
rm -rf /workspace/server-transcode/download/*

# ลบ log เก่า
rm -f /workspace/server-transcode/log/*.log
```

### Pod ถูก Preempt (Interruptible)

ไม่ต้องทำอะไร — เมื่อ pod กลับมา:
1. Worker จะ **resume** job ที่ค้างอยู่อัตโนมัติ (ถ้าตั้ง auto-start)
2. ถ้า job fail กลางทาง → resolution ที่ encode เสร็จแล้วยังใช้ได้ (graceful degradation)

## Cost Estimation

| Plan | ราคา/hr | ราคา/เดือน (24/7) | หมายเหตุ |
|------|---------|-------------------|---------|
| Interruptible (L4) | $0.22 | **~$158** | ✅ ถูกสุด อาจถูกเตะ |
| On-Demand (L4) | $0.39 | ~$281 | เสถียร |
| 3-Month Reserve (L4) | $0.34 | ~$245 | ผูกมัด 3 เดือน |

> **แนะนำ**: เริ่มจาก **Interruptible** — ถ้าถูกเตะบ่อยค่อยเปลี่ยนเป็น On-Demand
