# Testbench (TB)

이 디렉토리에는 ssync 칩간 직렬 동기화 신호 트랜시버의 SystemVerilog 테스트벤치가 포함됩니다.

## 개요

- **언어**: SystemVerilog (Simulation only)
- **목적**: RTL 동작 검증
- **합성 대상**: 아님 (시뮬레이션 전용)

## 특징

- SystemVerilog의 고급 기능 사용 가능
- 클래스, 인터페이스, 제약 조건 등 활용
- 광범위한 동작 검증을 위한 테스트 케이스 포함

## 테스트벤치 구조

테스트벤치는 다음을 검증합니다:
- APB 인터페이스 동작
- TX 경로 (전송)
- RX 경로 (수신)
- 크로스칩 통신
- 엣지 케이스 및 예외 상황

## 실행 방법

```sh
cd sim && make run      # 테스트벤치 빌드 및 실행
cd sim && make wave     # 테스트벤치 + FST 파형 생성
```

## 주의사항

- 테스트벤치는 합성 불가능
- `initial` 블록, 지연 등 합성 불가능한 구조 자유롭게 사용 가능
- RTL의 설계 규약과 충돌하지 않도록 주의

## 파형 분석

`cd sim && make wave`로 생성된 FST 파형 파일은 다음으로 분석:
- GTKWave 또는 기타 VCD/FST 뷰어

## 참고

자세한 테스트 실행 방법은 `sim/` 디렉토리의 Makefile 참조
