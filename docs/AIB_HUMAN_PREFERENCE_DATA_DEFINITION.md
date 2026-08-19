# 인간 선호 데이터 정의와 데이터 가치 비교

작성일: 2026-07-01

## 1. 핵심 결론

RLHF, DPO, reward model training, model evaluation에서 말하는 인간 선호 데이터는 단순히 "사람이 쓴 답변"이 아니다.

정확한 정의는 다음이다.

> 인간 선호 데이터(human preference data)는 같은 입력 또는 context에 대해 생성된 둘 이상의 후보 출력 중, 인간 평가자가 어느 출력이 더 낫다고 판단했는지를 기록한 비교, 순위, 점수, 이유 데이터다.

가장 표준적인 최소 단위는 `2개 중 1개`를 고르는 pairwise preference다.

```json
{
  "prompt": "...",
  "chosen": "인간이 더 선호한 응답",
  "rejected": "인간이 덜 선호한 응답"
}
```

이 구조는 DPO에 바로 들어갈 수 있고, reward model 학습에도 가장 널리 쓰인다.

## 2. 인간 선호 데이터에 포함되는 것

인간 선호 데이터는 여러 형태를 가질 수 있다.

| 형태 | 설명 | 활용 |
| --- | --- | --- |
| Pairwise comparison | 응답 A와 B 중 어느 쪽이 더 나은지 선택 | DPO, RLHF reward model, Arena |
| N-way best choice | N개 응답 중 가장 좋은 하나 선택 | chosen vs rejected pair 여러 개 생성 |
| N-way ranking | N개 응답 전체를 1위부터 N위까지 정렬 | reward model 학습에 풍부한 순위 신호 |
| Rating | 응답 하나에 1~5점 또는 1~7점 부여 | 평가, reward modeling, calibration |
| Rubric scoring | 정확성, 안전성, 친절함, 간결함 등 항목별 점수 | 전문가 데이터, B2B 평가 |
| Preference with rationale | 왜 이 응답이 더 나은지 설명까지 기록 | GenRM, 품질관리, 세일즈 가치 상승 |
| Expert preference | 도메인 전문가가 평가한 선호 | 의료, 법률, 코드, 금융 등 고가 데이터 |
| Collective preference | Reddit/StackExchange vote처럼 집단 반응에서 추론한 선호 | Stanford SHP류 dataset |

핵심은 후보 출력 사이의 상대적 품질 판단이 있어야 한다는 점이다.

## 3. 인간 선호 데이터가 아닌 것

다음은 비슷해 보이지만 엄밀히는 human preference data가 아니다.

| 데이터 | 왜 다른가 |
| --- | --- |
| 사람이 직접 쓴 정답 예시 | SFT/demonstration data이지 preference data는 아님 |
| 일반 대화 로그 | 선호 라벨이 없으면 학습 가능한 preference signal이 아님 |
| 사용자 질문만 모은 데이터 | 후보 응답 간 비교가 없음 |
| AI judge가 만든 chosen/rejected | synthetic preference 또는 RLAIF 데이터이지 human preference는 아님 |
| Red-teaming transcript 자체 | 위험도, 성공 여부, 선호 라벨이 붙어야 feedback data가 됨 |

정리하면:

> 사람의 출력이 아니라, 사람의 판단이 들어간 데이터가 인간 선호 데이터다.

## 4. RLHF에서의 사용 방식

전통적 RLHF에서는 인간 선호 데이터가 reward model을 학습시키는 데 쓰인다.

일반적인 파이프라인은 다음과 같다.

1. Prompt를 준비한다.
2. 모델이 같은 prompt에 대해 여러 응답을 생성한다.
3. 인간 평가자가 응답들을 비교하거나 순위화한다.
4. 이 비교 데이터를 사용해 reward model을 학습한다.
5. Reward model은 새 응답에 scalar reward를 부여한다.
6. PPO 같은 RL 알고리즘으로 policy model을 최적화한다.

즉 RLHF에서 인간 선호 데이터는 "정답 텍스트"라기보다 "보상 함수를 학습하기 위한 인간 판단 기록"이다.

OpenAI InstructGPT는 labeler가 모델 출력들을 비교한 데이터를 모아 reward model이 labeler가 선호할 출력을 예측하게 했고, 그 reward model을 PPO의 reward function으로 사용했다.

