# Themes

앱별 테마 값을 모아 두는 곳입니다. 앞으로 `setting.sh` 가 이 디렉토리를 읽어
고른 테마를 각 앱에 한 번에 적용하게 됩니다.

<!-- INDEX:START -->

| 앱 | 적용 방식 | nord |
| --- | --- | :---: |
| [Cursor](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/cursor/app.conf) | `merge-json` | [✓](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/cursor/nord.json) |
| [Ghostty](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/ghostty/app.conf) | `link` | [✓](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/ghostty/nord.conf) |
| [MobaXterm](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/mobaxterm/app.conf) | `manual` | [✓](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/mobaxterm/nord.mxtcolors) |
| [Orca](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/orca/app.conf) | `merge-json` | [✓](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/orca/nord.json) |
| [VS Code](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/vscode/app.conf) | `merge-json` | [✓](https://github.com/LIBRA-PARK/dotfiles/blob/main/themes/vscode/nord.json) |

앱 이름을 누르면 적용 정보(app.conf), ✓ 를 누르면 테마 파일로 이동합니다. — 는 아직 없는 조합입니다.

<!-- INDEX:END -->

---

## 구조

```
themes/
├── README.md        # 이 문서 (아래 인덱스는 index.sh 가 생성)
├── index.sh         # 앱 x 테마 인덱스 생성
├── cursor/
│   ├── app.conf     # 적용 정보: 대상 경로, 적용 방식
│   └── nord.json    # 테마 파일: <테마>.<THEME_EXT>
├── ghostty/
│   ├── app.conf
│   └── nord.conf
├── mobaxterm/
│   ├── app.conf
│   └── nord.mxtcolors
├── orca/
│   ├── app.conf
│   └── nord.json
└── vscode/
    ├── app.conf
    └── nord.json
```

- **앱 디렉토리** — `app.conf` 가 있는 하위 디렉토리 하나가 앱 하나입니다.
- **테마 파일** — `<테마>.<THEME_EXT>`. 같은 테마는 모든 앱에서 같은 이름을 씁니다.
  `setting.sh nord` 는 각 앱의 `nord.*` 를 찾아 적용합니다.
- **테마 값만** 둡니다. 폰트처럼 테마와 무관한 공통 설정은 각 앱의 기본 설정
  (`ghostty/config`, `cursor/settings.json` 등)에 둡니다.

## app.conf

`setting.sh` 가 `source` 하는 셸 변수 파일입니다.

| 변수           | 뜻                                                  |
| -------------- | --------------------------------------------------- |
| `APP_NAME`     | 표시 이름                                           |
| `THEME_EXT`    | 테마 파일 확장자                                    |
| `PLATFORM`     | 적용 가능한 OS (`macos`, `linux`, `windows` 공백 구분) |
| `APPLY_METHOD` | 적용 방식 (아래 표)                                 |
| `TARGET`       | 적용 대상 파일 경로                                 |
| `JSON_PATH`    | `merge-json` 일 때 병합할 위치 (jq 경로)            |
| `NOTE`         | 적용 후 안내 문구                                   |

| `APPLY_METHOD` | 동작                                            | 사용 앱          |
| -------------- | ----------------------------------------------- | ---------------- |
| `link`         | 테마 파일을 `TARGET` 에 심볼릭 링크             | Ghostty          |
| `merge-json`   | 테마 JSON 을 `TARGET` 의 `JSON_PATH` 에 병합 (jq) | Cursor, VS Code, Orca |
| `manual`       | 자동 적용 불가. `NOTE` 안내만 출력              | MobaXterm        |

`merge-json` 테마 파일은 jq 로 읽으므로 **주석 없는 순수 JSON** 이어야 합니다.

## 앱별 메모

- **Ghostty** — `ghostty/config` 가 `theme = Nord` 를 기본값으로 두고,
  `~/.config/ghostty/theme.conf` 가 있으면 그 값으로 덮어씁니다.
- **Cursor** — 대상 `settings.json` 이 레포의 `cursor/settings.json` 링크라서
  병합하면 레포 파일이 바뀝니다. 테마 확장은 `cursor/extensions.txt` 에 등록합니다.
- **VS Code** — Cursor 와 같은 키를 씁니다. 레포에 `vscode/settings.json` 이 아직
  없어 로컬 파일에만 병합됩니다. 테마 확장은 `vscode/extensions.txt` 에 등록합니다.
- **Orca** — `orca-data.json` 은 Orca 가 실행 중에 덮어쓰므로 **완전히 종료한 뒤**
  적용해야 합니다. 값은 Orca 내장 터미널 테마 이름입니다.
- **MobaXterm** — Windows 전용. `MobaXterm.ini` 의 `[Colors]` 섹션을 교체합니다.

## 추가하기

- **테마 추가**: 각 앱 디렉토리에 `<새테마>.<THEME_EXT>` 를 넣습니다.
- **앱 추가**: `themes/<앱>/app.conf` 와 테마 파일을 만듭니다.
- 어느 쪽이든 넣은 뒤 `bash themes/index.sh` 로 위 인덱스를 갱신합니다.
- `app` 은 테마 이름으로 쓸 수 없습니다 (`app.conf` 와 겹침).

> 공개 저장소입니다. 세션·계정 정보가 섞이지 않도록 색상 등 테마 값만 넣으세요.
