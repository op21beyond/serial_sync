# Linting (LINT)

이 디렉토리에는 ssync RTL 코드의 린트(정정) 검사 스크립트가 포함됩니다.

## 개요

- **목적**: RTL 코드의 설계 규약 준수 검증
- **도구**: Verilator (5.x 이상)
- **필수 조건**: 모든 커밋 전 반드시 통과해야 함

## 린트 검사 실행

```sh
./lint/run_lint.sh
```

### 성공 시
```
[OK] All lint checks passed
```

### 실패 시
경고 메시지 출력 후 종료
- 반드시 수정 필요
- 수정 후 다시 실행

## 검사 항목

### 1. 래치 감지 (Latch Detection)
```
-Wall -Wwarn-LATCH
```
- 모든 `always @(*)` 블록에서 모든 경로가 모든 출력을 할당하는지 확인
- 미할당 출력 → 래치 추론 → 실패

#### 예: 래치 문제
```verilog
always @(*) begin
  if (condition)
    output = value;
  // else 경로에서 output이 할당되지 않음 → 래치!
end
```

#### 올바른 방법
```verilog
always @(*) begin
  if (condition)
    output = value;
  else
    output = default_value;  // 모든 경로 할당
end
```

### 2. 기타 린트 규칙
- 사용되지 않는 신호 감지
- 초기화되지 않은 변수 감지
- 우도 있는 신호 대입 감지
- 합성 불가능한 구조 감지

## 커밋 전 체크리스트

1. **린트 검사**
   ```sh
   ./lint/run_lint.sh
   ```
   ✓ 반드시 통과

2. **시뮬레이션**
   ```sh
   cd sim && make run
   ```
   ✓ PASS 확인

## 린트가 실패하는 경우

### 원인 분석
1. 경고 메시지 읽기
2. 해당 파일과 줄 번호 확인
3. 코드 검토

### 수정 방법

**모든 경로 할당**
```verilog
// 나쁜 예
always @(*) begin
  out = 0;
  if (sel == 2'b01) out = in1;
  if (sel == 2'b10) out = in2;
  // sel == 2'b11인 경우?
end

// 좋은 예
always @(*) begin
  case (sel)
    2'b01: out = in1;
    2'b10: out = in2;
    2'b11: out = in3;
    default: out = 0;
  endcase
end
```

## 린트 결과 해석

### PASS (정상)
- 모든 설계 규약 준수
- 커밋 가능

### FAIL (오류)
- 경고 수정 필요
- 커밋 불가능
- 수정 후 재실행

## 설계 규약 요약

린트가 강제하는 주요 규약:

1. ✓ 래치 없음 (모든 `always @(*)` 출력 할당)
2. ✓ 합성 가능 (no `initial`, no delays)
3. ✓ 클록 관련 (no generated clocks)
4. ✓ 리셋 (async active-low)

## 린트 스크립트 옵션

스크립트 파일에서 수정 가능:

```sh
verilator [옵션] [파일]
  -Wall              # 모든 경고
  -Wwarn-LATCH       # 래치 경고
  --lint-only        # 린트만 (합성 안함)
  rtl/               # RTL 소스 디렉토리
```

## 참고사항

- 린트 검사는 빠름 (합성 안함)
- 모든 RTL 변경 후 즉시 실행 권장
- IDE 훅으로 자동화 가능

## 시뮬레이션과의 차이

| 항목 | 린트 | 시뮬레이션 |
|------|------|-----------|
| 속도 | 빠름 | 약간 느림 |
| 범위 | 문법/규약 | 동작 검증 |
| 목적 | 설계 규칙 | 기능 검증 |
| 필수 | 커밋 전 | 커밋 전 |

## 문제 해결

### "command not found"
Verilator가 설치되지 않았습니다.

### 래치 경고 무시하고 싶다면?
- **하지 마세요!** 래치는 설계 오류입니다.
- 항상 수정하세요.

### 특정 경고를 비활성화하려면?
- 지원하지 않습니다. (프로젝트 정책)
- 모든 경고는 설계 결함입니다.

## 참고

- RTL 코드: `rtl/` 디렉토리
- 시뮬레이션: `sim/` 디렉토리
- 사양: `doc/spec.md`
