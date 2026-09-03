# challenge_note_forge — WT-R20260829_004 (Forge 구간 자가 적대검증)

**대상**: `authoritative_remeasure.json` (권위 등급 **C** · W2_IV 채택안)
**규약**: v8.2 Self-Adversarial Challenge — 외부 Codex 라운드 없음. fabrication risk(schedule fidelity · SR provenance) 와 측정 basis 약점을 스스로 ≥3건 제기하고, 각 건에 대해 **재도출 결과**를 붙인다.

---

## C1. "권위 수치가 상류보다 나쁜 건 forge 가 뭔가 잘못 돌렸기 때문 아닌가"

**제기**: PORT_t 가 상류 1.1575 → forge 0.7547 로 **-0.4028** 내려앉았다. 상류를 재현하지 못한 것이면 forge 수치를 권위로 쓸 수 없다.

**재도출**: 지배항은 전략이 아니라 **벤치 계열**이다.

| | 상류(weighted_screen, 월별 259) | forge(share-based, 일별 5,319) | forge/상류 |
|---|---|---|---|
| 전략 누적 | — | — | **1.0688** |
| 벤치 누적 | — | — | **1.2286** |
| 전략 CAGR | 12.49% | 13.14% | +0.65%p |
| 벤치 CAGR | 9.63% | **10.93%** | **+1.30%p** |

전략 쪽은 오히려 forge 가 **높다**. 내려앉은 것은 액티브이고, 그 원인의 큰 쪽은 **forge 벤치가 22.9% 더 많이 복리된다**는 것이다(월별 집계 벤치 vs `BM_DT` 일별). 이는 5/20 라운드에서 확인된 것과 같은 계통(상류 basis PORT_t 1.196 vs 권위 0.646, 지배항 = 벤치 계열)이다.

**결론**: 두 PORT_t 는 **다른 양**이다. 어느 쪽도 상대를 반증하지 않고, 판정에 쓰는 값은 forge 권위값 하나다. 상류가 틀렸다고 서술하지 않는다.

---

## C2. "weights.csv 를 as-is 로 썼다는 건 어떻게 아나 — 재선택/스케줄 조작(STR_1715 Iter 31 계통)이 아닌가"

**제기**: forge 층 fabrication 의 정본 사례는 optimizer 가 92 dates 를 냈는데 run_all 이 alpha_scores 에서 240 monthly 를 자체 합성한 것이었다. 같은 일이 없었다는 증거가 필요하다.

**재도출**:
- `run_all.R` 은 `alpha_scores.parquet` 를 **열지 않는다**(파일 내 참조 0). 종목 선택 코드 자체가 없다.
- `weights.csv` ↔ optimizer 발행 `RES$W2_IV$W` 대조: **unmatched 0행 · max|Δw| 5.55e-17**. 소비 대상이 채택 패널 그 자체임이 실증됐다.
- 스케줄 밀도 **재도출** 1.0000 (260 as_of / 260 alpha sig_dates, skip 0) — 상류 선언값과 일치.
- 리밸 실행 259회 · 리밸일별 distinct 종목수 **25~25** (`audit_bt_result::holdings_cap` PASS).
- 260번째 as_of(2026-08-28)는 홀딩월 2026-09 가 미실현이라 `get_execution_date` 가 데이터 범위 밖 → **skip 1건**. 이 skip 은 기록되며, 직전 보유가 데이터 끝까지 유지된다(deploy extension **18 거래일**).

★**훅을 방어선으로 세우지 않았다**: `schedule_fidelity_check.sh` 는 `.claude/settings.json` 미등록 + 필드명 불일치로 무발화다. 위 밀도는 훅이 아니라 산출물에서 직접 재도출한 값이다.

**남는 약점**: 위 증거는 전부 "선택을 하지 않았다"의 증거이지 "상류 선택이 옳았다"의 증거가 아니다. 상류 선택의 타당성은 forge 소관이 아니다.

---

## C3. "detect_lookahead CLEAN 을 PIT 증명으로 팔고 있지 않은가"

**제기**: 상류 3층이 모두 CLEAN 을 냈고 forge 도 CLEAN 이다. 4층 연속 CLEAN 은 계기가 죽어 있다는 신호일 수 있다.

**재도출(양방향 대조 · forge 층 직접 실행)**:

| 판 | 결과 |
|---|---|
| `run_all.R` 원본 | clean=TRUE (349 lines, 0 violations) |
| **선언 idiom 주입**(full-sample `mean(Close) by Ticker` · `shift(w,-1)` · `NEGATE_FACTORS`) | **발화 (1 violation)** |
| **비선언 idiom 주입**(전 표본 `cov()` · `mean()` · 비중 재정규화 · `shift(...,-1)`) | **미발화 (0 violations)** |
| 음성 대조(주석 1줄만 추가) | clean=TRUE |

