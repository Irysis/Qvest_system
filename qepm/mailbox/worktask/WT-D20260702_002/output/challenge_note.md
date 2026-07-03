# Self-Adversarial Challenge — WT-D20260702_002 (PG2 Layer4 3-way 재심)

Judge: QEPM Judge (Opus 4.8). AX-008 3-source 중 self-adversarial source.
날짜: 2026-07-02. 대상 verdict 초안: **C_noL4 (Layer4 제거) 권고** — 증거-only, governor 수동.

Charter §8 의무: finalize 직전 자신의 verdict 약점을 ≥3건 자가제기 → 반박 가능 여부 검토 → 분류.

---

## 자가 제기 약점 (7건 — 요구 최소 3건 초과)

### W1. Panel-lineage: 종목레벨 재실행 아님 (scalar overlay 곱셈 계보)
**제기**: 3-way 전부 STR_1715 `ret_orig`(고정 종목 포트 수익률) 위에 discrete scalar(beta_R05/m4/beta_AR/beta_faith)를 곱한 계보다. Layer4 제거가 종목 selection·비중을 실제로 바꿨을 때의 상호작용(예: Layer4가 없으면 R05가 다르게 작동)은 측정 못 한다.
**반박 가능성**: 반박 성립. 3-way는 **동일 ret_orig·동일 R05·동일 m4** 위에서 Layer4 스칼라만 토글한 것 — Layer4의 *한계 기여*를 정확히 격리하는 설계다. R05/m4는 Layer4에 의존하지 않는 상위 게이팅(먼저 곱해짐)이라 "Layer4 없으면 R05가 달라진다"는 메커니즘이 없다. paired NW-t(C−B=+3.11, C−A=+4.08, 독립 재현 3.105/4.083)는 동일 종목 시계열 위 차분이라 selection noise가 상쇄된 clean한 한계 검정. 배포는 어차피 forward_weights_R05_FAITH.R가 이 계보를 그대로 쓴다 → 계보가 배포 현실.
**분류**: ACCEPT (caveat로 명기, verdict 무변). 단 governor 단계에서 종목레벨 재실행 1회 확인은 due-diligence로 권고.

### W2. Layer4 제거 = 실계좌 2008급 방어 취약성 노출
**제기**: Layer4(AR/faith)는 위기 방어 오버레이인데, 제거하면 다음 GFC급 스트레스에서 무방비 아닌가?
**반박 가능성**: 반박 성립 (실측). ① 3-way 모두의 binding MDD는 **2006-02→07 (−23.0~−23.3%)** — Layer4 무차별(전부 ~−23%). ② 2008-10/11: 전부 near-identical(2008-11 최대차 A−3.3 vs C−4.6 = 1.3pp, 인접월 회복). ③ 2020-03 COVID: faith 1.2pp 쿠션이나 C의 2020 연간 +44.3% ≫ B +7.8% — Layer4 drag가 방어 이득 압도. ④ MDD 세 변형 동일(~23%). **방어는 R05×m4가 담당**, Layer4 위기 쿠션은 고립월 ≤2.6pp이고 회복/확장년(2009 +42pp, 2020 +37pp for C over B)에서 되갚음. → "2008급 취약" 우려는 실측으로 REFUTED.
**분류**: REBUTTAL (실측 근거로 기각). 단 미래 tail은 표본 밖 — monitoring drift 조항으로 상시 감시 권고.

