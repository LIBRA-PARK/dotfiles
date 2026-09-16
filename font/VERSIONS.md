# Fonts

이 디렉토리의 폰트 파일 출처와 버전 기록입니다.
업데이트할 때 아래 "업데이트 방법" 절차를 그대로 따르면 됩니다.

## 구성

| 역할     | 패밀리명 (설정에 쓰는 이름)  | 한글 | Nerd 아이콘 | 파일 |
| -------- | ---------------------------- | ---- | ----------- | ---- |
| 기본     | `JetBrainsMono Nerd Font`    | ✗    | ✓           | `jetbrains-mono/JetBrainsMonoNerdFont-*.ttf` |
| fallback | `D2KodingLigature Nerd Font` | ✓    | ✓           | `d2coding/D2KodingLigatureNerdFont-*.ttf`    |

영문·기호는 JetBrains Mono 가, 한글은 D2Coding 이 담당합니다.
Nerd Fonts 패치본이라 Powerline / Font Awesome / Codicon / Devicon / Material /
Octicon 아이콘이 두 폰트 모두에 들어 있어, 어느 쪽으로 넘어가도 아이콘이 깨지지 않습니다.

> ⚠️ 패치본의 실제 패밀리명은 **`D2Koding`** 입니다 (`D2Coding` 아님).
> Nerd Fonts 가 상표 문제로 이름을 바꿔 패치하기 때문입니다.
> 에디터/터미널 설정에는 `D2KodingLigature Nerd Font` 를 그대로 써야 합니다.
> Linux 는 `fonts.conf` 에 `D2Coding` → `D2KodingLigature Nerd Font` 별칭을 넣어 뒀습니다.

## 출처

**Nerd Fonts v3.5.1** — https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.5.1

| 아카이브 | sha256 |
| -------- | ------ |
| `JetBrainsMono.zip` | `fab782a66f7d3019da64f6572db9fc5d3a4bcb19f9fa13e2d8a62e3693d6396e` |
| `D2Coding.zip`      | `8d1597b1537afdc8f2f7c75036a8224bc837e6c248062b80013a13258258541d` |

원본 폰트

- JetBrains Mono — https://github.com/JetBrains/JetBrainsMono (OFL-1.1)
- D2Coding — https://github.com/naver/d2codingfont (OFL-1.1)

라이선스 원문은 각 디렉토리의 `OFL.txt` 에 함께 두었습니다.
셋 다 OFL-1.1 이라 재배포에 문제가 없습니다.

## 커밋된 파일 (sha256)

```
ceece622ccbadb8df7be47d280f84dfade6a1069993e4753af8a9455f4e97072  d2coding/D2KodingLigatureNerdFont-Bold.ttf
d48bfd5f0ff167f28544c722bdf769117b56f923e1cbdd89430bbf3a742c35d3  d2coding/D2KodingLigatureNerdFont-Regular.ttf
19a2e3af8ccf99954941ea07e0a29df27574500f12016d86d6c4c059b825ffe1  jetbrains-mono/JetBrainsMonoNerdFont-BoldItalic.ttf
e490660ad75e0b152c93b1604c2ea1a4ea675f1b8a3fe0d005b1998568f99f1f  jetbrains-mono/JetBrainsMonoNerdFont-Bold.ttf
71d5466cc3ab31bee38b4e2c5cc99c2b41a749c4973ed4579b814ec992b0738e  jetbrains-mono/JetBrainsMonoNerdFont-Italic.ttf
1c680e8cde9fcf8b88a5605ce8d1fb94dd3fb15841f7ca7bf4c55664855e5611  jetbrains-mono/JetBrainsMonoNerdFont-Regular.ttf
```

같은 내용이 `SHA256SUMS` 에도 있습니다. 검증:

```bash
cd ~/dotfiles/font && sha256sum -c SHA256SUMS
```

## 왜 이 변형만 커밋했나

Nerd Fonts 는 한 폰트를 여러 변형으로 배포합니다. 전부 넣으면 JetBrainsMono 만
127MB 라서 터미널에 가장 알맞은 기본 변형만 골랐습니다.

| 변형 | 아이콘 폭 | 용도 |
| ---- | --------- | ---- |
| `JetBrainsMonoNerdFont-*`     | 자연 폭 (보통 2칸) | **채택.** 터미널이 폭을 직접 계산하므로 가장 잘 맞는다 |
| `JetBrainsMonoNerdFontMono-*` | 1칸으로 압축       | 아이콘이 잘리는 에디터에서 쓴다 |
| `JetBrainsMonoNerdFontPropo-*`| 가변 폭            | 문서용. 코딩에는 부적합 |
| `JetBrainsMonoNLNerdFont-*`   | —                  | NL = No Ligatures. 리거처가 싫을 때 |

D2Coding 은 `Regular` / `Bold` 두 굵기만 배포됩니다 (Italic 없음).

다른 변형이 필요하면 아래 절차로 받아서 해당 디렉토리에 추가하고,
`install.sh` 를 다시 실행하면 됩니다. (`install.sh` 는 디렉토리의 `.ttf` 를 전부 잡습니다)

## 업데이트 방법

```bash
VER=3.5.1   # https://github.com/ryanoasis/nerd-fonts/releases 에서 최신 태그 확인
cd "$(mktemp -d)"

for F in JetBrainsMono D2Coding; do
  curl -fLO "https://github.com/ryanoasis/nerd-fonts/releases/download/v${VER}/${F}.zip"
done

unzip -o -j JetBrainsMono.zip \
  'JetBrainsMonoNerdFont-Regular.ttf' 'JetBrainsMonoNerdFont-Bold.ttf' \
  'JetBrainsMonoNerdFont-Italic.ttf'  'JetBrainsMonoNerdFont-BoldItalic.ttf' \
  'OFL.txt' -d ~/dotfiles/font/jetbrains-mono

unzip -o -j D2Coding.zip \
  'D2KodingLigatureNerdFont-Regular.ttf' 'D2KodingLigatureNerdFont-Bold.ttf' \
  'OFL.txt' -d ~/dotfiles/font/d2coding

cd ~/dotfiles/font
sha256sum jetbrains-mono/*.ttf d2coding/*.ttf > SHA256SUMS   # VERSIONS.md 표도 갱신
bash install.sh                            # 링크는 그대로, 캐시만 갱신된다
```

패밀리명이 바뀌었는지 반드시 확인하세요. 바뀌었다면 `fonts.conf` 와
아래 앱별 설정도 같이 고쳐야 합니다.

```bash
fc-scan --format '%{family}\n' ~/dotfiles/font/*/*.ttf | sort -u
```
