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
├── sdkman/    # 프로젝트별 SDKMAN 설정 (.sdkmanrc)
│   ├── work/      # 회사 프로젝트
│   └── personal/  # 개인 프로젝트
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
| SDKMAN  | `<project>/.sdkmanrc`                               | `<project>/.sdkmanrc`           |

### SDKMAN

프로젝트별 `.sdkmanrc`를 `sdkman/<work|personal>/<project>/.sdkmanrc` 형태로 보관합니다.

```bash
# 예시: 회사 프로젝트
ln -s ~/dotfiles/sdkman/work/<project>/.sdkmanrc ~/work/<project>/.sdkmanrc
cd ~/work/<project> && sdk env
```

> ⚠️ 버전 정보(`java=21.0.4-tem` 등)처럼 민감하지 않은 설정만 커밋합니다.
> 사내 저장소 URL, 토큰, 계정 정보 등은 절대 포함하지 마세요.

## License

[MIT](./LICENSE)
