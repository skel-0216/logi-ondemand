# logi-ondemand

macOS에서 **Logi Options+**를 로지텍 마우스나 키보드가 실제로 연결되어 있을 때만 실행합니다.

Logi Options+는 로지텍 기기가 없어도 에이전트와 업데이터를 항상 백그라운드에서 실행하며, 대기 중에도
CPU와 배터리를 눈에 띄게 소모하는 경우가 있습니다. 로지텍 마우스를 가끔(예: 책상에서만) 쓴다면,
`logi-ondemand`가 기기가 연결될 때 Options+를 켜고 연결이 끊기면 다시 끕니다.
로지텍 기기가 없는 동안에는 **아무것도 실행되지 않습니다.**

## 동작 방식

일반적인 노트북 사용 패턴에 맞춰 만들었습니다. 필요할 때 마우스를 연결하고, 덮개를 닫을 때까지 씁니다.
기다리는 동안에도, 마우스를 쓰는 동안에도 logi-ondemand는 **상주하지 않습니다.**

- `launchd`가 다음 순간에만 작은 도우미 `logi-watch`를 1초 미만 실행합니다:
  - 로지텍(`VendorID 0x046D`) 마우스/키보드가 **USB**(Bolt/Unifying 수신기 포함)나 **블루투스**로 연결될 때
    (`LaunchEvents` / `com.apple.iokit.matching`)
  - Mac이 잠자기에 들어가거나 깨어날 때(`com.apple.powermanagement.systempowerstate`)
  - 로그인할 때
- 매번 로지텍 기기가 있으면 Options+를 켜고, 없으면 끈 뒤 바로 종료합니다.
- 가상 HID 장치와 로지텍 웹캠은 무시합니다.

Mac을 재우지 않고 마우스만 끄면 다음 잠자기 때까지(또는 `logi off`) Options+가 유지됩니다. `launchd`는 기기가
나타날 때는 프로그램을 실행해 주지만 사라질 때는 그렇지 않아서, 그 순간을 잡으려면 상주 프로세스가 필요합니다.
이를 위한 것이 `--resident` 모드입니다.

sudo가 필요 없고, 로지텍 파일은 건드리지 않습니다.

## 모드

| | `./install.sh` (기본) | `./install.sh --resident` | `./install.sh --polling` |
|---|---|---|---|
| 로지텍 기기 없음 | 실행되는 것 없음 | 실행되는 것 없음 | 20초마다 10ms 확인 |
| 기기 연결 | 즉시 Options+ 시작 | 즉시 Options+ 시작 | 20초 안에 시작 |
| 연결 중 | **실행되는 것 없음** | 도우미 대기 (약 12MB, CPU 0%) | 20초마다 10ms 확인 |
| Options+ 종료 시점 | 기기 없이 **잠자기/깨어나기** 할 때 | 마지막 기기 해제 10분 후 | 마지막 기기 해제 10분 후 |
| 필요 조건 | swiftc | swiftc | 없음 |

다른 모드의 10분 유예 시간은 블루투스 마우스가 잠깐 절전에 들어갈 때 Options+가 켜졌다 꺼졌다 하는 것을
막습니다. Swift 컴파일러가 없으면 `./install.sh`가 자동으로 폴링 모드로 설치합니다. 다른 옵션으로
`install.sh`를 다시 실행하면 모드가 바뀝니다.

## 설치

기본 모드와 `--resident` 모드에는 Xcode 명령줄 도구가 필요합니다(`xcode-select --install`).

```bash
git clone https://github.com/skel-0216/logi-ondemand.git
cd logi-ondemand
./install.sh
```

`logi-watch`를 빌드하고 `logi`와 함께 `~/.local/bin`에 설치한 뒤(`PREFIX=/경로`로 변경 가능) 감시를 등록합니다.
`~/.local/bin`이 `PATH`에 없다면 `~/.zshrc`에 추가하세요:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**그리고 로지텍 자체 자동 실행을 끄세요.** 그렇지 않으면 macOS가 로그인 때마다 Options+를 실행합니다:

시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → *백그라운드에서 허용* → **Logitech** /
**Logi Options+** 끄기. 아직 켜져 있으면 `logi status`가 경고를 표시합니다.

선택: 업데이터를 macOS가 단독으로 실행하지 않게 하려면:

```bash
sudo launchctl disable system/com.logi.optionsplus.updater
```

(되돌리기: `sudo launchctl enable system/com.logi.optionsplus.updater`. 업데이트는 Options+ 앱에서 직접 하세요.)

## 사용법

```
logi status   # 모드, 연결된 기기, Options+ 실행 여부
logi auto     # 자동 모드 (기본값)
logi on       # 지금 켜고 계속 유지 (자동 모드 일시 중지)
logi off      # 지금 끄고 계속 유지 (자동 모드 일시 중지)
logi log      # 최근 연결/해제 및 시작/종료 기록
```

기본적인 마우스/키보드 입력은 Options+ 없이도 동작합니다. 버튼 재지정, 제스처, 부드러운 스크롤 같은
추가 기능만 Options+가 필요하므로, 기기 연결 직후 잠시 뒤부터 사용할 수 있습니다.

## 설정

`~/.config/logi-ondemand/config` (셸 문법):

```bash
GRACE_MINUTES=10   # --resident / --polling: 마지막 기기가 끊긴 뒤 Options+를 유지할 시간(분)
```

## 제거

```bash
./uninstall.sh
```

기본 동작으로 되돌리려면 로그인 항목에서 Logitech을 다시 켜세요.

## 참고

- macOS 27(Apple Silicon) + Logi Options+ 환경에서 개발했습니다. macOS 13 이상에서 동작할 것으로 예상합니다.
- 로그: `~/Library/Logs/logi-ondemand.log`, 상태: `~/Library/Application Support/logi-ondemand/`
- Logitech과 무관한 개인 프로젝트입니다.

## 라이선스

MIT
