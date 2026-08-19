# AIB 관점의 Arena Learning/WizardArena 조사 정리

작성일: 2026-07-01

## 1. 핵심 결론

Microsoft/WizardLM의 Arena Learning/WizardArena 연구는 AIB의 핵심 주장, 즉 "평가/선호 데이터가 단순 리더보드용에 그치지 않고 post-training 학습 데이터로 전환될 수 있다"는 논리를 뒷받침하는 강한 근거다.

다만 정확한 표현이 중요하다. 이 연구는 실제 LMSYS Chatbot Arena의 인간 투표 데이터를 그대로 학습한 사례가 아니다. LLM judge가 오프라인에서 Chatbot Arena식 pairwise battle을 시뮬레이션하고, 그 synthetic battle data를 SFT, DPO, PPO 학습 데이터로 전환한 연구다.

따라서 AIB가 가져갈 수 있는 안전한 메시지는 다음이다.

> Arena류 pairwise preference data는 평가 신호일 뿐 아니라, 품질관리와 포맷 변환을 거치면 SFT/DPO/PPO post-training 데이터 플라이휠의 입력이 될 수 있다. Microsoft/WizardLM의 Arena Learning/WizardArena 연구는 이 전환 가능성을 실험적으로 보여준다. 다만 이 결과는 LLM judge 기반 synthetic arena에서 나온 것이므로, AIB의 CJK 실사용자 선호 데이터 효과는 별도 실증이 필요하다.

## 2. 왜 이 연구가 AIB에 중요한가

AIB의 데이터 자산 논리는 단순히 "사람들이 모델을 비교했다"에서 끝나면 약하다. 리더보드용 투표 데이터는 참고 지표일 뿐이라고 반박될 수 있기 때문이다.

Arena Learning/WizardArena가 중요한 이유는 이 반박을 한 단계 넘겨준다.

1. Arena식 비교는 pairwise preference 구조를 만든다.
2. Pairwise preference는 `prompt + chosen + rejected` 형태로 변환될 수 있다.
3. 이 형식은 DPO, PPO/RM, 일부 SFT 데이터 선택 파이프라인에 직접 들어갈 수 있다.
4. 실제 연구에서 이 전환을 반복했을 때 모델 성능이 크게 개선됐다.

즉 AIB 입장에서는 "우리는 리더보드를 만든다"보다 "우리는 CJK 실사용자 기반 post-training preference data layer를 만든다"가 더 강한 포지셔닝이다.

## 3. 연구 개요

### 3.1 원 논문과 최종 게재판

같은 연구가 두 이름으로 정리되어 있다.

| 구분 | 제목 | 링크 |
| --- | --- | --- |
| arXiv/Microsoft Research 버전 | Arena Learning: Build Data Flywheel for LLMs Post-training via Simulated Chatbot Arena | https://arxiv.org/abs/2407.10627 |
| NeurIPS 2024 최종판 | WizardArena: Post-training Large Language Models via Simulated Offline Chatbot Arena | https://proceedings.neurips.cc/paper_files/paper/2024/file/ca4aa9acc097e0f606af55bf986cb031-Paper-Conference.pdf |

참여 기관은 Microsoft, Tsinghua University, Shenzhen Institute of Advanced Technology, Chinese Academy of Sciences 계열이다.

### 3.2 핵심 아이디어

기존 Chatbot Arena는 사람이 두 모델의 답변을 비교해 선호를 누적하고 Elo를 계산한다. 신뢰도는 높지만, 대규모 반복 학습 데이터 생산에는 시간과 비용이 많이 든다.

Arena Learning/WizardArena는 이를 오프라인 LLM judge 기반 arena로 대체한다.

- Target model: WizardLM-beta
- Battle/reference models: Command R+, Qwen 계열, OpenChat, GPT-4o 등 강한 모델 조합
- Judge model: Llama3-70B-Chat/Instruct 등
- 평가 방식: 두 응답을 pairwise로 비교하고 winner, loser, tie를 판정
- 편향 완화: 응답 순서를 바꾸는 two-game setup 사용
- 집계: Bradley-Terry/Elo 계열 방식

