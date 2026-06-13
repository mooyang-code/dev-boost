.PHONY: all build server cli clean test \
        build-linux build-linux-server build-linux-cli \
        build-darwin build-darwin-server build-darwin-cli \
        build-windows build-windows-server build-windows-cli

# ===== 按项目修改以下变量 =====
SERVER_BIN := myapp
CLI_BIN    := myapp-cli
SERVER_PKG := ./cmd/server
CLI_PKG    := ./cmd/cli
# =============================

all: build

build: server cli

server:
	@echo ">>> Building server → $(SERVER_BIN)"
	go build -o $(SERVER_BIN) $(SERVER_PKG)
	@echo "    Done: ./$(SERVER_BIN)"

cli:
	@echo ">>> Building CLI → $(CLI_BIN)"
	go build -o $(CLI_BIN) $(CLI_PKG)
	@echo "    Done: ./$(CLI_BIN)"

# Linux amd64
build-linux: build-linux-server build-linux-cli

build-linux-server:
	@echo ">>> Building server (linux/amd64) → $(SERVER_BIN)-linux-amd64"
	GOOS=linux GOARCH=amd64 go build -o $(SERVER_BIN)-linux-amd64 $(SERVER_PKG)
	@echo "    Done: ./$(SERVER_BIN)-linux-amd64"

build-linux-cli:
	@echo ">>> Building CLI (linux/amd64) → $(CLI_BIN)-linux-amd64"
	GOOS=linux GOARCH=amd64 go build -o $(CLI_BIN)-linux-amd64 $(CLI_PKG)
	@echo "    Done: ./$(CLI_BIN)-linux-amd64"

# macOS (darwin) amd64 + arm64
build-darwin: build-darwin-server build-darwin-cli

build-darwin-server:
	@echo ">>> Building server (darwin/amd64) → $(SERVER_BIN)-darwin-amd64"
	GOOS=darwin GOARCH=amd64 go build -o $(SERVER_BIN)-darwin-amd64 $(SERVER_PKG)
	@echo "    Done: ./$(SERVER_BIN)-darwin-amd64"
	@echo ">>> Building server (darwin/arm64) → $(SERVER_BIN)-darwin-arm64"
	GOOS=darwin GOARCH=arm64 go build -o $(SERVER_BIN)-darwin-arm64 $(SERVER_PKG)
	@echo "    Done: ./$(SERVER_BIN)-darwin-arm64"

build-darwin-cli:
	@echo ">>> Building CLI (darwin/amd64) → $(CLI_BIN)-darwin-amd64"
	GOOS=darwin GOARCH=amd64 go build -o $(CLI_BIN)-darwin-amd64 $(CLI_PKG)
	@echo "    Done: ./$(CLI_BIN)-darwin-amd64"
	@echo ">>> Building CLI (darwin/arm64) → $(CLI_BIN)-darwin-arm64"
	GOOS=darwin GOARCH=arm64 go build -o $(CLI_BIN)-darwin-arm64 $(CLI_PKG)
	@echo "    Done: ./$(CLI_BIN)-darwin-arm64"

# Windows amd64
build-windows: build-windows-server build-windows-cli

build-windows-server:
	@echo ">>> Building server (windows/amd64) → $(SERVER_BIN)-windows-amd64.exe"
	GOOS=windows GOARCH=amd64 go build -o $(SERVER_BIN)-windows-amd64.exe $(SERVER_PKG)
	@echo "    Done: ./$(SERVER_BIN)-windows-amd64.exe"

build-windows-cli:
	@echo ">>> Building CLI (windows/amd64) → $(CLI_BIN)-windows-amd64.exe"
	GOOS=windows GOARCH=amd64 go build -o $(CLI_BIN)-windows-amd64.exe $(CLI_PKG)
	@echo "    Done: ./$(CLI_BIN)-windows-amd64.exe"

# 清理所有平台产物
clean:
	@echo ">>> Cleaning all binaries"
	rm -f $(SERVER_BIN) $(CLI_BIN)
	rm -f $(SERVER_BIN)-linux-amd64 $(CLI_BIN)-linux-amd64
	rm -f $(SERVER_BIN)-darwin-amd64 $(CLI_BIN)-darwin-amd64
	rm -f $(SERVER_BIN)-darwin-arm64 $(CLI_BIN)-darwin-arm64
	rm -f $(SERVER_BIN)-windows-amd64.exe $(CLI_BIN)-windows-amd64.exe

test:
	go test ./...
