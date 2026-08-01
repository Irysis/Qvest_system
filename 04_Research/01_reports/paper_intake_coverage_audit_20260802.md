# 논문 인입 라인 커버리지 감사 (2026-08-02)

**질문 (도훈, 원문)**: "신규 논문이 들어오지 않은건, 정말로 들어올만한 수준의 신규 논문이 없어서인가? 알파서칭이 탐구하지 않는 논문이 있나?"

**한 줄 답**: 둘 다 아니다 — **논문은 실재했고, 크롤러가 죽어 있었다.** 그리고 죽지 않았어도 현 질의·카테고리 설계로는 v8.3 주력 프론티어(비-return 원천)의 문헌면에 **구조적으로 도달할 수 없었다.**

| Q | 판정 |
|---|---|
| Q1 파이프라인 생사 | **(a) 크롤러 미발화** — 논문 부재 아님. MCP 탐색 프로브의 인터프리터가 Windows Store 스텁으로 해석돼 **exit 0 + 산출 0** 의 침묵 정지. 수리 후 `to_fetch 0 → 32` |
| Q2 소스 커버리지 | **arXiv q-fin 4카테고리 단독** (route 28건 전량 `source=arxiv`, 큐레이트 15링크 신규 0). 미커버 원천 다수 + 질의어가 8개 주제를 구조적으로 미도달 |
| Q3 게이트 과도성 | **과도하지 않음** — 6건 중 4건은 정당한 robustness FAIL(실측 PORT_t 음수~0.77), 1건은 **배관/데이터 결함**(정확 라벨됨), 1건은 **라우팅 누락**(screen-tier 미발급) |
| Q4 skip 11건 | **9건 명백 정당**(주식 횡단면 무관), **2건은 merit 기각 아닌 capability 기각**(뉴스감성 인프라 부재 등) |
| Q5 status-line DEGRADED | **스모크가 깨진 게 아니라 진짜 결손을 정확히 가리키고 있었다** — 리더가 `autorun=?` placeholder 출력. 스키마 드리프트 수리 후 **5/5 OK** |

---

## Q1. 파이프라인은 살아있는가 — (a) 크롤러 미발화

### 실측 로그 (내용 기준, mtime 아님)

`stage_artifacts/paper_recharge/paper_recharge_daily_*.log` 직접 열람:

```
20260727: MCP probe: status=mcp_ok       candidates=28  ... to_fetch=2   downloaded=2
20260801: MCP probe: status=read_failed  candidates=0   ... to_fetch=0   downloaded=0
20260802: MCP probe: status=read_failed  candidates=0   ... to_fetch=0   downloaded=0
```

`status=read_failed candidates=0` → 하류가 `total=15 mcp=0 to_fetch=0`. **"신규 논문 없음"과 겉보기가 완전히 같다.**

**결정적 확인**: `mcp_discovery_20260801.json` / `20260802.json` 은 **파일 자체가 존재하지 않았다**(디렉터리 전수 확인). 즉 후보 0이 아니라 **탐색이 실행되지 않았다**.

### 근본 원인 (재현 완료)

`02_Infrastructure/tools/paper_recharge_daily.R:281` (수리 전):

```r
py <- Sys.which("python3")
if (!nzchar(py)) py <- Sys.which("python")
```

실측 해석 결과:

```
Sys.which("python3") = C:\Users\99922\AppData\Local\MICROS~1\WINDOW~1\python3.exe
  → /c/Program Files/WindowsApps/Microsoft.DesktopAppInstaller_.../AppInstallerPythonRedirector.exe
```

스텁 직접 실행 실측:

```
$ python3 paper_recharge_mcp.py --out /tmp/qm_probe_stub.json
Python
exit=0
$ ls /tmp/qm_probe_stub.json → No such file or directory
```

**"Python" 한 줄 출력 + exit 0 + 산출 파일 없음.** R 쪽은 `system(cmd, ignore.stdout=TRUE, ignore.stderr=TRUE)` 로 종료코드 0(성공)을 보고, `fromJSON(out)` 만 실패해 `read_failed` 로 떨어졌다. **계측 사망이 정상 완료로 위장된 전형.**

동일 스크립트를 실 인터프리터(`$QVEST_PY`)로 실행:

```
status = mcp_ok
candidates = 34   (2026-07-30 게재분 포함 — 마지막 라우팅 07-27 이후 신규 실재)
errors = []
```

→ **논문 부재 가설은 실측으로 기각.**

### 이것은 이미 고쳐진 버그 클래스의 유일한 잔존분이었다

저장소 전수 grep 결과, live tree 에서 `QVEST_PY` 없이 bare `Sys.which("python3")` 를 쓰는 파일은 **`paper_recharge_daily.R` 단 1건**. 나머지는 전부 표준 준수:

