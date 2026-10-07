# dotfiles

💻 My development environment setup & dotfiles

개발 도구별 설정 파일을 한 곳에서 관리하기 위한 저장소입니다.

## Structure

루트는 세 가지 역할로 나눕니다. **데이터**(applications, assets, themes)는 읽히기만 하고,
**실행**은 모두 scripts 에서 합니다.

```
dotfiles/
├── applications/   # 앱별 설정 파일 (홈에 심볼릭 링크되는 원본)
│   ├── claude/       # Claude Code statusline
│   ├── cursor/       # Cursor settings.json, keybindings.<os>.json, extensions.txt
│   ├── vscode/       # VS Code settings.json, keybindings.<os>.json, extensions.txt
│   ├── ghostty/      # Ghostty config
│   ├── git/          # .gitconfig, .gitignore_global
│   ├── shell/        # .zshrc, .zprofile, aliases
│   ├── homebrew/     # Brewfile (설치할 CLI 패키지 목록)
│   └── sdkman/       # 프로젝트별 .sdkmanrc (work/, personal/)
├── assets/
│   └── fonts/        # 코딩 폰트 (JetBrains Mono + D2Coding, Nerd Font 패치본)
├── themes/         # 앱별 테마 값 (themes/README.md 참고)
└── scripts/        # 실행 스크립트
    ├── dotfiles.sh   # 단일 진입점 (TUI 메뉴)
    ├── lib/          # 공용 헬퍼(common.sh), TUI(ui.sh), OS 무관 작업 (font, theme, themes-index, ssh)
    ├── macos/        # macOS 초기 세팅 (setup.sh)
    ├── windows/      # Windows 초기 세팅 (setup.sh, Git Bash 에서 실행)
    └── linux/        # Linux 초기 세팅 (예정)
```

## Usage

모든 작업은 `scripts/dotfiles.sh` 한 곳에서 시작합니다.

```bash
git clone git@github.com:LIBRA-PARK/dotfiles.git ~/dotfiles
bash ~/dotfiles/scripts/dotfiles.sh                  # TUI 메뉴
bash ~/dotfiles/scripts/dotfiles.sh setup [옵션]     # OS 별 초기 세팅
bash ~/dotfiles/scripts/dotfiles.sh font [옵션]      # 폰트 설치/확인
bash ~/dotfiles/scripts/dotfiles.sh theme [테마]     # 테마 적용 (themes/README.md 참고)
bash ~/dotfiles/scripts/dotfiles.sh themes-index     # themes/README.md 인덱스 갱신
bash ~/dotfiles/scripts/dotfiles.sh ssh [명령]       # SSH 호스트 등록, 헬스체크, SFTP 설정
```

메뉴에서 고른 작업이 끝나면 메뉴로 돌아옵니다. 옵션은 하위 스크립트에 그대로 넘어가고,
하위 스크립트(`scripts/lib/*.sh`, `scripts/<os>/setup.sh`)는 단독으로 실행해도 됩니다.

#### TUI 와 gum

