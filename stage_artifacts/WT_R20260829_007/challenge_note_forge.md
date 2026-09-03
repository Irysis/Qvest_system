# Challenge Note — Forge (WT-R20260829_007)

**Self-Adversarial Challenge** (v8.2 — 외부 Codex 호출 없음). finalize 직전 forge 자신의 산출물을
적대적으로 검증한다. 아래는 **내가 나에게 제기한 반론**과 그 처리다.

권위 등급 = **C** (essence_score, sweep/chain 양 framing 동일). Grade A 5조건 **0/5**.

---

## CH-F1 (HIGH) — 벤치 basis 는 내가 고른 레버다. 그 레버가 전략 교체보다 6.9배 크다

**반론**: forge 권위 PORT_t 0.636 을 "제약을 지키는 구성의 진짜 값"이라 말하지만,
같은 전략을 alpha 쪽 cap-w 벤치에 대면 PORT_t 0.877 이다. 즉 **벤치 하나 바꿔서 t 를 0.37 움직일 수 있다.**
이건 사후 basis 쇼핑의 완벽한 표면이다.

**실측 2x2** (공통 259개월, `forge_diag.json`):

| | B_prod (KOSPI200 production) | B_alpha (alpha cap-w 프록시) |
|---|---|---|
| **S_alpha** (M1 EW25 base) | 0.5709 | **0.9286** ← 상류 보고값 재현 |
| **S_forge** (M2_buffer50) | **0.5039** | 0.8768 |

- 벤치만 교체: Δt = **−0.3577**
- 전략만 교체: Δt = **−0.0518**
- 지배항 = **벤치 계열, 6.9배**

**처리**: ①basis 를 **측정 전에** 선언했다 — production harness BM 이 계약 기본값이고 선택지가 아니었다.
②상류 보고값 0.92858 을 소수점 5자리까지 **재현**했으므로 내 추정기가 아니라 basis 가 격차의 원인임이 확정된다.
③동일 259개월 누적: B_prod **7.934** vs B_alpha **6.271** — production 벤치가 더 강해서 같은 전략의 활성 t 가 내려간다.
④**상류 PORT_t 와 권위 PORT_t 는 다른 양**이라고 산출물에 명시했다. 직접 비교하지 않는다.
⑤5/20 forge 라운드가 기록한 벤치 수치(7.934 / 6.271)와 **동일하다** — 우연이 아니라 상시 basis 격차다.

★잔여 위험: 이 격차는 라운드마다 반복될 것이다. 상류 층 basis 를 production BM 으로 통일하지 않는 한
층 간 좌표는 계속 어긋난다. next_probe 로 넘겼다(우회 아님).

---

## CH-F2 (HIGH) — optimizer 가 하류에 넘긴 핵심 관측의 **방향을 나는 재현하지 못했다**

**반론**: optimizer 는 "회전 제어가 oos_retention 을 −0.384 → −0.425 로 **악화**시켰다"고 명시 이관했고,
나에게 "네 권위 OOS retention 이 이 방향을 확인하는지 보고하라"고 했다. 확인했다고 쓰면 편하다.

**실측**: 확인되지 **않는다**.

| basis | M1 (alpha 생산 사양) | M2_buffer50 (채택) |
|---|---|---|
| optimizer 자체 월별 엔진 | −0.38305 | **−0.425 (악화)** |
| forge 재측정 (alpha BM, 동일 정의) | **−0.3831** ← 소수점까지 재현 | **−0.3616 (소폭 개선)** |
| forge 재측정 (production BM) | — | −0.6367 |
| **권위 essence (v2, splits −0.561/−0.693/−1.227)** | — | **−0.693** |

- M1 값은 내가 optimizer 를 **소수점 5자리까지 재현**했다 → 내 추정기는 정상이다.
- 따라서 불일치는 **M2 계열 측정 경로**에서 온다: optimizer = 월별 연속 비중 엔진 / forge = 일별 정수주 share-based 재구성.

**처리**: "확인됨"으로 쓰지 않았다. 산출물에 `direction_confirms = false` 로 박고 사유를 적었다.
**level(깊은 음수)은 두 층이 일치**하고 **M1→M2 변화의 부호만 층 간 불일치**다.
따라서 *"회전 제어가 retention 을 악화시켰다"* 는 **측정 경로 의존 명제**이며 확정 진술이 아니다.
반대로 *"병은 회전이 아니라 후반부 신호 붕괴"* 라는 optimizer 의 **진단 자체는 권위 층에서 확인된다**:
부기간 활성수익 **2005-14 +11.03%/yr (SR 0.768) → 2015-19 −3.61% → 2020-26 −6.53%**.

---

## CH-F3 (HIGH) — detect_lookahead CLEAN 을 PIT 증명으로 쓸 뻔했다. 양방향 대조가 그것을 막았다

**반론**: audit Check 15 가 "CLEAN — 0 violations" 를 냈다. 이걸 PIT 논거로 쓰면 안 되는데,
쓰지 않았다는 걸 어떻게 증명하나?

**실측** (`forge_pit_bidirectional.json`):

- **양성 대조 5/5 발화** — C7a `scale()` on signal / C7b fwd_ret rank / C15 direct parquet / C13 NEGATE_FACTORS / C12 best_sharpe.
  → 검출기는 **이 파일 위에서 살아있다**.
- **커버리지 반증 0/4 발화** — R 음수 shift `shift(Close,-1L)` / 전표본 `cov()` / 전표본 `mean()` 재정규화 / 수동 미래 인덱싱 `all_dates[i+1]`.
  → 이 4종은 **전부 실제 look-ahead 인데 한 건도 안 잡힌다**.