이 battle 결과는 평가에만 쓰이지 않는다. Target model이 진 문제는 약점으로 간주되고, 상대 모델의 winning response와 target model의 losing response가 학습 데이터로 전환된다.

### 3.3 학습 데이터 전환 방식

Arena Learning은 simulated battle data를 세 갈래로 활용한다.

| 활용 방식 | 데이터 변환 | 의미 |
| --- | --- | --- |
| SFT | target model이 진 instruction에서 상대 모델의 winning response를 supervised target으로 사용 | 모델 약점 영역을 보강 |
| DPO | 같은 prompt에 대해 winning response를 `chosen`, losing response를 `rejected`로 구성 | pairwise preference를 직접 학습 |
| PPO/RM | pairwise battle data로 reward model 또는 RL 신호 구성 | RLHF/RLAIF식 선호 최적화 |

이 구조가 AIB 논리의 핵심 연결고리다. Arena vote는 단순 표가 아니라 `prompt, chosen, rejected` 형태의 학습 가능한 preference object가 된다.

## 4. 수치 검증

첨부 자료에 나온 주요 수치는 대체로 맞다. 단, arXiv/Microsoft 버전과 NeurIPS 최종판의 headline 수치가 약간 다르므로 외부 문서에는 범위로 쓰는 편이 안전하다.

### 4.1 Microsoft Research/arXiv 계열 수치

WizardLM-beta-7B 기준으로 SFT-I0에서 PPO-I3까지 3회 반복 post-training을 거쳤을 때 다음 개선이 보고됐다.

| 지표 | 초기 모델 | 3회 반복 후 | 개선폭 |
| --- | ---: | ---: | ---: |
| WizardArena-Mix Elo | 871 | 1,274 | +403pt |
| Arena-Hard Auto | 5.2 | 31.5 | +26.3 |
| AlpacaEval 2.0 LC win rate | 8.2% | 34.2% | +26.0%p |
| MT-Bench | 6.41 | 8.16 | +1.75 |
| OpenLLM Avg | 57.75 | 68.08 | +10.33 |

### 4.2 NeurIPS 2024 최종판 수치

최종판은 핵심 결론은 같지만, Figure 5 기준 headline을 다음처럼 정리한다.

| 지표 | 초기 모델 | 3회 반복 후 | 개선폭 |
| --- | ---: | ---: | ---: |
| WizardArena Elo | 875 | 1,274 | +399pt |
| MT-Bench | 6.41 | 7.81 | +1.40 |

따라서 투자자 자료나 외부 공개 문서에서는 다음처럼 쓰는 것이 가장 안전하다.

> WizardArena Elo 약 +399~403pt, AlpacaEval 2.0 LC win rate +26%p 수준의 개선을 보고했다.

## 5. 왜 성능이 올랐는가

### 5.1 모델이 약한 문제를 골라냈다

Arena Learning의 중요한 포인트는 단순히 데이터를 많이 넣은 것이 아니라, target model이 실제로 약한 영역을 찾아냈다는 점이다.

NeurIPS 최종판은 pair-judge 방식이 original data, random sampling, K-means, instruction length, IFD, INSTAG보다 더 좋은 SFT 데이터 선택 효과를 냈다고 보고한다. 이는 "모델이 진 battle"이 모델 약점을 잘 드러내며, 그 약점 데이터를 학습에 되먹이는 방식이 효과적이라는 뜻이다.

### 5.2 Pairwise 데이터가 DPO/PPO에서도 유효했다

최종판은 SFT 이후 DPO와 PPO를 추가했을 때 Offline-Mix Arena Elo가 크게 오른다고 보고한다.

- SFT D1: 1063 Elo, MT-Bench 6.98
- SFT D1 ∪ D2: 1124 Elo, MT-Bench 7.15
- SFT + DPO D1 ∪ D2: 1198 Elo, MT-Bench 7.35
- SFT + PPO D1 ∪ D2: 1205 Elo, MT-Bench 7.29
- SFT + DPO + PPO D1 ∪ D2 ∪ D3: 1219 Elo, MT-Bench 7.40