| 파일 | 패턴 | 수리 이력 |
|---|---|---|
| `worktask/state_machine.R:255` | `Sys.getenv("QVEST_PY", ...)` | 07-03 |
| `worktask/cert_rules.R:442` | 동형 | 07-05 |
| `validation/v8_readiness_gate.R:352` | 동형 (주석: "bare python3 = Windows Store 스텁(rc 9009/49)") | 07-18 |
| `alpha_search/run_alpha_search.R:1435` | 동형 | 06-10 |
| `ops/weekly_cleaner_sweep.R:299` | 동형 | — |
| **`tools/paper_recharge_daily.R:281`** | **bare `Sys.which`** | **미적용 (본 감사에서 수리)** |

### 발화 시점의 불확실성 (명시)

정지 개시 시각은 **[2026-07-27 20:12, 2026-08-01 15:45] 구간으로만 특정 가능**하며 그 이상 좁힐 수 없다 — 07-28~07-31 4일간 **저장소 활동이 전무**했기 때문이다:

```
git log --since=2026-07-28 --until=2026-08-01  → 0 commits
20260728/29/30/31 명 산출물  → 각 0건
```

이 4일 공백은 논문 라인 고유 결함이 아니라 **머신 전체 유휴**이며, 메모리 `feedback-unattended-gap-check-limit-first`(도훈) 규약상 한도 기인 공백 = 정상 정지로 분류한다(별건, 조치 없음).

따라서 관측된 "route 6일 전" = **4일 머신 유휴 + 2일 인터프리터 결함**의 합성이다.

---

## Q2. 소스 커버리지 공백

### 현 수집원 = arXiv 단독 (실측)

`alpha_search_route_20260727.json` 실측:

```
source 분포     : {'arxiv': 28}          ← 전량 arXiv
curated_new_processed : 0  (curated_total 15)
```

큐레이트 링크 15개는 링크 헬스 체크(15 ok/0 dead)만 통과할 뿐 **신규 논문 기여 0**. 실질 단일 소스.

### 크롤 설계의 구조적 도달 한계 (config 실측)

`02_Infrastructure/docs/quant_sources.json::arxiv_queries` (수리 전):

- **카테고리 4종**: `q-fin.PM`, `q-fin.ST`, `q-fin.RM`, `q-fin.GN`
- **질의 9개** (전부 return-derived 미국 anomaly 어휘)
- 코드에 **하드 상한 `[:9]`** (`paper_recharge_mcp.py:276`) — config 에 질의를 추가해도 앞 9개만 사용되어 **설정 확장이 조용히 무시**되던 자리
- 결과측 필터 `_FINANCE_EXACT = {cs.lg, cs.ai, cs.ce, math.oc}` — **`cs.CL` 불포함**

9개 질의 어휘에 없어 **구조적으로 도달 불가**한 주제 (v8.3 주력 프론티어 포함):

| 미도달 주제 | 비고 |
|---|---|
| insider / 임원 거래 | **FQ-001~005 = v8.3 선언 주력인데 질의어에 "insider" 없음** |
| 규제공시 텍스트 (사업보고서·위험요인·MD&A) | 질의에 disclosure/filing/text 없음 + 해당 문헌 1차분류 `cs.CL` 이 필터 밖 |
| 공매도 / 대차 | FQ-003 lane |
| 공급망·기업 네트워크 | — |
| 기업이벤트 (M&A·자사주·분할) | — |
| 지배구조·소유구조 (가족/창업자 지배) | KR 지배적 형태 |
| 한국/아시아 시장 특화 | 질의에 지역어 전무 |
| 비용·수용력·crowding | 배포 제약 직결 |
| PIT/누출/평가 프로토콜 방법론 | **제1목표 직결인데 미도달** |
| LLM/NLP 금융 적용 | 질의에 관련어 전무 |

### 미커버 원천 (도구 실측 — 4주 스윕 2회 병렬 수행)

| 원천 | 현 파이프라인 | 실측 상태 |
|---|---|---|
| **SSRN** (계량 알파 최대 원천) | ❌ 미연결 | jina 경로 `Payment Required`(API 크레딧 부족) / paper-search 경로 **빈 배열 무오류 반환** = 침묵 실패. ★"검사가 잘못된 것을 잼" 계통 — 소비하면 영구히 "신규 없음" 보고 |
| **Crossref** | ❌ 미연결 | **정상 작동**. 경계 지정 필터(`from-pub-date`+`until-pub-date`) 필수. 단독으로 창내 저널 논문 ~30건 회수 (JFE·JAE·JFQA·Review of Finance·Management Science·J. Empirical Finance·J. Corporate Finance) |
| **Google Scholar** | ❌ 미연결 | 작동. SSRN 워킹페이퍼 간접 도달 = 죽은 SSRN 채널 부분 대체. ⚠ 날짜가 연 단위 placeholder |
| **OpenAlex** | ❌ 미연결 | 날짜 필터 부재 — 저수율 |
| **Semantic Scholar** | ❌ 미연결 | `year=2026` 시 전건 공백, 미지정 시 1992~2014 고전 반환 — 최신성 용도 불가 |
| **NBER / RePEc·IDEAS / CORE / BASE / DOAJ / DBLP** | ❌ 미연결 | 금융 질의에 전부 빈 결과 |
| **한국 학술지** (한국증권학회지·재무연구·APJFS) | ❌ 미연결 | Google Scholar 경유로만 일부 도달 |
| **arXiv 비-q-fin 카테고리** | ❌ 미크롤 | `q-fin.PR`·`cs.CL`·`cs.LG`·`cs.CE`·`econ.EM`·`econ.GN`·`math.OC` 등에 적용 가능 논문 다수 실재 |