## 5. DPO에서의 사용 방식

DPO는 reward model과 PPO 단계를 생략한다.

대신 같은 선호쌍을 모델 학습에 직접 사용한다.

```json
{
  "prompt": "질문 또는 대화 맥락",
  "chosen": "더 좋은 응답",
  "rejected": "덜 좋은 응답"
}
```

DPO는 같은 prompt에 대해 chosen의 상대 확률을 올리고 rejected의 상대 확률을 낮추는 방향으로 모델을 학습한다.

따라서 Arena류 pairwise vote는 DPO용 데이터로 전환하기 쉽다.

```text
사용자 prompt
응답 A
응답 B
사용자의 winner 선택
```

winner가 A이면:

```json
{
  "prompt": "사용자 prompt",
  "chosen": "응답 A",
  "rejected": "응답 B"
}
```

winner가 B이면 chosen과 rejected가 반대로 배치된다.

## 6. 2개 중 1개인가, N개 중 1개인가

둘 다 가능하다.

다만 표준 최소 단위는 `2개 중 1개`다.

| 방식 | 데이터 형태 | 특징 |
| --- | --- | --- |
| 2개 중 1개 | `chosen/rejected` | DPO와 Arena의 기본 형태 |
| N개 중 1개 | `chosen + 여러 rejected` | winner와 나머지 사이 pair 생성 가능 |
| N개 전체 순위 | `A > C > B > D` | 모든 응답 간 pairwise 관계 생성 가능 |
| N개 순위 + 이유/rubric | ranking + rationale + score | 가장 고급 데이터 |

### 6.1 2개 중 1개

예:

```text
Prompt: 한국어 자기소개서를 다듬어줘.
Response A
Response B
User choice: A
```

변환:

```json
{
  "prompt": "한국어 자기소개서를 다듬어줘.",
  "chosen": "Response A",
  "rejected": "Response B"
}
```

장점:

- 사용자가 판단하기 쉽다.
- 라벨링 시간이 짧다.
- 모바일/B2C UI에 적합하다.
- DPO 포맷으로 바로 변환된다.
- 대량 수집에 유리하다.

단점:

- 한 번의 판단에서 얻는 정보량은 제한적이다.
- 3개 이상의 후보 사이 전체 우열은 알 수 없다.

### 6.2 N개 중 최고 1개 선택

예:

```text
Prompt: 이 메일을 정중하게 바꿔줘.
Response A
Response B
Response C
Response D
User choice: A
```

이 경우 다음 pair를 만들 수 있다.

```text
A > B
A > C
A > D
```

4개 중 1개를 고르면 `N - 1`, 즉 3개의 pairwise signal이 생긴다.

장점:

- pairwise 1건보다 정보량이 많다.
- winner가 여러 후보를 이겼다는 강한 신호가 된다.

단점:

- 나머지 B, C, D 사이의 우열은 모른다.
- 사용자가 후보가 많아질수록 피로해진다.

### 6.3 N개 전체 순위화

예:

```text
A > C > B > D
```

4개 전체 ranking에서는 다음 6개 pair가 나온다.

```text
A > C
A > B
A > D
C > B
C > D
B > D
```

일반적으로 N개 전체 순위는 `N * (N - 1) / 2`개의 pairwise 관계를 만든다.

| N | 생성 가능한 pair 수 |
| ---: | ---: |
| 2 | 1 |
| 3 | 3 |
| 4 | 6 |
| 5 | 10 |

장점:

- 한 annotation에서 가장 많은 정보를 얻는다.
- reward model 학습에는 pairwise보다 더 풍부하다.
- 여러 모델의 상대 위치를 추정하기 좋다.

단점:

- 평가자 피로도가 높다.
- 후보가 많아질수록 판단 일관성이 떨어질 수 있다.
- B2C 사용자에게는 부담이 크다.
- 전문가 라벨링 비용이 올라간다.

## 7. 어떤 데이터가 더 값어치가 높은가

정답은 목적에 따라 다르다.

1건당 데이터 값어치는 일반적으로 다음 순서다.

```text
N개 순위 + 이유/rubric > N개 전체 순위 > N개 중 최고 1개 > 2개 pairwise
```

