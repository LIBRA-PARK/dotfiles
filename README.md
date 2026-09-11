# dotfiles

💻 My development environment setup & dotfiles

개발 도구별 설정 파일을 한 곳에서 관리하기 위한 저장소입니다.

## Structure

```
dotfiles/
├── cursor/    # Cursor 에디터 설정 (settings.json, keybindings.json 등)
├── vscode/    # VS Code 설정 (settings.json, keybindings.json, extensions 목록 등)
├── ghostty/   # Ghostty 터미널 설정 (config)
├── git/       # Git 설정 (.gitconfig, .gitignore_global 등)
└── shell/     # 셸 설정 (.zshrc, .bashrc, aliases 등)
```

## Usage

각 디렉토리의 설정 파일을 원래 위치에 심볼릭 링크로 연결해 사용합니다.

```bash
# 예시: Ghostty
ln -s ~/dotfiles/ghostty/config ~/.config/ghostty/config
```

| Tool    | 설정 파일 위치 (macOS)                              | 설정 파일 위치 (Linux)          |
| ------- | --------------------------------------------------- | ------------------------------- |
| Cursor  | `~/Library/Application Support/Cursor/User/`        | `~/.config/Cursor/User/`        |
| VS Code | `~/Library/Application Support/Code/User/`          | `~/.config/Code/User/`          |
| Ghostty | `~/.config/ghostty/config`                          | `~/.config/ghostty/config`      |
| Git     | `~/.gitconfig`                                      | `~/.gitconfig`                  |
| Shell   | `~/.zshrc`, `~/.bashrc`                             | `~/.zshrc`, `~/.bashrc`         |

## License

[MIT](./LICENSE)
