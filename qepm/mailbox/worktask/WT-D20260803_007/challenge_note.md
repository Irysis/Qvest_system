# challenge_note — WT-D20260803_007 (FQ-135) Self-Adversarial Challenge

**규약**: Qvest v8.2 — Codex Critic Round 제거, 메인 세션 모델 자체 적대검증. Charter §8 No Silent Override.
**대상**: `qepm/mailbox/worktask/WT-D20260803_007/alpha_package.json` + `stage_artifacts/WT_D20260803_007/alpha_validation.json`
**실측 근거**: `stage_artifacts/WT_D20260803_007/adversarial_probes.R` → `adversarial_probes.rds` / `probe_log.txt`
**판정 요약**: (a) FAIL t=+1.212 · (b) FAIL t=+1.304 · 사후 귀속 순증분 t=−0.571
**분류 집계**: ACCEPT 2 / PARTIAL 4 / REBUTTAL 2 (총 8건, 자가 제기)

---

## C1 [HIGH] 판정이 문턱 t≥2.0 **단일 draw** 에 취약한 것 아닌가

내 판정 t 는 1.212 / 1.304 다. 2.0 과 멀지 않다. 2026-08-02 실측(멤버십 jitter 5시드 paired t sd 0.378)이 "문턱 근방 단일 draw" 취약성을 이미 경고했다.

**분류: PARTIAL**

- **격자 강건성(반박 근거)** — AP1: era 창 W∈{24,36,48} 재측정에서 (a) = 1.338 / 1.212 / 1.658, (b) = 0.971 / 1.304 / 1.178. 사전등록 K∈{10,20,40}: (a) = 0.322 / 1.212 / 1.163, (b) = 0.098 / 1.304 / 1.150. 단일분할(IS191/OOS96) 대조: (a) 0.078 / (b) 0.062. **11개 변형 전부 문턱 미달, 최댓값 1.658.** 판정이 한 격자의 우연이 아니다.
- **인정 부분** — AP4 stationary block bootstrap(block=12, B=2000): (a) 중앙값 1.229 [−0.439, 2.829], **P(t≥2)=20.9%**; (b) 1.240 [−0.200, 2.747], **P=21.3%**. 167개월로는 "효과 부재"를 증명할 수 없다.
- **조치**: `POWER_LIMIT_167M` (MEDIUM) challenge_flag 신설 + `alpha_validation.power_limit.honest_statement` 에 "판정은 '사전등록 문턱 미달'이며 '부재 증명'이 아니다" 명문화. 결론 문장을 "구성 lane 전체 닫힘"에서 **"era-robust 축 config-scoped 미달, survivors 0"** 으로 축소(C6 참조).
- **비대칭 기록**: 반면 사후 귀속(순증분 ≤ 0)은 P(t≥2)=**0.85%** — 이 라운드가 실제로 확정한 것은 (a)/(b) 실패가 아니라 **순증분 부재** 쪽이다.

---

## C2 [HIGH] cap-w 벤치 아티팩트가 판정을 오염시킨 것 아닌가

무작위 K=20 composite 200 draw 의 cap-w PORT_t 평균이 **−0.941**, POOL_EW −0.789, placebo −1.585. 이 하네스의 귀무는 0 이 아니다. 모든 arm 이 구조적 음수 드리프트 아래 눌려 있으니 판정이 무의미할 수 있다.

**분류: REBUTTAL (단 standalone 해석에는 PARTIAL 유보 부기)**

- **수학적 상쇄 실증** — AP5: 두 arm 의 벤치 시계열 차 max = **0.0**, `(active_x − active_y) − (ret_net_x − ret_net_y)` max = **2.78e-17**. 판별식 (a)/(b) 는 paired 차이므로 벤치가 **정확히** 소거된다. basis 선택은 (a)/(b) 를 뒤집을 수 없다.
- **유보(부기)** — standalone PORT_t 해석에는 구속된다. EW-유니버스 basis 로 옮기면 A_REL_TOP 0.897→**2.193**, LEVEL_TOP_K20 1.028→**2.860**, POOL_EW −0.789→−0.342. cap-tier 분해: A_REL_TOP 은 MEGA 2.2% / MID 4.0% / OTHER 93.8%, A_REL_BOT 은 MEGA 11.8% / MID 19.2%. 즉 상위 arm 의 cap-w 열위 상당분이 **사이즈 노출**이다.
- **조치**: `CAPW_BENCH_STRUCTURAL_NEGATIVE` flag + v8.3 M2 dual-basis 라벨("cap-w FAIL ∧ EW-대비 생존 → 벤치 구성 미스매치 가능, screen_route 재분류 검토") 부여. 이 사실을 **NP-1(사이즈 중립 composite)** 로 다음 라운드에 이월 — 버리지 않는다.
- 단 EW-basis 에서도 **LEVEL_TOP_K20(2.860) > A_REL_TOP(2.193)** — basis 를 바꿔도 robustness 순증분 결론의 부호는 같다.

