# Challenge Note — WT-D20260802_009 (Self-Adversarial, v8.2)

**작성**: alpha-research agent, finalize 직전. Charter §8 No Silent Override.
**대상**: 대표 스마트베타 5종 수리 튜닝 paired A/B (사전등록 `stage_artifacts/WT_D20260802_009/preregistration.json`).

## Concern 목록 (자기 비평 — devil's advocate)

### C1 [HIGH] P2(모멘텀 경로효율) 문턱 통과의 기전 귀속 — **PARTIAL**
- **반론**: paired t +2.03은 문턱(2.0) 경계선이고, 사전등록 반증검정 F2(경로 조성 차별화)가 t=+1.05로 **미통과** (jc 0.339→0.330, pair self-cor 0.977 — 포트가 거의 동일). 개선 +2.93%/yr이 "경로 질"에서 온다는 주장 근거 부족. 대안설명: E=순변화/총변동의 분모가 vol에 비례 → 암묵적 저변동 tilt 아티팩트 가능.
- **판정 근거 (probe_challenge.R 실측)**: ① score-diff vs D03z(저변동+) 월평균 Spearman **+0.108** — tilt 실재하나 약함. ② 방향 논리: 저변동 arm 자체가 PORT_t −1.43(음수)이므로 "저변동 tilt가 개선을 만든다"는 대안설명은 tail-국소 효과(모멘텀 top-tail 내 최고변동 종목 제거)로만 성립 가능 — 전면 기각도 전면 수용도 불가. ③ 부기간: 개선이 pre2015(+2.84)에 편중, 2015-19 음수(−0.85), 2020+ +0.96.
- **처리**: 교체 후보 보고는 유지하되(사전등록 문턱 충족 — 사후 강등은 그것대로 규약 위반) **"통계 문턱 충족·기전 미확증" 라벨을 1급으로 병기**. 교체 confirm 전 후속 사전등록 검증(P2-NP1) 권고. 대안설명 검정치(+0.108)와 F2 미통과를 alpha_package challenge_flags HIGH로 기록.

### C2 [MEDIUM] 5-가설 family-wise 시각 — **ACCEPT**
- **반론**: 5개 독립 paired 검정 중 최고치가 2.03. 독립 null 5개에서 max t≥2.0 확률 ≈ 11% — "5개 중 1개 문턱 통과"는 family 수준에서 약한 증거.
- **처리**: chain(팩터별 독립 가설, argmax 선택 없음)이라 DSR 게이트 비발동은 규약대로이나, family-wise 관점 caveat를 alpha_validation과 보고서에 명기. graduation 권위는 어차피 forge 2.95 — 본 라운드는 screening.

### C3 [MEDIUM] 라운드 중 하네스 오용 발견·수리 (1차 측정 무효) — **ACCEPT (documented)**
- **사실**: 1차 eval은 scores를 유니버스로 선-제한하지 않아 canonical의 "adv 결측=통과" 유동성 시맨틱과 결합, top-25가 비유니버스 DB 종목(Ret_1m NA→0)으로 채워져 전 arm 수치 무효(포트 연vol 1.5% 물리불가로 적발 — random-25 통제 t −3.2가 하네스 구조 결함 확증). 유니버스 선-제한 수리 후 전량 재측정. 수리 전후 신호·문턱·설계 변경 0 (선택 오염 없음).
- **잔여**: 무효 run의 lag1/random 사이드카 엔트리 잔존(위생 — 판정 무관). canonical_screen_bt의 caller-책임 시맨틱은 재발 위험 → next_probe 배관 제안(NP-5).

### C4 [MEDIUM] P3 해석 — 더 나은 추정기가 더 나쁜 포트 — **ACCEPT (config-scoped)**
- **사실**: F3에서 EWMA가 미래 21d vol 예측 MSE를 26% 낮추고 월 승률 92% (추정기로서 우월 — 기전 지지, 단 NW t +1.03은 위기월 팻테일로 유의성 약함). 그러나 paired −1.74: 정렬 방향(저변동 롱)의 top-25 소비 자체가 손실 프레임(base −1.43)이라 **측정 순도 상승 = 손실 노출 순화**. AX-001 렌즈도 개선 없음(MDD 60.1→62.6%, CRISIS active −0.18→−0.39%/월).
- **처리**: "EWMA 추정기 우월" 능력은 확립(F3), 소비처는 알파 랭킹이 아니라 리스크 모델(Σ)·vol-targeting 입력 — 소비면 이식 next_probe(NP-2). 판정은 config-scoped(top-25 EW alpha 소비 한정).

### C5 [LOW] EB 파라미터화의 검정력 — **ACCEPT (한계 명시)**
- **반론**: tau²=1 고정 EB는 w 중앙값 0.98(self-cor 0.994~0.995) — 거의 항등변환이라 paired 검정이 저검정력. "shrinkage가 무효"가 아니라 "온건한 shrinkage가 무효"만 입증됨.
- **처리**: 결과 해석을 "이 파라미터화의 무효"로 한정(사전등록 no-sweep 준수 — 강한 prior 재시도는 본 라운드에서 하지 않음). 월별 empirical tau² 추정판은 NP-3으로 승계. F4/F5(σ² → 익월 z-이동 예측, t +13.4/+44.6)로 노이즈-식별 자체는 강하게 성립 — 기전은 살아있고 강도가 부족.

### C6 [INFO] 병렬 인프라 결함 발견 2건 — **ACCEPT (별건 처리)**
- ast_compile factor_db_monthly provider 1개월 stale(93/258 달, WT-004/006 패널 영향 — lag 방향이라 lookahead 아님) → spawn_task 발행 완료(task_5fef96aa). 본 WT base 패널은 connector 직접 경유로 무영향(parity: 정렬 165개월 diff 0 + stale 93개월 전월 정확 일치로 기전 확정).
- registry D03의 C13 정렬 실효 방향은 본 데이터에서 저변동 롱(s=+1 278/295개월) — WT-004 기록("5축 IC>0 고변동 롱")과 상반 서술이므로 소비자별 재확인 필요(정렬은 expanding-IC라 시기·집합 의존).

### C7 [LOW] P1 가치의 이중 결과 — **ACCEPT**
- 섹터-상대화는 사전등록 전제(F1: base top-25 섹터 집중, HHI t=+3.34)를 확증했으나 수익은 감소(paired −0.77). 해석: raw B/M의 섹터 베팅 성분 자체가 이 표본에서 수익 원천이었음 — "더 순수한 저평가 측정 = 더 나은 수익"이 아님을 실측. 단 P1은 5×5 상관 개선의 최대 기여자(self-cor 0.582, mean|offdiag| 0.209→0.145) — 풀 breadth 관점 가치는 잔존, 라우팅은 다팩터 합성 맥락.

## Self-rationalization auto-detection
answer-principles 회피표현 목록(축소·관행·결과동일성 계열 합리화 어휘 일체)을 본 노트·패키지 서술에서 사용하지 않았음을 점검 완료. 게이트 통과 주장에 proxy 수치 미사용(전 수치 metric_type=canonical_screen 라벨). P2를 문턱 통과로 보고하면서 반증 미통과 병기를 누락하는 패턴을 자가 적발 대상으로 지정 → challenge_flags CF-01에 1급 병기로 처리.

## Escalation 판정
HIGH 1건(C1, PARTIAL 처리) — HIGH ≥5 아님 / AX hard FAIL 0 / PIT C1 위반 0 → Q-Lead 자동 escalate 비발동.