TUI 는 [gum](https://github.com/charmbracelet/gum) 으로 그립니다 (Nord 색상).
gum 이 없으면 경고와 함께 현재 OS 에 맞는 설치 방법을 보여 준 뒤, 기본 bash TUI 로 계속합니다.
새 머신은 Homebrew 조차 없는 상태라 gum 없이도 끝까지 동작해야 하기 때문입니다.

| OS                    | 설치                                                       |
| --------------------- | ---------------------------------------------------------- |
| macOS                 | `brew install gum` (Brewfile 에 포함)                      |
| Linux                 | apt/dnf 는 Charm 저장소 등록 후 설치, `pacman -S gum`, `apk add gum` |
| Windows (Git Bash)    | `winget install charmbracelet.gum` 또는 `scoop install charm-gum` |

`DOTFILES_NO_GUM=1` 을 주면 gum 이 있어도 기본 TUI 를 씁니다. 화면 컴포넌트는 `scripts/lib/ui.sh` 에 있습니다.

`applications/` 의 설정 파일은 초기 세팅의 `dotfiles` 항목이 원래 위치에 심볼릭 링크합니다.

| Tool        | 설정 파일 위치 (macOS)                       | 설정 파일 위치 (Linux)            | 설정 파일 위치 (Windows)   |
| ----------- | -------------------------------------------- | --------------------------------- | -------------------------- |
| Cursor      | `~/Library/Application Support/Cursor/User/` | `~/.config/Cursor/User/`          | `%APPDATA%\Cursor\User\`   |
| VS Code     | `~/Library/Application Support/Code/User/`   | `~/.config/Code/User/`            | `%APPDATA%\Code\User\`     |
| Ghostty     | `~/.config/ghostty/config`                   | `~/.config/ghostty/config`        | —                          |
| Claude Code | `~/.claude/statusline-command.sh`            | `~/.claude/statusline-command.sh` | —                          |
| Git         | `~/.gitconfig`                               | `~/.gitconfig`                    | `%USERPROFILE%\.gitconfig` |
| Shell       | `~/.zshrc`, `~/.bashrc`                      | `~/.zshrc`, `~/.bashrc`           | —                          |
| SDKMAN      | `<project>/.sdkmanrc`                        | `<project>/.sdkmanrc`             | —                          |
| Fonts       | `~/Library/Fonts/`                           | `~/.local/share/fonts/`           | 수동 설치                  |

`—` 는 초기 세팅 스크립트가 아직 링크하지 않는 항목입니다.
Cursor / VS Code 의 OS 별 위치는 `scripts/lib/common.sh` 의 `app_config_dir` 이 정합니다.

### Fonts

`assets/fonts/` 에 폰트 파일을 직접 커밋해 둡니다. 새 머신에서 다운로드 없이 바로 같은
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
bash ~/dotfiles/scripts/dotfiles.sh font              # 홈 폰트 디렉토리로 심볼릭 링크
bash ~/dotfiles/scripts/dotfiles.sh font --list       # 현재 설치 상태 확인
bash ~/dotfiles/scripts/dotfiles.sh font --dry-run    # 변경 없이 실행 내용만 출력
bash ~/dotfiles/scripts/dotfiles.sh font --copy       # 링크 대신 복사
bash ~/dotfiles/scripts/dotfiles.sh font --uninstall  # 이 스크립트가 설치한 것만 제거
```

macOS 초기 세팅의 `font` 항목도 같은 스크립트(`scripts/lib/font.sh`)를 호출합니다.

#### 앱별 설정

Linux 는 `assets/fonts/fonts.conf` 가 `~/.config/fontconfig/conf.d/` 에 링크되어
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
받는 방법은 [`assets/fonts/VERSIONS.md`](./assets/fonts/VERSIONS.md) 를 참고하세요.

#### 업데이트 / 출처

버전, 체크섬, 업데이트 절차는 [`assets/fonts/VERSIONS.md`](./assets/fonts/VERSIONS.md) 에 있습니다.
현재 **Nerd Fonts v3.5.1** 기준이며, 두 폰트 모두 OFL-1.1 이라 재배포에 문제가 없습니다.

```bash
cd ~/dotfiles/assets/fonts && sha256sum -c SHA256SUMS   # 커밋된 파일 무결성 확인
```

### SSH / SFTP

서버 접속 정보를 손으로 적는 대신 `scripts/lib/ssh.sh` 가 묻고, **실제로 연결되는지 확인한 뒤에만** 저장합니다.
macOS, Linux, Windows(Git Bash)에서 같은 명령을 씁니다.

```bash
bash ~/dotfiles/scripts/dotfiles.sh ssh                  # 메뉴
bash ~/dotfiles/scripts/dotfiles.sh ssh add              # 호스트 등록
bash ~/dotfiles/scripts/dotfiles.sh ssh list             # 등록된 호스트 목록
bash ~/dotfiles/scripts/dotfiles.sh ssh check [호스트]   # 헬스체크 (--all 은 전부)
bash ~/dotfiles/scripts/dotfiles.sh ssh sftp [호스트]    # <프로젝트>/.vscode/sftp.json 생성
```

`-n`/`--dry-run` 은 설정 파일을 쓰지 않고(연결 확인은 실제로 합니다), `-y`/`--yes` 는 확인 질문을 건너뜁니다.
`add` 는 `--name --host --user --port --key`, `sftp` 는 `--dir --remote` 로 값을 미리 줄 수 있습니다.

헬스체크는 세 단계로 나뉘어 어디서 막혔는지 보여 줍니다.

| 단계        | 확인하는 것                              | 실패했을 때 볼 곳                  |
| ----------- | ---------------------------------------- | ---------------------------------- |
| 서버 응답   | 주소·포트에서 SSH 서버가 응답하는지      | 주소, 포트, 방화벽, VPN            |
| SSH 인증    | 키로 로그인되는지                        | 서버의 `~/.ssh/authorized_keys`    |
| SFTP        | SFTP 가 열리는지 (`sftp` 는 서버 경로까지) | 서버의 `Subsystem sftp` 설정       |

- **`add`** — 처음 보는 서버면 호스트 키 지문을 보여 주고 신뢰할지 묻습니다. 키가 서버에 없으면
  공개 키를 등록합니다(이때만 서버 비밀번호가 필요하고, `ssh` 가 직접 묻습니다).
  세 단계를 통과하면 `~/.ssh/config` 끝에 `Host` 블록을 덧붙입니다. 기존 내용은 건드리지 않고 먼저 백업합니다.
- **`sftp`** — [natizyskunk.sftp](https://open-vsx.org/extension/Natizyskunk/sftp) 확장이 읽는 설정 파일을 만듭니다.
  서버 경로에 실제로 들어갈 수 있는지 확인한 뒤 쓰고, git 저장소 안이면 `.gitignore` 에 추가할지 묻습니다.
- **비밀번호는 받거나 저장하지 않습니다.** 접속 정보도 이 레포가 아니라 `~/.ssh/config` 와
  각 프로젝트의 `.vscode/sftp.json` 에만 남습니다.

### SDKMAN

프로젝트별 `.sdkmanrc`를 `applications/sdkman/<work|personal>/<project>/.sdkmanrc` 형태로 보관합니다.

```bash
# 예시: 회사 프로젝트
ln -s ~/dotfiles/applications/sdkman/work/<project>/.sdkmanrc ~/work/<project>/.sdkmanrc
cd ~/work/<project> && sdk env
```

> ⚠️ 버전 정보(`java=21.0.4-tem` 등)처럼 민감하지 않은 설정만 커밋합니다.
> 사내 저장소 URL, 토큰, 계정 정보 등은 절대 포함하지 마세요.

### Setup

새 머신의 초기 세팅은 OS 별로 `scripts/<macos|windows|linux>/setup.sh` 에 있습니다.
`dotfiles.sh setup` 이 현재 OS 를 감지해 맞는 스크립트를 실행합니다.

```bash
git clone git@github.com:LIBRA-PARK/dotfiles.git ~/dotfiles
bash ~/dotfiles/scripts/dotfiles.sh setup
```

체크리스트 TUI가 뜹니다. `↑`/`↓` 이동, `space` 선택, `enter` 확인, `esc` 취소
(gum 이 없을 때의 기본 TUI 는 `a` 전체, `n` 해제도 지원). 고른 뒤 한 번 더 확인하고 설치합니다.
이미 설치된 항목은 `[설치됨]` 으로 표시되고 기본 해제됩니다.

```bash
bash scripts/dotfiles.sh setup --list              # 항목과 현재 설치 상태만 확인
bash scripts/dotfiles.sh setup --dry-run           # 변경 없이 실행 내용만 출력
bash scripts/dotfiles.sh setup --all               # 전체 항목을 질문 없이 설치
bash scripts/dotfiles.sh setup --only node,claude  # 특정 항목만 설치
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
| `sdkman`      | SDKMAN                   | JVM 툴체인 매니저 (bash 4 이상이 없으면 Homebrew 로 먼저 설치) |
| `font`        | Fonts                    | JetBrains Mono + D2Coding (Nerd Font 아이콘 포함) |
| `dotfiles`    | dotfiles 링크            | `applications/` 심볼릭 링크 + 에디터 확장 설치    |
| `shell`       | 기본 셸                  | `chsh` 로 zsh 전환                                |
| `macos`       | macOS 기본 설정          | 키 반복 속도, Finder, Dock, 스크린샷 위치         |

항목은 위 순서대로 설치되므로 의존 관계(Homebrew → fnm → Codex)가 자동으로 맞춰집니다.
모든 항목은 여러 번 실행해도 안전하며, 홈에 기존 설정 파일이 있으면 `.bak.<타임스탬프>` 로 백업한 뒤 링크합니다.
이 레포를 가리키던 옛 링크(디렉토리 이동으로 깨진 것 포함)는 백업 없이 새 경로로 교체합니다.
레포에 아직 없는 설정 파일은 조용히 건너뜁니다.

설치할 CLI 패키지는 [`applications/homebrew/Brewfile`](./applications/homebrew/Brewfile) 을 직접 수정해 관리합니다.

> macOS 기본 `/bin/bash` 는 3.2 이므로 스크립트는 bash 3.2 문법만 사용합니다.

#### Windows

Windows 는 체크리스트 없이 **설정 파일 링크와 에디터 확장 설치**만 하고, 테마 적용에 필요한 `jq` 가
있는지 확인합니다 (없으면 `winget install jqlang.jq`). Git Bash 에서 실행합니다.

> PowerShell / cmd 의 `bash` 는 Git Bash 가 아니라 WSL 입니다. 거기서 실행하면 Linux 로 동작해
> WSL 홈에 적용되므로 스크립트가 경고를 띄웁니다. PowerShell 에서 꼭 실행해야 하면
> `& "C:\Program Files\Git\bin\bash.exe" scripts/dotfiles.sh` 처럼 Git Bash 를 직접 지정합니다.

1. **개발자 모드 켜기** — 설정 → 시스템 → 개발자용 → 개발자 모드.
   관리자 권한 없이 심볼릭 링크를 만들 수 있게 됩니다. (또는 Git Bash 를 관리자 권한으로 실행)
2. **Git for Windows, Cursor / VS Code 설치** — 에디터 설치 화면의 "PATH 에 추가" 를 켜 둡니다.
3. **Git Bash 에서 실행**

```bash
git clone git@github.com:LIBRA-PARK/dotfiles.git ~/dotfiles
bash ~/dotfiles/scripts/dotfiles.sh setup --list      # 링크 대상과 현재 상태만 확인
bash ~/dotfiles/scripts/dotfiles.sh setup --dry-run   # 변경 없이 실행 내용만 출력
bash ~/dotfiles/scripts/dotfiles.sh setup             # 링크 + 확장 설치
```

Git Bash 의 `ln -s` 는 기본 동작이 복사라서, 스크립트가 `MSYS=winsymlinks:nativestrict` 로
진짜 심볼릭 링크를 만들게 합니다. 권한이 없으면 복사로 넘어가지 않고 실패합니다.
복사본은 `git pull` 을 따라가지 않기 때문입니다.

#### OS 간 동기화

한쪽에서 `git commit` / `git push`, 다른 쪽에서 `git pull` 하면 링크를 통해 바로 반영됩니다.

- **줄바꿈** — `.gitattributes` 가 텍스트 파일을 어느 OS 에서든 LF 로 체크아웃합니다.
- **settings.json** — OS 와 무관한 값만 둡니다. JDK 경로 같은 절대 경로는 넣지 않고
  기기마다 `JAVA_HOME` 으로 맞춥니다. `terminal.integrated.defaultProfile.osx` / `.windows`
  처럼 OS 접미사가 붙은 키는 한 파일에 같이 둬도 됩니다.
- **keybindings** — 수식키가 OS 마다 달라 `keybindings.macos.json` / `keybindings.windows.json`
  으로 나눕니다. 각 OS 의 setup 이 맞는 파일을 `keybindings.json` 으로 링크합니다.
- **확장** — 설치하거나 지운 뒤 `cursor --list-extensions` 로 `extensions.txt` 를 갱신합니다.

## License

[MIT](./LICENSE)