---

## C3 [HIGH] lag1 붕괴(0.897 → 0.134)는 미래참조 징후 아닌가

2026-07-05/06 실사고 이후 "lag1 스트레스 + strict-PIT A/B 만이 동월 누출을 판별한다"가 규약이다. A_REL_TOP 의 lag1 붕괴는 크다.

**분류: REBUTTAL**

- **통제군 대조(AP3)** — rank IC lag0→lag1 보존율: POOL_EW **0.899**, A_PERP_TOP **0.976**, A_REL_BOT 0.846, A_REL_TOP 0.744. 하네스 수준 미래참조라면 **동일 파이프라인을 지나는 전 arm 이 붕괴**해야 한다. 통제군이 보존됐다.
- **방향 온전성** — 전 arm rank IC 가 양수·유의(t 3.01~4.58). 신호→익월 수익 부호가 정상(PIT 방향 정상 지문).
- **경로 감사** — 전 arm 이 `load_month_factors(sig_date)` 경유(C15), `Z_Score_Aligned` 그대로(C13, NEGATE/FLIP 없음), Usable_Date ≤ sig_date(C14), 유동성은 t−1 ADV(C10). 저장 파생 패널을 base 로 소비하지 않음(2026-07-14 동월 look-ahead 노출면 없음).
- **위반 주입이 발화** — 전기간 지표 주입 시 paired t 1.212→**2.092**, OOS oracle→**4.367**. 누출이 있으면 좋아지는 방향이 실측으로 확인됐고 clean 판정은 그 상태가 아니다.
- **귀속**: A_REL_TOP 멤버는 consensus/EPS-revision 편중(consensus 0.193, value 0.243) — 신호 horizon 감쇠. `LAG1_DECAY_NOT_LEAK` (LOW) 로 기록.

---

## C4 [HIGH] 사후 arm(LEVEL_TOP_K20) 추가 = 사후 정당화 아닌가

사전등록에 없던 arm 을 결과를 본 뒤 추가했다. 이는 chain 규율 위반 소지다.

**분류: PARTIAL (절차 이탈 인정 + 완화조건 4종)**

1. (a)/(b) 는 `analyze_arms.R` 에서 **이미 산출·기록된 뒤** 추가했다 — 판별 문턱에 재적용하지 않았다(`posthoc_results.rds::not_a_discriminant = TRUE`).
2. **별도 스크립트 파일**(`posthoc_attribution.R`)로 분리해 사전등록/사후 경계를 파일 구조로 감사 가능하게 했다.
3. 이 arm 은 **내 treatment 를 불리하게 만드는 방향**으로 작동한다(A_REL_TOP − LEVEL_TOP_K20 = −0.571). 자기 유리한 사후 추가가 아니다.
4. **결론은 이 arm 에 의존하지 않는다** — 사전등록 arm 인 `A_PERP_TOP`(level-직교 robustness)이 standalone PORT_t **−1.068** 로 독립적으로 같은 결론을 준다. 사후 arm 은 그 확증일 뿐이다.
- **미완 인정**: 그럼에도 "사전등록 시 level 대조군을 넣었어야 했다"가 옳다. P_c 사전확인에서 cor(지표, level)=0.56~0.79 를 이미 봤으므로 그때 arm 으로 등재했어야 한다(A_PERP_TOP 만 추가한 것은 불충분). 차기 라운드 설계 규칙으로 이월.

---

## C5 [MEDIUM] 변형을 27개 봤으니 실질적으로 sweep 아닌가 (DSR 회피)

3 지표변형(rel/abs/perp) × K∈{10,20,40} × W∈{24,36,48} + 단일분할 — 열거 집합에서 고르면 sweep 이고 DSR 게이트 대상이다.

**분류: REBUTTAL**

- primary 규칙(WORST_ERA_REL, K=20, W=36)은 **측정 전 preregistration.json 에 단독 고정**되었고, 나머지는 (i) 사전등록 감도축(결과 무관 전량 보고) 또는 (ii) 적대검증 probe 다.
- **argmax/threshold-pick 이 없다** — 어느 변형도 primary 를 교체하지 않았고, 최댓값(1.658)도 문턱 미달이라 "좋은 것을 골랐다"는 사건 자체가 발생하지 않았다.
- 전량 보고했다(`alpha_validation.robustness.era_window_sensitivity` + `arms` + `paired_tests`).
- **자기구속 명시**: 만약 어느 변형이 통과했다면 그 순간 `selection_type` 을 sweep 으로 재분류하고 DSR HARD 를 적용해야 했다. 이 규칙을 사전등록에 적어 두었다.

