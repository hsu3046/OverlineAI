# Supertonic Device Benchmark

Overline에 Supertonic 3를 연결하기 전에 실제 iPhone에서 한국어 품질과 성능을 확인하는 독립 앱입니다. Overline 앱 타깃에는 ONNX Runtime이나 모델 파일을 추가하지 않습니다.

## 준비

```bash
cd Benchmarks/SupertonicDevice
./prepare.sh
open SupertonicDeviceBenchmark.xcodeproj
```

`prepare.sh`는 다음 고정 버전을 `Generated/`에 받습니다.

- Supertonic helper: `7e2804f96016a7028cb1ed627353c61c1e9dd281`
- Supertonic 3 model: `3cadd1ee6394adea1bd021217a0e650ede09a323`
- ONNX Runtime Swift package: `1.24.2`

모델 다운로드는 약 399MB이며, 빌드된 테스트 앱은 약 412MB입니다. `Generated/`와 XcodeGen 생성물은 Git에서 제외됩니다.

## 실기기 실행

1. Xcode의 `Signing & Capabilities`에서 Team을 선택합니다.
2. 연결된 iPhone을 실행 대상으로 선택합니다. 시뮬레이터 수치는 판단에 사용하지 않습니다.
3. `모델 준비`를 눌러 초기 로딩 시간과 메모리를 확인합니다.
4. 동일한 문단을 iPhone 고품질 음성과 비교해 듣습니다.
5. 5, 8, 12단계와 속도별로 `생성 및 재생`을 반복합니다.

## 기록할 항목

- 모델 준비 시간
- 합성 시간
- 오디오 길이
- RTF = 합성 시간 / 오디오 길이
- 재생 요청까지 걸린 시간
- 모델 준비 전후 및 합성 후 resident memory
- 10분 연속 실행 중 끊김, 발열, 앱 종료 여부

콘솔에는 텍스트를 기록하지 않고 측정값만 `supertonic_benchmark` 접두사로 출력합니다.

## 제품 통합 기준

- 최소 지원 기기에서 RTF가 1.0 미만이어야 합니다.
- 10분 연속 재생 중 큐 끊김이나 메모리 종료가 없어야 합니다.
- 설치된 iOS Premium 음성보다 한국어 낭독 품질이 명확히 좋아야 합니다.
- 생성 음성을 파일로 저장하지 않는 구조를 유지해야 합니다.

위 기준을 통과한 뒤에만 Overline에 음성 엔진 선택 계층과 선택형 모델 다운로드를 추가합니다. 약 400MB 모델을 기본 앱 번들에 포함하는 방식은 사용하지 않습니다.

## 배포 전 확인

이 앱은 성능 검증 전용입니다. Supertonic 코드와 모델의 라이선스가 서로 다르므로, 제품에 넣기 전에는 모델의 OpenRAIL-M 조건과 App Store 배포 범위를 별도로 검토해야 합니다.
