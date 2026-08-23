# alpha_search_queue 소비자 v3 (lean) — 팩터 → alpha-search 가동

하는 일은 **구현 → 실행 → 보고** 셋뿐이다. 판정 게이트와 원장 append 는 **래퍼**
(`alpha_search_queue_run.sh`)가 런 종료 후 산출물 전수에 기계로 적용한다 — verdict 를
손으로 모으지 않는다. v8 원본 = `_archive_v8_prompts/`.

주입 변수: `TODAY`(YYYYMMDD), `MAX_ALPHA`(이번 런 상한). 루트 = cwd.

## 1. 큐 상위 N편
```
.venv_qvest_ml/Scripts/python.exe 02_Infrastructure/ops/research_pool_predicates.py \
    alpha-pending stage_artifacts/paper_recharge --list ${MAX_ALPHA}
```
첫 줄 = 미소비 건수, 이후 각 줄 = `paper_id | title | factor_hint`.
**이 술어가 정본** — 큐 파일을 직접 훑어 재계산하지 말 것. 이번 런 최대 `MAX_ALPHA` 편.

## 2. 구현 — `factor_engine.R` 를 충실히 쓰거나, 못 쓰면 건너뛴다
필요하면 원문을 `mcp__jina__read_url`/arxiv MCP 로 보강해 impl_spec(신호 수식·유니버스·
리밸·PIT lag·long-only)을 정하고 `factor_engine.R` 를 쓴다.

**batch_434 가드 (2줄, 이게 전부다)**
- 실행되는 신호 = 논문이 기술한 신호. 라벨과 실행이 어긋나면 위반.
- 충실히 구현 못 하면 **합성·폴백 신호를 지어내지 말고 skip** + 사유 기록.
  (충실한 재구성 · L/S→long-leg 사상은 허용이며 가드 대상 아님.)

## 3. 실행
```
run_alpha_search(name, idea, engine_path,
                 n_holdings = <논문의 종목수>, weight_method = <논문의 비중방법론>)
```
`deep` 은 기본값 `FALSE`(경량 1패스). `n_holdings`/`weight_method` 는 **논문이 말한 값**을
넣고, 논문에 없으면 기본값을 쓰되 그 사실을 보고에 적는다.
산출은 `stage_artifacts/alpha_search/<id>/` 에 그대로 둔다(래퍼가 읽는다).

## 4. 보고
- 텔레그램 `tg_agent_brief(agent="AlphaSearch", title="alpha-search 큐 가동", relaxed=TRUE,`
  `force=TRUE, sections=...)` — 실행 N편 + 전략명/grade/score + skip 사유.
- stdout: 큐 N / 실행 편수 / 각 grade / skip 사유 / 산출 디렉터리. 날조·과장 금지.
- **Grade A 는 PG 편입 *권고* 한 줄만** — `book_state` 쓰기는 수동, governor 정지.

## 절대 가드
- **PIT C1~C15**. 실측 백테만(`run_alpha_search`/`build_bt_result`/`canonical_screen_bt`).
- KR 제약: long-only, max 25종목, Σw=1, weight∈[0,0.20], KOSPI200∪KOSDAQ150, 2005~, 15bps.
  크로스마켓·대체데이터 금지.
- 자본 admit/`book_state` 쓰기 금지. `tg_agent_brief` 단일 진입점.
  인라인 멀티라인 `Rscript -e` 금지(첫 줄만 실행됨).
- **판정을 스스로 선언하지 말 것** — ADOPT/SCREEN_TIER/QUARANTINE 은 래퍼가 부르는
  `auto_alpha_gate.R` 가 결정한다(fail-closed).