### 회수한 실재 신규 논문 (2026-06-01~, 도구 실측 — 전건 tool call 회수분)

두 스윕이 합계 **50편 이상**을 회수했고, 그중 Qvest 제약(KR·long-only·top-25·15bps·PIT·비-return 우대) 적용 가능분을 선별해 **FQ-076~089 14건**으로 등재했다(§ 등재 목록). 대표 예:

- **Jeong·Eo·Kang**, "Net arbitrage trading by foreign investors and short sellers and stock returns: Evidence from the Korean stock market", *Pacific-Basin Finance Journal* — **KR 시장 직접 증거**, 외국인·공매도 flow 로 anomaly 수익을 조건화. arXiv 로는 도달 불가.
- **Yuan & Zhang**, "Risk-based peer networks and return predictability: textual analysis on 10-K filings", *J. Empirical Finance* 88:101754, **2026-08-01** — 산업분류가 아닌 **언어**로 만든 종목 연결구조.
- **Yılkı**, "Supply Chain Propagation of Textual Signals: LLM Embeddings and Cross-Sectional Return Predictability", **arXiv:2606.29290** (2026-06-28) — 카테고리 `q-fin.PR` = **구 크롤 목록 밖**. FF5 α 7.27%/yr(t=2.30), placebo·섹터중립·OOS 통과 보고.
- **Alldredge·Biggerstaff·Blank**, "Tell me you have a plan! Insider trade signals from firms undergoing corporate downsizing", *J. Corporate Finance* 99:103006 (2026-06-01) — 이벤트-조건부 insider.
- **Wu & Jiang**, "Earnings Predictability of DuPont Factors", *JRFM* 19(6):408 (2026-06-04) — ΔPM 의 빠른 평균회귀가 **무조건부 fundamental 실패의 기전 후보**.
- **Aikawa & Yoshida**, "Assessing Post-Reform Changes in Risk Disclosure Quality", **arXiv:2606.26522** (`cs.CL`, 미크롤) — 일본어 19,770 firm-years, CJK 인접시장.
- **Halperin**, "Are Three Matrices All You Need To Beat the Market?", **arXiv:2607.27461** — 카테고리는 크롤됐으나 **9질의 어휘로 도달 불가**했던 사례.

⚠ **불확실성 명시**: SSRN·Google Scholar 경유 항목 일부는 도구 메타데이터가 **연 단위**라 정확한 게재 월을 확정하지 못했다. 해당 항목은 FQ `source_refs` 에 `⚠ 정확 월 미해결`로 라벨했다.

---

## Q3. 게이트가 과도한가 — 아니다 (단 1건은 라우팅 누락)

`alpha_search_queue_done.json::records` 실측 — **6건 처리, 6건 QUARANTINE, 0 ADOPT**:

| paper_id | factor | 실패층 | 실측치 | 판별 |
|---|---|---|---|---|
| 2606.08569 | p_index_fair_downside_insurance | robustness,fidelity | PORT_t **−2.757** | **(a) 정당** |
| 2606.04576 | size_enhanced_left_side_momentum | robustness,fidelity | PORT_t **−2.813** | **(a) 정당** |
| 2607.16450 | hill_tail_index | robustness | PORT_t **0.77** ≪2.95, IC≈0, FF3/FF5/Carhart t<1 | **(a) 정당** |
| 2606.08141 | vol_adj_volume_surprise | robustness | PORT_t **−1.454**, OOS retention **−0.58**, MDD 67%, 회전 996% | **(a) 정당** |
| 2607.14174 | dart_risk_section_sentiment | **fidelity** | 미구현(`impl_not_attempted`) | **(b) 데이터 결함 — 정확 라벨** |
| 2607.19497 | spec_mass_lowfreq_60d | robustness | OOS retention **0.263**, Calmar **0.207**, MDD 61.4% | **(a) 정당하나 ★라우팅 누락** |

### 개별 판별