하지만 비용 대비 효율은 반대에 가깝다.

```text
2개 pairwise > N개 중 최고 1개 > N개 전체 순위 > N개 순위 + 이유/rubric
```

즉:

> 1건당 정보량은 N개 ranking이 높고, 대량 수집성과 품질 안정성은 2개 pairwise가 높다.

## 8. 데이터 가치 비교표

| 기준 | 2개 pairwise | N개 중 최고 1개 | N개 전체 ranking | Ranking + 이유/rubric |
| --- | --- | --- | --- | --- |
| 사용자 난이도 | 낮음 | 중간 | 높음 | 매우 높음 |
| 수집 속도 | 빠름 | 중간 | 느림 | 느림 |
| 라벨 일관성 | 높음 | 중간 | 중간~낮음 | 평가자 품질에 따라 다름 |
| DPO 적합도 | 매우 높음 | 높음 | pair로 변환 필요 | 높음 |
| RM 학습 가치 | 기본 | 중간 | 높음 | 매우 높음 |
| GenRM 가치 | 낮음 | 낮음~중간 | 중간 | 매우 높음 |
| 판매 단가 | 낮음~중간 | 중간 | 높음 | 최고 |
| B2C 적합도 | 매우 높음 | 중간 | 낮음 | 낮음 |
| 전문가 데이터 적합도 | 중간 | 높음 | 높음 | 매우 높음 |

## 9. 사업적으로 보는 데이터 단가의 차이

단순 pairwise vote는 원자재에 가깝다.

```json
{
  "prompt": "...",
  "response_a": "...",
  "response_b": "...",
  "winner": "a"
}
```

이 데이터도 DPO에는 충분히 가치가 있다. 하지만 판매 단가를 높이려면 다음 정보가 붙어야 한다.

- 평가자의 언어권
- 평가자의 전문성
- 평가자의 신뢰도
- 평가 이유
- rubric 점수
- prompt domain
- prompt 난이도
- 모델명 blind 여부
- 위치 편향 통제 여부
- 길이/서식 편향 metadata
- 다중 평가자 agreement
- train/validation/test split

고급 preference data package는 다음처럼 구성된다.

```json
{
  "prompt": "...",
  "responses": [
    {"id": "A", "text": "..."},
    {"id": "B", "text": "..."},
    {"id": "C", "text": "..."},
    {"id": "D", "text": "..."}
  ],
  "ranking": ["A", "C", "B", "D"],
  "pairwise_pairs": [
    {"chosen": "A", "rejected": "C"},
    {"chosen": "A", "rejected": "B"},
    {"chosen": "A", "rejected": "D"},
    {"chosen": "C", "rejected": "B"},
    {"chosen": "C", "rejected": "D"},
    {"chosen": "B", "rejected": "D"}
  ],
  "rubric": {
    "correctness": 5,
    "helpfulness": 5,
    "safety": 4,
    "conciseness": 3,
    "cultural_fit": 5
  },
  "rationale": "A가 가장 정확하고 한국어 표현이 자연스러우며, C는 유용하지만 일부 설명이 장황하다.",
  "annotator_profile": {
    "locale": "ko-KR",
    "segment": "domain_expert",
    "expertise": "software_engineering",
    "verified": true
  },
  "quality_metadata": {
    "position_swapped": true,
    "model_names_hidden": true,
    "agreement_score": 0.82
  }
}
```

이런 데이터는 단순 leaderboard vote보다 훨씬 비싸게 팔릴 수 있다.

## 10. AIB 관점의 권장 전략

AIB는 한 가지 방식만 선택할 필요가 없다.

추천 구조는 이렇다.

### 10.1 일반 사용자 UI

일반 사용자에게는 2개 pairwise comparison이 적합하다.

```text
두 답변 중 어느 쪽이 더 좋나요?
```

이유:

- 참여 장벽이 낮다.
- 모바일 UI에 적합하다.
- 데이터가 빠르게 쌓인다.
- DPO 포맷으로 바로 변환된다.
- Arena식 리더보드와 잘 맞는다.

이 계층의 데이터는 대량 원자재다.

### 10.2 고가치 prompt 또는 전문가 평가

중요한 prompt, hard prompt, domain-specific prompt에서는 N-way ranking을 쓴다.

