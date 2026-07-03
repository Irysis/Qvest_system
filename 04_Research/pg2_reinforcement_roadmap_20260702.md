# PG2 강화 로드맵 — 딥리서치 통합 (2026-07-02)

**지시**: 도훈 — "PG2 breakdown + 적재 논문으로 어떻게 강화할지 딥리서치"
**입력**: ① 내부 실측 지형 (약점 W1~W4 · 클린-타이밍 판정 R1~R3 · settled-negative 8종 · 오버레이 감사) ② 논문 43편 큐 (`pg2_reinforcement_queue_20260702.json`) ③ 딥리서치 외부 claim 25건 (Search/Fetch 완료 — Verify 패널은 지출한도로 전멸, **미검증·출처-직접추출 라벨**. 단 핵심 논문들은 큐 평가 단계에서 원문 실독 완료)

---

## 0. 오버레이 감사 결과 (본 로드맵의 전제, 2026-07-02 실측)

### 감사 판정: 레이어별 신호 타이밍
| 레이어 | 소스 정렬 | 판정 |
|---|---|---|
| β_AR (2-1 Layer4) | `beta_t_mapping.csv` 행=적용월(7월 forward 행 존재) + 빌더 `shift(1)` = 라벨 오프셋 정확 보정 | **클린** |
| m4 | 동일 구조 (`m4_extended.csv` + shift(1)) | **클린** |
| β_R05 | `realized_ym = sig_date + 1m` 매핑 (빌더 L267-268 주석·코드 일치) | **클린** |
| **β_faith (2-2 Layer4)** | `run_layer5_faith_overlay.R` ym_next merge → S(EOM m)를 return_ym=m 윈도우에 적용. 재생성본(07-02 14:14)도 **S==EOM(return_ym) 정확일치 100%** | **concurrent (동월 누출)** — 유일 결함 레이어 |

배포(`forward_weights_R05_FAITH.R`)는 전월말 S로 클린 — 결함은 백테 증거에만 존재. 라벨 정합(return_ym)·리포팅 재산출·IKS200은 타 세션에서 수리 완료 확인.

**공식 승격수치 오염 확정**: WT-D20260701_002 forge는 pure measurement — `verify_overlay_series.csv`의 사전계산 ret_faith를 계약 승격했고, 그 시리즈의 값이 concurrent faith 시리즈와 정확 일치(2026-04/05/06 소수점 동일). ∴ **admit 근거 "1.675→1.875 개선"은 클린 AR vs 리키 faith의 비대칭 비교** — 클린 기준으론 faith≈AR(t 0.08). dossier의 정직 캐비앗(PROXY_PROMOTION·MECHANISM_GENERIC 등)도 타이밍 결함은 미포착. pit.md 절차상 faith 개선 주장은 무효 후보 — Layer4 처분(faith 유지/AR rollback/제거)은 P0-2 forge 재심 + 도훈 confirm.

### Book-level 함의 (같은 CSV 내 직접 대결, 269개월, |ΔE|×15bps)
| variant | SR | Calmar | 2026 H1 | NW-t vs AR book |
|---|---|---|---|---|
| AR book (전임 2-1, 클린 타이밍) | 1.836 | 1.659 | +85.7% | — |
| faith 기록 (현 2-2 admit 근거, concurrent) | 2.109 | 2.055 | +53.4% | +1.72 |
| **faith 클린 (배포-일치 타이밍)** | 1.787 | 1.682 | +52.1% | **+0.08** |
| **no_faith (R05×m4만)** | **1.897** | **1.943** | **+100.0%** | **+3.10** |
| naked (오버레이 전부 제거) | 1.678 | 1.118 | +133.3% | +2.38 |

