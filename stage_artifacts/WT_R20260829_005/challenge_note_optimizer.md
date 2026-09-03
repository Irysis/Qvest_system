# WT-R20260829_005 — Optimizer Self-Adversarial Challenge (v8.2)

finalize 직전, 내 산출물을 내가 적대적으로 심문한다. 외부 Codex 호출 없음.
분류: **ACCEPT**(인정·수정) / **PARTIAL**(부분 인정·보완) / **REBUTTAL**(학술 + 코드 + 정량 3축 반론)

---

## C1. "EW 를 골랐다는 건 optimizer 가 한 일이 없다는 뜻 아닌가"
**→ ACCEPT (수정 아님 — 그것이 결과다)**

맞다. 그리고 그것을 결과로 보고하는 것이 이 단계의 정직한 산출물이다. 5종 사다리 중 어느 것도 EW 대비 net_IR 을 materiality band(0.10) 밖으로 개선하지 못했고, 2종은 회전율 상한으로 실격했다. `qvest-opt-style` Cycle 2 항목이 명시적으로 요구하는 처리다 — "sizing 이 SR 을 보강했는지 EW baseline 대비 정량 비교 의무 · 개선 없으면 정직 보고(과장 금지)".

기여 0 을 감추기 위해 복잡한 방법을 고르는 것이 실제 위반이다. 그 유혹의 구체적 형태는 IVP 였고(§C4), 거절했다.

---

## C2. "트레일링 60개월 표본 2차 모멘트를 쓴 건 risk 의 Σ 재정의 아닌가"
**→ PARTIAL**

인정하는 부분: 나는 risk 가 주지 않은 시계열 2차 모멘트를 만들었다. 이건 명시 대상이고, `optimization_package.diagnostics.sigma_boundary_disclosure` 에 규약 5개와 함께 전량 기록했다.

인정하지 않는 부분: 이것은 재정의가 아니라 **PIT 가 강제한 결과**다. risk 는 단일 as-of Σ(2023-06~2026-07 창)만 발행했다. 그 Σ 를 2005년 스케줄에 소급하면 그 자체가 C1 full-sample 위반이다. walk-forward 스케줄(RF-O9 의무)과 단일 스냅샷 Σ 는 양립하지 않으며, 둘 중 PIT 가 이긴다.

보강 조치: ①원본 Σ 파일·값 무수정 ②as-of 위험보고(예측 변동성·TE·CVaR) **전량**을 원본 Σ 에서 산출 ③교차검증 — 내 as-of 예측 연변동성 **0.3424** 가 risk 의 `predicted_vol_ann` 0.3424 와 일치(같은 대상·같은 Σ 확인) ④Ledoit-Wolf 미사용(risk 의 축퇴 실증 존중).

---

## C3. "walk-forward MVO 를 안 돌린 건 회피 아닌가"
**→ PARTIAL**

인정: 사다리에 없다. 그리고 "risk 경계 때문" 이라는 **사후 정당화를 쓰지 않는다** — IVP/HRP/MinCVaR 도 똑같이 트레일링 모멘트를 쓰므로 그 논리는 나 자신에게 성립하지 않는다. 진짜 이유는 태스크가 선언한 5종 상한과 사전 사다리 구성(EW→RP→HRP→CVaR + uncertainty)이다.

보강: 권위 Σ 로 **as-of 민감도**에서 MVO(λ=2, long-only)를 측정했다 — 유효종목수 25 → **7.7**, w_max 0.261, 예측 변동성 0.3424 → 0.3064(상대 −10.5%). 방향이 breadth 와 정면 충돌하고 교환비가 나쁘다. 이것은 walk-forward 실측이 아니므로 "MVO 가 진다"고 **주장하지 않는다** — 미측정으로 남기고 next probe 에 넣는다.

---

## C4. "IVP 가 Calmar·MDD·TE·낙폭상태 전부 낫다. EW 를 고른 건 규칙에 숨은 것 아닌가"
**→ REBUTTAL (단, 관측은 전면 기록)**

IVP 우위는 사실이다: Calmar 0.270 vs 0.253 · MDD −51.1% vs −53.0% · TE 0.1644 vs 0.1704 · 낙폭상태 초과 +4.22%p vs −1.97%p.

