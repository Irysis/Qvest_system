# DART 임원 순매수 — 졸업-테스트 하네스 (재발화 가능)

**목적**: DART 임원(officer) 장내 순매수 신호가 배포 envelope(KOSPI200∪KOSDAQ150 top-25 long-only,
15bps, LIQ 2e8, NW lag-3)에서 **졸업(자본 자격)** 하는지 판정하는 **재사용·재발화 파이프라인**.
일회성 verdict 가 아니라, 다른 세션의 backfill 이 역사를 확장 완료하면 재실행해 milestone 판정을 발화한다.

**왜 milestone 후보**: KR return-derived·대부분 비-return 신호가 IC→PORT_t 전이 벽에 막히는데,
유일한 방향-양(+) lead = 임원 장내 순매수(Cohen-Malloy-Pomorski 2012, 대형주라 감쇠벽 밖).
full-history 로 검정력 확보 시 졸업 가능성.

**격리**: 모든 산출 `stage_artifacts/insider_graduation_harness/` 내. backfill(다른 세션 소유)
**무접촉**(읽기 전용). DART API·backfill 실행 **없음**.

---

## 구성

```
prep_market_monthly.py          RAWDATA(daily) → 슬림 월별 시장입력(수익/벤치/유동성). R arrow halt 회피.
build_officer_netbuy_signal.py  ★재배선판. 원문파서 출력(dart_parser_build/cache/monthly)을 소비.
                                officer-only + mechanical 제외 + KRW flow. PIT anti-look-ahead 배선.
pit_audit.py                    anti-look-ahead 감사(5 checks). FAIL 시 exit 1(하네스 중단).
run_graduation_gate.R           canonical_screen_bt 경유 top-25 실측 + 졸업 HARD 3종 + book-marginal ΔIR.
run_harness.py                  ★오케스트레이터. 위 4개 + lag1 스트레스 순차 실행. 멱등.
data/                           officer_netbuy_panel.parquet(신호) + 슬림 월별 시장입력 3종.
reports/                        signal_build_meta.json / pit_audit_report.json /
                                graduation_gate_result.json / lag_stress_comparison.json.
challenge_note.md               Self-Adversarial Challenge 기록(5 concern).
INTERIM_VALIDATION_REPORT.md    현 커버리지 interim 측정(비권위) 요약.
```

---

## 실행 (재발화 트리거)

**언제 재실행**: 다른 세션의 backfill(`stage_artifacts/dart_parser_build/`)이
`cache/monthly/*.parquet` 를 확장했을 때. backfill 완주(2005~2024 contiguous) 후가 이상적이나,
중간에도 재실행하면 그 시점 최신 커버리지를 자동 소비(멱등).

```bash
source .venv_qvest_ml/Scripts/activate    # Windows venv
QVEST_PY="$(which python)" QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot" \
  python -u stage_artifacts/insider_graduation_harness/run_harness.py
```

- `MIN_CONTIG_MONTHS`(default 60): 졸업 판정 유효 최소 연속 커버리지.
- `run_harness.py` 는 PIT_LAG=1(canonical) 실행 후 PIT_LAG=2(lag 스트레스)까지 자동 수행,
  마지막에 canonical(PIT_LAG=1) 상태로 원복. `reports/graduation_gate_result.json` = canonical.

**개별 스텝 재실행**(디버깅용):
```bash
python prep_market_monthly.py          # RAWDATA 갱신 시만
PIT_LAG=1 python build_officer_netbuy_signal.py
PIT_LAG=1 python pit_audit.py          # 반드시 PASS 후 진행
Rscript run_graduation_gate.R
```

---

## 커버리지 게이팅 (판정 해석)

| 최장 연속 커버리지 | verdict_level | 해석 |
|---|---|---|
| **< 60월** | `INTERIM_NONAUTHORITATIVE` | 부분데이터+갭+underpowered. **판정 아님** — 하네스 작동검증·방향 참고만. |
| **≥ 60월** | `GRADUATION_JUDGMENT_VALID` | 졸업 판정 유효. HARD 3종 통과 시 milestone. |

**졸업 HARD 3종** (measurement-graduation §3, forge-authoritative 단계에서 최종):
- `portfolio_alpha_t_nw_lag3 ≥ 2.95` (Harvey-Liu-Zhu 다중검정 반영) — **binding 지표**.
- `oos_retention ≥ 0.7` (essence_score v2, anchored 3분할 {55/65/75} 중앙값).
- `calmar ≥ 0.64` (=16%/25%, 위험조정).
- **+ book-marginal ΔIR** = new_IR − incumbent(net_active_recon_v1 IR **1.416**) ≥ 0.05.

**중요 규율**:
- `metric_type = canonical_screen` = **screening-tier**, NOT forge-authoritative.
  졸업 확정(자본)은 forge `build_bt_result` 로 최종 재측정 후 governor(수동+도훈).
- **rank-IC ≠ PORT_t** — 둘 다 보고하되 졸업 binding = PORT_t. (Cycle 2 교훈: rank-IC 강해도 PORT_t 약할 수 있음.)
- **anti-look-ahead**: 신호 M 의 필링 → M+1 수익에만 적용(usable=sig+PIT_LAG≥1). `Date<anchor` 안티패턴 금지.
  `lag_stress_comparison.json` 이 PIT_LAG 1↔2 PORT_t 붕괴 여부로 누출 자동 점검.

---

## 신호 정의 (net officer open-market KRW flow)

- **officer-only**: `reporter_type == "officer"`(등기+비등기 임원). 주요주주/지배주주/기타 제외
  (연기금 블록딜·지수리밸 기계적 매매 노이즈 격리). ★2009+ 만 신뢰(pre-2009 필드 sparse).
- **mechanical 제외**: report `n_mechanical == 0 & n_discretionary > 0` (주식분할·상여·유상신주 등 섞인 report 통째 배제).
  파서 `disc_change_qty`(장내 순증감)는 전량 NULL → report-level 근사 필터가 유일 clean 경로.
- **KRW flow**: firm-month `krw = Σ(net_change_qty × 월말 Close)`. 정규화 변형 `nflow = krw / 월말 시총(Size)`.
- score = krw / nflow 2변형 × 시대(contiguous_run / combined_all) 각각 canonical screen.

---

## 재발화 체크리스트

1. backfill 이 checkpoint 추가했나? → `ls stage_artifacts/dart_parser_build/cache/monthly | wc -l` 증가 확인.
2. `python run_harness.py` 실행.
3. `reports/graduation_gate_result.json::verdict_level` 확인.
   - `INTERIM_NONAUTHORITATIVE` → 아직 검정력 부족. 다음 backfill 확장 대기.
   - `GRADUATION_JUDGMENT_VALID` + HARD 3종 PASS → **milestone 후보** → forge dossier 로 승격(도훈 confirm).
4. `reports/lag_stress_comparison.json::verdict` = `NO_LEAKAGE_graceful_degrade` 인지 매 실행 확인(누출 회귀 방지).