**결론**: 양성 대조가 살아 있으므로 CLEAN 은 "미스캔"이 아니다. 그러나 **비선언 idiom 계통은 0/1 미발화** — 상류 3층 실측(0/3)과 동형이다. 따라서 CLEAN 은 **선언 idiom 부재의 증거**로만 인용했고, `strategy_spec$lookahead_prevention` 에 그 한계를 문장으로 박아 넣었다(`audit` Check 7 이 그 문장을 그대로 보존한다). PIT 의 실제 논거는 구조다: 신호는 `as_of_date`(신호월말)에서만 오고 체결은 `get_execution_date` = **홀딩월 첫 거래일**이며, 소비 컬럼에 `anchor_date`·`realized_ym` 이 **존재하지 않는다**.

---

## C4. "오버레이 PIT item4 를 자기 코드 grep 으로 통과시킨 것 아닌가"

**제기**: 초판 item4 는 `anchor_date in decision path = TRUE` 를 냈다. 그대로 뒀으면 위반으로 읽혔을 것이고, 반대로 문장만 고쳐 FALSE 를 만들면 **자기참조 조작**이다.

**재도출**: TRUE 의 정체는 `spec$lookahead_prevention` 안의 **선언 문장 자기 자신**("anchor_date/realized_ym 결정경로 미참조")이었다. optimizer 층이 남긴 `self_reference_note` 와 정확히 같은 함정이다. 문장을 지우는 대신 **결정경로의 정의를 좁혀 재도출**했다:
- 결정경로 = `deparse(.replay)` 함수 본문 + `weights.csv` 소비 블록 → `anchor_date` **FALSE** · `realized_ym` **FALSE**
- 독립 증거(자기참조 불가) = **소비 컬럼 헤더** 검사 → 둘 다 **FALSE**
- 파일 전문 스캔 결과(TRUE)도 `whole_file_scan_*` 필드로 **함께 기록**해 은폐하지 않았다.

---

## C5. "오버레이 PIT 가 clean 하다는 판정에 양성 대조가 있나"

**재도출(forge basis · optimizer 발행 `build_scores`/`make_W` 그대로 호출, 국면맵만 교체)**:

| 판 | Calmar | SR | 판정 |
|---|---|---|---|
| base(현행 컷오프) | 0.1843 | 0.5699 | — |
| **lag1**(신호 1개월 늦춤) | 0.1948 | 0.5907 | **NO_COLLAPSE** (+5.69% / +3.65%) |
| strict-PIT A/B | current == strict | — | **인플레 0.0000 (clean)** |
| **위반 주입**(신호 1개월 앞당김 = 홀딩월 자신의 국면) | **0.2350** | 0.6138 | **인플레 +27.54% (flag TRUE)** |

재구성 판이 채택 패널과 동일함을 먼저 확인했다(unmatched 0 · max|Δw| 5.55e-17) — 즉 위 세 판의 차이는 **국면맵 하나**에서만 온다.

**의미**: ①계기가 살아 있다(위반을 넣으면 뛴다) ②현행 판은 그 값을 내지 않는다 ③**위반 주입판 Calmar 0.2350 이 최선의 무조건화 IV(0.2063)를 넘는다** — alpha 층(0.224 > 0.206)·optimizer 층(0.2495 > 0.2180) 실측과 3층 동형이다. 이 라운드에서 "오버레이가 되는 것처럼 보이는 유일한 판"은 look-ahead 판이다.

---

## C6. "오버레이 한계기여 음수를 forge 권위로 주장하려면 반대 구성도 forge 로 재야 한다 — 그런데 그건 pure function 위반 아닌가"

**제기**: 비교 대상 비중을 forge 가 만들면 그 순간 optimizer 소관 침범이다.

**처리**: 만들지 않았다. optimizer 가 `o2_objects.rds` 에 **이미 발행한** 패널(W1_EW · W5_WCH_IV · C1_EW_off · C2_IV_off)을 그대로 소비해 동일 기간 · 동일 15bps delta · 동일 share-based NAV · 동일 계약(`build_bt_result`)으로 재측정했다. authoritative 는 W2_IV 하나이고 아래 표는 **진단**이다.

| 구성 | CAGR | SR | MDD | Calmar | netIR | PORT_t |
|---|---|---|---|---|---|---|
| **W2_IV (채택 · 권위)** | 13.12% | 0.5699 | 69.59% | 0.1885 | 0.1719 | 0.7547 |
| W1_EW (incumbent) | 12.13% | 0.5315 | 69.82% | 0.1737 | 0.1364 | 0.6006 |
| W5_WCH_IV | 13.25% | 0.5614 | 69.82% | 0.1897 | 0.1873 | 0.8256 |
| C1_EW_off | 13.61% | 0.5706 | 69.82% | 0.1950 | 0.2043 | 0.9012 |
| **C2_IV_off (오버레이 OFF)** | **14.35%** | **0.6027** | 69.59% | **0.2063** | **0.2308** | **1.0149** |

