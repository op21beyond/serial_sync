# serial_sync (ssync) — 설계 스펙

칩간 시리얼 동기신호 송수신회로

## 1. 품질 수준

- Verilog HDL 설계 과제. **양산 수준**.
- **합성 가능**해야 하고, **래치는 생성되지 않아야 함**.

---

## 2. 송신 (TX)

### 2.1 인터페이스

- APB 인터페이스로 data 레지스터에 값을 쓰면 LSB부터 `cfg.length` 레지스터에 설정된 비트 수만큼 시리얼로 N비트씩 전송함.
- N은 1, 2, 4 중 하나로 `cfg.width` 레지스터로 설정.
- `cfg.length`는 N의 배수만 허용하고 1~16.
- `cfg.length` 길이 이상의 data 레지스터 상위비트는 사용되지 않음.

### 2.2 시리얼 전송 주파수

- APB 클럭을 `cfg.clkdiv` 레지스터 값만큼 분주한 주파수 속도로 전송한다.
- `cfg.clkdiv` 허용값은 100~1000.
- 분주회로를 통해 클럭을 만드는 게 아니라 **clock enable 신호**를 만들어서 사용한다.
  - 클럭을 만들어서 쓰면 STA에서 클럭소스를 만들게 되지만, clock enable을 만들어서 쓰면 클럭소스가 늘지 않는다.

### 2.3 시리얼 프로토콜

- 2핀으로 serial clock + serial data, 또는 1핀으로 preamble 2비트 -> serial data 를 출력한다.
- serial clock은 data 전송 중에만 토글한다. 전송하지 않을 때는 0이다.
- preamble은 두 serial 사이클 동안 1 -> 0 이 모든 데이터 핀에 순차적으로 전송된다.
- 두 모드 중 선택은 `cfg.mode` 레지스터로 설정한다 (디폴트는 preamble).

### 2.4 전송 중 쓰기 제한

- 현재 시리얼 전송 중에는 APB로 data 레지스터를 덮어쓰지 못하고 write는 무시한다.
- 시리얼 전송 중에 다른 제어 레지스터는 쓰기를 하지 않는다고 가정한다.

### 2.5 TX 활성화 (`cfg.tx_en`)

- APB 레지스터 접근(read/write)은 `cfg.tx_en` 값과 무관하게 항상 가능하다.
- `cfg.tx_en=0`이면 시리얼 신호 생성 및 출력이 비활성화되고, `ss_tx_clk`/`ss_tx_data`는 0으로 고정된다.
- `cfg.tx_en=1`(default)일 때만 실제로 시리얼 프레임을 생성/출력한다.

---

## 3. 수신 (RX)

- 송신과 수신은 일방향이다.
- 각 칩의 송신과 수신은 같은 레지스터 설정으로 동작하는 것을 가정한다.
  (예: `cfg.mode`, `cfg.length`, `cfg.width` 등 동일)

수신단에는 `cfg.mode`에 따라:

- **clock 모드**: serial clock이 data와 함께 올 경우, serial clock의 **falling edge**에서 serial data를 채서 N비트 수신 후 parallel로 변환하여 data 레지스터에 저장한다.
  - N비트 serial data 수신이 끝난 후에만 data 레지스터에 저장되고, serial data 수신 중 중간 값으로 data 레지스터를 쓰지 않는다.
- **preamble 모드**: preamble 비트 패턴 감지 후 시리얼 비트 수만큼 serial data를 수신한 후 data register를 업데이트한다.

### 3.1 RX 활성화 (`cfg.rx_en`)

- APB 레지스터 접근(read/write)은 `cfg.rx_en` 값과 무관하게 항상 가능하다.
- `cfg.rx_en=0`이면 serial 입력 수신 동작이 비활성화된다. preamble 검출/clock edge 감지를 포함한 모든 수신 FSM 동작이 정지되고, `rx_valid`는 발생하지 않는다.
- `RXDATA`, `RXCOUNT`는 비활성화 시점의 마지막 값을 그대로 유지한다 (클리어되지 않음).
- `cfg.rx_en=1`(default)일 때만 실제로 수신 동작을 수행한다.

---

## 4. 레지스터 맵 (구현 정의)

원본 스펙은 `cfg.mode`, `cfg.length`, `cfg.width`, `cfg.clkdiv`, `cfg.tx_en`, `cfg.rx_en`라는 논리적 필드명만 정의하고 있어,
아래는 이를 APB 레지스터로 매핑한 본 구현의 세부 정의이다. (byte address, 4B word-aligned)

| Addr | Name      | R/W | 설명 |
|------|-----------|-----|------|
| 0x00 | CFG       | RW  | 아래 비트필드 참고 |
| 0x04 | TXDATA    | RW  | 송신 데이터. busy 중 write는 무시됨 |
| 0x08 | TXSTATUS  | RO  | bit0 = tx_busy |
| 0x0C | RXDATA    | RO  | 최근 수신 데이터 |
| 0x10 | RXSTATUS  | RO  | bit0 = rx_valid(sticky, read 시 clear) |
| 0x14 | RXCOUNT   | RW  | preamble 비트 카운터 (32bit, `cfg.rx_count_en`=1일 때만 증가, 0xFFFFFFFF에서 0으로 wrap). APB write로 임의 값 초기화 가능 |

### CFG 비트필드 (0x00)

