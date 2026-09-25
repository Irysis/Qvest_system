# 유기적 강화 설계 — 개방형 진화형(탐색 공간의 성장·퇴출)

- 작성: 2026-09-25 16시 KST
- 성격: 읽기 전용 설계다. 운영 트리·원장·레지스트리·기억 쓰기 0, R 실행 0, 텔레그램 0, 커밋 0. 원장·카탈로그·CSV 는 python 표준 라이브러리로 읽기만 했다.
- 관점: 다른 두 관점(베이지안 순차 배분형, PIT-우선 워크포워드 메타형)과 독립으로 설계했다.
- 근거: 결정 `REINFORCE-ORGANIC-AUTONOMY`(09-25 13:54 · 완전 자율 + 필수 가드 8종 + 헌법 권한 불변) · 결정 D-E(pit.md C1) · 레버 감사 최종본(`organic/lever_audit_final.md`) · 플랜 `qvest-1-drifting-eclipse.md`.

---

## 0. 요지 · A 기여 경로 · 사전확률

**한 줄 요지**
- 격자를 칸의 **개체군**으로 다시 읽는다.
- 개체군은 **틈새 지도**(기술자 3축) 위에서 유지·퇴출된다. 적합도는 **기계 결정 시점 τ\* 이전 데이터로만** 잰다(as-of).
- 새 arm 은 **격리 칸(shadow entry)** 을 거쳐서만 들어온다.
- 네 층(예산·공간·선택·구조)은 각각 정책(policy)으로서 사전등록 → shadow → 중첩 리플레이 → live 순서로 오른다.
- 러너 본체는 그대로 둔다. 판정은 `rf_runner_gates.R` 의 순수 함수와 러너 밖 컨트롤러가 맡고, 러너 수정은 O1 3줄 + O4 3줄이다.

**A 에 기여하는 경로 — 정직하게**

레버 감사의 결론은 세 가지다.
- 격자 반복이나 선택 규칙 교체로는 A 가 나오지 않는다.
- 구속 축은 OOS 다(1,105/1,193칸).
- A 에 가려면 Calmar +0.16 과 OOS +0.36 이 **동시에** 필요하다. OOS 벽은 2017~20년과 2025~26년에 거의 모든 칸이 공유하는 EW−CW 공통 활성 성분이다.

이 설계가 그 벽에 닿는 경로는 셋뿐이다.

| 경로 | 기전 | 구속 축과의 관계 | 성격 |
|---|---|---|---|
| (a) 예산 회수 → 새 기저 | B3 계열·B5 의 하류 소비자 없는 칸과 해로운 arm 을 as-of 규칙으로 줄이고, 그 몫을 신규 논문(ALPS 0층)으로 돌린다 | 천장을 옮기는 유일한 경로는 새 기저다. 다만 D10-06("기저 품질이 결과를 거의 예측하지 않는다")이 이 경로의 가치를 깎는다 | 효율. 확실함 |
| (b) 틈새 다양성 유지 | 기술자 δ1 = EW−CW 틸트 계수(≤τ\*)로 틈새를 나눈다. 틸트가 낮은 엘리트도 PT 가 높은 고틸트 칸에 밀려 사라지지 않게 보존한다 | 전기간 PT argmax 는 IS 알파가 가장 강한 칸, 곧 고틸트 칸으로 수렴한다. 이것이 "선택이 비구속 축을 올린다"는 진단의 기전이다. 다양성 보존은 방향을 선호하지 않으므로 OOS 를 겨냥한 선택이 아니다 | 재료 보존. 간접 |
| (c) 확정된 새 구조의 호스팅 | PR-L1 `cap_core`·PR-L2 B7 as-of 가 사전등록 판정에서 confirmed 가 되면 **블록 템플릿**으로 인스턴스화한다. 비어 있는 저틸트 틈새에 개체를 공급하는 경로다 | 유일하게 EW−CW 성분을 직접 치는 유형(cap_core)을 전 계보로 전파한다 | 조건부 |

**이 설계가 A 를 측정상 멀게 만드는 면**
- 기계의 모든 선정 통계를 τ\* 이전으로 자르면, 새로 태어나는 계보는 OOS 창을 보고 고른 **선택 인플레**를 잃는다. 그러면 측정된 A 근접도는 내려간다.
- 이것은 플랜 원칙 1("측정을 먼저 고친다. 고치면 A 는 멀어진다")에 해당하는 정정이지 퇴보가 아니다.
- 이 규율 아래서 나오는 A 는 Judge 6축의 selection 정직성을 통과할 수 있다. 지금 방식의 A 는 통과할 수 없다.

**Calmar 전이 한계**
- 최고 칸(22632 promo3 B1_3 · close_t1)의 두 큰 낙폭은 2007-11→2008-10 −0.563(τ\* 이전, 기계가 봄)과 2018-01→2020-03 −0.580(τ\* 이후, 기계가 못 봄)이다(`09_drawdowns.csv` 직접 확인).
- 기계는 GFC 형 낙폭만 최적화할 수 있다. 전기간 Calmar 로 전이될지는 기전이 두 국면 모두에 일반화되느냐에 달렸다. 전이 가능성은 판단상 중간(0.3~0.5)이다.

**사전확률(모두 판단값이다)**
- 새 구조 없이 유기체 단독으로 6개월 안에 권위 A(관문 + Judge PASS)가 나올 확률: **1% 미만**.
- 프로그램 A 확률(플랜 약 5%)에 대한 이 설계의 증분: **+0.5~1.5%p**. 대부분 (a) 새 기저 유입 속도와 (c) L1 확정 시 전파에서 온다.
- 확실한 이득은 A 확률이 아니라 다음 셋이다.
  - 예산 효율: 칸의 25~35% 회수. 원장 B3 206 + B5 247 = 1,311 중 34.6%, 이 중 상주·대조·진단 1칸은 남긴다.
  - 새 계보 OOS 의 정직성.
  - 단일 계보 쏠림 해소: 22632 가 B 225칸 중 104칸(46%), PT≥2.95 39칸 중 39칸이다.

---

## 1. 네 층 설계

### 1.0 지형 지도 검증·정정 (코드 직접 확인)

지도의 줄 번호와 기전은 대부분 맞다(러너 :138 첫 active 1건, :443-460 예산 재도출, :664-699 `.winner_of`, :754-783 바닥, gates :92-101, :391-434, :552-559, rf_promote :36-60·:93-124, ledger :712-753). 아래는 정정과 보강이다.

| # | 지도 서술 | 확인 결과 |
|---|---|---|
| C-1 | "fixed_axes(헌법)가 blocks 와 같은 파일" | 맞다. 보강할 점: `fixed_axes` 에는 INV-7 밖의 설계 변수 `base_weight 0.5` · `weight_cap null` 도 들어 있다. `rf_preflight.R:375-376` 은 **같은 파일**의 fixed_axes 로 셀을 대조한다. 기계가 이 파일을 쓰면 대조 기준까지 같이 움직인다(자기참조 가드). → 기계는 이 파일을 절대 쓰지 않고 **패치 파일 + 해시 고정**을 쓴다(§5) |
| C-2 | "22632 계보 전체 C1" | 맞다. 규모 보강: C1 표식 칸 = `selection_basis_full_sample_ic` 60 + `_inherited` 501 = **561/1,311(43%)**. 22632 는 B 104/225 · PT≥2.95 39/39 를 차지한다. as-of 아카이브에서 이 계보를 빼면 **현 엘리트 상단 전체가 빠진다** — 유기체의 출발 개체군은 나머지 47개 뿌리(084807 B 34 · 14760 29 · 18444 20 · 720 19 …)다 |
| C-3 | "P0-14 는 derive 의 '승계 집합 ⊆ factors' 를 재사용" | `02_Infrastructure`·`08_Tests` 의 R 소스에 `full_sample_ic_inherited` 를 만드는 함수가 **없다**(원장에만 있음). 배포 도구(`/c/tmp/p0_08_apply`) 쪽에만 있는 것으로 보인다(미확인). P0-14 는 운영 함수를 새로 만들어야 한다 |
| C-4 | "비중 퇴출 = status 필터" | `rf_weight_arms.R:40` 은 `retracted/withdrawn/failed` 3종만 거른다. `blocked_inputs 5 · unverified 5 · degraded_wiring 3` 은 probe_ok 가 걸러내지 않는 한 뽑힐 수 있다. 새 상태 `dormant` 를 넣으려면 :40 한 줄을 고쳐야 한다(오버레이 :47 `active` 만 · 팩터 lifecycle active 만 → 자동 제외) |
| C-5 | "RF_DECISION_KINDS 에 prereg_verdict 없음"(플랜 디렉터 절) | 이미 등재돼 있다(ledger :716 `a_eligibility`·`prereg_verdict`). 유기체 kind 는 새로 등재해야 한다 |
| C-6 | "P1-08 priority/experiment 필드" | 원장 64 entry 어디에도 `priority`·`experiment` 키가 없다(미구현). shadow entry 설계는 P1-08 을 전제로 한다 |
| C-7 | "상주 칸 삽입 (a) 만 남음" | 맞다. `rf_standing_decision:57` 은 코드 시도가 있으면 arm 이 suspended 여도 TRUE 다. 새 측정은 없고 커서만 유지한다 — 문제없음 |
| C-8 | "B1 as-of" | as-of 날짜 = `fixed_axes.start_date`(2005-01-01) = **사전표본 선정**이다(τ\* 보다 엄격). 유기체는 이것을 τ\* 로 **완화하지 않는다** |
| C-9 | 계보 구조 | 뿌리 48 · 깊이 분포 {0:47, 1:9, 2:4, 3:3, 4:1}. 승격 사슬은 소수 계보에 몰려 있다 |

### 1.A 공통 기층 — 네 층이 공유하는 상태

**(1) 기계 결정 시점 τ\* 와 내부 절단 τ₀**
- τ\* = `constraint_defaults.json::diagnostics.oos_calendar_splits[1]` = **2016-11-30**. 새 숫자가 아니라 기존 진단 키를 가리키는 포인터다.
- 근거: essence OOS retention 의 세 분할(0.55·0.65·0.75)은 2005 시작 칸에서 2016-11-30 · 2019-02-11 · 2021-04-08 이다(`essence_score.R:193` · constraint_defaults 의 골든 산출). 2005 이후 시작 칸의 분할은 더 늦다. 따라서 **τ\* 이하 데이터만 쓰는 선정은 어떤 칸의 등급 OOS 성분도 소비하지 않는다.**
- τ₀ = [2005-02-01, τ\*] 구간에 essence 와 같은 비율 0.55 를 적용한 절단일(약 2011 중반)이다. 계열에서 재도출하며 수치를 박지 않는다. 정책 리플레이의 내부 평가 창 (τ₀, τ\*] 을 정한다(§3 G4).
- τ\* 는 "기계 연구자가 서 있는 결정 시점"이다. 데이터를 가두는 창이 아니다. 사람·등급·Judge 는 전기간을 그대로 쓴다(lockbox 폐지 준수, §9).