**정당한 robustness FAIL 4건.** `06_Registry/layer_bottleneck_map.md` v25 부기가 hill_tail_index·vol_adj_volume_surprise 2건을 독립 실측으로 교차확인한다 — hill: "꼬리위험 프리미엄 채널 KR 비성립", vol_surp: "D3 dead class(microstructure/flow) 재확증". 게이트 판정과 병목지도가 **일치**하며, 두 건 모두 `next_probe` 2개씩을 산출해 보고 완성 요건을 충족했다. HARD 문턱(PORT_t 2.95) 대비 실측이 음수~0.77이라 **문턱 조정으로 뒤집힐 사안이 아니다.**

**2607.14174 = 배관/커버리지 결함이며, 그렇게 정확히 라벨됐다.** `quarantine_reason = batch_434_data_structural_mismatch`. 사유: US 10-K Item 1A(위험요인 전용 섹션, filing 의 57%)의 KR 직접 대응물 부재 — 삼성전자 2022 사업보고서 54개 TOC 전수 확인 결과 '위험관리 및 파생거래' 2,550자가 최유사이나 파생/헤지 정책이라 위험서술 아님. 인프라는 정상 확인(DART API 키·document.xml ZIP+XML 파싱 3.9M자 성공), 차단 요인은 **KR 공시 구조 자체**. 이 건은 **robustness FAIL 로 오분류되지 않았고**, `next_probe`로 FQ-074/075 를 발급해 대체 경로(전문/MD&A)로 재라우팅했다 — **게이트가 옳게 작동한 사례**.

**★2607.19497 = 판정은 옳으나 소비 라우팅이 누락됐다.** OOS retention 0.263 은 `measurement-graduation.md §3` 의 "<0.5 무조건 FAIL(증거 무관)" 에 정확히 걸리므로 자본 tier 기각은 정당. 그러나 **신호는 실재한다** — CAGR 12.7%, FF3 α 4.28%/yr, 기각 사유가 MDD 61.4% 구조적. 이는 §3 게이트 2계층의 `screen_route = OVERLAY_CANDIDATE` 조건("MDD·turnover 등 *구조* 사유로 grade C/F여도 신호가 실재하면 후속 소비 경로 라우팅")에 해당하는데, **quarantine 만 되고 screen_route 는 발급되지 않았다**. quarantine 레코드의 `revival_conditions` 자체가 이를 명시한다: "MDD 레버로 overlay 적용 후 OVERLAY_CANDIDATE 라우팅: 신호력 존재 → 국면/DD overlay시 cap-w port_t 통과 가능성".

→ **결론: 게이트 문턱은 과도하지 않다. 과도한 것이 아니라 screen-tier 회수 배관이 quarantine 경로에 연결돼 있지 않다.** 이는 FQ-006(overlay_candidate_queue 드레인) lane 과 동일 성질의 누락.

---

## Q4. skip 11건 — 9건 명백 정당, 2건은 capability 기각

`alpha_search_route_20260727.json` 의 `route=skip` 11건 전수:

| arXiv id | 제목 | skip 사유 | 판별 |
|---|---|---|---|
| 2607.22317 | Latent Fragility and Clustered Withdrawals in Dynamic Banks Runs | 은행런 이론(mean-field game) — 횡단면 종목 신호 없음 | 정당 |
| 2607.21687 | Optimal Surplus Management for Insurers | 보험사 잉여금 최적화(HJB) | 정당 |
| 2607.18815 | Cloud failure and cyber insurance | 사이버보험 스트레스 시나리오 | 정당 |
| 2607.18623 | Dead Reckoning: Counting Your Customers | 고객 생애가치 생존분석 | 정당 |
| 2607.18616 | Prediction of bank transaction fraud using TabNet | 은행 거래 사기탐지 | 정당 |
| 2607.16281 | Hybrid Quantum Reservoir Computing | 양자 인프라 부재 | 정당 |
| 2607.06153 | From Gravity to Confinement: Wealth Redistribution | 거시/정책 이론 | 정당 |
| 2606.29793 | Fund2Persona: Financial Advisor Personas | LLM 에이전트 응용 | 정당 |
| 2607.12248 | When Directional Accuracy Lies (LoRA TimesFM) | 결과 all-negative, 구현가능 팩터 없음 | 정당 |
| **2607.20093** | Retail Trader's Ruin: Anatomy of Popular Signal Failure | "단일 종목 시계열 타이밍 룰, KR 횡단면 아님" | **경계 — 정당** |
| **2607.13968** | Measuring Sentiment News with Transformer-Based LMs | "대체데이터(뉴스 피드) 의존, **KR 인프라 미구축**으로 skip" | **★merit 아닌 capability 기각** |

**잘못 버려진 건 없다.** 단 마지막 2건의 성격을 구분해 둘 필요가 있다:

- **2607.13968** 은 논문 품질이나 적합성 때문이 아니라 **우리 쪽 인프라 부재** 때문에 버려졌다. 이는 `capacity_gated` 성격(FQ-061 FM 사례와 동형)이며, 영구 기각이 아니라 **인프라 확보 시 부활 대상**으로 남아야 한다. 현 배관은 skip 을 영구 폐기와 구분하지 않는다.
- **2607.20093** 은 "인기 신호 4종 REFUTED" 라는 **정보성 negative** 를 담고 있어, 팩터 사냥 우선순위의 외부 사후확률 보강 자료로는 가치가 있다(팩터 자체는 skip 정당).