```text
아래 4개 응답을 가장 좋은 순서대로 정렬해주세요.
```

또는:

```text
가장 좋은 응답을 고르고, 왜 그런지 한 줄로 설명해주세요.
```

이 계층의 데이터는 고급 판매용 정제 데이터다.

### 10.3 B2B 판매 패키지

AIB는 데이터를 두 층으로 제품화할 수 있다.

| 제품 | 구성 | 고객 |
| --- | --- | --- |
| AIB-CJK-Preference-Basic | 대량 pairwise chosen/rejected | DPO/ORPO 학습 고객 |
| AIB-CJK-Preference-Pro | 전문가 ranking + rationale + rubric + metadata | frontier lab, enterprise model team |
| AIB-CJK-Eval-Set | held-out prompt + blind evaluation + agreement | 모델 평가/벤치마크 고객 |
| AIB-CJK-GenRM-Data | preference + rationale + rubric | reward/judge model 학습 고객 |

## 11. AIB 핵심 문구

짧은 정의:

> 인간 선호 데이터는 "사람이 쓴 답"이 아니라 "사람이 어떤 답을 더 낫다고 판단했는지"에 대한 구조화된 학습 신호다.

2개 vs N개 가치 설명:

> 2개 pairwise는 가장 싸고 빠르게 대량 수집할 수 있는 기본 preference unit이고, N개 ranking은 1건당 정보량이 높아 reward model과 고급 평가 데이터셋에 더 값어치가 크다.

AIB 전략 문구:

> AIB는 일반 사용자에게는 쉬운 2-way 비교를 제공해 대량 CJK preference pair를 축적하고, 고가치 영역에서는 전문가 N-way ranking과 rationale을 결합해 post-training ready dataset으로 제품화한다.

더 짧은 슬라이드 문구:

> 2-way vote scales. N-way ranking sells premium.

한국어 슬라이드 문구:

> 2개 비교는 대량 수집용, N개 순위화는 고급 판매용.

## 12. 주의할 점

2개 pairwise가 싸다고 해서 가치가 낮은 것은 아니다. DPO에는 2개 pairwise가 가장 직접적이다.

반대로 N개 ranking이 항상 더 좋은 것도 아니다. 평가자가 피로해지고 순위 일관성이 낮아지면 노이즈가 커진다.

따라서 중요한 것은 annotation design이다.

| 상황 | 추천 방식 |
| --- | --- |
| 일반 사용자 참여 | 2개 pairwise |
| 모바일/게임형 UI | 2개 pairwise |
| 빠른 대량 수집 | 2개 pairwise |
| 전문가 소수 평가 | 3~5개 ranking |
| 모델별 세밀 비교 | N-way ranking |
| DPO 학습 데이터 | 2개 pairwise 또는 N-way에서 변환 |
| Reward model 학습 | pairwise 대량 + ranking 일부 |
| GenRM/judge model 학습 | ranking + rationale + rubric |

## 13. 참고 링크

- OpenAI InstructGPT paper: https://cdn.openai.com/papers/Training_language_models_to_follow_instructions_with_human_feedback.pdf
- DPO paper: https://arxiv.org/abs/2305.18290
- Hugging Face TRL DPOTrainer: https://huggingface.co/docs/trl/en/dpo_trainer
- Anthropic HH-RLHF dataset: https://huggingface.co/datasets/Anthropic/hh-rlhf
- Label Studio Human Preferences for RLHF template: https://labelstud.io/templates/generative-pairwise-human-preference
- Stanford SHP-2 dataset: https://huggingface.co/datasets/stanfordnlp/SHP-2
- Scale Generative AI Data Engine: https://scale.com/generative-ai-data-engine
- Surge AI Anthropic RLHF case: https://surgehq.ai/blog/anthropic-surge-ai-rlhf-platform-train-llm-assistant-human-feedback
- RLHF Book, Preference Data: https://rlhfbook.com/c/11-preference-data

## 14. PortableBrain 참고 노트

- `b36e65a1b88f7034` - RLHF·선호 데이터의 미래 — 다각도 검토와 전망
- `fc10910afc67b35a` - Arena_AI_Data_Business_Research
- `23a675c601ff9ff7` - 포스트트레이닝·Alignment 방법론 메커니즘 레퍼런스 (2026.06)
