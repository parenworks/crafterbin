# CrafterBin Makefile
# Builds a standalone SBCL executable

SBCL := sbcl
TARGET := crafterbin
BUILD_SCRIPT := build.lisp
PREFIX := /usr/local
BINDIR := $(PREFIX)/bin

# Deploy paths (match existing systemd service)
DEPLOY_DIR := /home/glenn/crafterbin
STORAGE_DIR := /mnt/crafterbin/storage

.PHONY: all build clean install uninstall deploy help

all: build

build: $(TARGET)

$(TARGET): $(BUILD_SCRIPT) crafterbin.asd $(wildcard src/*.lisp)
	$(SBCL) --dynamic-space-size 1024 --non-interactive --load $(BUILD_SCRIPT)

run: $(TARGET)
	./$(TARGET) --host 127.0.0.1 --port 8080 --storage $(STORAGE_DIR)

clean:
	rm -f $(TARGET)
	rm -rf ~/.cache/common-lisp/sbcl-*/**/crafterbin/

install: $(TARGET)
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)

# Deploy to the existing crafterbin service location
deploy: $(TARGET)
	install -d $(DEPLOY_DIR)
	install -d $(STORAGE_DIR)
	install -m 755 $(TARGET) $(DEPLOY_DIR)/$(TARGET)
	@echo "Deployed to $(DEPLOY_DIR)/$(TARGET)"
	@echo "Storage at $(STORAGE_DIR)"
	@echo "Restart with: sudo systemctl restart crafterbin"

help:
	@echo "CrafterBin - Temporary File Sharing Service"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build executable (default)"
	@echo "  build    - Build standalone executable"
	@echo "  run      - Run locally"
	@echo "  install  - Install to $(BINDIR)"
	@echo "  deploy   - Deploy to $(DEPLOY_DIR) (match systemd service)"
	@echo "  clean    - Remove build artifacts"
	@echo "  help     - Show this help"