반론 3축:
- **학술/규약**: 사전등록 1급 지표가 비결정이면 그게 판정이다. 결과를 본 뒤 2급 지표(Calmar·낙폭상태)로 갈아타는 것은 사전등록의 파기다. 특히 낙폭상태 진단은 risk 정정 ②를 **받은 뒤** 만든 것이라 순수한 사후 지표다.
- **정량**: net_IR 격차 +0.0005 는 SE(연율 IR) ≈ 0.215 의 **0.2%** 다. 노이즈조차 아니다. 그 대가는 회전율 +0.94/yr = 비용 +0.14%p/yr 로 실재한다. 무차별한 이득에 확정 비용을 지불하는 교환이다.
- **게이트 결과 불변**: 자본층 Calmar 문턱은 0.64 다. 0.253 → 0.270 은 등급을 바꾸지 않는다. 즉 축을 갈아탄 대가로 얻는 것이 **판정에서 0** 이다. 이 조건에서 축 교체는 순수하게 서사를 위한 것이 된다.

처리: 선택 불변. 관측은 `weight_method_selected.md` §7 와 패키지 `drawdown_state_diagnostic` 에 전면 기록하고 **next probe 1번**(낙폭상태 활성수익을 1급으로 사전등록해 재측정)으로 승계.

---

## C5. "as-of 예측 TE 0.2704(보정 0.3742)가 실현 활성 TE 0.1704 보다 크다. 모형이 틀린 것 아닌가"
**→ ACCEPT (숫자를 맞추지 않고 둘 다 보고)**

두 값은 같은 양이 아니다 — 예측치는 2026-07-31 단일 종목집합 × 2023-06~2026-07 창 × **cap-w 194종 프록시** 벤치 기준이고, 실현치는 21.6년 시변 보유 × 실제 KOSPI200 TR 기준이다. 어느 쪽을 맞추려 조정하면 그게 조용한 오버라이드다.

조치: `risk_metrics.te_inconsistency_disclosure` 에 두 값과 차이의 출처를 명기. `expected_information_ratio` 는 raw(0.241)·calibrated(0.174) 양쪽 제시. 하류가 어느 쪽을 쓸지 스스로 고르게 한다.

---

## C6. "낙폭상태를 54개월로 잡았는데 risk 는 125개월이라 했다"
**→ ACCEPT (재현 주장 철회)**

내 조작화(벤치 **누적** 낙폭 ≤ −20%)와 risk 의 조작화(벤치 월별 낙폭 상태)가 다르다. 나는 risk 의 상태정의를 재현하지 않았고, 재현했다고 주장하지 않는다.

조치: `state_definition_caveat` 로 명기. 내 진단은 **내 정의 위에서만** 해석되어야 한다. risk 의 −29.6%p 초과손실 수치를 내 표에 섞지 않았다.

---

## C7. "회전율 8.82 는 드리프트를 무시한 규약이다. 실제 회전율을 과소표시한다"
**→ ACCEPT (양쪽 병기)**

사실이다. 드리프트 반영 시 EW 는 8.820 → **9.497** 이다(+0.68). 하지만 이 규약은 내가 고른 게 아니라 **alpha 재현으로 확정된 하우스 규약**이다(드리프트 반영판은 `period_returns_production.csv` 와 max diff 2.46e-4 로 어긋나고, 미반영판은 5.27e-16 로 일치).

조치: `turnover_conventions_all` 에 3규약(no-drift ×12 / drifted ×12 / round-trip ×2) 전량 기록. 상한 11.0 판정은 하우스 규약으로 하되, 드리프트 반영 시에도 EW 9.497·IVP 10.068 은 통과하고 **HRP 11.501·MinCVaR 15.773 은 여전히 실격**이라 실격 판정이 규약 선택에 의존하지 않음을 확인했다.

---

## C8. "detect_lookahead 가 3건을 잡았는데 통과라고 쓰는 건 합리화 아닌가"
**→ PARTIAL (탐지기 출력 무수정 기록 + 구조 증명)**

탐지기 출력을 지우지도, 패턴을 우회하도록 코드를 고치지도 않았다. 대신 의사결정 경로와 사후 평가기를 **원문에서 행 범위로 잘라내** 각각 스캔했다(손으로 다시 쓰지 않았다 — 동일 텍스트 보장):