**(2) as-of 적합도 F_τ(c) — R 계약**
- 셀 c 의 현행 규약(close_t1) 형제 판(`measurement_regime.remeasure_path` → `remeasure_close_t1_*/03_period_returns.csv`·`05_benchmark_returns.csv`)을 날짜 ≤ τ 로 자르고 essence 성분을 산출한다.
- 이것은 곧 P1-03 `sa_subwindow(end=τ)` 다. end = 원 종료일이면 essence 와 비트 동일해야 한다(플랜의 양성 대조).
- 성분: m^τ = {PT_τ, Calmar_τ, SR_τ, CAGR_τ, R_τ}. R_τ 는 ≤τ 계열 안의 내부 retention 이다.
- 등식 조건(정당성): 엔진이 PIT 이면 t 시점 수익은 ≤t 정보에만 의존하므로 "전기간 백테스트를 τ 에서 자른 것 = τ 시점 연구자가 돌린 백테스트"다. 엔진 PIT 는 detect_lookahead·B09 가드가 전제한다.
  - 전제가 깨지는 칸, 곧 C1/C11 표식 칸(P0-14 계보 승계 포함)은 **정의상 as-of 적합도를 가질 수 없다** → 아카이브·선택에서 제외한다.
- 유도량:
  - `d_A^τ(c) = min_j m_j^τ(c)/θ_j` — P1-01 산식이고 θ = `tier_graduation`(PT 2.95 · R 0.7 · SR 0.8 · CAGR 0.16 · Calmar 0.64)이다. 읽기만 한다.
  - `S^τ(c) = Σ_j max(0, θ_j − m_j^τ(c)) / σ̂_j`
  - σ̂_j = 통제칸(P1-06 null-factor 희석 · carry 재현)의 짝지은 차이에서 얻은 축별 잡음 척도다. 위상쌍 B6_32/33 은 SE 원천으로 쓰지 않는다(레버 감사 "하지 말 것").
- R_τ 비율 게임 방어: 선택 규칙에는 R_τ 가 올라도 PT_τ 가 잡음 띠 밖으로 내려가면 안 된다는 사전 조건이 있다(§1.3). 비율의 분모(IS 알파)를 희석해 retention 을 올리는 경로를 막는다.

**(3) 행동 기술자(behavior descriptors, ≤τ\*)** — 틈새 좌표이지 적합도가 아니다

| 기술자 | 정의 | 원천 | 칸 수 |
|---|---|---|---|
| δ1 틸트 | 일간 활성수익을 [시장, EW_U − K200] 에 회귀한 EW−CW 계수 b_ewcw | P2-02 `tilt_attribution.R`(**선행 필수** · 현재 파일 없음) | 4분위 |
| δ2 하락 포착 | 벤치 일간 하위 10% 날의 전략/벤치 평균수익 비 | P2-02 또는 `defensive_score` 심층 capture 정의 재사용 | 3분위 |
| δ3 집중 | 04_holdings 의 N_eff = 1/Σw² 중앙값 | 보유 파일 직접 | 3분위 |

- 틈새는 4×3×3 = 36 개다.
- **분위 경계는 epoch 개시 때 한 번 고정한다.** 경계의 원천은 강화를 거치지 않은 충실구현 기저 모집단의 ≤τ\* 기술자 분포다. 사전등록하며, 바꾸면 새 epoch 이 된다. 결과를 보고 적응적으로 구간을 나누지 않는다.
- 선정 근거:
  - δ1 = OOS 벽의 구조 원천(레버 감사 §② · 플랜 진단 2 PC1 54.5%).
  - δ2 = Calmar(GFC 형 capture).
  - δ3 = B2 에서 집중형 arm 이 최악이었던 축.
- 기술자는 **방향 선호가 없다**. 어느 칸도 틸트가 낮다는 이유로 이기지 않으며, 틈새마다 엘리트가 따로 산다. 따라서 δ1 은 OOS 를 겨냥한 선택이 아니다.
- δ1 을 고른 것은 사람의 연구 판단이다(문헌: 사이즈 프리미엄의 불안정성 — Asness et al. 2018). 자동 선정 규칙이 아니다.

**(4) 엘리트 아카이브 𝒜 (MAP-Elites · 사다리 삽입)**
- 틈새 n 마다 엘리트 집합 E_n 을 둔다(≤ k_elite 칸).
- 삽입 규칙(Blum & Hardt 2015 의 사다리):
  - `MC(c) ∧ d_A^τ*(c) > max_{e∈E_n} d_A^τ*(e) + κ·σ̂_dA` 이거나, `|E_n| < k_elite ∧ MC(c)` 이면 삽입한다.
  - 잡음 띠 아래의 개선은 **삽입이 아니다.** 잡음 증분을 쫓는 예산 흐름을 막는 장치다(D-F "잡음 파생 여백").
- **최소 기준 MC(c)**(Brant & Stanley 2017 의 minimal criterion) — 아래를 모두 만족해야 한다.
  - 고정 축 재도출 통과(`rf_preflight_verify_axes`)
  - regime = 현행
  - 유니버스 = k200_kq150
  - 창 허용(D-C)
  - C1/C11/`treatment_misspecified` 표식 없음(P0-14 계보 승계 포함)
  - B5 자기 층이면 G2 pass
  - `organic_shadow` 칸이 아님. shadow 칸은 별도의 **그림자 아카이브**로 간다.
- 삽입 사건 로그 = `rf_trial_log.jsonl` 의 `elite_insert` 레코드. 예산 층의 수확률 y 는 이 로그에서만 센다.

---

### 1.1 층 ① 예산 — ALPS 연령층 + 블록 연속 반감

**상태 변수**

| 변수 | 뜻 |
|---|---|
| `s = (s_0, s_1, s_2)` | 연령층 몫. 연령 = 승격 깊이이고 층은 0 = {0}, 1 = {1,2}, 2 = {≥3} 이다. prereg 레인은 층 밖에서 항상 먼저, 반사실 레인은 항상 마지막이다(D-G 순서) |
| `tier_b ∈ {full, half, min}` | 블록별 칸 수 등급. b ∈ {B1,B2,B3,B5,B6,B7,B4} |
| `n_b = {full: n_max_b, half: ⌈n_max_b/η⌉, min: n_min_b}` | 등급별 칸 수 |
| `b5_budget` | D-G 상태. 상주 + 2 ↔ 복원 |
| `entry_cap_e` | entry 별 상한. **축소를 허용한다** |

**결정 규칙**

- **(B-1) 레인 스케줄(결손 라운드로빈)**
  - entry 가 열릴 때 `j* = argmax_j ( s_j · C_7d − u_{j,7d} )` 로 층을 고른다. C_7d = 최근 7일 측정 칸, u = 층별 사용 칸이다.
  - 층 0 안에서는 큐 FIFO(P1-08 · `exhausted_at` 오름차순)를 따른다.
  - 층 1·2 안에서는 승격 후보 사슬을 부모 best 의 d_A^τ\* 로 줄 세운다. 잡음 띠 안은 동률로 보고 FIFO 로 깬다.
  - ALPS(Hornby 2006)의 요점은 **젊은 개체가 늙은 개체와 경쟁하지 않는다**는 것이다. 22632 promo 사슬이 신규 논문 예산을 잠식하지 못하게 한다. D-G 의 "승격 세대당 신규 논문 ≥1" 을 층 0 하한으로 구현한다.
- **(B-2) 층 몫 적응(주 1회)**
  - `s_j ← normalize( max( f_j, LCB90_Wilson(ŷ_j) ) )`
  - ŷ_j = 층 j 의 최근 W주 엘리트 삽입 수 / 측정 칸 수다.
  - f_j = 층 하한이다. f_0 은 D-G 에서 온다(config 값, 결정 ID 표기).
- **(B-3) 블록 연속 반감(Successive Halving · Jamieson & Talwalkar 2016 · Li et al. 2018)**
  - y_b = 최근 W_b 개 종료 entry 에서 블록 b 칸당 엘리트 삽입률이다(as-of).
  - 창마다 한 단계씩 움직인다.
    - `UCB90(y_b) < ȳ` 이면 강등(full → half → min).
    - `LCB90(y_b) > ȳ` 이면 승급.
  - ȳ = 프로그램 전체 칸당 삽입률, η = 3(Hyperband 기본). n_max = 5 이면 5 / 2 / 1 칸이다.
  - B1 은 min 하한 1 칸이다(하류가 B1 승자 위에 선다). B3 은 min 1 칸을 남긴다(유니버스 의존성의 유일한 진단원 — 레버 감사 ④).
- **(B-4) B5 = D-G 그대로**
  - "G2 pass 0 ∧ compose_only 지속 → 상주 + 2 칸, pass ≥1 이면 복원"이다. **도훈이 이미 결정한 사항이라 기계 재량이 아니다** → O1 에서 바로 live 가 가능하다.
  - B5 는 G2 pass 전에는 n_max 를 넘지 않는다(하지 말 것 1).
- **(B-5) entry 상한**
  - `entry_cap_e = Σ_b n_b(entry 개설 시 tier) + n_standing + n_control`
  - 구판 `max(auto, manual)` 의 래칫을 없앤다. 수동 상향은 **만료(entry 종료)와 결정 기록**이 있는 override 로만 허용한다.
- **(B-6) 승격 soft 예산(D-F)**
  - `cap_child = max(n_floor, round(M_full · P̂(Δd_A^τ* > 0)))`
  - P̂ = 부모 best 대비 자식 대표 칸의 짝지은 블록 부트스트랩 확률이다(≤τ\* 일간 계열, `adv_block_len` 재사용 · Politis & White 2004).
  - 짝지은 LCB>0 을 하드 규칙으로 쓰지 않는다(하지 말 것 5).

**입력**
- 원장 attempts: regime = 현행, vintage_flags 반영, `inherited_from` 제외.
- F_τ 캐시와 아카이브 삽입 로그.
- entry.parent.depth.
- 적대검증 verdict 와 `overlay_guard_h3/h4` jlog(D-G 판정).

**갱신 주기**
- B-1 은 entry 개설마다.
- B-3 은 entry 종료마다(다음 개설부터 적용).
- B-2 는 주 1회.
- B-6 은 승격 시.

**파라미터** — config 키 `reinforce_auto_config.json::organic.budget.*`