연구진은 pair-judge battle에서 나온 데이터가 SFT뿐 아니라 DPO/PPO용 고품질 pair로도 작동했다고 해석한다.

### 5.3 모델이 강해질수록 데이터 난이도도 올라갔다

반복 학습이 진행되면 쉬운 문제는 더 이상 target model을 구분하지 못한다. 그래서 다음 iteration에서는 더 어려운 battle이 남는다. 이 구조가 data flywheel이다.

데이터 플라이휠의 의미는 "더 많은 데이터"가 아니라 "현재 모델이 아직 못 이기는 더 어려운 데이터"를 계속 발견하고 학습하는 것이다.

## 6. 신뢰도와 한계

### 6.1 Judge model 신뢰도

NeurIPS 최종판은 Offline WizardArena-Mix가 LMSYS Chatbot Arena 기준 순위와 높은 일관성을 보였다고 보고한다.

| 기준 | 수치 |
| --- | ---: |
| Offline-Mix Spearman correlation | 97.76% |
| Offline-Mix average consistency | 92.80% |
| Arena-Hard average consistency | 91.57% |
| MT-Bench average consistency | 33.02% |

또한 200개 샘플에 대해 Llama3-70B-Chat judge와 professional human annotator를 비교했다. 세 비교 조건에서 Llama judge의 win rate는 34.1%, 41.3%, 79.7%였고, 인간 평가는 31.8%, 37.7%, 82.1%로 비교적 가까웠다.

### 6.2 핵심 한계

이 연구를 AIB 문서에 인용할 때 반드시 붙여야 할 한계는 다음이다.

1. 실제 LMSYS 인간 투표를 그대로 학습한 것이 아니다.
2. LLM judge가 만든 synthetic offline arena data를 사용했다.
3. 영어 중심 open-domain instruction 환경과 WizardLM 계열 target model에서 나온 결과다.
4. CJK 실사용자 선호 데이터에도 동일한 개선폭이 나온다는 증거는 아직 없다.
5. Judge model이 인간 선호를 잘 모사하지 못하면 ranking과 training data가 모두 훼손될 수 있다.

따라서 "인간 Arena vote만으로 +403 Elo가 입증됐다"는 표현은 피해야 한다.

## 7. DPO와 데이터 포맷 관점

DPO는 reward model을 별도로 학습하지 않고, 선호쌍을 직접 이용해 language model을 fine-tune하는 방법이다.

일반적인 DPO preference dataset은 다음 구조를 갖는다.

```json
{
  "prompt": "사용자 질문 또는 대화 맥락",
  "chosen": "더 선호된 응답",
  "rejected": "덜 선호된 응답"
}
```

Arena류 데이터는 본질적으로 이 구조와 잘 맞는다.

```text
사용자 prompt
모델 A 응답
모델 B 응답
사용자 또는 judge의 winner 선택
```

winner가 model A이면:

```json
{
  "prompt": "사용자 prompt",
  "chosen": "모델 A 응답",
  "rejected": "모델 B 응답"
}
```

winner가 model B이면 chosen과 rejected가 반대로 배치된다. Tie 또는 both_bad는 별도 규칙이 필요하다.

Tie 처리 선택지는 다음과 같다.

| 케이스 | 처리 방법 | 비고 |
| --- | --- | --- |
| 명확한 winner | DPO pair로 사용 | 가장 직접적 |
| tie | 제외하거나 KTO/이진 피드백으로 변환 | DPO에는 직접 부적합 |
| both_bad | negative-only 데이터, safety filter, KTO 후보 | 품질관리 필요 |
| 다중 응답 비교 | pairwise로 쪼개거나 ranking loss 사용 | GRPO/PRM/GenRM 확장 가능 |

## 8. PortableBrain 검색 결과

브레인에는 이미 AIB 관점의 관련 노트가 여러 개 있었다.

### 8.1 Arena_AI_Data_Business_Research