---

## Q5. `status-line smoke: DEGRADED — broken: ResearchPool` — 스모크는 옳았다

### 진단

`research_pool_status.py` 를 단독 실행하면 **exit 0, 정상 3줄 출력**. 즉 리더가 예외로 죽는 게 아니었다.

`boot_status_smoke.py:69` 의 placeholder 단언이 잡고 있던 것:

```
AlphaQueue: testable route 2 / 소비큐 3 (autorun=?) — ...
                                          ^^^^^^^^^
```

정규식 `(?:^|[ =(/·])\?(?:$|[ )/·,])` → `=?)` 매치 → FAIL. **스모크는 고장난 게 아니라 리더의 진짜 결손을 정확히 지목하고 있었다.**

### 근본 원인 ① — 생산자 스키마 드리프트

`alpha_search_queue_*.json` 최상위 키 실측 비교:

```
20260621 : ['date','autorun','max_alpha','candidates']                       autorun=0
20260726 : ['date','autorun','max_alpha','candidates', ...]                  autorun=0
20260727 : ['date','runtime_vars','source_files','n_processed', ...]         autorun=None  ← 키 소멸
           runtime_vars = {'TODAY':'20260727','MAX_ALPHA':2}
```

07-27 산출부터 최상위 `autorun` 이 사라지고 실행 파라미터가 `runtime_vars` 로 이동했는데, 리더(`research_pool_status.py:214`)는 여전히 `aj.get("autorun")` 만 봤다. **필드명 불일치는 예외 없이 조용한 빈 값이 된다** — `factor_name`(07-26 수리) / `created_at`↔`logged_at`(907행 사건)과 **동일 계통 3회차**.

생산자가 `claude -p` 프롬프트(`alpha_search_queue_prompt.md`)로 JSON 을 쓰기 때문에 **스키마가 핀되어 있지 않은 것**이 구조적 배경이다.

### 근본 원인 ② — 집계 대상 오인 (별건으로 함께 적발)

화면은 `처리 누적 6 (ADOPT 0/QUAR 5)` 를 표시했으나 **실제 격리는 6건**. 리더가 판정을 **원장이 아니라 파생 산출**에서 셌기 때문:

```
원장 alpha_search_queue_done.json::records  → 6건 전부 QUARANTINE
auto_verify_*.json glob                     → 7파일 중 gate_decision 보유 5건
  · auto_verify_2607.14174.json              gate_decision 키 없음(L1_pit_pass 등 다른 스키마)
  · auto_verify_resid_info_vol_20260727.json gate_decision 없음(미게이트·진행 중)
  · 2607.19497 은 파일명이 paper_id 아님(auto_verify_spec_mass_lowfreq_20260727.json)
```

→ 스키마·명명 드리프트가 **조용한 누락 집계**로 나타나던 자리.

### 수리 + 위반 주입 검증

| 항목 | 수리 전 | 수리 후 |
|---|---|---|
| autorun | `autorun=?` | `autorun=2` (라우터 `autorun_candidates` 를 권위 폴백으로) |
| 격리 집계 | `QUAR 5` (오집계) | `QUAR 6` (원장 권위) + `⚠드리프트(auto_verify 0/5 vs 원장 0/6)` 표면화 |
| 스모크 | `DEGRADED - 4/5 OK, broken: ResearchPool` | **`5/5 readers OK`** |

**★차단 실효 실증 (오탐 제거가 아니라 데이터 수리임을 증명)** — 샌드박스에 사본을 두고:

```
[대조군] 온전한 사본            → [OK  ] ResearchPool          ← 정상 통과
[위반 주입] autorun 원천 3곳 제거 → [FAIL] ResearchPool
                                    placeholder '?' 잔존: ... (autorun=?) ...
```

주입 시 **원래 증상 그대로 재발화**. 경보를 끈 것이 아니라 데이터를 고친 것이 실증됐다.

---

## 수리 목록 + 실측 전후

### R1. MCP 프로브 인터프리터 해석 (`02_Infrastructure/tools/paper_recharge_daily.R`)

QVEST_PY → venv → PATH 순 해석 + **Store 스텁 명시 기각** + 실패 사유를 status 에 실어 상류 전달.

```
수리 전: MCP probe status=read_failed candidates=0  | total=15 mcp=0  to_fetch=0
수리 후: MCP probe status=mcp_ok      candidates=34 | total=49 mcp=34 to_fetch=15
```

