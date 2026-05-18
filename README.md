# CCQuick

<img src="https://github.com/hashibit/ccquick/raw/main/docs/assets/icon.png" width="80" alt="CCQuick Icon" />

A macOS menu bar application that executes AI-powered tasks via Claude Code, triggered by a global keyboard shortcut.

## Features

- **Global Hotkey**: Invoke the input window from anywhere with a single keystroke
- **Background Execution**: Run Claude Code tasks asynchronously without blocking the UI
- **System Notifications**: Receive results via native macOS notifications
- **Task History**: View previous tasks and their outputs
- **Dual Execution Modes**: Support for both Claude subscriptions and Anthropic CodingPlan API
- **Sandboxed Execution**: Secure file and command execution restricted to project directories

## Screenshots

<img src="https://github.com/hashibit/ccquick/raw/main/docs/assets/screenshot-20260513-115509.png" width="320" />
<img src="https://github.com/hashibit/ccquick/raw/main/docs/assets/screenshot-20260513-115348.png" width="320" />
<img src="https://github.com/hashibit/ccquick/raw/main/docs/assets/screenshot-20260513-115414.png" width="320" />
<img src="https://github.com/hashibit/ccquick/raw/main/docs/assets/screenshot-20260513-115430.png" width="320" />

## Requirements

- macOS 12.0 or later
- Swift 5.9+
- Xcode 14.0+

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/hashibit/ccquick.git
cd ccquick

# Build
xcodebuild -scheme CCQuick -configuration Release build

# Or use the Makefile
make build
```

### Run

The application runs as a menu bar icon. After building, drag the compiled app to `/Applications`.

## Configuration

1. Open the application
2. Access Settings via the menu bar icon
3. Choose execution account:
   - **Claude Subscription**: Uses local Claude CLI
   - **CodingPlan API**: Requires Anthropic API key
4. Grant accessibility permissions when prompted (required for global hotkey)

## Architecture

```
CCQuick/
├── App/                    # Application entry point
├── MenuBar/               # Status bar icon and menu
├── InputWindow/           # Global hotkey trigger window
├── Task/                  # Task execution and management
├── Notifications/         # System notification handling
├── History/              # Task history and UI
└── Settings/             # Configuration storage
```

## How It Works

1. Press the global hotkey (configurable)
2. Enter your task prompt
3. The app launches Claude Code in the background
4. Results are delivered via system notification
5. Access full task history from the menu bar

## Security

- **File Access Restriction**: File operations (Read/Write) are restricted to project working directories
- **Command Validation**: Bash commands are checked to prevent direct access to files outside the sandbox
- **Limited Tool Set**: Only 4 tools available (Bash, Read, Write, Skill) — no arbitrary code execution
- **Trust Model**: Bash has full system access, so security depends on trusting Claude API responses
- **Local Configuration**: API keys and settings stored in `~/.ccquick/settings.json` (not encrypted)
- **Open Source**: Full transparency on execution and data handling

## Technical Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI + AppKit
- **Concurrency**: Swift async/await
- **Storage**: JSON-based task metadata
- **Notifications**: Native UserNotifications framework
- **Package Manager**: Swift Package Manager

## Development

```bash
# Build and run
make build
make run

# Run tests
xcodebuild -scheme CCQuick test
```

## Troubleshooting

### Global hotkey not working
- Check macOS Settings > Security & Privacy > Accessibility
- Ensure CCQuick has accessibility permissions

### Tasks not executing
- Verify your execution account is configured (Settings)
- For Claude subscription: ensure `claude` CLI is installed
- For CodingPlan API: verify your API key is valid

## License

MIT License - see [LICENSE](LICENSE) file for details

## Author

Hashi Bitton
