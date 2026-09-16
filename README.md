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
├── font/      # 코딩 폰트 (JetBrains Mono + D2Coding, Nerd Font 패치본)
│   ├── jetbrains-mono/  # 기본 폰트
│   └── d2coding/        # 한글 fallback
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
| Fonts   | `~/Library/Fonts/`                                  | `~/.local/share/fonts/`         |

### Fonts

`font/` 에 폰트 파일을 직접 커밋해 둡니다. 새 머신에서 다운로드 없이 바로 같은
화면을 볼 수 있고, 버전이 레포에 고정되므로 머신마다 렌더링이 달라지지 않습니다.

| 역할     | 패밀리명 (설정에 쓰는 이름)  | 한글 | Nerd 아이콘 |
| -------- | ---------------------------- | ---- | ----------- |
| 기본     | `JetBrainsMono Nerd Font`    | ✗    | ✓           |
| fallback | `D2KodingLigature Nerd Font` | ✓    | ✓           |

영문·기호는 JetBrains Mono 가, 한글은 D2Coding 이 담당합니다. 둘 다 Nerd Fonts
패치본이라 Powerline / Font Awesome / Codicon / Devicon / Material / Octicon
아이콘이 양쪽에 모두 들어 있어, 어느 쪽으로 넘어가도 아이콘이 깨지지 않습니다.

> ⚠️ 패치본의 실제 패밀리명은 **`D2Koding`** 입니다 (`D2Coding` 아님).
> Nerd Fonts 가 상표 문제로 이름을 바꿔 패치하기 때문입니다.
> 설정에는 `D2KodingLigature Nerd Font` 를 그대로 쓰세요.

```bash
bash ~/dotfiles/font/install.sh              # 홈 폰트 디렉토리로 심볼릭 링크
bash ~/dotfiles/font/install.sh --list       # 현재 설치 상태 확인
bash ~/dotfiles/font/install.sh --dry-run    # 변경 없이 실행 내용만 출력
bash ~/dotfiles/font/install.sh --copy       # 링크 대신 복사
bash ~/dotfiles/font/install.sh --uninstall  # 이 스크립트가 설치한 것만 제거
```

macOS 초기 세팅 인스톨러의 `font` 항목이 이 스크립트를 그대로 호출합니다.

#### 앱별 설정

Linux 는 `font/fonts.conf` 가 `~/.config/fontconfig/conf.d/` 에 링크되어
시스템 전역에서 fallback 이 동작합니다. macOS 는 fontconfig 를 쓰지 않으므로
아래처럼 앱마다 순서를 지정해야 합니다.

**Ghostty** — `font-family` 를 여러 번 적으면 적은 순서대로 fallback 됩니다.

```ini
font-family = "JetBrainsMono Nerd Font"
font-family = "D2KodingLigature Nerd Font"
font-size = 14
```

**VS Code / Cursor** — `settings.json`

```json
{
  "editor.fontFamily": "'JetBrainsMono Nerd Font', 'D2KodingLigature Nerd Font', monospace",
  "editor.fontLigatures": true,
  "terminal.integrated.fontFamily": "'JetBrainsMono Nerd Font', 'D2KodingLigature Nerd Font', monospace"
}
```

**IntelliJ IDEA** — `Settings → Editor → Font`

- Font: `JetBrainsMono Nerd Font`
- Fallback font: `D2KodingLigature Nerd Font`

아이콘이 잘려 보이는 앱에서는 `NerdFontMono` 변형을 대신 쓰면 됩니다.
받는 방법은 [`font/VERSIONS.md`](./font/VERSIONS.md) 를 참고하세요.

#### 업데이트 / 출처

버전, 체크섬, 업데이트 절차는 [`font/VERSIONS.md`](./font/VERSIONS.md) 에 있습니다.
현재 **Nerd Fonts v3.5.1** 기준이며, 두 폰트 모두 OFL-1.1 이라 재배포에 문제가 없습니다.

```bash
cd ~/dotfiles/font && sha256sum -c SHA256SUMS   # 커밋된 파일 무결성 확인
```

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
| `font`        | Fonts                    | JetBrains Mono + D2Coding (Nerd Font 아이콘 포함) |
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