1. **FaithTrend의 admit 우위는 타이밍 아티팩트**: 클린 faith vs AR book = NW-t 0.08 (무차별). 기록상 우위(2.109)는 concurrent 신호 산물.
2. **Layer4 자체(AR이든 faith든)가 panel 기준 음(−)의 한계기여**: no_faith가 AR book을 t +3.10으로 유의하게 이기고, SR·Calmar·2026 참여 전부 우위. 반면 R05×m4는 존치 가치 명확 (naked 대비 MDD 40.7%→23.3% + SR 1.678→1.897).
3. 외부 문헌과 정합 (딥리서치 claim, 미검증 라벨): Cederburg-O'Doherty 계열 — vol-managed는 103개 전략 중 실전(walk-forward)서 102/103 열위, 팩터-레벨 무효(market-level만 생존), 비용 후 SR 하락, 2000년대 이후 alpha 소멸. **KOSPI vol-기반 Layer4가 클린 기준 무가치라는 내부 실측과 독립적으로 일치.**

---

## 로드맵 (우선순위순)

### P0 — 측정 정정 + "빼는 강화" (즉시, 최고 확실성)
**P0-1. faith merge 타이밍 정정**: 2-2 canonical의 S merge를 ym_next→ym+2 (배포와 동일 타이밍)로 정정. 05_Production 수정은 promote 절차 필요 → 정정판을 `04_Research`에 두고 **도훈 confirm 후 반영**. 이후 모든 오버레이 백테는 이 타이밍이 기본.
**P0-2. Layer4 존치 재심 (사실상 최저비용 강화)**: 감사표 근거로 **forge full-rerun A/B** (①현행 faith ②AR rollback ③Layer4 제거=R05×m4) → judge → 도훈. panel 기준 기대효과: SR +0.06~0.11, Calmar +0.26, 2026 참여 +47%p, 회전율 감소. *리스크*: panel-diagnostic tier — forge 레벨에서 뒤집힐 수 있음. MDD는 faith가 소폭 우위(21.2% vs 23.3%)라 방어-우선이면 존치 논거도 있음 — 판단은 forge 수치로.
- 검증 프로토콜(전 로드맵 공통): 클린 타이밍 의무 + **lag1 지연 스트레스 의무**(placebo/OOS/subperiod는 동월누출 판별 불가 — R2.5 실증) + sweep n_trials 기록(DSR) + graduation HARD 3종 + book-marginal ΔIR≥0.05.

### P1 — W2 알파 갱신 (최고 EV, 오버레이 결함과 무관)
score_eff(1M) 감쇠의 대체/보강 — 내부 earnings@3M lead (H3 IR 1.56, t 3.58)와 수집 논문의 정확한 합류점.
**P1-1. 리비전 신호 순도 상승** (큐 p8×2 + p7×2):
- *혁신 리비전 분리* (Gleason-Lee 2003): 컨센서스로부터 멀어지는(고정보) 리비전만 — herding 리비전 제거. 딥리서치 claim: drift가 다음 어닝 catalyst까지 지속(≈우리 3M horizon과 일치), 리비전 시리얼 상관이 drift 크기 예측(JBFA).
- *TP implied return 섹터內 상대화* (Da-Schaumburg 2011): 내부 TP_gap 팩터 정제 직결.
- *3-신호 합의* (EPS리비전×추천×TP 동시변경 2012).
- 구현: QuantiWise 컨센서스 C02/C04/C05/TP_gap 재가공(`add_factor` 템플릿), C14 Usable_Date 준수. 검증: canonical_screen_bt → 3M horizon 파이프(1M 파이프는 이 공간을 못 봄 — 실증).
**P1-2. 보유밴드 회전억제** (Beyond FF, Robeco FAJ 2023): top-25 진입 + 상위 40~50% 잔류 시 보유 규칙. 문헌: 회전 1,800%→net alpha +6% 전환(브레이크이븐 25~30bps > 우리 15bps). **어떤 신호에도 이식 가능한 구현 레이어** — P1-1 산출물에 기본 장착해 실측.
- 기대: score_eff 대체 시 book 알파 절반의 감쇠 문제 직접 해소. 성공 기준 = graduation HARD + 기존 book 대비 ΔIR≥0.05.

