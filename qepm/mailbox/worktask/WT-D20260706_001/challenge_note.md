# Self-Adversarial Challenge Note — WT-D20260706_001 (Alpha)

**대상**: mega-cap 앵커 구성 screening-tier 재현 alpha_package_draft.json
**방식**: v8.2 Self-Adversarial (Opus 4.8 native, 외부 Codex 없음). finalize 직전 devil's advocate.
**규율**: measurement-graduation §1 (proxy 손계산 금지 — 모든 반론을 build_benchmark_compare 실측으로 규명). No Silent Override.

---

## Concern 1 (HIGH) — "앵커 개선은 mega-cap beta 국면 harvest지 진짜 구성효과 아니다"

**devil's advocate**: 삼성/하이닉스 20%cap 앵커가 PORT_t를 3.78→4.75로 올린 건 2020~2024 반도체 대형주 강세를 사후적으로 올라탄 beta harvest일 뿐. 알파 아님.

**분류: REBUTTAL (실측 근거 3축)**
1. **특정성 실측 (CH-C2)**: 임의 top-2(3~4위 cap) 앵커 PORT_t = **1.404** ≪ 삼성/하이닉스 앵커 4.751. "아무 대형주"로는 개선 안 됨 → 효과는 **벤치를 실제 지배하는 top-2에 특정적** = mega-cap *gap* 메커니즘 확증 (임의 beta harvest 아님).
2. **alpha-fill vs bottom-fill (partC)**: alpha-fill이 bottom-fill 대비 full +5.71 / 2017+ +1.85 우월. 앵커를 고정한 채 fill을 반전하면 무너짐 → fill selection(score_eff)의 실 알파 기여 존재.
3. **placebo (partC)**: random-fill 150 draw p=0.0000. 앵커 고정, fill만 랜덤화한 clean null 대비 유의.
- **학술 근거**: mega-cap 집중 벤치 대비 분산북의 구조적 tracking gap은 KR post-2017 실증 (reference-kr-2025-megacap-semi-regime — 삼성6x/하이닉스14x 연속, BM+227%<CW+374%).
- **잔여 caveat**: beta harvest 성분이 0은 아님. 2017+ edge(+1.85)가 full(+5.71)보다 축소 = 최근 fill 알파 기여 약화, 앵커 beta 의존도 상승. → CF-5로 명시 유지.

---

## Concern 2 (HIGH) — "paired-active NW-t = -1.923 음수 = anchored가 base보다 실제로 못하다"

**devil's advocate**: SR/PORT_t 헤드라인만 좋고, 월별 active-diff의 paired NW-t가 음수면 anchored는 base 대비 통계적으로 우월하지 않다. 헤드라인 cherry-pick.

**분류: PARTIAL (음수 인정 + 규명, 단 thesis와 정합)**
- **원인 규명 (CH-C1 국면분해)**:
  - 2004~2016: paired diff −0.0074, **NW-t −3.70** (base active 0.0164 > anchored 0.0090) ← 음수 paired-t의 원흉. pre-2017엔 base(순수 알파)로 충분, 앵커 불필요.
  - 2017~2020: +0.649 / 2021~2026: **+1.268** (base 2021+ active −0.0003로 사멸). post-2017엔 anchored 우월.
- **SR vs 초과수익 (CH-C1b)**: anchored active sd 0.0262 ≪ base 0.0433. base mean active 0.0102 > anchored 0.0077. → **앵커의 SR/PORT_t 상승은 초과수익 증대가 아니라 tracking-vol 축소(분모)에서 상당부분**.
- **처리**: "anchored가 전기간 일관 우월"이라 주장하지 **않음**. 정직한 명제 = "①post-2017 mega-cap 레짐에서 우월 + ②전기간 tracking-vol 축소로 SR 개선". thesis(post-2017 gap 레버)와 **완벽 정합** — 앵커는 조건부(post-2017) 레버.
- **governor 핸드오프 경고 강화**: book-marginal ΔIR 판정 시 이 tension이 재현됨. incumbent 대비 ΔIR이 pre-2017 포함 전기간 평균에서 희석될 수 있음. paired-active NW-t 음수를 governor에 명시 surface (CF-2 유지).

---

## Concern 3 (HIGH) — "40% 단일 2종목 집중은 배포 불가 리스크"

**devil's advocate**: 삼성+하이닉스 40% 고정은 헌법 weight bound [0,0.20]는 지키나(각 20%), 2종목 40% + 반도체 단일섹터 집중 = 특정 국면(반도체 급락) 파국 리스크. 배포 부적격.

**분류: ACCEPT (집중 리스크 인정 — risk/governor 영역으로 명시 이관)**
- **집중 실측**: 앵커 40% 고정 vs 벤치 실제 top-2 share mean 26.8%/max 40.2% (partD). 앵커 40%가 벤치 실share를 초과하는 국면 존재 → 순수 벤치-정합이 아니라 벤치-초과 틸트인 구간 있음.
- **처리**: 이건 alpha 영역에서 해소 불가 — **risk agent 집중/stress/regime-beta 거버넌스** + **governor 자본 판정(도훈 수동)** 대상. CF-3로 명시 + handoff에 상세 기록.
- **optimizer 완화 여지 (CH-C3)**: cap-proportional 앵커 PORT_t 5.200 > 20%flat 4.751. **동적 cap-proportional 앵커가 (a)PORT_t 더 높고 (b)벤치 실share 추종으로 집중 초과 완화** → optimizer 탐색 강력 권고. 40% flat이 최적이라 단정하지 않음.

---

## Concern 4 (MEDIUM) — "screening EW-fill 근사가 production STR_1715와 다르다"

**devil's advocate**: screening은 EW-fill + 재구성 selection. production은 LinearTilt λ1.5 + 유동성 + TOphi + overlay. screening 4.75가 production forge서 재현 안 될 수 있다.

**분류: PARTIAL (인정 — forge milestone 게이트로 이관)**
- alpha 영역에서 production 완전 재현은 forge 권한 (build_bt_result authoritative). screening은 alpha 검증 증거(canonical top-N)로만 유효, 최종 authoritative 아님 (명시).
- CF-4 + next_verification_points에 "forge production selection+앵커 재측정 = milestone 관건" 명시.

---

## Concern 5 (MEDIUM) — self-rationalization 자기검증

**금지어 스캔** ("미미/관행적/실무적/보수적이면 OK/대부분 동일"): draft/probe에서 **미사용**. 모든 판정을 실측 수치로 규명. 
- oos 0.526을 "0.7에 거의 근접하니 OK"로 합리화하지 **않음** → band[0.5,0.7) HARD 미달 명시 + 조건부 증거 3/3은 screening proxy임을 명시 + forge 재판정 필수.

---

## Escalation 판정
- HIGH severity flag = 3건 (CF-1/2/3). 자동 escalate trigger(HIGH≥5)는 **미달** → escalate 불요.
- AX axiom hard FAIL = 0. PIT C1(lockbox·lookahead) 위반 = 없음 (lag1 graceful + size_lag t-1).
- **판정: 재현 성공 + thesis 강건 + 3 caveat(oos band / paired-t 음수 / 40% 집중)을 정직 surface. risk→optimizer→forge 진행 권고. 최종 milestone은 forge-authoritative.**

## Verification Triangulation (AX-008, 3-source 중 self 1개)
- self-adversarial: 완료 (본 note). 잔여 2 source = forge(build_bt_result) + architect(온디맨드) — Q-Lead orchestration.