**★1차 수리본은 죽은 검사였다 (위반 주입으로 자가적발).** 최초 판별자는 `grepl("WindowsApps", p)` 였는데 `Sys.which()` 는 **8.3 단축경로**(`...MICROS~1\WINDOW~1\python3.exe`)를 돌려주므로 **한 건도 못 잡는다**. 드라이런이 통과한 것은 QVEST_PY 가 먼저 해석돼 판별자가 **애초에 실행되지 않았기** 때문이었다 — 통과를 성공으로 읽었다면 그대로 출고됐을 자리. `normalizePath()` 로 긴 이름 복원 후 판정하도록 수리.

### R2. 스테일 산출물 읽기 (동 파일, 잠재 결함 — 본 감사에서 신규 발견)

같은 날 앞선 실행이 남긴 discovery 파일이 있으면, 이번 python 이 죽어도 `fromJSON(out)` 이 **직전 파일을 읽어 `mcp_ok` 를 반환**한다. 실행 전후 mtime 대조로 강등하도록 수리.

```
[위반 주입] 실인터프리터 실패(.py 실행 불가 실행파일) + 기존 파일 잔존
수리 후 실측: status=stale_not_rewritten(py=Rscript.exe,exit=1) candidates=0   ✅
              (파일 mtime 미갱신 확인: YES — 1785606135 → 1785606135)
수리 전 거동: 미측정 (코드 경로상 fromJSON(out) 이 잔존 파일을 읽어 mcp_ok 를
              반환하는 구조 — 수리 전 상태로 되돌려 측정하지는 않았다)
```

⚠ **주입 방법 주의 (2회 무효 주입 후 발견)**: `~/.Renviron` 이 `QVEST_PY` 를 핀하고 있어 셸에서 `QVEST_PY=... Rscript` 로 주입해도 **R 시작 시 덮어써진다**. 유효 주입에는 `R_ENVIRON_USER=/dev/null` 동반이 필수. 앞선 2회 주입은 이 때문에 조용히 no-op 였고, 그대로 믿었다면 "검증했다"는 거짓 결론이 됐다.

### R3. 수집 커버리지 (`02_Infrastructure/docs/quant_sources.json` + `paper_recharge_mcp.py`)

| 항목 | 전 | 후 |
|---|---|---|
| 카테고리 | q-fin 4종 | **q-fin 전 9계열** (PR/TR/CP/MF/EC 추가) |
| 질의 | 9개 (코드 하드상한 `[:9]`) | **24개**, 상한을 config `max_queries`(기본 40)로 이관 |
| 결과측 허용 | `{cs.lg, cs.ai, cs.ce, math.oc}` | **`cs.cl` 추가** (공시텍스트 문헌 1차분류) |

신규 질의 15개 = insider / 공시텍스트 / 위험요인 언어 / 공매도·대차 / 공급망 / 컨퍼런스콜 / 기관·개인 flow / 기업이벤트 / 애널리스트 텍스트 / LLM 공시 / **한국 KOSPI·KOSDAQ** / 신흥 아시아 / 비용·수용력·crowding / long-only 집중 포트 / **PIT·look-ahead·누출 평가**.

```
최종 실측: MCP probe status=mcp_ok candidates=38 | total=53 mcp=38 to_fetch=32
전체 전후:  to_fetch 0 → 32
```

**★확장안 2건을 실측으로 기각했다 (정밀도 양방향 검증).** 커버리지만 재고 정밀도를 안 재면 같은 실패를 반복하므로 후보 목록을 육안 확인했다:

- **1안 `cs.LG/cs.CL/cs.AI` 를 검색축에 추가** → 후보 75건, 상위가 *Seiberg Dualities(hep-th) / 휴머노이드 로보틱스 / Vision Transformer 양자화 / 종양학 / LEO 위성 측위* — **금융 관련 사실상 소멸. 기각.**
- **2안 `econ.*/stat.*` 추가** → 후보 61건, 상위가 *테니스 서브 전략 / AMOC 기후예측 / Covid 기부 / 연합학습 암호화* — **기각.**
- **채택안 q-fin 전 9계열** → 후보 38건 **전량 금융 도메인**, `cs.CL` 논문(FinSMART·FinanceHarness·AWARE-FX)은 **cross-list 로 정상 유입**.

원인은 코드 주석(`paper_recharge_mcp.py:32-35`)이 이미 관측해 둔 대로 **arxiv-mcp 의 `categories` 인자가 느슨하고 `sort_by=date` 가 질의 적합도와 무관하게 신착을 반환**하는 것 — 넓은 카테고리는 그대로 firehose 가 된다. 이 근거를 `_categories_note` 에 기록해 재확장 시도를 차단했다.

**잔여 공백 (알려진 한계)**: `cs.*` 1차분류 ∧ q-fin 미교차 논문은 여전히 미도달. 비-arXiv 원천(SSRN·Crossref·Google Scholar)도 미배선 — FQ 로 등재.

### R3-부수. 실적재 32편 (검증 중 발생한 실제 상태 변경 — 명시)

