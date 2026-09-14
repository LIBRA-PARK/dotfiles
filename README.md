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
├── setup/     # 새 머신 초기 세팅용 인스톨러 스크립트 (.sh)
│   ├── macos/     # macOS 전용
│   └── linux/     # Linux 전용
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

### Setup

새 머신의 초기 세팅을 진행하는 인스톨러 위저드 스크립트를 OS별로 `setup/<macos|linux>/` 에 보관합니다.

```bash
git clone git@github.com:LIBRA-PARK/dotfiles.git ~/dotfiles
bash ~/dotfiles/setup/macos/install.sh
```

체크리스트 TUI가 뜹니다. `↑`/`↓` 이동, `space` 선택, `a` 전체, `n` 해제, `enter` 설치, `q` 취소.
이미 설치된 항목은 `(이미 설치됨)` 으로 표시되고 기본 해제됩니다.

```bash
bash install.sh --list              # 항목과 현재 설치 상태만 확인
bash install.sh --dry-run           # 변경 없이 실행 내용만 출력
bash install.sh --all               # 전체 항목을 질문 없이 설치
bash install.sh --only node,claude  # 특정 항목만 설치
```

| key           | 항목                     | 내용                                              |
| ------------- | ------------------------ | ------------------------------------------------- |
| `xcode`       | Xcode Command Line Tools | git, 컴파일러 등 기본 개발 도구                   |
| `homebrew`    | Homebrew                 | 설치 + `.zprofile` 에 `brew shellenv` 등록         |
| `brewfile`    | Brewfile 패키지          | ripgrep, fzf, bat 등 CLI 도구 모음                |
| `ghostty`     | Ghostty                  | `brew install --cask ghostty`                     |
| `ohmyzsh`     | Oh My Zsh                | `--unattended` 로 설치 (셸 변경은 별도 항목)      |
| `node`        | Node.js                  | fnm + 최신 LTS, `.zshrc` 에 `fnm env` 등록        |
| `claude`      | Claude Code              | Anthropic 공식 CLI                                |
| `codex`       | Codex                    | `npm install -g @openai/codex`                    |
| `herdr`       | Herdr                    | herdr.dev 설치 스크립트                           |
| `antigravity` | Antigravity              | Google Antigravity CLI                            |
| `sdkman`      | SDKMAN                   | JVM 툴체인 매니저                                 |
| `dotfiles`    | dotfiles 링크            | 설정 파일 심볼릭 링크 + 에디터 확장 설치          |
| `shell`       | 기본 셸                  | `chsh` 로 zsh 전환                                |
| `macos`       | macOS 기본 설정          | 키 반복 속도, Finder, Dock, 스크린샷 위치         |

항목은 위 순서대로 설치되므로 의존 관계(Homebrew → fnm → Codex)가 자동으로 맞춰집니다.
모든 항목은 여러 번 실행해도 안전하며, 홈에 기존 설정 파일이 있으면 `.bak.<타임스탬프>` 로 백업한 뒤 링크합니다.
레포에 아직 없는 설정 파일은 조용히 건너뜁니다.

설치할 CLI 패키지는 [`setup/macos/Brewfile`](./setup/macos/Brewfile) 을 직접 수정해 관리합니다.

> macOS 기본 `/bin/bash` 는 3.2 이므로 스크립트는 bash 3.2 문법만 사용합니다.

## License

[MIT](./LICENSE)