- item_id: `fc10910afc67b35a`
- 유형: RESEARCH
- 핵심: Arena.ai의 pairwise vote 데이터가 리더보드뿐 아니라 DPO/RLHF 학습 데이터로 전환될 수 있다는 사업 논리를 정리한 master research note.
- 관련 내용:
  - Arena 데이터 3회 반복 post-training → Elo +403pt, AlpacaEval LC +26%, MT-Bench +1.75
  - DPO는 `(prompt, chosen, rejected)` 형식이 필요하며 Arena vote와 구조적으로 맞음
  - pairwise vote가 평가 데이터와 학습 데이터 양쪽으로 수익화될 수 있음

### 8.2 포스트트레이닝·Alignment 방법론 메커니즘 레퍼런스

- item_id: `23a675c601ff9ff7`
- 유형: RESEARCH
- 핵심: RLHF, DPO, KTO, ORPO, SimPO, APO, GenRM 등 post-training 방법론을 loss와 데이터 의존성 관점에서 정리.
- AIB 시사점:
  - AIB pairwise 데이터는 DPO/RM 학습의 원료
  - RM에서 GenRM으로 이동할수록 "왜 나은지 근거가 붙은 CJK 선호"의 가치가 커짐
  - 저품질 preference pair는 모델 성능을 망칠 수 있으므로 검증 가능한 선호 데이터가 중요

### 8.3 선호도 평가 트렌드의 근본 원인

- item_id: `88eada4b38159a4f`
- 유형: RESEARCH
- 핵심: 정적 벤치마크가 포화, 오염, 측정 불일치에 부딪히면서 업계가 arena식 선호 평가로 이동하는 구조적 이유를 분석.
- AIB 시사점:
  - "한국어 아레나"는 약한 포지셔닝
  - 더 강한 포지셔닝은 "CJK 실사용자 위에서 검증 가능한 선호 데이터"
  - 해자는 투표 UI가 아니라 누구의 선호인지와 그 선호의 신뢰성

### 8.4 Arena.ai 전문가 투표의 실체

- item_id: `aa1d9c741f294463`
- 유형: RESEARCH
- 핵심: Arena Expert는 유료 전문가 패널이 아니라, LLM이 expert-level prompt를 태깅하고 그 subset의 crowd vote를 재집계하는 구조.
- AIB 시사점:
  - Arena는 실사용 crowd scale이 강점이지만 전문성 검증은 약함
  - Scale/Surge식 유료 전문가 패널은 비싸고 확장성이 낮음
  - AIB의 빈틈은 "검증 가능한 CJK 도메인 전문가/실사용자 선호 신호"

## 9. AIB 전략 해석

### 9.1 핵심 메시지

AIB는 "리더보드를 만든다"보다 "CJK 실사용자 선호 데이터를 학습 가능한 형태로 축적한다"가 더 큰 시장을 향한다.

Arena Learning은 이 전략을 기술적으로 뒷받침한다.

- Pairwise 비교는 post-training 데이터가 될 수 있다.
- 모델이 진 케이스는 약점 데이터로 가치가 높다.
- 반복 battle과 학습은 data flywheel이 될 수 있다.
- DPO/ORPO/SimPO/GenRM 흐름은 pairwise preference data 수요를 계속 만든다.

### 9.2 AIB의 차별점

Arena Learning이 증명한 것은 "pairwise battle data가 유효하다"는 점이다. 하지만 AIB가 경쟁해야 할 지점은 같은 UI가 아니다.

AIB의 차별점은 다음이어야 한다.

| 축 | 일반 Arena | AIB 기회 |
| --- | --- | --- |
| 언어 | 영어 중심, 글로벌 평균 | 한국어/일본어/CJK 실사용 맥락 |
| 선호 주체 | 익명 crowd | 검증 가능한 사용자/도메인 segment |
| 데이터 품질 | 투표 중심 | 5차원 품질 필터, style-control, burstiness, 언어 혼합도 |
| 학습 활용 | 공개 일부 데이터, 평가 중심 | B2B post-training dataset package |
| 해자 | 트래픽과 리더보드 권위 | CJK preference graph와 검증가능성 |