| 키 | 기본 | 근거 |
|---|---|---|
| `age_layers` | [[0],[1,2],[3,99]] | ALPS 연령층(Hornby 2006, https://doi.org/10.1145/1143997.1144142) |
| `layer_share_floor` | {L0: D-G 인용값, L1/L2: 0} | D-G(decision_register) |
| `eta` | 3 | Hyperband(https://arxiv.org/abs/1603.06560) · Successive Halving(https://arxiv.org/abs/1502.07943) |
| `window_entries` · `window_weeks` | 사전등록 | 사다리 기반 판정 창(Blum & Hardt 2015, https://arxiv.org/abs/1502.04585) |
| `n_min_by_block` | B1 1 · B3 1 · 그 외 1 | 레버 감사 ④(B3 진단원) · 하류 의존 |
| `promote_soft.n_floor` | 결정 D-F 인용 | D-F · 블록 부트스트랩 길이 = Politis & White 2004(https://doi.org/10.1081/ETC-120028836) |

**러너 개입 지점**(러너 본체 불변)
- `rf_runner_gates.R:98-101` `rf_budget_want(auto, manual, policy = NULL)`
  - policy 가 NULL 이면 `max(auto, manual)` 로 비트 동일하다.
  - 러너 `reinforce_auto_parallel.R:448` 은 `policy = rf_organic_entry_cap(E, ROOT)` 인자 하나만 더한다. **(수정 1줄)**
- `reinforce_auto_parallel.R:436` 뒤에 `cells <- rf_organic_cells_filter(cells, E, ROOT, log = jlog)` 를 넣는다. **(추가 1줄)**
  - entry 에 고정된 패치 판에서 블록별 n 으로 절단한다. n=0 이면 **명시적으로 건너뛴다**(L389 의 격자 폴백으로 새지 않게).
  - 휴면 축을 쓰는 B4 LOO 칸도 함께 뺀다. 유기체가 꺼져 있거나 entry 가 고정되지 않았으면 항등이다.
- `reinforce_auto_next_paper.R:61-65`(LIFO)와 :130-323(레인 순서)에 `rf_organic_next_lane()` 을 둔다. 러너 밖이다.
- `reinforce_auto_tick.sh:73` 과 `:89` 사이에 `Rscript rf_organic_tick.R` 을 넣는다. 컨트롤러는 **러너 claim(`rf_claim.R`)을 쥐고** 직렬화한다. 선례: `rf_l2_auto.R`.

---

### 1.2 층 ② 탐색 공간 — 입장·격리·퇴출·부활·생성 쿼터·다양성

**상태 변수**
- arm 생애: `proposed → quarantine → probation → active → dormant → retired`, 그리고 `tombstoned`(사람 전용).
- 카탈로그 `status` 는 **소비 스위치**로만 쓴다. 픽커는 기존대로 status 를 거른다.
- 생애 이력은 `06_Registry/rf_organic_state.json::arms[]` 에 둔다(`status_history` append-only).
- arm 별 as-of 통계: 측정 칸 수, 계보 수, 짝지은 Δd_A^τ\*·ΔCalmar^τ\*·ΔPT^τ\* 분포(바닥 대비), 엘리트 보유 수.
- 그림자 아카이브 𝒜ˢ: quarantine arm 의 격리 측정 결과다.

**결정 규칙**

- **(S-1) 입장(admission)**
  - 새 arm 은 `proposed` 가 된다.
  - 기존 정적 관문을 **그대로** 통과해야 한다: `rf_overlay_admit` G1 · `admit_generated` · `rf_factor_autoregister` 중복 ρ · `overlay_pit_guard` + B09 probe · 고정 축.
  - 통과하면 `quarantine` 이 되고 **shadow entry** 에서 측정한다.
    - shadow entry = `rf_open_entry(priority='organic_shadow', experiment=...)` (P1-08 전제). 바닥은 as-of 기준 바닥 집합 R = {r_1..r_K}(K=3)이고 짝지은 통제칸을 둔다.
    - 기준 바닥은 floor v2 에서 **C1 표식이 없는 칸만** 쓴다. F1(22632)은 P0-14·플랜대로 as-of 재선정 새 칸으로 대체한다.
  - `probation` 조건: `∃r: MC(c_r) ∧ ( 그림자 아카이브 삽입 ∨ ν(c) ≥ q_ν )` 다. ν = 신규성이다.
  - `active` 조건: probation 에서 live entry P_prob 회를 거치는 동안 해로움(`UCB90(med Δd_A^τ*) < 0` 이 서로 다른 바닥 2곳 이상)이 없어야 한다.
- **(S-2) 휴면(dormant)**
  - 조건: `n_x ≥ n_min ∧ lineages(x) ≥ m_min ∧ UCB90(med Δd_A^τ*) < 0 ∧ UCB90(med ΔCalmar^τ*) < 0 ∧ elites(x) = 0`
  - 부트스트랩은 **뿌리 계보 군집** 단위다. 휴면이 되면 status=`dormant` 로 픽커 소비만 멈추고 삭제하지 않는다.
  - 레버 감사가 지목한 해로운 arm(CDaR_LP·SchurDamping·minvar·B1 7+ 적층)은 **정답지로 쓰지 않는다.** 그 목록은 전기간 판정이다. as-of 규칙이 독립적으로 도달하는지는 보고용 일치율로만 적는다.
- **(S-3) 부활(reopen)**
  - dormant → probation 으로 되돌리는 트리거:
    - `measurement_regime` 변경
    - arm 코드·엔진 파일 md5 변경(원인 수리)
    - 새 바닥 계열의 기술자 거리가 기존 시험 바닥 전부와 d_min 이상 떨어짐
    - 휴면 26주 경과 시 주기 재시험 1칸
  - 근거: 기억 카드 "닫힌 칸에는 되살리는 어휘가 있어야 한다".
- **(S-4) 퇴역(retired)**: dormant ≥ T_ret 주 ∧ 부활 시험 2회 실패. 기록은 남는다. `tombstoned` 해제는 사람만 한다.
- **(S-5) 생성 쿼터 — 빈 틈새 겨냥**
  - 네 생성 레인(`rf_overlay_propose` · B5 설계 · B1 설계 · `rf_weight_catalog_grow` · `rf_factor_autoregister`)에 **표적 기술자 힌트**를 준다: 엘리트가 없는 틈새 중 도달 가능성이 가장 높은 곳.
  - 쿼터는 기존 가드 상한(H2 `daily_arm_cap`, H4 `max_active_generated`) **아래에서만** 조정한다. 기계는 가드 상한을 올리지 못한다.
  - B5 기전 지도(`rf_mechanism_map.R:95`)의 (action,state) 표적과 합친다. 포화 k 는 격자값 그대로 쓴다.
- **(S-6) 다양성·모드 붕괴 방지**
  - 계보 점유 상한: `elites(top_lineage)/|𝒜| ≤ c_lin`.
  - 적합도 공유(Sareni & Krähenbühl 1998): 예산 층이 쓰는 유효 적합도 `f'(c) = d_A^τ*(c) / (1 + Σ_{c'∈같은 계보 엘리트} 1[‖δ(c)−δ(c')‖ < σ_share])`
  - 신규성(Lehman & Stanley 2011): `ν(c) = (기술자 ⊕ 유전형 Jaccard 공간에서) 아카이브 k 최근접 평균 거리`. 유전형은 `rf_spec_sig` 서명이다.
  - 아카이브 엔트로피 `H = −Σ_n p_n log p_n` 을 추적한다.

**입력**
- 세 카탈로그: overlay 33(active 31 · retired 1 · suspended 1), weight 52(active 39 …), factor 370(active 366).
- `overlay_arm_ledger.jsonl`(26행) · `rf_coverage.R` 서명 색인 · F_τ 캐시 · P0-14 표식 · 적대검증 verdict · `pit_quarantine.json`(읽기만).

**갱신 주기**
- 입장·probation: shadow 칸이 끝날 때마다.
- 휴면·퇴역·부활: 주 1회.
- 생성 쿼터: 하루 1회(기존 레인 주기).

**파라미터** — `organic.space.*`

| 키 | 근거 |
|---|---|
| `descriptors` · `bins` · `k_elite` | MAP-Elites(Mouret & Clune 2015, https://arxiv.org/abs/1504.04909) · QD(Pugh et al. 2016, https://doi.org/10.3389/frobt.2016.00040) |
| `novelty_k`(15) | Lehman & Stanley 2011(https://doi.org/10.1162/EVCO_a_00025) — 미로 실험 k |
| `sigma_share` · `lineage_share_cap` | Sareni & Krähenbühl 1998(https://doi.org/10.1109/4235.735432) |
| `minimal_criterion` | Brant & Stanley 2017(https://doi.org/10.1145/3071178.3071186) · POET(https://arxiv.org/abs/1901.01753) |
| `retire.n_min` · `m_min` · `T_ret` · `reopen_weeks` | 사전등록. 군집 부트스트랩 검정력(`required_effect_size.R`)으로 n_min 을 정하고 산출식을 config note 에 적는다 |
| `quarantine.floors_K` · `probation_entries` | 사전등록 |

**러너 개입 지점**
- 러너 수정은 없다.
- `rf_runner_gates.R:395` `rf_candidate_facts` 에 `organic_shadow` 사실을 추가한다. 모든 역할(winner·floor·carry_base·promote)에서 제외되며, 러너·`rf_promote_best` 가 같은 함수를 부르므로 한 곳에서 해결된다.
- `rf_weight_arms.R:40` 필터에 `dormant` 를 추가한다(1줄).
- `rf_b1_design_lib.R:175-202` 검증에 lifecycle≠active 거부를 넣는다. 설계 레인이 휴면 팩터를 고르지 못하게 한다.

---

### 1.3 층 ③ 선택 기준 — as-of 체비쇼프 d_A + 사다리 띠 + 틈새 동률 깨기

**상태 변수**: live 선택 정책 id(π₀ 또는 π_τ 계열), 역할별 가치 함수, 잡음 띠 κ.

**결정 규칙**(`rf_select_value(a, by, role, pol)` · `rf_runner_gates.R` 신설 순수 함수)
- **π₀(현행)**: `essence[[by]]`. by 는 **격자 `blocks[].select_winner_by` 를 실제로 읽는다.** 격자 값(B1 port_t · B2 port_t · B3 calmar · B5 calmar)이 러너 리터럴과 같으므로 비트 동일이다. 동시에 죽은 선언(P1-05)이 해소된다.
- **π_τ(유기체)**:
  1. 후보 C = `rf_candidates_keep` 통과 ∧ MC 통과 ∧ F_τ\* 캐시 존재. 캐시가 없으면 `asof_unmeasured` 로 제외하고, 로그 없이 조용히 폴백하지 않는다.
  2. 가치 `v(a) = d_A^τ*(a)` (체비쇼프 스칼라화). A 는 모든 축이 문턱을 넘어야 하므로 가장 약한 축을 올리는 스칼라화가 목표와 정합한다.
  3. 사다리 띠: `C_top = { a : v(a) ≥ max v − κ·σ̂_dA }`.
  4. 비율 게임 방어: C_top 에서 `PT_τ*(a) < max PT_τ* − κ·σ̂_PT` 인 칸을 제거한다.
  5. 동률 깨기: C_top 안에서 **점유가 적은 틈새**의 칸을 먼저 고르고, 그래도 같으면 가장 작은 n 을 고른다(결정론).
- **승격**(`rf_promote.R:114-117`): `PT(best) > PT(parent)` 대신 `d_A^τ*(best) − d_A^τ*(parent_best) > κ·σ̂_dA` 를 쓴다. 연장(:74-87)도 같은 가치를 쓴다. 깊이 hard 상한 6 은 유지한다.
- **carry 기준선**(`.beats_carry` · `rf_floor_carry_gate`): 같은 가치 함수와 같은 띠를 쓴다.
- **블록 순서**(`rf_lesson.R:115`): **바꾸지 않는다.** 블록 순서 최적화 재투입은 금지다(하지 말 것 1 · 09-18 NO-GO).

**입력**: F_τ 캐시 · σ̂(통제칸) · 아카이브 점유.

**갱신 주기**: 배치마다 승자를 해석할 때(러너 기존 주기).

**파라미터** — `organic.selection.*`

| 키 | 근거 |
|---|---|
| `scalarization`("chebyshev_dA") | NSGA-II 계열 다목적 관행(Deb et al. 2002, https://doi.org/10.1109/4235.996017) + P1-01 d_A 정의 |
| `kappa_band` | D-F("짝지은 SE 배수") · Ladder(https://arxiv.org/abs/1502.04585) |
| `tie_break` = ["niche_occupancy_asc","n_asc"] | MAP-Elites 틈새 보존 |

**러너 개입 지점(O4)**
- `reinforce_auto_parallel.R:683` `v <- vapply(cand, function(a) rf_select_value(a, by, paste0("winner_", bid), .POL), numeric(1))` **(1줄)**
- `:766` 과 `:774` 바닥 가치 **(2줄)**
- `:726/:729/:736` 은 호출 인자 `by` 를 그대로 둔다. 가치 함수가 격자를 읽는다.
- `rf_promote.R:59` 와 `:114-117` 은 러너 밖이다.
- `.POL` 은 `rf_organic_policy(E, ROOT)` 로 entry 에 고정된 선택 정책이다. O1 에서 추가한 PROG 줄과 같은 자리에 둔다.

---

### 1.4 층 ④ 구조 — 허용 목록 안의 변이만

**상태 변수**
- 유효 격자 = 기저 `reinforce_program.json`(sha 고정) ⊕ `06_Registry/reinforce_program_patch.json`(판 번호).
- entry 는 개설 시 패치 판을 고정한다(`entry.organic_patch_ver`). 이것이 블록 순서 사전등록(`rf_record_block_order`)과 같은 불변성이다.

**허용 변이 집합 𝓜**(나머지는 거부 — deny-by-default)

| 변이 | 조건 |
|---|---|
| M1 블록 칸 수 등급 | 층 ①(B-3)의 결과를 패치에 쓴다 |
| M2 블록 휴면(n=0) | K 창 연속 `UCB90(y_b)=0` ∧ B1 아님 ∧ 그 블록이 어떤 기술자 칸의 유일한 공급원이 아님. 그 축을 쓰는 B4 LOO 칸도 같이 뺀다 |
| M3 통제 상주 칸 | 통제 템플릿(`carry_replay`·`null_factor` · P1-06)만 붙이거나 뗀다. control 태그 칸은 서명 dedup·승계에서 뺀다(플랜 P1-06) |
| M4 템플릿 블록 인스턴스화 | `06_Registry/block_templates.json` 에 **사람이 구현·검사해 등재한** 템플릿만 쓴다. 예: B4 LOO 5·6축 확장(B6·B7 · program `loo_gap_note`), `cap_core`(**PR-L1 confirmed 이후에만**), B7 as-of(PR-L2 confirmed 이후) |
| M5 블록 분할·병합(계열 기준) | O4 이후 선택 사항이다. `test_rf_grid_contract.R:36`(블록당 5칸 계약)을 패치 경계 인지형으로 바꾼 뒤에만 허용한다 |

**금지**
- 블록 순서
- fixed_axes 전체(INV-7 + `base_weight` 포함)
- `graduation` · `execution`
- 새 엔진 코드(기계는 템플릿을 고르기만 한다)
- G2 pass 0 동안 B5 n > 5

**결정 규칙**
- 트리거가 서면 변이 제안 → 사전등록 → shadow(유효 격자를 계산하되 적용하지 않고, 리플레이가 결과를 예측) → live 게이트(§3 G4) 순서로 간다.
- 트리거 셋:
  - (i) 블록 수확률 창 판정
  - (ii) 빈 틈새 ∧ 그 기술자를 겨냥하는 템플릿 존재
  - (iii) LOO 공백 축의 수확률 > 0

**갱신 주기**: 주 1회. 주당 live 변이 ≤ 1 이다(`policy_state.R` 회로차단기와 같은 값을 그대로 쓴다).

**파라미터**: `organic.structure.{templates_path, max_live_mutations_per_week, dormant_windows_K}` · 근거는 POET 의 환경 변이 + 최소 기준(https://arxiv.org/abs/1901.01753).

**러너 개입 지점(O1)**
- `reinforce_auto_parallel.R:138` 뒤에 `PROG <- rf_program_effective(ROOT, E, base = PROG)` 를 넣는다. **(1줄)**
  - 패치가 없거나, entry 가 고정되지 않았거나, 유기체가 꺼져 있으면 base 를 그대로 돌려준다(비트 동일).
- :124 는 그대로 둔다. :124~138 사이에서는 PROG 를 쓰지 않는다(확인함).

---

## 2. ★ D-E 정합 — 자동 선정과 pit.md C1 의 관계

### 2.1 무엇이 충돌하는가

- D-E 문언: "평가 창 결과를 소비하는 자동 선정 규칙도 C1/C14 대상 — 팩터·arm·슬리브를 전기간 IC·ic_bad·상관으로 고르면 시점 t 보유를 미래 통계로 정한 것. 선정 통계는 as-of 로만. 사람이 문헌 근거로 고르는 것은 해당 없음."
- 같은 날(09-23) 도훈 확정 사항 "선택 규율 (A)": "sweep 정직 표기 + 강건 선택 + A 후보 구속 축 다중검정 서류 — **전기간 데이터 유지**".
- 현 러너의 자동 선정 5곳(`.winner_of`·바닥·carry·승격 best·연장)은 전부 **전기간 essence argmax** 다. B2·B5 승자는 곧 **arm 선정**이다.
- 문언대로 읽으면 현 격자 승자 선택부터 C1 이다. 실제 운영은 이를 (A) sweep 회계로 다뤄 왔다. **두 결정 사이에 명문 경계선이 없다.**
- 자율 적응 층은 정의상 평가 결과를 소비하는 자동 선정 규칙이므로 이 공백 한가운데에 선다.

### 2.2 두 개의 시간축과 두 종류의 통계

| | 시장 시각 t (백테스트 달력) | 연구 시각 s (선택이 이뤄진 벽시계) |
|---|---|---|
| **성분 통계**(부품의 성질: 팩터 IC · 슬리브 ic_bad · 상관 · arm 풀링 Δ) | 22632: B1 규칙 픽커가 전기간 IC 로 팩터를 **측정 전에 걸렀다.** 걸러진 370 후보는 N 에 잡히지 않았다 | 유기체 arm 퇴출(풀링 Δ)이 여기다 |
| **후보 통계**(완전히 명세된 한 후보의 백테스트) | — | 격자 argmax · carry · 승격 · 유기체 선택 층. 측정 칸 = N 에 잡힘 |

핵심 관찰 두 가지.
- 명세가 고정된 후보는 **어떻게 골랐든 그 자체로 PIT 규칙**이다. 선택의 문제는 선택 편향이지 데이터 가용성이 아니다.
- 그런데 D-E 는 성분 스크린을 C1 로 규정했다. 성분 스크린의 해악은 **보이지 않는 시행**, 곧 측정되지 않아 N 에 안 잡히는 수백 건의 선별이다. 이 점에서 설명된다.

### 2.3 해석 선택지

**(i) 좁은 해석 — 성분 통계만 C1**
- 명세 후보의 백테스트로 고르는 것(격자 argmax·carry·승격·유기체 선택·arm 생애)은 전부 다중검정 회계 대상이다(N·DSR·PBO).
- 장점: 현 격자와 결정 (A)를 그대로 유지한다.
- 약점:
  - arm 풀링 Δ 는 부품의 성질이라 성분 통계와의 경계가 흐리다(D-E 문언에 "arm" 이 명시돼 있다).
  - 전기간 창을 수천 번 **적응적으로 재사용**하는 것은 DSR 의 독립 시행 가정 밖이다(Dwork et al. 2015, 적응적 홀드아웃 재사용). 유기체가 OOS 창을 보고 진화하면 새 계보의 OOS retention 이 선택으로 부풀고, Judge 6축(selection 정직성)의 판별력이 사라진다.

**(ii) 넓은 해석 · 사전표본 — 모든 자동 선정은 결정 시점 = 백테스트 시작일(2005-01-01) 이전 정보만**
- B08 의 B1 픽커가 이미 이 기준이다.
- 결과:
  - 성과를 쓰는 모든 적응이 불가능하다. 유기체의 자율은 비고 격자 argmax 도 금지된다.
  - 기존 강화 계보 전부에 보류 코드가 붙고, 워크포워드 메타 전략(시간 가변 arm 집합)을 새로 만들기 전까지 강화 A 경로가 소멸한다.
- 가장 엄격하고 문언에 가장 가깝다. 비용은 사실상 강화 프로그램 전체다.

**(iii) 회계 가능성 기준**
- **측정되지 않은 선별**(성분 통계로 후보를 측정 전에 떨어뜨리는 것 — IC·ic_bad·상관·풀링 Δ 스크린)만 C1 이다.
- **측정되어 N 에 잡힌 후보 사이의 선택**은 다중검정이다.
- 유기체는 자기가 고려하는 모든 대안을 측정 칸(shadow 포함)으로만 다뤄야 한다. 성분 스크린은 as-of(사전표본)일 때만 허용한다.
- 장점: D-E(22632·B7 ic_bad = 보이지 않는 스크린)와 결정 (A)(측정 칸 sweep)를 한 원리로 묶는다.
- 약점: (i)과 같은 적응 재사용 문제가 남는다. N 은 적응성을 가두지 못한다.

**(iv) 권고 — (iii)을 법적 경계선으로 삼고, 기계에는 τ\* 분리 as-of 를 부과한다**
- ① **경계선**: C1 = 측정되지 않은 성분 스크린. 22632 표식·B7 표식·B08 은 모두 여기서 C1 이다(현행 유지).
- ② **기계 규율**: 기계(유기체 전 층, O4 이관 뒤의 격자 선택 연산자·carry·승격)가 쓰는 **모든 선정 통계는 ≤τ\* 데이터로만** 계산한다.
  - τ\* = 등급 OOS 첫 달력 분할(2016-11-30)이다. 따라서 **어떤 칸의 등급 OOS 성분도 기계 선택의 입력이 된 적이 없다.**
  - 정책 승격(리플레이)도 (τ₀, τ\*] 에서만 평가한다. 두 단 as-of 다.
- ③ **정직한 한계**:
  - (iv)는 문언의 엄격판(보유 t 마다 ≤t)을 [2005, τ\*] 구간에서는 **만족하지 않는다.** 이 구간은 기계 선택에 대해 in-sample 이다.
  - (iv)가 보장하는 것은 "평가받는 OOS 창을 선택이 소비하지 않는다"이다. 이는 pit.md 가 '측정 규율'로 존치한 IS/OOS 앵커 분할과 같은 성격이다.
  - 문언 엄격판이 필요하면 (ii)밖에 없다.
- ④ **과도기**:
  - 현 격자 argmax 는 O4 이관 전까지 결정 (A)(sweep 회계) 아래에 둔다. 이관 전에 태어난 칸에는 `selection_basis=full_sample_grid` 라벨만 단다(보류 아님 — 결정 (A) 존중).
  - 이관 뒤 태어난 칸에는 `selection_asof=τ*` 라벨을 단다. 이 라벨이 있는 계보만 Judge selection 정직성 축에서 "선택이 OOS 를 보지 않았다"를 **증명할 수 있다.**
- ⑤ **남는 오염원 표기**:
  - LLM 설계 레인의 사전학습 기억은 C1~C15 밖이다(기억 카드 09-24).
  - 설계 재료가 ≤τ\* 가 아니면 as-of 가 깨진다(P1-09 design basis 를 τ\* 판으로).
  - 따라서 `design_source ∈ {rule_asof, llm, human_literature}` 를 기록하고, 메타 평가는 출처별로 나눠 보고한다.

### 2.4 선택지별 일관성

| 대상 | (i) 좁은 | (ii) 사전표본 | (iii) 회계 가능성 | **(iv) 권고** |
|---|---|---|---|---|
| 격자 승자 선택(전기간 argmax) | 합법(sweep) | **위반** — 전 계보 보류 | 합법(측정 칸) | 과도기 합법(A) → O4 뒤 ≤τ\* |
| carry | 합법 | 위반 | 합법 | 승자와 같은 연산자 |
| 승격 | 합법 | 위반 | 합법 | ≤τ\* 가치 + 잡음 띠 |
| 22632 표식(전기간 IC 스크린) | C1 | C1 | C1 | C1(현행 유지) |
| B7 ic_bad 슬리브 | C1 | C1 | C1 | C1 |
| 유기체 arm 퇴출(풀링 Δ) | 회색(문언 "arm") | 불가 | 측정 칸 풀링이면 합법 | ≤τ\* 풀링만 |
| 유기체 예산·구조 | 합법 · 적응 재사용 무제한 | 성과 무관 결정만 | 합법 | ≤τ\* + 중첩 리플레이 |
| 새 계보 OOS 의 정직성 | 오염(선택이 OOS 창을 봄) | 정직 | 오염 | **정직(기계 선택에 대해)** |
| 현 A 관문 영향 | 없음 | 보류 코드 신설 · 전 계보 | 없음 | 없음(라벨만) · 22632 는 기존 보류 |

### 2.5 도훈 결정 안건 문안

> **ORGANIC-DE-INTERP — 자동 선정 규칙(격자 승자·carry·승격·유기체 적응)과 pit.md C1(D-E)의 관계 해석**
> - 배경: D-E("평가 창 결과를 소비하는 자동 선정 규칙 = C1/C14")와 결정 (A)("sweep 정직 표기 · 전기간 데이터 유지")가 같은 날 확정됐으나 경계가 명문화되지 않았다. 현 러너의 자동 선정 5곳은 모두 전기간 essence argmax 이고 B2·B5 승자는 arm 선정이다. REINFORCE-ORGANIC-AUTONOMY 로 기계가 arm 생성·퇴출·선택 기준까지 결정하게 됐으므로 경계가 필요하다. PIT 해석은 기계 권한 밖이다.
> - 선택지:
>   - (i) 성분 통계만 C1, 후보 선택은 다중검정
>   - (ii) 모든 자동 선정은 사전표본(≤2005-01-01)만 — 강화 A 경로 사실상 소멸
>   - (iii) 측정되지 않은 선별만 C1, 측정 칸 사이 선택은 다중검정
>   - (iv) (iii) + 기계의 모든 선정 통계는 τ\*(= diagnostics.oos_calendar_splits[1], 2016-11-30) 이하만, 정책 승격은 (τ₀, τ\*] 중첩 평가, 격자 연산자는 O4 이관 전까지 (A) 과도기
> - Q 권고: **(iv)**
> - 부속 질문:
>   - (a) τ\* 고정 vs 분할점 따라 전진 — 권고 **고정**. 전진은 OOS 정직성을 적응성과 맞바꾼다.
>   - (b) 이관 전 격자 선택 칸의 A 처리 — 권고 **라벨만**(결정 (A) 존중). 대안: `selection_full_sample` 보류 코드.
>   - (c) 유기체가 태어나게 한 A 후보의 DSR N 범위 — 권고: 서류에 program-epoch N 병기, 게이트 N 은 D-A 유지(P1-03 보정 뒤 재상정).
> - 결정 전 기본값: 유기체는 **shadow·리플레이만**(live 0). 예외로 **성과 무관 결정**과 **도훈 기결정 D-G 구현**(b5_budget·FIFO·레인 순서)은 live 를 허용한다. 격자는 현행 (A).
> - 차단: 유기체 live(성과 소비 결정 — 예산 적응·arm 퇴출·선택 연산자·구조 변이) · O4 이관 · P1-07 H1 지표 교체.

---

## 3. 가드 8종 · 킬스위치 · 롤백 · 승격식 · 주간 보고

### 3.1 가드 구현

| 가드 | 파일·함수 | 검사(양성 대조 / 위반 주입 / 돌연변이) |
|---|---|---|
| **G1 시행 회계** | `06_Registry/rf_trial_log.jsonl`(P1-02 정본을 공유한다 — 새 저장소가 아니다). writer `reinforce_ledger.R::rf_trial_log_append(kind, …)`. kind ∈ {organic_proposal, organic_admit, organic_reject, organic_shadow_cell, organic_policy_eval, organic_retire, organic_reopen, organic_structure, elite_insert}. `rf_a_eligibility` ④ 에 "유기체 epoch 칸은 `n_trials_basis` 에 program_epoch 병기" 검사를 추가한다 | 양성: 원장 epoch 칸 수 = 로그 shadow+live 칸 수(재도출). 위반: 로그 append 1건 누락 → red. 돌연변이: writer 가 kind 검증을 빼면 red |
| **G2 as-of 만** | ① 계약 `rf_asof_fitness(a, tau)`(= P1-03 `sa_subwindow`). ② 유기체 모듈은 essence 에 **뷰 함수 `rf_organic_view(a)`** 로만 접근한다(≤τ 성분 + 메타데이터). ③ 설계 레인 재료 = τ\* 판 | 양성: end = 원 종료일 → essence 비트 동일 · τ 이전 수익 교란 → 결정 변함. 위반: τ\* 이후 수익·전기간 essence 필드 교란 → 모든 유기체 결정·아카이브 **불변**(핵심 검사 · 밤마다 자가 실행 = K1). 정적: `rf_organic_*.R` 안의 `essence$`·`[["essence"]]` 직접 접근(뷰 함수 제외) → red. 돌연변이: 뷰 함수가 전기간 필드를 흘리면 red |
| **G3 자동 사전등록** | `rf_prereg.R`(P2-01) writer. `06_Registry/prereg/organic/<policy_id>.json` = {kind, rule sha, params, 가설, 지표((τ₀,τ\*] 예측 평가), 성공/실패, 멈춤, 예산, K_pol 순번}. 덮어쓰기 거부 | 양성: 신규 등록 → shadow 개시. 위반: 같은 id 재기록 → 거부. 돌연변이: 거부 분기 제거 → red. 사전등록 없는 정책의 shadow 개시 → 컨트롤러 stop |
| **G4 shadow → 리플레이 → live** | `rf_organic_replay.R`(04_Research 파일럿 `replay_engine.R` 이식 + as-of). 전이 = `axiom/replay/policy_state.R::pol_transition(env = rf_organic_env())` — **전역 `QVEST_POLICY_UNATTENDED` 기본값(0)은 건드리지 않고** 유기체만 명시 env 를 넘긴다 | 양성: 합성 우월 정책 → live 도달. 위반: 사전등록 없음·리플레이 패·플라시보 미통과 → shadow 잔류. 돌연변이: 게이트 항목 1개 제거 → red |
| **G5 킬스위치** | `rf_organic_guard.R::rf_organic_trip()` · config `organic.enabled` · 층별 `mode ∈ {off, shadow, live}` · env `QVEST_RF_ORGANIC=off` | 발화 조건 K1~K10(아래) 각각에 주입 픽스처 1개. 발화 후 러너 결정 = π₀ **비트 동일**(최근 tick 결정 기록 재생) |
| **G6 롤백** | 패치 `versions[]` + `live_version` 포인터 · 정책 판 · 카탈로그 `status_history` 역기록 | 양성: 롤백 후 `rf_program_effective()` = 직전 판 identical. 고정된 entry 는 자기 판 유지. 돌연변이: 포인터만 바꾸고 status 를 되돌리지 않으면 red |
| **G7 결정 레지스터 자동 기록** | `reinforce_ledger.R::dr_record_machine(id, kind, authority="REINFORCE-ORGANIC-AUTONOMY", undo, evidence)`. owner="machine", status="enacted". 허용 kind 목록과 authority 가 resolved 결정인지 대조한다. `dr_resolve`(owner=dohoon 전용)는 쓰지 않는다. 세부 결정은 `rf_record_decision` 에 새 kind 로 기록 | 양성: live 전이 1건 → 레지스터 1행 + decisions 1행. 위반: authority 가 open/부재 → 거부. 돌연변이: 대조 제거 → red |
| **G8 주간 보고** | `rf_organic_weekly.R` → `tg_agent_brief()`, 표제 `[1계층·강화] 유기체 주간 보고 — …`(qvest-telegram §5.6b) | 드라이런 본문 ≤4096자(기억 카드 09-05) · 발신기 formals 대조 · `ok=FALSE` 도 실패로 읽는다 |

### 3.2 킬스위치 발화 조건

수치는 전부 `organic.killswitch.*` config 에 둔다.

| 코드 | 조건 | 조치 |
|---|---|---|
| K1 | G2 교란 자가검사 실패(밤마다) | 전 층 off |
| K2 | 헌법 대조 실패: 유효 fixed_axes ≠ 기저, 기저 sha ≠ 고정값, 패치 스키마 위반 | 전 층 off |
| K3 | 시행 로그 쓰기 실패 또는 재도출 불일치 | 전 층 off(fail-closed) |
| K4 | 최상위 계보의 엘리트 점유 > c_mono 가 2주 연속 | 예산 층 → π₀ 몫 |
| K5 | 아카이브 엔트로피 주간 하락 > ΔH | 공간 층 → shadow |
| K6 | 층 0(신규 논문) 7일 칸 몫 < 하한 | 예산 층 off |
| K7 | live 정책이 최신 m 트리 중 k 패(`pol_gate_demote`) | 그 정책을 강등 |
| K8 | `organic_shadow` 칸이 승자·바닥·carry·승격 결정 기록에 등장(결정 로그 감사) | 전 층 off |
| K9 | 유기체 live 아래 A 후보 발생 | 트립 아님. 표식만 달고 기존 A 관문을 그대로 탄다 |
| K10 | live 변경 뒤 러너 tick 실패율 > 기준 + x | 해당 변경 롤백 |

**롤백 단위**
- 정책 판(policy_id@sha), 패치 판, 카탈로그 status 1건이 각각 롤백 단위다.
- entry 는 개설 때 고정한 판으로 끝까지 간다. 롤백은 새 entry 에만 효력이 있다.
- 킬스위치는 부분 복원을 하지 않는다. π₀ 로 전면 복귀한다.

### 3.3 shadow → live 승격식(정책 π 대 π₀)

```
live(π)  ⇔  G_shadow(π) ∧ G_live(π)

G_shadow (pol_gate_shadow · 문턱 = policy_state.R::pol_cfg 기존 기본값, 새 숫자 아님):
  heldout_win ≥ 0.60      # 계보 군집 hold-out 트리 중 Gain(π) > Gain(π0) 비율
  null_pct   ≥ 0.95       # 같은 예산 무작위 정책 분포 대비 백분위
  discovery_drop ≤ 0.10   # (τ0,τ*]-엘리트 중 π 가 측정하지 않았을 몫 (예산·구조 정책)
  unreachable ≤ 0.20      # π 가 원했으나 기록에 없는 칸의 비율
  best_loss ≤ 0.05        # 프로그램 최고 d_A^(τ0,τ*] 손실
  peek_blocked ∧ static_clean ∧ negative_control_ok

  Gain_tree(π) = d_A^{(τ0, τ*]}( π 가 ≤τ0 적합도로 고른 최종 바닥 )
  ★(τ0, τ*] 밖(특히 τ* 이후)은 어떤 항에도 들어가지 않는다 — 두 단 as-of

G_live (pol_gate_live):
  shadow_weeks ≥ 4 ∧ informative_disagreements ≥ 3 ∧ newest_replay_win ∧ placebo_ok
  ∧ live_same_kind < 1 ∧ live_total < 2 ∧ activations_this_week < 1
  ∧ LCB90_cluster_bootstrap( mean(Gain(π) − Gain(π0)) ) > 0   # 뿌리 계보 48개 군집
  ∧ unattended = config organic.live_auto ∧ REINFORCE-ORGANIC-AUTONOMY resolved
     ∧ (정책이 성과 소비형이면 ORGANIC-DE-INTERP resolved)
```

- 리플레이 한계: 과거 트리의 칸 자체는 전기간 정보로 설계됐다(LLM 재료·전기간 argmax). 그래서 π 와 π₀ 의 **상대 비교**만 의미가 있다. 이 점을 보고서에 명기한다.
- 판정 가능 트리: 종료 entry 41 + 계보 군집 48. 검정력은 사전등록 때 `required_effect_size.R` 로 계산해 기록한다.

### 3.4 주간 보고 내용(`[1계층·강화] 유기체 주간 보고`)

1. 상태: 층별 mode, live 정책(id·판·개시일), 킬스위치 상태와 되돌리기 명령.
2. 이번 주 변경: arm 입장·probation·휴면·부활·퇴역 목록(사유 코드), 블록 등급 변화, 층 몫, 구조 변이.
3. 시행 회계: 이번 주 측정 칸(live/shadow), 누적 N_prog, 평가한 정책 수 K_pol.
4. 내부 목표(≤τ\*): QD 점수(상한 적용 · §7), 아카이브 채움 수 · 엔트로피 · 계보 점유 상위 3.
5. **외부 성적표(사람 전용 · 기계에 되먹이지 않음)**: 유기체 live 아래 태어난 계보의 전기간 d_A · τ\* 이후 구간 d_A · IS−OOS 격차 추세 · A 후보 수와 보류 코드.
6. 가드 발화 기록(K1~K10) · 다음 주 shadow 예정 · 사전등록 신규.
7. 기억 카드 쓰기 없음. 무인 레인은 `memory_inbox/` 를 거친다(M1).

---

## 4. 시행 회계 — 적응 결정 자체를 N 에 넣는 방식

**단위**
- 측정된 칸 1개(live 또는 shadow)가 시행 1이다.
- 성과를 보지 않는 정적 관문의 기각(스키마·PIT·고정 축)은 시행 0이다. 로그에는 남긴다.
- **성과로 측정 전에 후보를 떨어뜨리는 선별은 유기체에 존재하지 않는다**(2.3 (iii) 경계). 모든 대안은 측정 칸이 된다.

**가족**

| 가족 | 정의 | 쓰임 |
|---|---|---|
| N_lineage | 현행(D-A raw · `rf_selection_accounting` · 계보 선행 측정 + 배치) | DSR 게이트(D-A 유지) |
| N_prog(t) | 유기체 epoch 개시 이후 t 까지 전 계보 + shadow 측정 칸 | A 서류 병기 · PBO 가족 |
| K_pol | 리플레이로 평가한 정책 수(사전등록 순번) | 메타 가족. 서류에 "선택 규칙 자체가 K_pol 개 중 선택됨"으로 표기 |

**DSR·PBO 가 더 엄격해지는 효과**
- N 이 계보 약 50에서 프로그램 약 10³ 이 되면, 귀무 최대 SR 기댓값의 분위 인자는 대략 √(2 ln N) 비로 **약 1.3배** 커진다(Bailey & López de Prado 2014).
- 다만 플랜 기록상 최고 칸은 N=1083 에서도 DSR 0.86 이라 **DSR 은 구속하지 않는다.** 실질적으로 구속할 것은 가족 단위 **CSCV-PBO**(Bailey et al. 2017)와 가족 조정 Calmar CI 다(P1-03).
- 게이트 N 의 범위 확대는 도훈 안건(2.5 부속 (c))이다.

**예산과 A 후보 서류(P1-03/04)의 분리 — 한 방향 방화벽**
- 유기체의 입력: F_τ\*(≤τ\*) · 기술자 · 통제칸 σ̂ · 시행 로그뿐이다.
- 서류의 입력: 전기간 essence · 시행 로그(N) · 부트스트랩 · 절단판.
- **서류 산출물은 유기체 입력이 될 수 없다.** 정적 검사: `rf_organic_*.R` 가 `selection_accounting.R`·`selection_dossier.json` 을 source 하거나 읽으면 red. 섭동 검사: 서류 값을 바꿔도 유기체 결정이 불변이어야 한다.
- 그러므로 예산은 "서류 수치를 좋게 만드는 쪽"으로 흐를 수 없다. 기계는 서류를 보지 못한다.

---

## 5. 헌법 경계 — 기계가 바꾸지 못하는 것을 코드로 봉쇄

**쓰기 경로 허용 목록**(나머지 쓰기 0)
1. `06_Registry/rf_organic_state.json`
2. `06_Registry/reinforce_program_patch.json`
3. 카탈로그 status — 기존 writer 경유만(`.wc_ledger_set_status` · overlay status writer 신설 · factor lifecycle writer)
4. `rf_trial_log.jsonl` · `rf_decisions.jsonl` · `decision_register.json`(`dr_record_machine` 만)
5. `06_Registry/prereg/organic/`

**봉쇄 장치**

| 대상 | 장치 | 양방향 검사 |
|---|---|---|
| 고정 축(INV-7 + fixed_axes 전체) | 기계는 `reinforce_program.json` 을 쓰지 않는다(정적 검사: `rf_organic_*.R`·컨트롤러에서 그 경로의 쓰기 호출 0). 유기체 epoch 개시 때 기저 sha 를 고정하고, 불일치하면 K2. `rf_program_effective()` 가 `identical(eff$fixed_axes, base$fixed_axes)` 를 단언한다 | 위반 주입: 패치에 `fixed_axes.n_max=30` → 스키마 거부. 기저 파일 1바이트 변경 → K2 트립. 돌연변이: 단언 제거 → red |
| 패치 스키마 | `06_Registry/organic_patch_schema.json` = **허용 키 목록**(`blocks[].n_live`·`blocks[].enabled`·`standing_controls[]`·`instantiated_templates[]`). 그 밖의 키는 거부(deny-by-default) | 양성: 허용 변이 → 유효 격자 변화. 위반: `graduation`·`execution`·`blocks[].rule` 주입 → 거부 |
| 등급 문턱 | 유기체는 `.rfl_thresholds`(tier_graduation)를 읽기만 한다. `constraint_defaults.json`·`a_eligibility_gate.json` 쓰기 경로 0 | 정적 + 주입(패치에 `tier_graduation`) → 거부 |
| PIT 격리 | 카탈로그 status writer 가 `suspended`(C11)·`pit_quarantine` 항목·사람이 붙인 `tombstoned`·`retired` 에서 active 로 가는 전이를 거부한다. 허용 전이표 = {active↔dormant, proposed→quarantine→probation→active, dormant→probation(부활), dormant→retired} | 위반 주입: pg2_risk_overlay_v1 부활 시도 → 거부. 돌연변이: 전이표 우회 → red |
| arm 정의 | 기계는 arm 코드·파라미터를 편집하지 않는다. 새 arm 은 기존 생성 레인 + 입장 관문으로만 들어온다 | 정적: 카탈로그 `params`·`code` 필드 쓰기 0 |
| BOOK | 유기체 코드에서 `book_registry.R` source·`06_Registry/book/` 쓰기 0. A 는 기존 관문 → judge_request → 도훈 경로만 탄다 | 정적 + `book_write_guard.sh`(기존 훅) |
| 프로덕션 | `05_Production/` 경로 문자열 0 | 정적 |
| LLM 권한 | 유기체는 새 LLM 진입 함수를 만들지 않는다. 생성은 기존 `rf_llm_agent_run` 단일 진입(M1 AutoMem 차단 포함). 설계 레인 env = `QVEST_DESIGN_LANE=1`(M2 성과 열람 차단) | 기존 M1/M2 검사 재사용 |

모든 정적 검사는 **소비자를 parse 해서 formals·호출과 대조**한다(기억 카드 "서명은 계약이 아니다"). grep 한 줄 검사만으로 방어선에 올리지 않는다.

---

## 6. 레버 감사 우선순위 · 플랜 항목과의 관계

| 레버 감사 # | 관계 | 설명 |
|---|---|---|
| 1 tilt_attribution | **선행 조건** | δ1·δ2 기술자의 원천이다. P2-02 없이는 O2 가 서지 않는다 |
| 2 쓰이지 않는 예산 회수 | **흡수** | 층 ① B-3·B-4 + 층 ② S-2 가 이것을 as-of 규칙으로 구현한다. 첫 live 후보다 |
| 3 통제칸 | **선행 조건 + 흡수** | σ̂ 의 원천이다. 구조 층 M3 통제 템플릿으로 상주시킨다(P1-06 구현) |
| 4 PR-L2 | **독립 · 호스팅** | prereg 레인(ALPS 밖, 최우선)으로 돈다. 유기체는 사전등록 arms·예산을 건드리지 않는다. confirmed 가 되면 M4 템플릿이 된다 |
| 5 PR-L1 cap_core | **독립 · 호스팅** | 같다. confirmed 전 상주 배포는 금지(플랜) |
| 6 D-F soft | **흡수** | B-6 승격 soft 예산 + 선택 잡음 띠 |
| 7 선택 가치 함수 | **흡수·대체** | P1-05 `rf_select_value` = 층 ③(π₀ 는 격자 선언을 실제로 읽음 · π_τ = as-of) |
| 8 설계 레인 학습 고리 | **부분** | 설계 출처별 엘리트 삽입률을 예산에 반영한다. expect 채점(P3-03)은 여전히 별도 전제다 |
| 9 크래시 위험 선별 | **후순위 템플릿 후보** | L2 판정 뒤 사람이 구현하면 M4 로 올린다 |

**플랜 항목과의 관계**
- **P0-14**: **최우선 선행.** 관문 시점의 계보 기반 표식 승계를 운영 함수로 새로 만든다(C-3). 유기체 MC 가 같은 함수를 쓴다. 러너 재개 전 필수라는 판정은 그대로다.
- **P1-01** d_A: 선행 조건(basis='organic' = ≤τ\* 추가).
- **P1-02** 시행 로그: 선행 조건(G1 공유 저장소).
- **P1-03** `sa_subwindow`: 선행 조건(= F_τ).
- **P1-05**: 층 ③ 으로 대체한다.
- **P1-06**: 흡수(M3).
- **P1-07**: 유기체 층에 한해 "live 는 도훈 confirm" 조항을 결정 REINFORCE-ORGANIC-AUTONOMY 로 대체한다. **H1 지표("IS-only 평가 OOS 활성 IR")는 폐기를 권고**한다. OOS(τ\* 이후)로 정책을 고르면 메타 누출이다 → (τ₀, τ\*] 중첩 평가로 교체한다. 결정 안건 차단 항목이다.
- **P1-08**: 흡수(ALPS 레인 + FIFO + priority 필드 = shadow entry 의 전제).
- **P1-09**: 설계 재료 design basis 를 **τ\* 판**으로 만든다(as-of 전제).
- **P2-01** `rf_prereg.R`: 선행 조건(G3).
- **P3-01** 레버 장부: 유기체 arm 통계 = 레버 장부에 τ 인자를 추가한 것이다(PE-5 수용 게이트 적용). 저장소를 둘로 만들지 않는다.
- **P3-03**: 설계 출처 신용의 전제.

**폐기·수정하는 플랜 조항**
1. P1-07 "live 는 도훈 confirm 후" — 유기체 층 한정으로 대체(결정 REINFORCE-ORGANIC-AUTONOMY).
2. P1-07 H1 "OOS 활성 IR" — (τ₀, τ\*] 중첩 평가로 교체(안건 차단).
3. P3 "보류(도훈 재승인 후): policy_state 자동 live" — 유기체 층 한정으로 해제. π_lever(Thompson)는 이 설계가 쓰지 않는다.
4. `rf_budget_want = max(auto, manual)` 래칫 — policy 인자가 있을 때 대체.
5. 유지하는 것: 플랜 "하지 말 것" 1(순서 최적화·B5 확대 금지)과 5(DSR·LCB 하드 규칙 금지)는 유기체의 **제약**으로 그대로 둔다.

---

## 7. 메타 목표 — "유기체가 나아지고 있는가" · Goodhart 방지 · 실패 모드

**내부 목표(기계가 최적화 · ≤τ\*)**
- `J_int = QD-score = Σ_n min(1, max_{e∈E_n} d_A^τ*(e))`(Pugh et al. 2016 의 QD 점수)다.
- **틈새마다 d_A 를 1에서 자른다.** 문턱을 넘은 뒤의 in-sample 초과분에는 보상이 없다. 이것이 **목표 축에 건 상한**이다(기억 카드 "상한은 자원 축이 아니라 목표 축에").
- 기계가 할 일은 더 많은 틈새를 문턱 가까이 채우는 것이지, 한 틈새를 IS 에서 더 깊게 파는 것이 아니다.

**외부 성적표(사람 전용 · 되먹임 금지)**
- 유기체 live 아래 태어난 계보의 **τ\* 이후 구간 d_A** 와 전기간 d_A.
- IS(≤τ\*) − OOS(>τ\*) 격차의 추세.
- 관문 통과 A 후보 수.
- 기계는 이 값을 읽지 않는다(정적 검사 + G2 섭동). 킬스위치도 이것을 읽지 않는다. 외부 성적표로 트립하면 살아남는 정책이 τ\* 이후 데이터로 선택되기 때문이다.
- J_int 는 오르는데 외부 성적표가 내려가면 **사람이** 판단한다(메타 과적합 경보).

**실패 모드 10개와 대응**

| # | 실패 모드 | 대응 |
|---|---|---|
| F1 | ≤τ\* 창 적응 재사용으로 인한 메타 과적합 | 사다리 띠(잡음 아래 개선 무시) · 두 단 as-of(τ₀) · 주당 정책 활성 ≤1 · K_pol 회계 · 외부 성적표 사람 감시 |
| F2 | 단일 계보 쏠림(22632 46% 재현) | ALPS 층 · 계보 점유 상한 · 적합도 공유 · K4 |
| F3 | 기술자·틈새 경계를 결과에 맞춰 조정 | epoch 개시 때 사전등록 고정 · 변경 = 새 epoch + 새 사전등록 |
| F4 | 문맥 의존 arm 을 성급히 퇴출(한 바닥에서만 해로운 arm) | 계보 수 ≥ m_min · 복수 바닥 · 휴면(삭제 아님) · 부활 트리거 4종 |
| F5 | 신규 논문 기아(착취 편중) | 층 0 하한(D-G) · K6 |
| F6 | 조용한 폴백(0칸 → 격자 폴백 L389 · F_τ 캐시 부재 → π₀) | 명시적 건너뛰기 · `asof_unmeasured` 제외 로그 · 폴백 발생 시 jlog + 주간 보고 집계 |
| F7 | 발화하지 않는 가드(양성 대조 부재) | 가드 8종 × {양성 · 위반 · 돌연변이} · K1 밤마다 자가 주입(격리 QM_ROOT) |
| F8 | shadow 칸이 승자·바닥·carry 로 누출 | `rf_candidate_facts` 단일 술어 · K8 결정 로그 감사 |
| F9 | 헌법 표류(패치·기저 파일 경유) | 허용 키 스키마 · 기저 sha 고정 · fixed_axes identical 단언 · K2 |
| F10 | 오염 승계(C1 표식이 새 칸에 안 붙음 — rf_runner_gates.R:552 구멍) | P0-14 선행 · MC 가 계보 기반 표식 사용 |

덧붙이는 위험 두 가지.
- 샌드박스 R 이 `~/.Renviron QM_ROOT` 에 덮여 운영을 오염시킬 수 있다(기억 카드 09-25) → 모든 검사는 빈 `R_ENVIRON_USER` + 루트 리터럴 + 전후 스냅샷으로 돌린다.
- LLM 사전학습 기억은 C1~C15 밖이다 → `design_source` 로 나눠 보고한다.

---

## 8. 구현 단계 O0~O4

| 단계 | 산출 | 검사 | 완료 판정 | 규모(세션) |
|---|---|---|---|---|
| **O0 선행·결정** | P0-14(계보 표식 승계 운영 함수) · P1-02 시행 로그 · P1-01 d_A(basis organic) · P1-03 `sa_subwindow` = `rf_asof_fitness` · P2-01 사전등록 writer · P2-02 tilt_attribution(δ1·δ2) · P1-06 통제 템플릿(σ̂) · 결정 ORGANIC-DE-INTERP | 각 항목의 플랜 검사 + **F_τ 교란 검사**(τ 이후 교란 불변 / 이전 교란 변화 / end=원 종료일 비트 동일) · P0-14: 22632 carry 새 칸 합성 → vintage_flag 보류(구판 통과 = red) | 전부 green · 결정 기록 | 6~8(대부분 플랜 기존 항목) |
| **O1 골격(shadow 전용 · 러너 3줄)** | `rf_organic_state.R`(writer) · `rf_program_effective`·`rf_organic_cells_filter`·`rf_organic_entry_cap`(gates) · 패치 스키마 · 킬스위치·롤백·`dr_record_machine` · 새 kind 등재 · 컨트롤러 `rf_organic_tick.R`(claim 경유) · **D-G live**(b5_budget·FIFO·레인 순서 — 도훈 기결정) | 유기체 off/unpinned → 러너 결정 π₀ 비트 동일(최근 tick 결정 재생 + 단위 픽스처) · 헌법 위반 주입 7종 거부 · 롤백 identical · 러너 돌연변이(줄 삭제) red | 비트 동일 · 가드 G5~G7 양방향 green · D-G live 1주 무사고 | 3 |
| **O2 공간·아카이브(shadow)** | 기술자·틈새 고정(사전등록) · 아카이브 재구축(현행 규약·표식 제외 칸) · arm 생애 통계(P3-01 + τ) · 입장/휴면/부활 제안(shadow) · shadow entry(P1-08) · 주간 보고 | 아카이브 재도출 결정론(해시) · 합성 우월 arm → 엘리트 삽입 1위 · 순열 귀무 \|중앙Δ\|<띠(PE-5 준용) · 레버 감사 해로운 arm 목록과의 **일치율 보고만**(목표 아님) | 주간 보고 2회 · 제안 로그 채움 100% · K1 자가 주입 발화 실증 | 3 |
| **O3 리플레이·첫 성과형 live** | `rf_organic_replay.R`(두 단 as-of) · 정책 3종 사전등록(블록 연속 반감 · ALPS 몫 적응 · arm 휴면) · shadow ≥4주 | 무작위 정책 부정 대조 · 우월 합성 정책 양성 대조 · peek 검사(τ\* 이후 교란 → 리플레이 판정 불변) · 게이트 항목 제거 돌연변이 red | 정책 ≥1 판정(live 든 철회든 완료) · ORGANIC-DE-INTERP 기록 전에는 live 0 | 3 + 벽시계 4주 |
| **O4 선택·구조 live** | 러너 3줄(:683 · :766 · :774) + `rf_promote.R` 가치 함수 · π_τ shadow → live · M3/M4 템플릿(L1·L2 판정 뒤) · `selection_asof` 라벨 | π₀ 모드 비트 동일 · 격자 `select_winner_by` 사본 변경 → 결과 변화(P1-05 검사) · 기록된 chosen = 다음 블록 SPEC 승계(독립 재도출) · shadow 누출 주입 → K8 | 선택 정책 판정 · 새 계보에 `selection_asof` 라벨 100% | 3 |

**신규 config 키**(`reinforce_auto_config.json::organic.*` — 값은 여기서만 읽고 근거 문헌을 note 에 둔다)
- `enabled` · `mode.{budget,space,selection,structure}` · `live_auto` · `epoch_started_at` · `base_program_sha`
- `asof.tau_source`(= "constraint_defaults.json::diagnostics.oos_calendar_splits[1]") · `asof.tau0_ratio_source`(= "essence_score.R .ESSENCE_OOS_SPLITS v2[1]")
- `budget.{age_layers, layer_share_floor, eta, window_entries, window_weeks, n_min_by_block, promote_soft.n_floor}`
- `space.{descriptors, bins_source, k_elite, novelty_k, sigma_share, lineage_share_cap, minimal_criterion, retire.{n_min, m_min, T_ret_weeks}, reopen.{weeks, desc_distance_min}, quarantine.{floors_K, probation_entries}}`
- `selection.{scalarization, kappa_band, tie_break}`
- `structure.{templates_path, max_live_mutations_per_week, dormant_windows_K}`
- `policy.{shadow_min_weeks, informative_min, replay_lcb_level, …}` — `pol_cfg` 기존 기본값을 인용한다
- `killswitch.{c_mono, entropy_drop, l0_share_floor_7d, tick_fail_delta}`
- `report.{weekly_dow, max_chars}`

**신규 파일**
- `02_Infrastructure/reinforcement/`:
  - `rf_organic_state.R` — writer · 판 관리 · 롤백
  - `rf_organic_budget.R` — B-1~B-6
  - `rf_organic_space.R` — 아카이브 · 기술자 · 생애 · 신규성
  - `rf_organic_select.R` — π_τ(gates 의 `rf_select_value` 가 호출)
  - `rf_organic_structure.R` — 𝓜 · 템플릿
  - `rf_organic_replay.R`
  - `rf_organic_guard.R` — K1~K10 · 헌법 단언
  - `rf_organic_weekly.R`
- 계약: `02_Infrastructure/contracts/selection_accounting.R::sa_subwindow`(P1-03)를 `rf_asof_fitness` 로 쓴다.
- 컨트롤러: `02_Infrastructure/ops/rf_organic_tick.R`
- 레지스트리: `06_Registry/rf_organic_state.json` · `reinforce_program_patch.json` · `organic_patch_schema.json` · `block_templates.json` · `prereg/organic/`
- 검사(`08_Tests/reinforcement/`): `test_rf_organic_bitidentical.R` · `test_rf_organic_asof_perturb.R` · `test_rf_organic_constitution.R` · `test_rf_organic_archive.R` · `test_rf_organic_budget.R` · `test_rf_organic_replay.R` · `test_rf_organic_killswitch.R` · `test_rf_organic_rollback.R` — `run_all_hooks.sh` SUITES 에 편입한다.

**수정 파일**(국소)
- `ops/reinforce_auto_parallel.R`: O1 3줄(:138 뒤 · :436 뒤 · :448) + O4 3줄(:683 · :766 · :774).
- `reinforcement/rf_runner_gates.R`: `rf_budget_want(policy=)` · `rf_candidate_facts` 의 organic_shadow · `rf_select_value` · `rf_a_eligibility` ④ program_epoch 병기.
- `reinforcement/reinforce_ledger.R`: `RF_DECISION_KINDS` 에 organic_* 추가 · `dr_record_machine` · `rf_trial_log_append`.
- `reinforcement/rf_promote.R:59,:114-117`.
- `ops/reinforce_auto_next_paper.R:61-65,:130-323`.
- `ops/reinforce_auto_tick.sh`(:73 과 :89 사이 1줄).
- `ops/rf_weight_arms.R:40` · `ops/rf_b1_design_lib.R:175-202`.
- `08_Tests/reinforcement/test_rf_grid_contract.R:36`(M5 착수 시에만).

**하네스 규율**: 새 훅 0 · 기존 훅 13 유지 · 새 LLM 진입점 0 · 무인 레인 기억 쓰기 0(`memory_inbox/` 경유).

---

## 9. 하지 말 것

1. 유기체 적합도·선택·예산·구조·킬스위치 입력에 **τ\* 이후 데이터**(전기간 essence·전기간 d_A·OOS retention 원값·절단판·A 서류)를 넣지 않는다.
2. τ\* 를 lockbox 계열 어휘(잠근 창·보관 창)로 부르지 않는다. τ\* 는 "기계 연구자의 결정 시점"이다. 사람·등급·Judge 는 전기간을 그대로 쓴다.
3. 블록 순서 최적화를 재투입하지 않는다. G2 pass 전에 B5 칸을 늘리지 않는다. 같은 격자를 더 돌리는 것을 A 레버로 보고하지 않는다.
4. `reinforce_program.json`(fixed_axes 포함)·`constraint_defaults.json`·`a_eligibility_gate.json`·`pit_quarantine.json`·`06_Registry/book/`·`05_Production/` 에 기계 쓰기 경로를 만들지 않는다.
5. shadow 칸을 승자·바닥·carry·승격·결합 풀·A 서류 기준선에 넣지 않는다.
6. 성과(IC·상관·풀링 Δ)로 후보를 **측정 전에** 떨어뜨리는 스크린을 만들지 않는다. 모든 대안은 측정 칸이다.
7. 레버 감사의 해로운 arm 목록·블록 Δ 표(전기간)를 규칙의 교정 목표나 초기값으로 쓰지 않는다. 일치율만 보고한다.
8. 기술자·틈새 경계·τ\*·τ₀·잡음 띠를 결과를 본 뒤 바꾸지 않는다. 바꾸면 새 epoch 과 새 사전등록이다.
9. PR-L1·PR-L2 사전등록 arms·예산·멈춤 조건을 유기체가 건드리지 않는다. confirmed 전에 cap_core·B7 as-of 를 템플릿으로 인스턴스화하지 않는다.
10. 휴면·퇴역·미결을 '벽'이나 '한계'로 적립하지 않는다(AX-000). 퇴역은 삭제가 아니다. 사람이 붙인 tombstone·C11 suspended 를 기계가 되살리지 않는다.
11. 외부 성적표(τ\* 이후 d_A)를 기계 입력·킬스위치로 되먹이지 않는다(Goodhart).
12. C1/C11 표식 계보(22632 포함)를 엘리트·기준 바닥·입장 시험 바닥으로 쓰지 않는다. B08 의 사전표본 as-of 를 τ\* 로 완화하지 않는다.
13. 킬스위치 발화 시 부분 복원하지 않는다. π₀ 비트 동일로 돌아간다.
14. 새 훅 등록·cwd 이동·새 LLM 진입 함수를 만들지 않는다. Q-Lead 가 python·손계산으로 정책 성패를 판정하지 않는다(판정 = R 계약 · AX-008). 양방향 검증이 없는 가드를 방어선에 올리지 않는다.
15. ORGANIC-DE-INTERP 결정 전에 성과 소비형 결정을 live 로 올리지 않는다.

---

## 부록 A. 참고 문헌(원문 링크)

- Mouret & Clune (2015) *Illuminating search spaces by mapping elites* — https://arxiv.org/abs/1504.04909 (원문 확인)
- Blum & Hardt (2015) *The Ladder: A Reliable Leaderboard for Machine Learning Competitions* — https://arxiv.org/abs/1502.04585 (원문 확인)
- Dwork, Feldman, Hardt, Pitassi, Reingold, Roth (2015) *Generalization in Adaptive Data Analysis and Holdout Reuse* — https://arxiv.org/abs/1506.02629 (원문 확인)
- Manheim & Garrabrant (2018) *Categorizing Variants of Goodhart's Law* — https://arxiv.org/abs/1803.04585 (원문 확인)
- Li, Jamieson, DeSalvo, Rostamizadeh, Talwalkar (2018) *Hyperband* — https://arxiv.org/abs/1603.06560 (원문 확인)
- Jamieson & Talwalkar (2016) *Non-stochastic Best Arm Identification and Hyperparameter Optimization* — https://arxiv.org/abs/1502.07943 (원문 확인)
- Jaderberg et al. (2017) *Population Based Training of Neural Networks* — https://arxiv.org/abs/1711.09846 (원문 확인 · 승격 사슬 = exploit/explore 유비)
- Wang, Lehman, Clune, Stanley (2019) *POET* — https://arxiv.org/abs/1901.01753 (원문 확인)
- Lehman & Stanley (2011) *Abandoning Objectives: Evolution Through the Search for Novelty Alone* — https://doi.org/10.1162/EVCO_a_00025
- Pugh, Soros, Stanley (2016) *Quality Diversity: A New Frontier for Evolutionary Computation* — https://doi.org/10.3389/frobt.2016.00040
- Hornby (2006) *ALPS: The Age-Layered Population Structure* — https://doi.org/10.1145/1143997.1144142
- Brant & Stanley (2017) *Minimal Criterion Coevolution* — https://doi.org/10.1145/3071178.3071186
- Sareni & Krähenbühl (1998) *Fitness Sharing and Niching Methods Revisited* — https://doi.org/10.1109/4235.735432
- Deb, Pratap, Agarwal, Meyarivan (2002) *NSGA-II* — https://doi.org/10.1109/4235.996017
- Bailey & López de Prado (2014) *The Deflated Sharpe Ratio* — https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2460551
- Bailey, Borwein, López de Prado, Zhu (2017) *The Probability of Backtest Overfitting* — https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2326253
- Politis & White (2004) *Automatic Block-Length Selection for the Dependent Bootstrap* — https://doi.org/10.1081/ETC-120028836
- Asness, Frazzini, Israel, Moskowitz, Pedersen (2018) *Size Matters, If You Control Your Junk* — https://doi.org/10.1016/j.jfineco.2018.02.001 (δ1 기술자의 문헌 사전)
- 확인 범위: arXiv 8건은 이번 세션에 원문 페이지로 제목·저자를 대조했다. DOI·SSRN 9건은 서지 정보를 기억에 의존했다(SSRN 은 403 으로 대조 불가) — 착수 전 대조 필요.

## 부록 B. 이 설계에서 쓴 실측(읽기 전용 재집계)

- 원장 L1: entry 64(exhausted 41 · parked 21 · active 1 · skipped 1) · attempt 1,311 · 블록 {B1 337, B2 256, B5 247, B3 206, B4 152, B6 49, B7 25, 미상 39} · 등급 {C 929, B 225, F 86, NA 기타}.
- 표식: `fdb_202608_v1` 881 · `selection_basis_full_sample_ic_inherited` 501 · `selection_basis_full_sample_ic` 60 · `pit_c11` 35 · `treatment_misspecified` 25.
- 뿌리 48 · 깊이 {0:47, 1:9, 2:4, 3:3, 4:1} · 22632: B 104/225 · PT≥2.95 39/39.
- `rf_decisions.jsonl` 3행 · `overlay_arm_ledger.jsonl` 26행 · 카탈로그 overlay 33(31/1/1) · weight 52(39/5/5/3) · factor 370(366/2/2).
- 골든 close_t1 낙폭: 2018-01-30→2020-03-23 −0.5798 · 2007-11-07→2008-10-27 −0.5631.
- config: `enabled=false` · `daily_cap 200` · `parallel_cells 5` · `promote_extend_min_delta 0.01` · `b5_budget` 키 없음 · 격자 `fixed_axes` 에 `base_weight 0.5` 동거.
