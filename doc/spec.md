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

---

## 3. 수신 (RX)

- 송신과 수신은 일방향이다.
- 각 칩의 송신과 수신은 같은 레지스터 설정으로 동작하는 것을 가정한다.
  (예: `cfg.mode`, `cfg.length`, `cfg.width` 등 동일)

수신단에는 `cfg.mode`에 따라:

- **clock 모드**: serial clock이 data와 함께 올 경우, serial clock의 **falling edge**에서 serial data를 채서 N비트 수신 후 parallel로 변환하여 data 레지스터에 저장한다.
  - N비트 serial data 수신이 끝난 후에만 data 레지스터에 저장되고, serial data 수신 중 중간 값으로 data 레지스터를 쓰지 않는다.
- **preamble 모드**: preamble 비트 패턴 감지 후 시리얼 비트 수만큼 serial data를 수신한 후 data register를 업데이트한다.

---

## 4. 레지스터 맵 (구현 정의)

원본 스펙은 `cfg.mode`, `cfg.length`, `cfg.width`, `cfg.clkdiv`라는 논리적 필드명만 정의하고 있어,
아래는 이를 APB 레지스터로 매핑한 본 구현의 세부 정의이다. (byte address, 4B word-aligned)

| Addr | Name      | R/W | 설명 |
|------|-----------|-----|------|
| 0x00 | CFG       | RW  | 아래 비트필드 참고 |
| 0x04 | TXDATA    | RW  | 송신 데이터. busy 중 write는 무시됨 |
| 0x08 | TXSTATUS  | RO  | bit0 = tx_busy |
| 0x0C | RXDATA    | RO  | 최근 수신 데이터 |
| 0x10 | RXSTATUS  | RO  | bit0 = rx_valid(sticky, read 시 clear) |

### CFG 비트필드 (0x00)

| Bits  | Name       | 설명 |
|-------|------------|------|
| [0]   | mode       | 0=preamble(default), 1=clock+data |
| [2:1] | width_sel  | 00=1(default), 01=2, 10=4 |
| [6:3] | length_m1  | length = length_m1+1 (1~16), default 0(=1) |
| [16:7]| clkdiv     | 100~1000, default 100 |

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
