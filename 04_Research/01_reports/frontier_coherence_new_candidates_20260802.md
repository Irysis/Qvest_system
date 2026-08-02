# 정합 스크린 수리로 새로 드러난 후보 7건 — 판정 기록 (2026-08-02)

`frontier_registry_coherence.R` 의 대상 선정이 `startsWith(status, OPEN)` 이라 **status 의
`frontier_open` 이 접미로 오는 8건**(open 후보의 19%)이 스캔 밖에 있었다. 수리 후 실원장
후보 **12 → 19건**(like-for-like, main 현행 코드 기준). 아래가 새로 드러난 7건이다.

> ⚠ 이 스크린은 **판정이 아니라 후보 생성기**다(도구 헤더 명시). 아래 "판정" 열은 내가 실제로
> 원문을 읽은 건에만 채웠고, 나머지는 **미판정**으로 남긴다 — 미판정을 '이상 없음'으로
> 흘리지 않는다.

| FQ | 저촉 | 판정 |
|---|---|---|
| FQ-035 (R22 포렌식 이벤트 재과녁) | DIST-AR-018 | **정탐 — 소비됨** |
| FQ-036 (R23 제출지연×심각사건) | DIST-AR-018 | **정탐 — 소비됨** |
| FQ-037 (R24 전체-필러 유니버스) | DIST-AR-018 (주제어 7겹), DIST-AR-007 | **정탐 — 조건부** |
| FQ-024 (R11 P-pure 발전 chain) | DIST-AR-007 | 미판정 |
| FQ-026 (R13 P-pure 감쇠속도 축) | DIST-AR-007, DIST-QPM-003 | 미판정 |
| FQ-039 (R26 PG2 8번째 팩터+교체) | D6 dead(composite/packaging), DIST-AR-003/007 | **정탐 — 이관·해소됨** |
| FQ-120 (하락 지속성 시간스케일) | DIST-AR-008 | 미판정 |

## 판정 상세 — FQ-035/036/037 클러스터

세 항목은 **R22 → R23 → R24 단일 체인**이고, **DIST-AR-018(2026-07-18, expiry 2027-07-18)이
R24 까지 소비해 판정을 냈다**. 카드 본문이 그 라운드를 직접 인용한다:

> "② R24 극단지각→심각사건 lead 강건(lift 10x·LOO 27/27)이나 사고 전부 소형주
> (중대형 극단지각 15에피소드 0사고)"

즉 큐의 세 항목이 들고 있는 `next_action`(P1 재과녁 / P2 소형주 coverage 확장 / P3 채널 분리)은
**카드보다 앞선 시점의 계획**이다. 이 스크린이 존재하는 이유("큐가 자기보다 나중 판정을 반영
안 함")의 교과서적 사례.

- **FQ-035 / FQ-036**: 체인이 R24 까지 진행돼 카드로 정리 → next_action 이미 소비. status 갱신 대상.
- **FQ-037**: 카드가 인용한 라운드 본체. 남은 P2(소형주 coverage 확장)는 카드의 **국소화 판정과
  모순되지는 않으나**, 카드가 **자본·선별 소비면을 config-scoped negative 로 닫고 유효 소비면을
  monitoring 조기경보로 한정**했다. FQ-037 자신이 "Stage-1 지식 라운드 · 자본/PORT_t 주장 없음 ·
  필터 소비는 배포 유니버스 내로 2단 분리"를 선언하고 있어 **설계상으로는 정합** — 다만 성과
  소비면으로 밀면 충돌한다. 착수 시 이 경계를 사전등록에 명시할 것.
- **부활 조건(카드 명시)**: 중대형 심각사건/극단지각 표본 실재 관측, 또는 공매도·대차 교차에서
  대형 tier 전이 신호. `monitored_source` = `filing_delay_watch` tripwire + FQ-038/FQ-003.

### 부활 감시원 생존 확인 (실측)

카드의 부활은 감시기가 살아 있어야 발화한다. `qepm/observability/filing_delay_watch_latest.json`
= **2026-08-02 20:00 산출, 현 북 14종목, n_warn=0** 로 정상 가동. 산출물의 `warn_tone` 이 카드와
동일 실측을 인용한다("중·대형 극단지각 15에피소드는 12M 내 심각사건 0건, 신호는 소형주 국한").
→ 부활 신호가 실제로 발화 가능한 상태.

## 판정 상세 — FQ-039 (dead 축 + 카드 2종 동시 저촉)

**저촉은 정탐이다.** FQ-039 는 PG2 `score_eff` **composite** 에 8번째 팩터를 z-blend 하자는
제안이고, D6 는 정확히 "composite/packaging (mega-cap 앵커·joint packaging·MID-tier composite)
07-10 천장 확정"이다(joint packaging 승자 IS 3.282 → OOS −1.634 붕괴, sweep-DSR 0.457 FAIL).

단 FQ-039 자신이 그 선례를 **정직하게 인용**하고 차별점 4개(R6 deployzone 실현-PORT_t 라벨 07-11 ·
ΔIR window-matched control 07-13 · R16 신규 팩터 미검 · composite z-blend 소비형태 미검)를 들어
INV-7 경로-scoped 논리를 제대로 밟았다 — 그 자체로는 재도전 자격이 있다.

**★그런데 저촉보다 강한 사유가 원문에 있다: 이 항목은 이미 이관·해소됐다.**
`next_action` = "frontier 분기 FQ-040·FQ-041 로 이관". 두 자식의 현재 상태:

| 자식 | status | 내용 |
|---|---|---|
| FQ-040 (R26 P2) | `screening_pass_reversed_lookahead_base` | R27 screening PASS 가 **base look-ahead 로 반전** |
| FQ-041 (R26 P1) | `config_scoped_negative` | SETTLED R28 — "R26 IS-positive = look-ahead 아티팩트" |

즉 R26 의 양성 신호는 자식 라운드에서 **저장 패널 동월 look-ahead 아티팩트**로 판정됐다
(2026-07-14 사건, `project-stored-panel-samemonth-lookahead` 계열). 부모인 FQ-039 만
`config_scoped_negative_frontier_open` 으로 남아 있어, 큐만 보고 집으면 이미 반증된 라인을 연다.

### 이 판정이 드러낸 스크린 갭 (제안)

현 스크린은 **큐 × EV지도 × Distilled 카드** 3면만 본다. FQ-039 의 실제 사유는 **큐 × 큐
(부모-자식 상태 일관성)** 이었고 그 축은 없다 — 계보는 `next_action` 본문에 자연어로만 있다.
제안 4번째 축: *"자식이 전부 종결(settled/negative/reversed)인데 부모가 open"* 을 탐지.
FQ-039 는 그 축의 실사례 픽스처가 된다.

## 남은 3건에 대한 지침

미판정 3건(FQ-024/026/120)은 착수 전 3단 게이트로 사람이 판정해야 한다.
스크린 재실행: `Rscript 02_Infrastructure/ops/frontier_registry_coherence.R --json`
(수리는 브랜치 `claude/confident-pasteur-53fafb` 7f9e4ff1 — main 미반영 시 접미형 7건이 다시 안 보인다).