---

## C6 [MEDIUM] "구성 lane 전체가 닫혔다"는 과잉 일반화 아닌가

**분류: ACCEPT**

시험한 것은 **minimax 계열 era-robust 선택자**(절대/상대/level-직교) 하나의 축이다. 구성(composition) 일반이 아니다. 미시험 구성축이 남아 있다 — 비등가중 결합, 조건부 결합, 사이즈 중립화, 배제기(filter) 형 소비, 비-return 리프 기반 풀.

- **조치**: 판정문을 **"era-robust 축에서 config-scoped 미달 — survivors 0. 구조 판결 아님(INV-7)"** 으로 확정하고 `alpha_validation.verdict.construction_lane` 에 그대로 기록. 부활 조건 3종 등재.

---

## C7 [MEDIUM] 역방향 통제군(A_REL_BOT)이 애초에 약했던 것 아닌가 — (a) 의 설계 검정력 문제

A_REL_BOT 의 PORT_t −0.751 은 무작위 귀무 평균 −0.941보다 **높다**(백분위 68.0). 지표의 하위 tail 이 음의 정보를 담지 않는다면, (a) 는 처음부터 판별하기 어려운 검정이었다.

**분류: ACCEPT**

- 실측 그대로다. 지표는 **상위 tail 에서만** 무작위와 분리된다(A_REL_TOP 99.0 백분위 vs A_REL_BOT 68.0). (a) 의 낮은 t 는 treatment 가 약해서만이 아니라 **control 이 약해서**이기도 하다.
- **결론이 이에 의존하지 않음을 명시**: 진짜 관문 (b)는 SINGLE_BEST 대조이고, 사후 귀속·A_PERP_TOP·무작위 귀무 셋 다 A_REL_BOT 을 쓰지 않는다.
- `alpha_validation.verdict.metric_discriminates` 에 "하위 tail 은 무작위보다 오히려 나음 = 지표의 음의 정보가 없다"로 기록.

---

## C8 [MEDIUM] 회전율 상한 위반

A_REL_TOP 실측 turnover **12.42/yr > 상한 11.0** (SINGLE_BEST 12.42, LEVEL_TOP_K20 12.41, A_REL_BOT 9.21).

**분류: ACCEPT** — `TURNOVER_CEILING_BREACH` flag. 구성 lane 이 살아났더라도 Production Constraints(Implementation Discipline) 별도 관문에 걸린다. 15bps 비용은 이미 net 반영이며 회전 자체가 규율 위반.

---

## 자기합리화 자동탐지 (v8.2 규약 3)

금칙어 기계 스캔 — `영향 미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 이미 반영` 및 회피표현 grep 목록에 대해 `alpha_package.json` · `alpha_validation.json` · L-code 아티팩트 전수 검사.

- 적발 2건 모두 **오탐**: "점**추정**"(point estimate, AP4 문맥) / "사전 **추정** 불가"(WT-006 인용). 통계 용어이며 회피 표현 아님. RE-VIEW 불요.
- **문턱 미달을 '사실상 통과'로 서술한 문장 없음** 자가 확인 — (a)/(b) 는 전 산출물에서 FAIL 로만 표기.

## Q-Lead 자동 escalate 판정

| 트리거 | 실측 | 발화 |
|---|---|---|
| HIGH severity ≥ 5 | HIGH 3건 (DISCRIMINANT_A/B_FAIL, ROBUSTNESS_ADDS_NOTHING) | 미발화 |
| AX axiom hard FAIL ≥ 3 | 0 (AX-001 v2 조건부 병기 이행, AX-002 하네스 내 실측, AX-008 3-source 중 2 확보) | 미발화 |
| PIT C1(lockbox·lookahead) 위반 | 0 — C3 반박 + 위반 주입 발화 | 미발화 |

**→ escalate 불요.** 정상 보고 경로.

## AX-008 Verification Triangulation

| source | 상태 |
|---|---|
| Self-Adversarial (본 문서) | ✅ 8 concern 제기·분류·조치 |
| Forge | ⏸ 미실행 — gate_eligible=FALSE, 자본 주장 없음(forge-authoritative 판정 불요) |
| Architect | ⏸ 미호출 |
| **내부 대체 검증** | canonical parity 2종 max_abs_diff = **0** (composite top-80 절단 / fast-path 재현) + 위반 주입 2종 발화 + basis 불변 2.8e-17 |

3-source 중 1 확보. **자본 게이트를 향하지 않는 measurement round 이므로 2/3 요건 미적용**(gate_eligible=FALSE·capital_claim=none). 후속 라운드가 이 산출을 자본 경로로 소비하려면 그 시점에 forge/architect 확보 의무가 발생한다 — 이 조건을 명시 기록한다.