위반 주입 검증 1회가 `--dry-run` 없이 수행되어 **수리된 파이프라인이 실제로 백로그를 인입했다**. 오염이 아니라 의도된 동작이며, 인입분이 곧 그동안 놓치고 있던 논문이다.

```
06_Registry/paper_registry.json : 476 → 508 (신규 32건, 전건 status=downloaded)
.cache/arxiv_papers/            : 22 (불변 — 별도 경로)
```

인입분에 §Q2 에서 지목한 논문이 실제로 포함됐다:

- `P0490` arXiv:2607.27461 Halperin, "Are Three Matrices All You Need To Beat the Market?" → **FQ-087 근거**
- `P0505` arXiv:2607.20168 "Quantum Kernels and the Cross-Section of Stock Returns" — point-in-time 유니버스 vs full-sample 스크린 유니버스로 **정반대 결론이 제조되는 과정**을 실증(C6/DSR 교훈의 외부 독립 재현)
- `P0481` FinSMART / `P0483` FinanceHarness / `P0486` AWARE-FX — `cs.CL` 논문이 cross-list 로 정상 유입된 실증
- `P0504` "The Fundamental Structure of Risk: From Characteristics to Covariance"

⚠ 이 32편은 **아직 라우팅되지 않았다**(리더가 `Routing: PENDING` 로 표시 중) — next_probe ①.

### R4. 리더 스키마 드리프트 (`02_Infrastructure/ops/research_pool_status.py`)

§Q5 참조. 스모크 `DEGRADED 4/5 → 5/5 OK`.

### R5. 회귀 테스트 승격 (`08_Tests/ops/test_paper_intake_resolvers.R` 신규)

scratchpad 검증은 세션과 함께 죽으므로(메모리 `project-measurement-coherence-lineage-resolver` 교훈) 저장소에 승격. **원본 파일에서 판별자 본문을 직접 추출해 평가**하므로 수리가 원본에서 풀리면 여기서 잡힌다.

```
위반 주입 4 + 음성 통제 4 → RESULT: 8 PASS / 0 FAIL (exit 0)
```

---

## 등재한 프론티어 큐 (FQ-076~089, 14건)

`06_Registry/alpha_frontier_queue.json` (75 → **89 entries**). 전건 `owner="paper-intake-audit 2026-08-02"`, `status="frontier_open"`, 기존 스키마 11필드·lane vocab 준수(신규 lane 0), id 충돌 0.

**등재 전 `hypothesis_index.json`(1,083 entries) lookup 수행** — 결과가 등재 내용에 실제로 반영됐다:

| id | lane | 제목 |
|---|---|---|
| FQ-076 | text_non_return | 위험-서술 텍스트 피어 네트워크 — 산업분류 아닌 '언어'로 만든 종목 연결구조 |
| FQ-077 | text_non_return | 공급망 1-hop 텍스트 임베딩 전파 (매출처/매입처 그래프) |
| FQ-078 | non_return | insider 거래 magnitude 정규화 + symbolic 하위 tercile 제거 |
| FQ-079 | non_return | insider 공시지연 gap 가중 + 거래 시퀀스 인코딩 |
| FQ-080 | non_return | 이벤트-조건부 insider — 구조조정/손상 공시 창 안의 내부자 매수만 |
| FQ-081 | book_enhancement | DuPont 산업-상대 조건부 (ΔPM·ΔATO 를 산업내 경쟁위치로 조건화) |
| FQ-082 | non_return | 애널리스트 cross-extrapolative 잔차 |
| FQ-083 | non_return | 영문 컨퍼런스콜 개시 = 외국인 접근성 이벤트 (KR 실증 직접 이식) |
| FQ-084 | non_return | 차익거래자 활동 조건부 게이트 (외국인·공매도) |
| FQ-085 | non_return | KOSPI200 개별종목 옵션-내재 특성 횡단 랭킹 |
| FQ-086 | non_return | 가족/창업자 지배구조 유형 — 조건부(위기) 평가 |
| FQ-087 | method_frontier | 변동성-랭크는 예측 가능, 수익-랭크는 아니다 — 예측 대상 교체 |
| FQ-088 | method_frontier | decision-time 전용 macro vintage kNN 아날로그 팩터 랭킹 |
| FQ-089 | text_non_return | 공시 품질 다차원 변화 — '위험↔전략 정합도' 축 추가 |

### 중복 배제로 **탈락**시킨 후보 (lookup 이 실제로 작동한 증거)

