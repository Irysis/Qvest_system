# Qvest v8.1.0 SOT — 3-Mode 헌법 · 실측 거버넌스 · 모듈 자동흐름

**발효**: 2026-06-05 · **계보**: v8.0.0 → **v8.1.0** · **Branch**: `v8.1-promotion` → `main`
**상위**: `CLAUDE.md` (헌법 Active Version) · 본 문서는 v8.1 설계 단일 진실(SOT).

---

## 1. 개요

v8.1은 v8.0(Opus 4.8-Native · Polyglot) 위에서 **① 3개 리서치 모드의 헌법 정립 ② 자가발전 공리 엔진의 원전(r7) 설계 복원 ③ 측정 거버넌스의 실측-only 재설계 ④ 모듈 표준화·자동흐름**을 더한 MINOR 승격(backward-compatible). 도훈 mandate 9건 + 횡단 E2E 4축 검증.

---

## 2. 3-Mode 체계

### 2.1 alpha-search (Lane2 — 논문 1편 경량 검증, 모듈 *생산*)
- **★ 제1원칙: 논문 완전 복제** (`.claude/skills/alpha-search/SKILL.md`):
  - 팩터 구성 방법론(회귀기간·skip·표준화·랭킹)·포트폴리오 비중·종목수·리밸·long/short = **논문 그대로**.
  - **유니버스 = K200∪KQ150 고정** (`universe="K200_KQ150"`, PIT 시변 멤버십).
  - **기간 = 2005-01-01~현재 고정** (`start_date` 기본값).
  - 임의 변형(top20/순수스코어/유니버스 축소) = 별개 전략 = **검증 무효**.
- `run_alpha_search.R`: universe/start_date 기본값 + `register_module` 배선 + PIT-WARN(외부 데이터 의존).

### 2.2 factor-rotation (Lane3 — 모듈 국면배합 meta-layer, 모듈 *소비*)
- 모듈을 생산하지 않고 국면 조건부로 배합. STR_XXXX 모듈(부품) → FR_XXXX 운용체계.
- 1모드 2트랙(Track1 레짐엔진 + Track2 배분). `register_module` 공용계약(등급무관) + **RCMA 6기준**(국면조건부 양방향: 방어형 CRISIS + 공격형 확장) + `run_factor_rotation` 신선도 자동인식.
- governor 정지(book_state 수동).

### 2.3 QEPM (Lane1 — 6-에이전트 풀파이프라인, 모듈 *생산*)
- alpha→risk→optimizer→forge→judge→governor. Codex Critic Round 의무.

### 2.4 모드 간 연결 (E2E 4축 배선 닫힘)
```
생산(alpha-search·QEPM·ML·DPL) → register_module → 04_Research/strategies/{id}/sim_result.rds
  → build_module_performance.R(광역 80+, 등급게이트 폐지) → RCMA → factor-rotation 소비 → FR_XXXX
자본 게이트(book_state confirm + 실주문) = 2버튼만 수동
```
- ML/DPL 다리: `register_research_module.R` + `register_research_outputs.R`(run_ml_cycle.py 호출).

---

## 3. Axiom 엔진 r7 원전 복원

- **5축 boolean-AND**: 독립·엄밀·반증·표본외·메커니즘 각 min-hurdle 동시 충족(weighted-sum 착시 폐기).
- **3-mode 2-tier**: alpha_search(proxy → mode-local `AX-AS-NNN`) / QEPM·FR(backtested → global `AX-NNN`). proxy는 global 승격 불가(INV-1).
- **INV-1~7 안전 불변식**: metric_type 게이트 / 생성≠강제 / rollback+weekly리포트 / min-hurdle / AX-008 2/3 / statement 정제 / negative=provisional.
- **AX-003~007 provisional 재분류**: N=2~3 섣부른 부정형 공리 → 잠정 실패기록(재도전 대상).
- SOT: `.claude/rules/axiom-engine.md`.

---

## 4. 실측-only 거버넌스 (measurement-graduation)

- **real-computation 의무**: proxy 손계산(top-quintile EW + 인라인 근사) graduation 폐지. `canonical_screen_bt` 또는 `build_bt_result` 경유 + `metric_type` 라벨.
- **portfolio-alpha t = forge-authoritative** (`forge_package.portfolio_alpha_t_nw_lag3`, NW lag-3). rank-IC t와 명확 구분.
- **HARD 게이트**: `portfolio_alpha_t_nw ≥ 2.95` + `oos_retention ≥ 0.7` + `calmar ≥ 0.64`(=16%/25%). DSR≥0.5는 **다중검정 스타일(n_trials>1)에서만** HARD.
- **admission = book-marginal** ΔIR ≥ 0.05. governor 자동화 금지(비가역 자본 게이트).

---

## 5. KR 데이터 한계 reference (2026-06-05 캐시 진단)

| 데이터 | 가용 시점 | 비고 |
|---|---|---|
| value/BM (`V01_BM`, FF3 HML) | **2002-08~** | 재무제표 의존(factor DB·fundamental 공통 한계) |
| `M08_Residual_Mom` | **1995~** | 가격 기반(재무 불요) |
| factor DB 전체 | **1990~** | Long(Date/Ticker/Factor_Name/Raw_Value/Z_Score), ~330 factor |
| `kr_factor_returns_v2` | MKT/SMB 2001-04~, HML/RMW/CMA 2002-08~ | `step0_kr_ff5_backfill.R` 빌드 |

→ FF/value 의존 전략은 **2005-08~**(value 2002-08 + 36m 회귀), 가격 기반은 1990~. **표준 기간 2005** 채택(논문 FF3 복제 충실).

---

## 6. 부팅 (bootstrap v8.1)

- 배너 3곳 v8.1 + **Step 4e(신규)**: RAWDATA `K200/KQ150` 멤버십 검증(`read_parquet col_select`) + `kr_factor_returns_v2` 신선도 — alpha-search `universe=K200_KQ150` 런타임 stop 사전 차단.
- 부팅 직후 체크리스트 13+5+**v8.1 4건(19-22)**. v8 readiness 15→16 check(`v8_architecture`).
- **부팅 갭(P1 후속, 미패치)**: axiom_weekly 7일조건 완화 / register_research_outputs 부팅 dry-run / module_performance 선제 초기화.

---

## 7. 미완(후속)

1. **residual momentum 사이클** register/factor_analysis 단계 디버깅(universe·fe_residmom 논문스펙은 OK, 등재 단계서 3회 중단).
2. **Axiom global 실가동** — backtested 공리 축적 후 promote_global 첫 가동.
3. `WT_WT-*` double-prefix bulk cleanup.
4. git push(`v8.1-promotion` → `main`) — GCM 인증.

---

## 참조

- `CLAUDE.md` v8.1.0 · `CHANGELOG.md` · `00_Lawbook/VERSIONING.md`
- `.claude/rules/{axiom-engine, measurement-graduation, factor-rotation, python-policy, artifact-naming, pit, backtest-contract}.md`
- `.claude/skills/{alpha-search, factor-rotation, qvest-telegram}/SKILL.md`
- 메모리: `project-qvest-e2e-validation` · `feedback-alpha-search-paper-replication` · `project-axiom-engine-v8-renewal` · `project-factor-rotation-mode-build`

## Change log
- 2026-06-05 v8.1.0: 신규 발행. 3-Mode 헌법 + r7 복원 + 실측 거버넌스 + 모듈 자동흐름 + KR 데이터 한계 reference.