**부수 발견 (검출기 결함, 우회 0 · 기록만)**: 1차 시도에서 Python 방언 idiom(`.shift(-1)` 등)을
양성 대조로 주입했더니 **0/3 미발화**였다. `detect_lookahead` 는 `is_python` 으로 분기하고
`PY_*` 패턴은 `.py` 전용이다. 그 결과 **R 분기에는 음수 shift 대응 패턴이 아예 없다**.
→ "축을 옮기면 양성 대조도 옮겨라" 의 실증 사례. next_probe 로 넘겼다.

**처리**: CLEAN 을 **선언 idiom 부재의 증거**로만 인용했다.
실제 PIT 논거는 **구조**다 — 비중이 forge 밖(`weights.csv`)에서 결정되고 forge 는 재선택을 하지 않으므로
**미래정보가 종목선택에 들어갈 경로 자체가 없다.**

---

## CH-F4 (MEDIUM) — MDD 55.03% 인데 structural_drawdown = FALSE 다. 라벨이 무르지 않은가

**반론**: `graduation_params$mdd_hard = 0.45` 가 존재하는데 MDD 0.5503 이 hard_fail 을 안 냈다.
게이트가 죽은 것 아닌가?

**실측**: `hard_fail = FALSE` · `hard_fail_source = "none"` · `drawdown_profile$structural_hard_fail = 0`.
이는 **v9.21 규약대로**다 — MDD 는 등급을 접지 않고 위험 축은 **Calmar 하나**(0.2516 < 0.64 로 이미 FAIL).
`mdd_hard` 는 파라미터 파일에 남아 있으나 판정에 쓰이지 않는다.

★단, `drawdown_profile$tail_review = 1` 이 켜져 있다(severe45_count 7 · severe45_hard_count 15 ·
severe45_period_hard_frac 0.25). **라벨은 FALSE 지만 tail_review 는 ON** 이라는 사실을 산출물에 남겼다.
이 후보를 오버레이 그릇으로 라우팅할 때의 근거가 여기다.

**처리**: MDD 직접 문턱을 되살리지 않았다. 등급은 Calmar 로만 접었다.

---

## CH-F5 (MEDIUM) — 통과한 감사 19건 중 실제로 판정하지 않은 것이 있다

**반론**: `audit_bt_result` 19/19 PASS 를 "전부 검증됨"으로 읽으면 안 된다.

**실측**: Check 13 `t_plus_1_cadence_consistency` 의 details 가
`rebalance_rule='month_end_signal_t_plus_1 (get_execution_date)' (T+1 미선언, skip)` 이다.
문자열 매칭이 내 선언 문구를 T+1 선언으로 인식하지 못해 **skip 한 뒤 PASS 를 냈다**.
PASS 이지만 **판정한 것이 아니다**.

**처리**: 산출물 `audit.check13_note` 에 기록했다. 반대로 **Check 14 / Check 15 는 실제로 실행됐다** —
`factor_engine_path` 를 처음부터 배선했기 때문이다(details: `lmf=0 / align=0 hits`, `318 lines, 0 violations`).
미배선이면 두 체크가 WARN skip 으로 내려앉고 그건 "위반 없음"이 아니라 **"미측정"**이다(5/20 교훈 적용).

---

## CH-F6 (LOW) — 상류 SR 주장과 내 실측이 다르다

optimizer M2_B50 `net_sharpe` 0.6445 vs forge 실측 **0.6877**. divergence **0.0432**.
`|div| < 0.6` → **NEGLIGIBLE** (FABRICATION 아님).
잔차의 알려진 원인 2종: ①창 길이(forge 259M 2005-02~ vs optimizer 247M 2006-01~, Σ warm-up 12M 절단)
②집행 해상도(일별 정수주 share-based vs 월별 연속 비중). **두 값은 같은 양이 아니며 forge 값이 권위다.**

회전은 반대로 잘 맞는다 — forge 독립 재측정 연 양방향 **10.113** vs optimizer 10.35, 둘 다 cap 11.0 통과.

---

## 사전 선언 무결성 — 내가 갈아타지 않았음의 증거

- 채택 **M2_B50** 만 측정했다. **M5_BUF40 으로 갈아타지 않았다**(문언 그대로 읽으면 유일 적격이지만 사후 재해석 금지).
- **B=60 으로 갈아타지 않았다** — net_IR 0.2863 으로 더 높지만 사전 선언은 "게이트를 만족하는 **최소** B"였다.
- 두 해석의 존재를 `upstream_constraint_incident.predeclaration_ambiguity_record` 에 기록했다.
- 3-package md5 **시작 == 완료** (3/3 동일). `target_weights` / `alpha_vector` / Σ 수정 0건.
- 쓰기 범위: `stage_artifacts/WT_R20260829_007/` 만. 병렬 라운드 `_004` / `_006` 접근 0.

---

## 남는 정직한 약점

1. **등급은 선행 런과 동일 C 다.** 좌표는 4축 모두 개선 방향이나 어느 것도 문턱 근처에 못 갔다
   (PORT_t 0.303 → 0.636 / 문턱 2.95).
2. **무신호 대조가 없다.** alpha 층이 규율상 미구축이라 forge 층에도 없다 —
   제약형 롱온리 25종은 형태 자체가 대형주 노출을 담으므로 **신호 기여는 여전히 증명되지 않았다**.
3. **RF-O2 마진 27bp.** 순활성 3.38%/yr vs 2×비용 3.11%/yr = 2.18배. 비용이 40.5bp 로 오르면 즉시 발화한다.
4. **β 0.687 을 안전 근거로 쓰지 않았다** — risk 1급 경고(COVID β 0.946 · 하방 TDC 0.545)대로
   시장 노출은 작아진 게 아니라 꼬리로 옮겨간 것이다. 꼬리 판정은 EVT(ES99 월 0.2123)로만 한다.
