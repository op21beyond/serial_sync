# Simulation (SIM)

이 디렉토리에는 ssync 프로젝트의 시뮬레이션 환경 설정 및 스크립트가 포함됩니다.

## 개요

- **시뮬레이터**: Verilator 5.x
- **빌드 방식**: Makefile 기반
- **타이밍**: `--binary --timing` 옵션 사용

## 주요 명령어

### 기본 시뮬레이션
```sh
cd sim && make run
```
- RTL과 테스트벤치 빌드
- 시뮬레이션 실행
- PASS/FAIL 결과 출력

### 파형 생성
```sh
cd sim && make wave
```
- 기본 시뮬레이션 실행
- FST 형식의 파형 파일 생성 (`build/` 디렉토리)
- GTKWave로 분석 가능

### 정리
```sh
cd sim && make clean
```
- 빌드 산출물 및 생성된 파일 삭제

## 디렉토리 구조

```
sim/
├── Makefile          # 빌드 및 시뮬레이션 규칙
├── build/            # 빌드 산출물 (임시)
└── [파형 파일들]     # make wave 실행 시 생성
```

## Verilator 설정

- **버전**: 5.x 이상
- **컴파일 옵션**: `--binary --timing`
- **기능**: 하드웨어 타이밍 정확도 지원

## 시뮬레이션 결과 해석

### PASS
모든 테스트 케이스 통과

### FAIL
하나 이상의 테스트 케이스 실패
- 파형 분석 필요
- RTL 코드 검토
- 테스트벤치 검토

## 파형 분석 도구

생성된 FST 파형 파일은 다음 도구로 분석:
- **GTKWave** (권장)
- Verilator 내장 뷰어
- 기타 VCD/FST 호환 뷰어

## 사전 커밋 검사

커밋 전 반드시 실행:
```sh
cd sim && make run      # 모든 테스트 PASS 확인
```

## 참고사항

- 시뮬레이션은 매우 빠름 (Verilator의 C++ 생성 코드)
- 대규모 테스트도 몇 초 내 완료
- 복잡한 상황 재현 시 파형 분석으로 디버깅

## 문제 해결

### make: command not found
Verilator가 설치되지 않았습니다. 설치 필요.

### 시뮬레이션 FAIL
1. 파형 생성: `make wave`
2. GTKWave에서 분석
3. RTL 또는 TB 수정
4. 다시 실행

## 참고

- RTL 코드: `rtl/` 디렉토리
- 테스트벤치: `tb/` 디렉토리
- 린트 검사: `lint/` 디렉토리