### W3. Clean faith가 진짜 배포 재현인가 (concurrent leak 재발 없나)
**제기**: A_faith_clean의 clean-timing 재구성(S EOM m→realized_ym m+2)이 구 admit의 concurrent leak을 정말 제거했나? 혹시 다른 look-ahead가 남았나?
**반박 가능성**: 반박 성립 (코드 검증). gap_days 테스트: signal source EOM date vs return-window anchor_date = **min 30 / median 33일, 269/269 rows 모두 gap>0** (신호가 윈도우 개시 전 확정). concurrent(구) 정렬은 gap −30~−21 전 rows 누설 확인. benchmark S 재구성은 trailing frollmean/frollapply(252)+causal EWMA+causal phi, CF 계수 하드코딩(paper#4 frozen, in-sample fit 없음). → clean 재현·PIT C1 확정.
**분류**: REBUTTAL (기각). 단 A는 어차피 패자(C가 지배)라 verdict 무관.

### W4. oos_retention 지표 불일치 (forge CSV 1.073 vs essence 0.534)
**제기**: forge CSV는 C_noL4 oos_v2=1.073으로 "과적합 게이트 통과"를 시사. 그런데 essence_score는 active-series oos_retention=0.534 (band_fail)을 낸다. 어느 게 맞나? verdict가 잘못된 지표에 의존하나?
**반박 가능성**: 부분 반박. measurement-graduation §3 정의 = **active(−BM) Sharpe OOS/IS**. forge CSV oos_v2는 **total-return** ret에 산식 적용(잘못된 대상). 독립 재계산: ACTIVE oos med A=0.295 / B=0.349 / **C=0.534** vs TOTAL A=0.964/B=0.98/C=1.073. → **C의 진짜 active oos_retention=0.534 = band_fail** (forge CSV 1.073은 graduation 게이트엔 부적절). 단 **상대순위 C>B>A는 두 정의 모두 보존** → 3-way *처분* verdict 무변. 절대 graduation 자격은 별개(band → 2/3 escalation 필요, governor 소관).
**분류**: PARTIAL (verdict 무변 — 순위 강건 / 단 graduation-tier 헤드라인 정정 의무: C는 자동졸업 아님, band_fail).

### W5. metrics 테이블 annualization 버그 (CAGR/Calmar 2524/10838)
**제기**: bt_result$metrics의 CAGR=2524, Calmar=10838, Sharpe 7.46 — annualization_factor=252를 monthly에 적용. essence_score가 이 버그값을 읽어 CAGR≥0.16/Calmar≥0.64 HARD 게이트를 통과시킨다. 게이트가 무의미한 것 아닌가?
**반박 가능성**: 부분 반박. essence는 metrics에서 CAGR/Calmar를 *읽기만* 함 → 버그값(inflate)이 게이트를 "우연히" 통과(deflate 아님이라 verdict 왜곡 방향은 관대측). 독립 scale=12 재계산: **CAGR 0.4526, Calmar 1.943** — 정상값도 게이트 여유 통과. → verdict 무변. 단 게이트 메커니즘 자체는 신뢰 불가 = 인프라 결함(별도 수리 대상).
**분류**: PARTIAL (verdict 무변 / 인프라 버그 spawn_task 대상 — build_bt_result가 monthly에 af=252로 CAGR/Calmar 산출).

### W6. audit 테이블 공란 (build 시 placeholder, forge가 audit_bt_result 미호출)
**제기**: 3 rds 전부 audit=0 obs. 계약 무결성 미검증 상태 아닌가? blocking?
**반박 가능성**: 반박 성립. build_bt_result는 audit을 nrow=0 placeholder로 두고 audit_bt_result()로 채우는 설계(L753). forge가 후자 미호출 = 게으름이나 build 실패 아님. Judge가 직접 audit_bt_result 실행: **PASS=10 FAIL=0 WARN=6, integrity=WARNING, CRITICAL 0**. WARN 6건 전부 "holdings/entry_date/factor_engine_path 부재 → 자동검증 skip"(panel-lineage 구조 필연) — substantive fail 아님. lookahead 자동 WARN은 내가 수동 PIT 검증(gap_days)으로 커버.
**분류**: REBUTTAL (non-blocking — Judge가 audit 실행으로 gap 종결).

### W7. 다중검정 지위 (선행 오버레이 sweep n=31이 본 3-way를 오염하나)
**제기**: faith 오버레이 자체가 n=31 sweep에서 나왔다. 본 3-way를 "prespecified"라 부르지만 실은 그 sweep 산물의 재측정 아닌가? DSR 게이트 적용해야?
**반박 가능성**: 부분 반박. 본 3-way는 **감사 결과로 고정 지정된 3후보**(제거/AR/faith) — 이 3개 안에서 argmax 탐색 없음(전부 보고). selection_type="prespecified/chain" 타당. 단 **승자 C_noL4는 "Layer4 제거"라 sweep 산물이 아님**(오히려 sweep가 만든 faith를 걷어내는 방향) → DSR 다중검정 우려의 반대. faith(A)는 sweep 산물이나 패자. → 본 verdict(C 권고)에 DSR 게이트 부적용 정당. 단 만약 governor가 A_faith를 부활 검토하면 그땐 n=31 sweep DSR 재고 필요.
**분류**: PARTIAL (C 권고엔 무영향 / faith 부활 시나리오엔 DSR flag 유지).

---

## 종합
- **REBUTTAL 3건** (W2 tail-defense / W3 clean-timing / W6 audit) — 실측·코드로 기각.
- **PARTIAL 4건** (W1 lineage / W4 oos지표 / W5 annualization버그 / W7 다중검정) — **전부 verdict 무변**(상대순위 C>B>A 강건), 단 헤드라인 정정·인프라 flag·governor 조건부.
- **verdict 뒤집는 약점 0건**. AX axiom hard FAIL 0. PIT C1 hard violation 0.
- **자동 Q-Lead escalate 트리거 미충족** (HIGH<5, AX hard<3, PIT C1 위반 없음).

## verdict에 반영할 정정 (정직 보고 — AX-000)
1. C_noL4 graduation 헤드라인: forge CSV oos 1.073 ❌ → **active oos_retention 0.534 (band_fail)**. 3-way 처분(C 권고)은 무변하나, C의 **자동 자본졸업은 불가** — band 2/3 escalation 또는 governor 판단 필요.
2. metrics CAGR/Calmar는 버그값 — 정상 재계산 CAGR 0.453 / Calmar 1.943 인용.
3. audit는 Judge 실행 결과(PASS10/FAIL0/WARN6, CRITICAL 0)로 대체 기재.