한계기여(ON − OFF): IV 짝 ΔCalmar **−0.0178** · ΔSR −0.0328 · ΔnetIR −0.0588 · ΔPORT_t −0.2602 · ΔCAGR −0.0124 / EW 짝 −0.0213 · −0.0391 · −0.0679 · −0.3006 · −0.0149. **전 축 음수 · 무조건화 IV 가 전 구성 지배** — optimizer 주장 **재현(REPRODUCED)**.

---

## C7. "그럼 오버레이가 왜 빼는가 — 라벨이 틀린 것 아닌가" (내가 제기하고 내가 반증)

**라벨 품질 재도출**: 패닉일의 BM 중앙 수중깊이 **−28.5%** vs 정상일 −12.5%. BM 이 20% 이상 수중일 때 패닉 발화율 **34.7%** vs 전체 평균 10.2%. ⇒ **라벨은 위기를 제대로 짚는다.** "라벨이 틀렸다"는 설명은 기각된다.

**실제 기전**: 패닉으로 라벨된 구간에서 KR 시장이 강하게 **반등**한다(BM 연율 **+45.5%**, 540 거래일/26개월). 저변동성 구성으로 갈아탄 롱온리 book 이 그 반등 베타를 반납한다 — 패닉 구간 액티브 **연율 −8.05%p**. 정상 구간에서 번 액티브(+4.81%p)를 패닉 구간에서 되돌려주는 구조다. alpha 층 F2(예측되는 성분이 특이위험이 아니라 **시장노출**)와 같은 이야기의 다른 얼굴이다.

**★자기 반증 — 이 기전 서술의 한계**: 국면별 액티브의 t 는 패닉 **−0.60** · 정상 **+1.02** 로 **둘 다 유의하지 않다**. 에피소드가 26개월뿐이다. 따라서 "패닉 구간에서 진다"는 **방향은 실측이되 크기는 0 과 구분되지 않는다**. 한계기여 음수는 전 표본 점추정으로 읽어야 하고, 국면별 분해를 유의한 발견으로 승격하면 안 된다.

---

## C8. "MDD 69.6% 인데 등급이 C 인 게 말이 되나"

**처리**: MDD 는 **어느 층에서도 등급을 접지 않는다**(도훈 지시 2026-08-24). 위험 축은 Calmar 하나(0.1885 < 0.64 → FAIL). `structural_drawdown = TRUE` 는 **라벨**이며 `hard_fail = FALSE`(source=none — 외부 judge 주입 없음). 등급 C 는 A 5조건 **0/5** 와 B 문턱(PORT_t ≥ 2 · netIR ≥ 0.2) 미달에서 나온 것이지 MDD 에서 나온 게 아니다. 문서 정합 중 MDD 직접 문턱을 되살리지 말 것.

---

## C9. 남는 미측정 (해소하지 못한 것)

1. **비선언 idiom 검출 커버리지 0/1** — 계기가 그 계통을 못 본다는 사실만 기록했고 대체 검사기를 만들지 않았다(하네스 쓰기 금지 경계).
2. **국면별 분해의 검정력** — 26 에피소드로는 국면 조건부 주장을 유의 수준으로 올릴 수 없다.
3. **`oos_retention −0.660`** — 상류가 전 method 음수(−0.857 ~ −0.066)라 보고한 축이고 forge 도 음수다. **비중으로 고칠 축이 아니다**(`OPT-CH2` HIGH). forge 는 이 축을 개선하지 못했고 개선 시도도 소관이 아니다.
4. **인계 이슈(우회 없음·기록만)**: `schema.json:17` task_id 정규식에 v10 접두 `R` 없음 + `wt_type` enum 에 `reinforcement` 없음. `worktask_constraint_enforcer.sh` 의 `WT-([DP])` 도 R 미포함이나 미매치 시 deployment 기본값이라 fail-safe 방향. `schedule_fidelity_check.sh` 미등록.

---

## 종합

3-package md5 시작/완료 동일(변조 0). `audit_bt_result` **19/19 PASS**(WARN 0 · FAIL 0), `factor_engine_path` 배선으로 Check 8·14·15 가 실제 실행됨(WARN skip 아님). 권위 등급 **C**, Grade A 5조건 **0/5**.

이 라운드의 실측 결론을 한 문장으로: **"오버레이 강화가 C 를 받았다"가 아니라 "오버레이가 없었으면 더 나았다"** 이며, 그 음수는 라벨 실패가 아니라 **롱온리 구성 교체가 반등 베타를 반납하는 구조**에서 온다.
