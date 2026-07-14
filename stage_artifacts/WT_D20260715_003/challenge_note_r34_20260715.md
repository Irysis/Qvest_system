# R34 Self-Adversarial Challenge Note — insider net-buy tripwire 배선 + 북 de-risk 진단

**WT-D20260715_003 / FQ-050 / 2026-07-15** — Opus 4.8 자체 적대검증 (AX-008 3-source 중 1).
판정: `capability_established` (monitoring tripwire 배선 + 북-레벨 per-holding 확증). base = production clean T-1 §7b.

아래 약점을 finalize 전 자가제기하고, 판정에 어떻게 반영했는지 기록한다.

---

## Concern 1 — 순매수 클러스터 기저율·표본 (희소성 → 검정력 한계)

**약점**: 북 보유(top-25 슬리브) 내 net-buy flag는 **드물다** — 6,698 held-name-months 중 flagged 277건(**4.14%**), 월평균 **2.45종/월**, 신호 존재 월 113/268. R33 universe 기저율(28.2 flags/월, 126월)과 비교하면 top-25로 좁히며 표본이 1/10로 줄었다. gap_ret NW-t = **+2.50**은 2.0을 겨우 상회 — universe t+3.36보다 약하다. 소수 표본의 우연 가능성.

**검토·반영**:
- 방향·크기가 **R33 universe와 일관**(universe gap +12.4%/yr t3.36 → 북 +20.7%/yr t2.50 · restricted +2.68). 다른 데이터·다른 부분집합에서 같은 부호·유의 = 우연 아님을 지지.
- 세 위험축이 **동시 일치**(하방 -7.6%<-8.3% · 급락 4.7%<7.0% · 수익 +3.68%>+1.93%) — 단일 지표 우연이 아닌 결합 신호.
- **정직 라벨**: 검정력은 희소성에 제약됨을 verdict `coverage`·challenge에 명시. 자본 주장 아님(monitoring)이라 이 표본으로 게이트 통과 선언 없음 — HARD 3종 미적용(소비면 진단). next_probe #1(coverage 확장)로 표본 강화를 등재.

## Concern 2 — 북 보유종목 커버리지 + 재구성 슬리브 vs 라이브 14종

**약점**: (a) 현 14 보유 중 **3종(A007340/A023530/A003030) NO_INSIDER_DATA** — 저커버 소형/신규. (b) 진단의 held-set = **재구성 top-25 score_eff 슬리브**인데, 라이브 북은 오버레이 현금조절+weight cap으로 **14종**(6종 zero-weight). 즉 진단 유니버스가 라이브 북보다 넓다. (c) 현 시점 **NET_BUY_SAFE 0건** — tripwire가 지금 아무 것도 안 잡음.

**검토·반영**:
- (a)(c)는 **정직한 live 상태**로 보고 — armed·inactive. 0건은 실패가 아니라 "이번 달 flagged 보유 없음"(최대 INS02 +0.91<1.0). 배선 검증의 목적은 tripwire가 PIT-clean하게 **작동**함을 실증하는 것이고, 그것은 확인됨(홀딩월 202607, signal 2026-06-30, 판정 로직 통과).
- (b) 오버레이는 **북-레벨 현금조절이지 종목선택이 아니므로** equity 슬리브 = top-25 score_eff가 올바른 held-set. 라이브 14종은 그 슬리브의 캡·현금-스케일 부분집합 — 진단은 슬리브 전체(더 보수적·표본 큼)에서 수행하고, 라이브 스냅샷은 별도 병기. verdict `held_reconstruction`·`task2_wiring`에 이 구분 명시.
- 소비 caveat: 진단은 **미래 라이브 발화의 사전 특성화**이지 현 0건에 대한 조치 아님. next_probe #2로 live 발화 추적(OOS)을 등재.

## Concern 3 — 안전신호의 look-ahead (PIT 무결성)

**약점**: INS02는 6개월 임원 매수 breadth. panel signal_date(월말) → 홀딩월(m+1) 정렬을 신뢰하는데, 나는 **R32/R33이 빌드한 insider 패널을 재사용**했고 패널 빌더 내부의 filing rcept_dt→signal_date lag를 이 라운드에서 독립 재감사하지 않았다. 만약 패널이 동월 filing을 포함해 signal_date를 찍었다면 잔여 동월 look-ahead 가능(faith/overlay 재발 위험 유형).

**검토·반영**:
- **lag-1 스트레스 실행**: flag을 +1개월 더 밀어(신호 2개월 전) 재측정 → gap +2.50→**+1.89**(감쇠하나 **붕괴·부호반전 없음**). 동월 누출이면 lag-1에서 붕괴(overlay 사고 패턴) — 붕괴 안 함 = 동월 look-ahead 아님을 지지.
- 정렬은 **홀딩월 시작 전** 데이터만(signal 월말 m < 홀딩월 m+1 첫날) = C5 준수. 배선 코드도 `signal_date <= check_date` + `hy = signal월+1` fail-safe.
- **잔여 노출 정직 병기**: 패널 빌더 내부 lag 독립 재감사는 미실행(R33이 패널 PIT 기 검증). lag-1 non-collapse가 실무 방어선. next_probe #3(exit-timing 대칭 검정)이 추가 PIT 스트레스 겸함.

## Concern 4 (추가) — cohort-path de-risk 과대주장 위험

**약점**: "de-risk"라는 단어가 포트폴리오 낙폭 감소를 암시하나, **cohort-path MDD/vol은 flag가 오히려 악화**(-34.5% vs -16.7% · vol 35.5% vs 22.5%). 이를 뭉개고 "de-risk 성공"이라 보고하면 조용한 단순화(answer-principles 5금지).

**검토·반영**:
- verdict에 **`cohort_path_basis_CONFOUNDED`** 절 신설 — 악화는 **분산 아티팩트**(2.5 vs 22.5종 EW 바스켓)이지 위험속성 아님을 명시. `kill.derisk_cohort_path=true`.
- 배선 코드(filing_delay_watch Part C)·monitoring_init에 **consumption_caveat** 내장: "per-holding 안전 특성화만 — 자본/sizing 근거 금지". de-risk 값 = 유지 안전 라벨(고수익+급락회피)이지 포트-path 저변동 아님.
- 이것이 monitoring-only 배선(집중/사이징 아님)인 이유의 근거 — per-holding basis가 tripwire의 올바른 소비면.

---

**종합**: 4개 약점 모두 판정 방향을 뒤집지 않음(capability_established 유지) — 단 (1) 자본 아님·표본 희소 명시, (4) cohort-path 과대주장 차단이 **판정 스코프를 per-holding monitoring으로 좁힘**. 배선은 이 스코프에 정확히 배치. 남은 리스크는 next_probe 3종(coverage·live OOS·exit 대칭)으로 이월.