### 9.3 IR/피치덱용 핵심 문장

다음 문구를 권장한다.

> Microsoft/WizardLM의 Arena Learning/WizardArena 연구는 Chatbot Arena식 pairwise battle data가 단순 평가 지표를 넘어 SFT/DPO/PPO post-training 데이터 플라이휠로 전환될 수 있음을 보여준다. 해당 연구는 WizardLM-beta에서 WizardArena Elo 약 +399~403pt 및 AlpacaEval 2.0 LC win rate +26%p 수준의 개선을 보고했다. AIB는 이 구조를 CJK 실사용자 선호 데이터 영역으로 확장해, 평가와 학습 양쪽에 쓰이는 검증 가능한 preference data layer를 구축한다.

더 짧은 슬라이드용 문구는 다음이다.

> Arena votes are not just leaderboard signals. They are post-training preference data.

한국어 슬라이드용:

> 비교 투표는 순위표가 아니라 학습 데이터가 된다.

또는:

> AIB의 핵심 자산은 리더보드가 아니라 CJK 선호 학습 데이터다.

## 10. 피해야 할 표현

다음 표현은 과장 또는 부정확하게 읽힐 수 있다.

| 피해야 할 표현 | 문제점 | 안전한 대체 표현 |
| --- | --- | --- |
| 실제 인간 Arena 투표만으로 +403 Elo가 입증됐다 | 연구는 LLM judge 기반 synthetic data | LLM judge 기반 simulated arena data로 +399~403 Elo를 보고했다 |
| CJK 인간 선호 데이터도 동일하게 +403 Elo 개선된다 | AIB 자체 실증 전에는 미검증 | CJK 선호 데이터도 같은 형식의 학습 신호가 될 가능성이 높으며, AIB 실험으로 검증할 계획 |
| Arena UI가 해자다 | Arena UI는 이미 commodity | 해자는 선호 모집단과 검증가능성 |
| 선호 데이터는 모두 DPO에 바로 넣으면 된다 | tie, noisy vote, length bias, model identity leakage 처리 필요 | 품질관리와 포맷 변환 후 DPO/ORPO/RM 학습에 투입 가능 |

## 11. AIB 후속 실험 설계 제안

이제 필요한 것은 AIB 자체의 작은 실증이다. 외부 연구 근거를 "우리 데이터도 된다"로 바꾸려면 다음 미니 실험이 적합하다.

### 11.1 목표

CJK 실사용자 preference data가 실제 post-training 성능 개선으로 이어지는지 검증한다.

### 11.2 데이터셋

초기 규모는 2,000~5,000 preference pairs로 충분하다.

필수 필드:

```json
{
  "prompt": "...",
  "chosen": "...",
  "rejected": "...",
  "language": "ko | ja | zh | mixed",
  "domain": "learning | coding | work | creative | daily | expert",
  "evaluator_segment": "student | professional | domain_expert | general_user",
  "vote_reason": "...",
  "length_metadata": {},
  "style_metadata": {},
  "quality_flags": {}
}
```

권장 메타데이터:

- 응답 길이
- heading/list/bold 사용량
- 언어 혼합도
- 중복도
- burstiness
- evaluator 신뢰도
- prompt 난이도
- domain tag
- tie/both_bad 여부

### 11.3 실험 모델

비용을 낮추려면 7B급 또는 8B급 오픈모델을 사용한다.

후보:

- Qwen 계열 7B/8B
- Llama 계열 8B
- Gemma 계열
- 한국어 성능이 있는 경량 모델

### 11.4 학습 방식

최소 실험:

1. Base/SFT model 준비
2. AIB preference pair로 DPO 또는 ORPO 학습
3. Held-out Korean/Japanese/CJK prompt set에서 blind pairwise evaluation
4. 길이 편향 제거 전후 결과 비교

확장 실험:

1. DPO vs ORPO vs SimPO 비교
2. vote_reason을 활용한 GenRM 후보 실험
3. 일반 crowd vs 검증 사용자 segment 비교
4. 한국어 only vs CJK mixed 비교
5. length/style metadata 필터링 전후 비교