| Bits  | Name         | 설명 |
|-------|--------------|------|
| [0]   | mode         | 0=preamble(default), 1=clock+data |
| [2:1] | width_sel    | 00=1(default), 01=2, 10=4 |
| [6:3] | length_m1    | length = length_m1+1 (1~16), default 0(=1) |
| [16:7]| clkdiv       | 100~1000, default 100 |
| [17]  | rx_count_en  | 1=preamble 모드에서 preamble 검출마다 RXCOUNT 증가, 0=비활성(default) |
| [18]  | tx_en        | 1=TX 신호 생성/출력 활성(default), 0=`ss_tx_clk`/`ss_tx_data` 0 고정 |
| [19]  | rx_en        | 1=RX 수신 동작 활성(default), 0=수신 FSM 정지(APB 접근은 항상 가능) |

---

## 5. 설계 시 판단/가정 사항 (원문에 명시되지 않아 구현 시 결정한 부분)

원 스펙 문서에 구체적으로 명시되지 않아 설계자가 판단한 부분들이다. 실제 사용 전 검토 필요.

1. **비트 주기 정의**: `cfg.clkdiv` 값만큼의 APB 클럭 사이클을 "1 serial tick"으로 정의.
   - clock 모드에서는 1비트 = 2 tick (rising tick에서 데이터 셋업, falling tick에서 RX 샘플).
   - preamble 모드에서는 1비트 = 1 tick (clock 핀이 없으므로).
2. **preamble 동기화**: RX는 clock 핀이 없는 preamble 모드에서, data 라인의 0→1 상승 엣지를 preamble 시작으로 감지하고
   자체 tick 카운터의 위상을 그 시점에 맞춰 재동기화한다 (TX/RX가 동일 `cfg.clkdiv`를 사용한다는 가정 하에 유효).
3. **비트 전송 순서**: `length` 비트를 N비트씩 그룹으로 나눌 때 data 레지스터의 LSB 그룹부터 순서대로 전송 (스펙의 "lsb부터" 문구 반영).
4. **CDC(Clock Domain Crossing)**: RX 입력(`ss_clk_i`, `ss_data_i`)은 2단 동기화(double-flop synchronizer) 후 사용. 두 칩이 별도 클럭 도메인이라는 실제 사용 환경을 고려한 안전장치.
5. **Reserved 값 처리**: `cfg.width_sel = 2'b11`은 미정의이며 구현에서는 N=4로 처리.
6. **clkdiv=0 방어**: 스펙상 허용 범위가 100~1000이므로 발생하지 않아야 하나, 0 입력 시 divide-by-1로 클램프하여 hang을 방지.
7. **preamble 비트 카운터 (RXCOUNT)**: `cfg.mode`가 preamble일 때, preamble 비트 패턴(1→0)이 검출될 때마다 (R_PRE_CHK0 통과 시점, 즉 실제 데이터 수신 시작 직전) 32bit 카운터를 1 증가시킨다.
   - `cfg.rx_count_en`(CFG bit 17)로 활성화/비활성화 제어. 기본값은 비활성(0).
   - clock 모드에서는 preamble이 없으므로 카운터가 동작하지 않는다 (증가하지 않음).
   - `0xFFFFFFFF` 도달 후 다음 증가에서 `0x00000000`으로 자연 wrap-around (추가 로직 없이 32bit 레지스터 오버플로우로 구현).
   - APB write로 카운터 값을 임의로 초기화 가능. write와 preamble 검출로 인한 증가가 동일 사이클에 겹치는 경우는 없다고 가정(APB write side effect는 write pulse 사이클에만 반영되고, 그 외 사이클은 RX 코어 값을 그대로 래치).
8. **`cfg.tx_en` / `cfg.rx_en` 기본값 및 동작**: 두 비트 모두 리셋 후 기본값은 **1 (활성)** 이다 — 이 필드가 없던 기존 동작(항상 송수신 가능)과의 호환을 위한 선택.
   - `tx_en=0`으로 전환되는 순간, TX 코어는 진행 중이던 프레임 유무와 관계없이 즉시 `S_IDLE`로 강제되고 `tx_busy`, `ss_tx_clk`, `ss_tx_data`가 모두 0으로 클리어된다. `rx_en=0`도 동일하게 RX FSM을 즉시 `R_IDLE`로 강제한다(`RXDATA`/`RXCOUNT` 값은 보존, `rx_valid`만 억제).
     - 스펙 2.4항("시리얼 전송 중에 다른 제어 레지스터는 쓰기를 하지 않는다고 가정")과 동일한 전제 하에, 정상 사용에서는 전송 도중 `tx_en`/`rx_en`을 바꾸지 않는다고 가정한다. 다만 구현은 방어적으로 즉시 idle로 복귀하도록 만들어, 어떤 시점에 비활성화되어도 출력이 확실히 0이 되도록 했다.
   - `TXDATA` write는 `tx_en` 값과 무관하게 APB 상에서는 항상 정상적으로 동작한다(스펙 2.4의 busy 체크만 적용). 다만 `tx_en=0`이면 그 write가 만든 `tx_start` 펄스를 TX 코어가 무시하므로 실제 송신은 시작되지 않는다.

---

## 6. 폴더 구조

```
ssync/
├── CLAUDE.md      # 프로젝트 작업 지침 (Claude Code 세션용)
├── doc/           # 본 문서
├── rtl/           # 합성 가능 Verilog RTL
├── tb/            # 테스트벤치 (SystemVerilog, self-checking)
├── sim/           # Verilator 기반 시뮬레이션 Makefile
├── syn/           # 합성 관련 노트/스크립트
└── lint/          # lint 스크립트
```