- 의사결정 경로(비중규칙 5종 + `build()`): **CLEAN, 0건**
- 사후 평가기(`eval_sched`/`stats_of`): 2건 — 전부 `sd(act)*sqrt(12)`, 즉 **이미 생성된** 계열의 연율 IR·TE 분모

"영향 미미" 라고 말하지 않는다. 구조로 증명한다: ①의사결정 경로는 `sd(.)*sqrt(` 패턴을 아예 쓰지 않는다 ②`build()` 본문이 `eval_sched`/`stats_of` 를 참조하지 않는다(문자열 검색 FALSE) ③트레일링 창은 `rw_dates < d` 단 한 줄이 결정하며 미래 인덱스 참조가 없다. 평가기 수치가 비중으로 돌아가는 경로가 존재하지 않는다.

★그럼에도 이건 탐지기가 못 가르는 영역이다. 다음 라운드에서는 의사결정 코드와 평가 코드를 **처음부터 다른 파일로** 두는 것이 옳다(L-code 후보).

---

## C9. "제약을 완화하고 싶은 유혹은 없었나"
**→ 실측 자기점검: 완화 0건**

시장 분산비중 81.2% 는 롱온리·Σw=1·현금불가에서 줄일 레버가 **없다.** 여기서 숏/현금/25종 초과를 레버로 제시하면 게임을 이기는 게 아니라 바꾸는 것이다(INV-7). 제안하지 않았다.

회전율 상한 11.0 을 넘긴 2종은 **상한을 움직이지 않고 실격 처리**했다. `no_silent_override.relaxed_any_constraint = false`.

훅 양방향 실증(경고 0 만 보고 방어선이라 부르지 않는다):

| 주입 | 결과 |
|---|---|
| 원본 | `{}` (통과) |
| n = 26 | **block** — max_names 26 > 25 |
| w < 0 | **block** — long-only 위반 |
| Σw = 1.05 | **block** — Σw ≠ 1.0 |

`worktask_constraint_enforcer.sh` 가 이 파일에서 실제로 판정하고 있음을 확인했다(reinforcement → deployment 분기 적용).

---

## C10. 계기 결함 1건 보고 — schedule fidelity 인증서 무발화
**→ ACCEPT (사실 보고, 상류 미수정)**

`weights.csv` 는 259/259 = **밀도 1.000**(스킵 0)이다. 그런데 `schedule_fidelity_check.sh` 는 `alpha_package.diagnostics.sig_dates_count` 를 읽는데 이 alpha_package 는 그 키 대신 `canonical_n_months`/`n_months`(=259)를 쓴다. 훅의 fallback 체인도 못 잡아 `SIG_DATES=0` → 조건 미충족 → **인증서 미발급이면서 warn 도 없다**(무발화).

즉 이 계기는 지금 이 WT 에서 판정하지 않았다. 밀도 사실은 내 패키지의 `weights_csv_unique_dates_count` / `alpha_sig_dates_count` / `schedule_density_ratio` / `schedule_density_pass` 가 보유한다. alpha_package 는 수정하지 않았다(read-only 경계).

---

## 종합

| 분류 | 건수 | 항목 |
|---|---|---|
| ACCEPT | 5 | C1, C5, C6, C7, C10 |
| PARTIAL | 3 | C2, C3, C8 |
| REBUTTAL | 1 | C4 |
| 자기점검 | 1 | C9 (완화 0건) |

**Q-Lead escalate trigger: 미발화.** Hard Constraint 위반 0 · HIGH 5건 미만 · RF-O9 single-snapshot 아님(259 dates) · turnover 8.82 ≤ 11.0.

**AX-008 정합**: self-adversarial 은 3-source 중 1개다. 나머지 2개(Forge 실측 · Architect)는 하류에서 온다. 본 노트 단독으로 검증을 종결 선언하지 않는다.

**체인 완주**: 사이징 기여 0 은 체인을 멈추는 근거가 아니다(도훈 2026-08-29). forge 가 그대로 소비할 259일 스케줄을 발행했다. 판정은 체인 종점의 essence 등급이며, 나는 등급을 선언하지 않는다.