### P2 — W3 직교 sleeve: DART 내부자 (신규 정보원, 중기)
- *Decoding Inside Information* (JF 2012): routine(3년 연속 동월 거래)/opportunistic 분리 — opportunistic 매수만 예측력(EW 월 180bps 문헌치). + persistence(2017) 개인-수준 가중 + KR clustering(2023) 현지 실증.
- registry 373팩터 중 insider 계열 **0건** = 논문풀 소진 후 유일 미탐색 정보원(메모리 정합). 가격/재무/컨센서스와 정보원 자체가 분리 → §6 "직교≠수익" 원칙상 PORT_t 실측이 최종 판정.
- 구현 단계: DART elestock API 백필(2005~, rcept_dt 기준 PIT) → routine 분류기 → 월간 net opportunistic buy 팩터 → screen tier → graduation. 백필이 큰 빌드라 P1과 병렬 진행 권장.
- 보조 후보: Tug of War overnight/intraday 분해(2019) — 일별 OHLC만으로 구현 가능.

### P3 — W1 오버레이 재도전 (P0 종결 후, 스탠스 하향)
딥리서치의 핵심 기여 = **이 각도의 EV를 낮춘 것**. 내부(클린 전원 사망: F5·G3b·G1 모두 no_faith 미달) + 외부(vol-managed 팩터레벨 회의론, 미검증 라벨) 합치.
- 잔여 유효 방향: ① **R05×m4 게이트 자체의 정밀화** — Continuous Statistical Jump Models(2024)로 hard-bin→soft probability (M4 개선, Layer4 신설 아님) ② BBT/MTP 방향-구조 신호는 US/20개국 근거 강하나(OOS 92% 효율 claim) **KR 지수레벨 클린 실측서 사망** — 재도전은 홀딩스-레벨 구성 레버(리스크-on 고β 틸트·집중도)로만 ③ Conditional Vol Targeting(2020)은 "고변동 상태에서만 de-risk"가 R05 게이트 개선 아이디어로 흡수 가능.
- 어떤 후보든 성공 기준: **클린 타이밍에서 no_faith(1.897) 초과 + lag1 생존**.

### P4 — W4 uncertainty-aware 선택 (레버④ 미탐색)
- ML 예측 불확실성(2025)·forecast disagreement(2023)·conformal(2024/25): score 예측치의 SE/불일치로 top-N 선별 정교화 (가중 학습 아님 — DPL settled와 구분).
- P1 신호 갱신과 자연 결합: 새 composite의 예측구간으로 borderline 종목 필터. 25종 천장(SR~1.1) 돌파 레버 중 유일하게 미실측.

### 지속 트랙
- 미평가 44편은 라우터 v2 일일 배치로 소화. factor-db-discovery 스킬의 horizon×style 축(3M 파이프)과 P1 통합.

---

## 검증 거버넌스 (전 항목 공통)
1. **클린 타이밍**(전월말 신호→당월 윈도우) + **lag1 스트레스** 의무 — 이번 감사의 최대 방법론 교훈.
2. metric_type 라벨: panel-overlay 실험 = diagnostic-tier / 자본 결정 = forge build_bt_result + essence_score PORT_t.
3. sweep 기록 (본 스레드 누적 n_trials=31 + 후속), DSR은 graduation 시.
4. governor admit = 수동 (도훈 confirm) — P0-2 Layer4 재심 포함 전부.

## 실행 결과 (2026-07-02 당일, 도훈 승인분)