- **개인투자자 순매수 contrarian** (Aboura, J. Investing 2026-06-20) → `DIST-QPM-005` **알파 부재 확정** 과 동일 방향. 미등재.
- **외국인 순매수 랭킹** 계열 → `STR_AS_20260613_073448` Anti-Herding **FAIL** / `STR_AS_20260613_061838` 외국인 국면 MARGINAL. FQ-084 는 flow 를 **스코어가 아니라 조건부 게이트**로 쓰는 구조만 delta 로 삼고, 이 선례를 `wall_check`·`source_refs` 에 명시.
- **HMM 2-state 국면 오버레이** → `STR_AS_20260613_062356` **FAIL** + `DIST-RAMP-006` 천장 ~2.85. FQ-088 은 잠재 국면변수를 두지 않는 vintage-아날로그 검색만 delta 로 등재.
- **부실/파산 서술 스코어** → FQ-031/035 포렌식 스택과 중복. 미등재.
- **공매도 일반** → FQ-003 lane 기존. FQ-084 에 `related` 로 연결만.
- **HRP/ERC 계열 비중** → `project-hrp-frontier-weighting-settled` NO-GO. 미등재.
- **DPL/direct portfolio 딥러닝** → 06-26 settled-negative. 미등재.

각 신규 항목의 `wall_check` 에는 07-13 확립 사실("벽은 재료가 아니라 long-only 횡단선택→cap-w 전이 자체")과의 대조를 명시했고, 데이터 미확인 항목은 `data_gate` 에 census 선행 의무를 걸어 두었다(FQ-077 거래처 링크 / FQ-082 애널리스트 매핑 / FQ-083 영문 IR 메타데이터 / FQ-085 개별주식옵션 / FQ-088 FRED·ECOS 아카이브 vintage).

---

## next_probe

1. **[즉시·기계] 라우터를 신규 적재분에 대해 1회 가동** — 리더가 이미 `Routing: PENDING — collect=2026-08-02 > route=2026-07-27` 로 표시 중. `paper_router_run.sh _FORCE=1` 로 to_fetch 32건을 라우팅해 확장 질의의 실제 수율을 측정(현재는 프로브 후보 수만 측정됐고 **라우터 통과율은 미측정**).
2. **[배관] quarantine → screen_route 연결** — Q3 의 2607.19497 처럼 "OOS/Calmar 는 FAIL 이나 신호 실재 + MDD 구조적" 건이 `OVERLAY_CANDIDATE` 로 자동 라우팅되도록 `auto_alpha_gate.R` 에 screen-tier 발급을 배선. 현재는 quarantine 이 종점이라 FQ-006 큐로 흘러가지 않는다.
3. **[커버리지] 비-arXiv 채널 1개 배선** — Crossref 경계지정 창(`from-pub-date`+`until-pub-date`)이 실측에서 유일하게 안정적으로 작동했고 저널 논문 ~30건을 단독 회수했다. SSRN 두 경로는 **침묵 실패**(빈 배열 무오류)라 그대로 소비하면 영구히 "신규 없음"을 보고하므로, 배선 시 **발화 0 감지**(양성 대조 질의로 최소 N건 회수 확인)를 동반해야 한다.
4. **[스키마]** `alpha_search_queue_prompt.md` 에 산출 JSON 필수 키를 핀하고 생산 직후 검증 — 본 건은 프롬프트 산출 스키마가 자유롭기 때문에 발생했고, 같은 계통이 3회차다(`factor_name` / `created_at`↔`logged_at` / `autorun`).
5. **[분류]** skip 을 `merit_reject` 와 `capability_gated` 로 분리 — 2607.13968(뉴스감성)처럼 인프라 부재로 버려진 건이 영구 폐기와 구분되지 않는다(FQ-061 FM capacity-gated 선례 존재).
6. **[감사]** `paper_recharge_sources.csv` 인코딩 경고 — 07-26/27 로그에서 `invalid input found on input connection` + `Error: paper_recharge_sources.csv is empty or missing` 로 **첫 호출이 halt** 했다가 재호출에서 통과한 흔적이 있다. 현재는 15/15 정상이나 간헐 실패 여지가 남아 있어 인코딩 확정 필요(본 감사 범위 밖 — 미측정).

---

## 부기: 본 감사에서 내가 밟은 함정 3건 (같은 계통)

정직 보고 — 세 건 모두 **실행 검증에서만** 걸렸고 정적 추론으로는 전부 통과했다.

1. **`_latest()` 가 `alpha_search_queue_done.json` 을 고른다고 추정** → 실측하니 `_date_of` 기반이라 정상 선택(`done`→`00000000`). 파일명 사전순으로 추론한 내 `sorted()` 가 틀렸다.
2. **스텁 판별자 `grepl("WindowsApps")`** → 8.3 단축경로 때문에 **한 건도 못 잡는 죽은 검사**. 드라이런 통과는 판별자가 실행조차 안 된 결과였다.
3. **`QVEST_PY=... Rscript` 주입이 2회 no-op** → `~/.Renviron` 이 R 시작 시 덮어쓴다. 주입이 먹었다고 믿었다면 "스테일 가드 검증 완료"가 거짓이 될 뻔했다.

공통 기전은 저장소에 이미 적립된 것과 동일하다 — **검사가 잘못된 것을 잰다**. 그리고 세 건 모두 "통과"로 보였다: 오탐 제거와 검사 사망은 겉보기가 같다.
