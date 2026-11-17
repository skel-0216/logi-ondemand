# logi-ondemand

macOS에서 **Logi Options+**를 로지텍 마우스나 키보드가 실제로 연결되어 있을 때만 실행합니다.

Logi Options+는 로지텍 기기가 없어도 에이전트와 업데이터를 항상 백그라운드에서 실행하며, 대기 중에도
CPU와 배터리를 눈에 띄게 소모하는 경우가 있습니다. 로지텍 마우스를 가끔(예: 책상에서만) 쓴다면,
`logi-ondemand`가 기기가 연결될 때 Options+를 켜고 연결이 끊기면 다시 끕니다.
로지텍 기기가 없는 동안에는 **아무것도 실행되지 않습니다.**

## 동작 방식

- `launchd`가 IOKit에 로지텍(`VendorID 0x046D`) 마우스/키보드가 나타나는지 지켜봅니다
  (`LaunchEvents` / `com.apple.iokit.matching`). 기다리는 동안 비용은 0입니다.
- **USB**(Bolt/Unifying 수신기 포함)나 **블루투스**로 연결되면 `launchd`가 작은 도우미 `logi-watch`를
  실행하고, 도우미가 즉시 Options+를 켭니다.
- 연결되어 있는 동안 `logi-watch`는 IOKit 알림만 기다립니다(약 12MB, CPU 0%).
- 마지막 로지텍 기기가 끊기고 10분(설정 가능)이 지나면 Options+를 끄고 종료합니다. 블루투스 마우스가
  잠깐 절전에 들어가도 켜졌다 꺼졌다 하지 않도록 유예 시간을 둡니다.
- 가상 HID 장치와 로지텍 웹캠은 무시합니다.

sudo가 필요 없고, 로지텍 파일은 건드리지 않습니다.

**폴링 대체 모드:** Swift 컴파일러가 없으면 `./install.sh`가 20초마다 확인하는 셸 스크립트 방식(1회 약 10ms)으로
설치됩니다. `./install.sh --polling`으로 직접 선택할 수도 있습니다.

## 설치

이벤트 모드에는 Xcode 명령줄 도구가 필요합니다(`xcode-select --install`).

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
GRACE_MINUTES=10   # 마지막 기기가 끊긴 뒤 Options+를 유지할 시간(분)
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
