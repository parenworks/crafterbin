# CrafterBin

A temporary file sharing service written in Common Lisp. Inspired by [0x0.st](https://0x0.st).

## Features

- **File upload** via `curl` / HTTP POST (multipart/form-data)
- **URL fetch** - store a remote file by URL
- **Secret URLs** - longer, hard-to-guess IDs
- **Configurable expiry** - per-upload or via retention curve
- **Size-based retention curve** - small files live longer, large files expire sooner
- **Management tokens** - delete files or update expiry via `X-Token` header
- **Background cleanup** - periodic sweep removes expired files
- **Custom filenames** - append `/filename.ext` to any URL

## Retention Curve

```text
retention = min_age + (max_age - min_age) * (1 - file_size / max_size)^3
```

Default: 7-day minimum, 365-day maximum, 512 MiB max file size.

## Usage

```bash
# Build
make

# Run locally
./crafterbin --host 127.0.0.1 --port 8080 --storage /mnt/crafterbin/storage

# Deploy (matches systemd service paths)
make deploy

# Install to /usr/local/bin
sudo make install
```

## CLI Options

```text
  -H, --host ADDR            Bind address (default: 127.0.0.1)
  -P, --port PORT            Listen port (default: 8080)
  -s, --storage DIR          Storage directory (default: /mnt/crafterbin/storage)
      --min-age DAYS         Minimum retention in days (default: 7)
      --max-age DAYS         Maximum retention in days (default: 365)
      --max-size MIB         Maximum upload size in MiB (default: 512)
      --cleanup-interval SECS  Cleanup sweep interval (default: 60)
      --base-url URL         Public base URL for generated links
  -h, --help                 Show help
```

## cURL Examples

```bash
# Upload a file
curl -F'file=@yourfile.png' https://crafterbin.glennstack.dev

# Upload from URL
curl -F'url=http://example.com/image.jpg' https://crafterbin.glennstack.dev

# Secret URL
curl -F'file=@yourfile.png' -Fsecret= https://crafterbin.glennstack.dev

# Set expiry (24 hours)
curl -F'file=@yourfile.png' -Fexpires=24 https://crafterbin.glennstack.dev

# Delete (use token from X-Token response header)
curl -Ftoken=TOKEN -Fdelete= https://crafterbin.glennstack.dev/ID

# Update expiry
curl -Ftoken=TOKEN -Fexpires=72 https://crafterbin.glennstack.dev/ID
```

## Systemd Service

```ini
[Unit]
Description=CrafterBin Text Sharing Service
After=network.target

[Service]
Type=simple
User=glenn
WorkingDirectory=/home/glenn/crafterbin
ExecStart=/home/glenn/crafterbin/crafterbin -H=127.0.0.1 -P=8080 -s=/mnt/crafterbin/storage --base-url=https://crafterbin.glennstack.dev
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

## Requirements

- SBCL
- Quicklisp
- Libraries: hunchentoot, ironclad, bordeaux-threads, unix-opts, drakma, trivial-mimes, babel, alexandria, local-time, jzon

## License

MIT