### P0-2 Layer4 3-way 재심 — 완료 (WT-D20260702_002, forge+judge)
- forge (클린 타이밍, sanity 4/4): **C_noL4(Layer4 제거) SR 1.898 · Calmar 1.943 · PORT_t 6.21** > B_AR(1.836/4.50) > A_faith_clean(1.779/4.67). paired NW-t: C vs B +3.11, C vs A +4.08. MDD·Sortino도 C 동률 이상 — Layer4는 방어 기여조차 없음(방어=R05×m4).
- judge: **RECOMMEND_REMOVE_LAYER4**, Gate A(PIT)/B/C PASS, AX-008 2/3(Forge+Self-Adv), self-adversarial 7건 제기·verdict 무변.
- **judge 정직 정정**: ① oos_retention은 active(−BM) 기준 **C=0.534 (band_fail)** — forge CSV 1.073은 total-return 오산식. 순위 C>B>A 불변이나 **C 자동 자본졸업 불가 → band 2/3 escalation 필요**. ② build_bt_result annualization 버그(monthly에 252) — 별도 수리.
- **→ 도훈 결정 대기: Layer4 제거 승인(governor 수동 book_state)**. 승인 시: promote + 종목레벨 재실행 1회 + monitoring drift. **판정: 최저비용 강화("빼는 강화")가 증거상 확립.**

### P0-2 심층분석 (Layer4 포함 vs 제거, deepdive) — 완료
- **Layer4 방어 = 조건부·희소·비일관**: 국면순기여 CAUTION +65 / CRISIS +48bps but BULL −34 / NORMAL −64bps/월. 위기국면 19/269월(7%)뿐이라 평상시 드래그가 압도. **MDD 기여 사실상 0**(faith 23.0% vs NOL4 23.3% — 방어 주력은 R05×m4, naked 40.7%→23.3%). 위기 비일관(GFC=AR최강 / COVID=faith근소 / 2022=faith가 NOL4보다 손해). 최악 12개월 중 faith 방어 6/12(나머지 β=1 미발화).
- **롤링 36m**: NOL4가 faith 72% 윈도우 우위(Δ중앙 +0.045), AR 53%.
- **라이브 노출(제거의 유일 실질 리스크)**: 현 faith 활발 발화 → 제거 시 즉시 +17.6%p(특정월 +46~48%p) 노출 급증 = 방어모드→강세베팅 전환. 강세 지속 이득 / 조정 시 대가(단 R05×m4 수준까지, naked 아님).
- **제거 book 자본적정([I] band escalation)**: NOL4 active oos 0.534(band [0.5,0.7)) → 보강증거 **3/3 충족**(trailing60m active PORT_t 1.84>0 · 전기간 active PORT_t **6.21≫2.95** · 제거 유의개선 NW-t 4.08). 조건부 PASS 근거 확보(단 자동졸업 아님 — governor 수동).
- **딥리서치 synthesize 완주**: W1 최고레버=turning-point 레짐오버레이(8 claim 3-0, 92% OOS)이나 **KR 비이전 확정**(日·香港 dynamic 실패 5개국 포함, KR 표본부재, 지수타이밍≠종목선택 — R3 클린사망과 합치). vol-managed 부정 prior(4 claim 3-0: 스칼라 vol 오버레이 실전 열위·팩터레벨 비용후 소멸) = faith 제거의 외부 문헌 뒷받침.
- **권고: REMOVE(NOL4)** — 실측·문헌 수렴. 결정변수 = 도훈 시장관(위험조정만 보면 제거 / 조정보험 중시면 유지, 연 SR −0.12 비용). 산출: `qepm/mailbox/worktask/WT-D20260702_002/output/deepdive_*.csv`

### P1 earnings@3M composite — 완료 (`stage_artifacts/pg2_w2_earnings3m/`, alpha-search)
- **best = S3 3-신호합의 + 보유밴드**: PORT_t 2.20 · SR 1.04 · Calmar 0.587 · TO 360% · paired NW-t **+2.03 vs baseline(유의)**. 단 **자본 HARD(2.95/0.64) 미달** — 유의 개선이나 standalone 졸업 아님.
- 보유밴드(Blitz): 회전 3~10배 절감, **지속신호(S3/S1)만 PORT_t↑ / 노이즈신호(BASE/S2)↓** — persistence 요구(generic 회전툴 검증).
- **S2_tpsect(Da-Schaumburg 섹터상대 TP) = VALIDATED negative** (KR long-only 비이전, PORT_t −0.12/full −1.30/recent).
- recent 2021+ 전신호 PORT_t<0.12 = cohort decay 재확인. IC강(t 8.45)≠PORT_t. lag1 스트레스로 감쇠(PIT-clean 확인).
- L-code Grade C 적립. **다음: standalone 아닌 book-marginal — S3+band forge full-rerun → book ΔIR≥0.05 + active-cor<0.30 (score_eff 1M-dead 대체 후보).**