### 11.5 성공 기준

초기 실험의 성공 기준은 거창할 필요가 없다.

- Held-out CJK preference win rate +5~10%p
- 한국어 subjective quality 평가에서 유의미한 선호 상승
- 길이 편향 통제 후에도 개선 유지
- 특정 domain에서 AIB data-trained model이 baseline 대비 우세
- noisy pair 제거 후 성능 개선폭 증가

핵심은 +400 Elo 재현이 아니다. AIB 데이터가 "학습 가능한 신호"라는 첫 증거를 만드는 것이다.

## 12. 제품/데이터 패키지 관점

AIB가 장기적으로 판매할 수 있는 데이터 패키지는 단순 CSV가 아니라 post-training ready dataset이어야 한다.

### 12.1 기본 패키지

```text
AIB-CJK-Preference-v1
- prompt
- chosen
- rejected
- language
- domain
- evaluator_segment
- vote_reason
- quality_flags
- metadata for length/style/burstiness
```

### 12.2 고급 패키지

```text
AIB-CJK-Preference-Pro
- verified evaluator segment
- domain-specific split
- hard/expert prompt subset
- tie/both_bad labeled data
- style-controlled preference subset
- GenRM-ready rationale field
- train/validation/test split
```

### 12.3 세일즈 포지션

평가 시장용:

> CJK market-specific model preference benchmark.

학습 시장용:

> Post-training ready CJK preference dataset for DPO, ORPO, RM, and GenRM.

전략 문구:

> AIB is not only measuring which model users prefer. AIB is producing the preference data that future CJK models need to learn from.

## 13. 최종 정리

Arena Learning/WizardArena는 AIB에게 "리더보드 이후의 시장"을 설명하는 근거다. 평가 데이터는 일회성 점수가 아니라 모델 개선에 재투입되는 데이터 플라이휠의 입력이 될 수 있다.

하지만 이 근거는 그대로 과장하면 위험하다. 핵심은 "실제 인간 Arena 투표가 +403 Elo를 만들었다"가 아니라 "Arena식 pairwise battle data가 post-training 데이터로 전환될 수 있고, synthetic offline arena에서 그 효과가 실험적으로 확인됐다"이다.

AIB의 다음 과제는 이 논리를 CJK 실사용 데이터로 자체 검증하는 것이다. 작은 DPO/ORPO 실험만 성공해도 AIB의 내러티브는 "한국어 리더보드"에서 "CJK preference data layer"로 격상된다.

## 14. 참고 링크

- Arena Learning arXiv: https://arxiv.org/abs/2407.10627
- Microsoft Research page: https://www.microsoft.com/en-us/research/publication/arena-learning-build-data-flywheel-for-llms-post-training-via-simulated-chatbot-arena/
- NeurIPS 2024 WizardArena paper PDF: https://proceedings.neurips.cc/paper_files/paper/2024/file/ca4aa9acc097e0f606af55bf986cb031-Paper-Conference.pdf
- DPO original paper: https://arxiv.org/abs/2305.18290
- Hugging Face TRL DPO Trainer: https://huggingface.co/docs/trl/en/dpo_trainer
- Chatbot Arena paper: https://arxiv.org/abs/2403.04132
- LMSYS Chatbot Arena dataset release: https://www.lmsys.org/blog/2023-07-20-dataset/
- LMArena arena-human-preference-140k dataset: https://huggingface.co/datasets/lmarena-ai/arena-human-preference-140k
- Arena Expert blog: https://arena.ai/blog/arena-expert/
- LMArena arena-expert-5k dataset: https://huggingface.co/datasets/lmarena-ai/arena-expert-5k

## 15. PortableBrain 참고 노트

- `fc10910afc67b35a` - Arena_AI_Data_Business_Research
- `23a675c601ff9ff7` - 포스트트레이닝·Alignment 방법론 메커니즘 레퍼런스 (2026.06)
- `88eada4b38159a4f` - 선호도 평가 트렌드의 근본 원인
- `aa1d9c741f294463` - Arena.ai 전문가 투표의 실체