### 딥리서치 Verify — 부분 완료 (한도 소진)
- BBT/MTP 4-state **15 claim CONFIRMED 3-0**(no-look-ahead·OOS 92%·국제일반화). **단 KR 클린 실측선 사망(R3) — 문헌 실재≠KR 이전 확정.** P3 스탠스 하향 유지(방향-구조는 KR 단일지수 오버레이로 비이전).
- **미완(resume)**: vol-managed 회의론 verify ~10건 + synthesize = 한도 FAIL. `Workflow({scriptPath:".../deep-research-wf_6d49769d-0b1.js", resumeFromRunId:"wf_6d49769d-0b1"})`로 캐시 복원+실패분만 재실행. P3 외부근거 확정용(비-blocking).

## W1 오버레이 3중 최종부정 (2026-07-02, 병렬 3트랙 — 도훈 지시)

| 트랙 | 방법 | 결과 | 판정 |
|---|---|---|---|
| **turning-point 완전복제** | Harvey BBT Appendix C a_Co/a_Re ex-ante estimator 원문 파싱 충실구현(dynamic speed-blend 실작동) → NOL4 이식, 클린+lag1 | SR 1.704<1.897 · PORT_t 6.13→4.97 · ΔIR **−0.276** · NW-t −3.90 · lag1 더 음수 · floor강건 | **FAIL 3/3** — R3 정적판+dynamic 충실판 모두 사망. 메커니즘 KR 부재 확정(long-only가 turning-point de-risk로 급반등 놓침). |
| **vol-managed MARKET 예외** | 문헌 재검증(MM 2017·BD 2021·Cederburg 2020·DeMiguel 2024) + KR 실측(437m KOSPI, MM 충실복제) | MARKET 예외 문헌 실존하나 in-sample·행태·OOS붕괴. KR vol-managed net SR 0.213<buy-hold 0.261(전 cap). book 오버레이=faith와 동일레버(cor −0.632), faith dominate | **비이전** — MARKET 예외 KR 미적용. faith가 잡은 건 vol-timing 알파 아닌 MDD레버. |
| **analyst-revision drift** | 문헌 4편(Gleason-Lee·JBFA·Da-Schaumburg) + P1 연계 | S3+보유밴드 문헌 3중정합, recent decay 문헌 독립확인, S2 정합적 배제 | **W2 조건부GO** — book-marginal 관문은 overlay/regime 결합 2021+ 생존. |

**통합 결론**: KR long-only에서 **시장노출 타이밍 오버레이(vol/trend/turning-point 전부) = regime-cash층(R05×m4) 이상의 가치 없음**. MDD 방어는 R05×m4가 전담(naked 40.7%→23.3%), 그 위 2번째 스칼라 타이밍층은 순드래그. Layer4 제거가 이 관점서도 정당(제거 book=R05×m4=계층 최상). **W1 각도 종결 → 자원은 W2(earnings book-marginal)+W3(insider)로 완전 전환.**

## 산출물 링크
- 감사: `stage_artifacts/pg2_offense_overlay/audit_layer_timing_book_comparison.csv` (+ R1~R3 전체)
- 논문 큐: `stage_artifacts/paper_recharge/pg2_reinforcement_queue_20260702.json` / 수집 보고: `04_Research/paper_collection/pg2_reinforcement_papers_20260702.md`
- 딥리서치 raw claim 25건: 세션 task 출력 (Verify 패널 지출한도 전멸 — 미검증 라벨 유지, 재검증은 한도 리셋 후)
- 오버레이 연구노트: `04_Research/pg2_offense_overlay/offense_overlay_research_note_20260702.md`
