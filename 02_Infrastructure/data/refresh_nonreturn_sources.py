# -*- coding: utf-8 -*-
"""refresh_nonreturn_sources.py — 비-return firm/sector 원천 자동 리프레시 (FQ-064 NPS · FQ-073 관세청)

발효 2026-07-25 (도훈 지시 "지금 수집하는 데이터들 모두 자동 리프레시되도록 배선").

★설계 원칙 — 이 스크립트의 핵심은 "최신화"가 아니라 **vintage 보존**이다.
  두 원천의 개정 성질이 다르므로 리프레시 전략도 다르다:

  [NPS 국민연금 사업장 내역]  월별 파일이 각각 별도 게시 → 신규 월만 append.
     기존 월은 **절대 재다운로드·덮어쓰기하지 않는다**(first-release 보존, PIT_plan §2).
     data_ym은 파일 내부 자료생성년월이 유일 권위(파일 제목 라벨과 최대 1개월 어긋남 —
     2026-07-25 실측: 124개월 중 63개월 불일치).

  [관세청 품목별 수출입]  ★API에 vintage 파라미터가 없고 **개정이 무기한 반복**된다
     (매월 15일경 "전월까지의 자료" 전체 현행화 — PIT_plan_fq073 §1-b). 즉 오늘 pull하면
     과거 전체가 최신 개정판으로 돌아온다. 따라서 최신판으로 덮어쓰는 것은 **소급 정보
     주입(look-ahead)** 이다. 규약(§2-b2): 매 pull을 `vintage_store/customs_hs_<PULLDATE>.parquet`
     로 **append-only 스냅샷** 저장하고, latest revised는 별도 파일로만 유지하며
     `vintage_basis` 라벨을 붙인다. 스냅샷이 2개 이상 쌓이면 동일 (hs, ym) 차분으로
     개정폭을 실측한다(§2-c 전향 축적).

실행:
  <venv python> 02_Infrastructure/data/refresh_nonreturn_sources.py [--source nps|customs|all]
  멱등: 신규 월이 없거나 이번 달 스냅샷이 이미 있으면 no-op으로 종료(daily 호출 안전).
"""
import os, re, sys, json, time, argparse, datetime as dt
import urllib.parse, urllib.request, urllib.error
import xml.etree.ElementTree as ET
import pandas as pd

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SCAF = os.path.join(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold")
PULL = os.path.join(SCAF, "data_pull")
NPS_OUT = os.path.join(PULL, "nps_headcount_raw.parquet")
FQ073 = os.path.join(SCAF, "fq073")
CUST_LATEST = os.path.join(FQ073, "customs_hs_monthly.parquet")
VSTORE = os.path.join(FQ073, "vintage_store")
TMP = os.path.join(ROOT, ".cache/nps_probe")
STATUS = os.path.join(ROOT, "qepm/observability/nonreturn_refresh_status.json")

for d in (VSTORE, TMP, os.path.dirname(STATUS)):
    os.makedirs(d, exist_ok=True)


def _key():
    for line in open(os.path.join(ROOT, ".env"), encoding="utf-8"):
        if line.startswith("DATA_GO_API_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit("[refresh] DATA_GO_API_KEY 부재")


def log(msg):
    print(f"[refresh] {msg}", flush=True)


# ─────────────────────────── NPS ───────────────────────────
BASE_DG = "https://www.data.go.kr"
UA = {"User-Agent": "Mozilla/5.0", "Referer": f"{BASE_DG}/data/15083277/fileData.do"}
NPS_FIELDS = [
    ("data_ym", "DATA_CRT_YM", "자료생성년월"), ("wkpl_nm", "WKPL_NM", "사업장명"),
    ("bizno6", "BZOWR_RGST_NO", "사업자등록번호"), ("corp_type", "WKPL_STYL_DVCD", "사업장형태구분코드"),
    ("induty", "WKPL_INTP_CD", "사업장업종코드"), ("hc", "JNNGP_CNT", "가입자수"),
    ("amt", "CRRMM_NTC_AMT", "당월고지금액"), ("acq", "NW_ACQZR_CNT", "신규취득자수"),
    ("lss", "LSS_JNNGP_CNT", "상실가입자수"),
]
NPS_COLS = [f[0] for f in NPS_FIELDS]


def _post(url, data):
    body = urllib.parse.urlencode(data, encoding="utf-8").encode()
    with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=UA), timeout=90) as r:
        return r.read().decode("utf-8", "replace")


def _norm(s):
    s = re.sub(r"\(주\)|㈜|주식회사|\(유\)", "", str(s))
    return re.sub(r"[\s\-\.,]", "", s)


def _resolve_cols(path):
    """헤더 vintage 드리프트 흡수 — 영문코드 1순위, 한글명 폴백."""
    raw = list(pd.read_csv(path, encoding="cp949", nrows=0, low_memory=False).columns)
    idx = {}
    for std, eng, kor in NPS_FIELDS:
        hit = next((i for i, c in enumerate(raw) if eng in str(c)), None)
        if hit is None:
            hit = next((i for i, c in enumerate(raw) if str(c).strip().startswith(kor)), None)
        if hit is None:
            raise ValueError(f"컬럼 미해석 {std}")
        idx[std] = hit
    return idx


def _nps_download(html, dst):
    """상세 페이지의 CSV 내려받기 링크(fn_fileDataDown)로 파일을 받는다. 링크가 없으면 ValueError."""
    m = re.search(r"fn_fileDataDown\(\s*'15083277'\s*,\s*'[^']*'\s*,\s*'(FILE_\d+)'\s*,\s*'(\d+)'", html)
    if not m:
        raise ValueError("atchFileId 미검출")
    url = f"{BASE_DG}/cmm/cmm/fileDownload.do?atchFileId={m.group(1)}&fileDetailSn={m.group(2)}&insertDataPrcus=N"
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=900) as r, open(dst, "wb") as f:
        while True:
            ch = r.read(1 << 20)
            if not ch:
                break
            f.write(ch)


def _ym(v):
    """'YYYY-MM' · 'YYYYMM' · 'YYYY.MM' → 'YYYY-MM'(형식 미상 = None)."""
    m = re.match(r"^(20\d\d)[-./]?(\d{1,2})", str(v).strip())
    return f"{int(m.group(1)):04d}-{int(m.group(2)):02d}" if m else None


def _stamp(html, label):
    """상세 페이지의 '<label> YYYY-MM-DD'(사이 태그 허용 — 등록일 · 수정일) — 없으면 None."""
    m = re.search(label + r"\s*(?:<[^>]*>\s*)*(20\d\d-\d\d-\d\d)", html)
    return m.group(1) if m else None


def _nps_content_month(html, dst):
    """파일을 받아 안의 자료생성년월(DATA_CRT_YM — data_ym 의 권위값) 최빈값을 'YYYY-MM' 으로 돌려준다(2026-11-10).
    받은 파일(dst)은 지우지 않는다 — 새 달이면 호출부가 적재에 그대로 쓴다."""
    _nps_download(html, dst)
    idx = _resolve_cols(dst)
    s = pd.read_csv(dst, encoding="cp949", usecols=[idx["data_ym"]], dtype=str, nrows=200000).iloc[:, 0].dropna().str.strip()
    if not len(s):
        raise ValueError("자료생성년월 비어 있음")
    v = s.mode().iloc[0]
    ym = _ym(v)
    if not ym:
        raise ValueError(f"자료생성년월 형식 미상: {v!r}")
    return ym


def refresh_nps():
    if not os.path.exists(NPS_OUT):
        log("NPS: 기존 패널 부재 — 최초 전량 수집은 pull_nps_files.py로 수행할 것. skip")
        return {"source": "nps", "action": "skip_no_base"}

    have = pd.read_parquet(NPS_OUT, columns=["file_label_ym", "data_ym"])
    have_set = set(have.file_label_ym.unique())
    # 자료 달(파일 안 자료생성년월) 공간의 보유 달 — 라벨(제목) 달과 2015~2022-09 에 1개월 어긋났다(라벨 = 자료 − 1 · 63달 ·
    #   2026-11-10 실측 · 1:1 대응). 내용으로 해석한 달은 두 공간 모두에 없을 때만 새 달로 본다 — 포털이 라벨을 다시 바꿔도
    #   조용히 겹치거나 빠지지 않고, 두 공간이 갈리면 넣지 않고 크게 남긴다.
    have_data = {y for y in map(_ym, have.data_ym.dropna().unique()) if y}

    landing = urllib.request.urlopen(
        urllib.request.Request(f"{BASE_DG}/data/15083277/fileData.do", headers=UA), timeout=60
    ).read().decode("utf-8", "replace")
    pks = list(dict.fromkeys(re.findall(r"uddi:[0-9a-f\-]+(?:_\d+)?", landing)))
    hist = _post(f"{BASE_DG}/tcs/dss/selectHistAndCsvData.do",
                 {"publicDataPk": "15083277", "publicDataDetailPk": pks[0]})
    hist_uddi = list(dict.fromkeys(re.findall(r"uddi:[0-9a-f\-]+(?:_\d+)?", hist)))

    # ★uddi→연월 해석은 manifest 우선, 미등재분만 상세페이지 조회.
    #   (구판은 hist HTML에서 uddi와 '20NN년 N월'이 400자 내에 인접하다고 가정한 정규식을 썼는데
    #    실측 127월 중 53월만 매칭됐다 — 나머지 74월은 영영 신규로 인식되지 못하는 침묵 결손.
    #    2026-07-25 적발·수리. 신규 월은 정의상 manifest에 없으므로 상세 조회가 유일 경로다.)
    man_path = os.path.join(PULL, "nps_endpoint_manifest.json")
    known = {}
    if os.path.exists(man_path):
        for e in json.load(open(man_path, encoding="utf-8"))["endpoints"]:
            known[e["path"].split("/")[-1]] = e["data_ym"]

    # ★2026-11-10 수리 2건(신선도 CRITICAL — 2026-05 뒤 5개월 동안 새 달 0):
    #   ① 첫 화면의 현재 파일(pks)도 후보에 넣는다 — 이력 목록(hist)은 지난 판만 싣는다. 구판은 hist 만 돌아
    #      가장 최근 달이 구조적으로 빠졌다.
    #   ② 상세 페이지가 '20NN년 N월'을 더 싣지 않는다(등록일 · 수정일 · 차기 등록 예정일만 — 2026-07-23 판부터 실측).
    #      구판은 정규식이 None 이면 **기록 없이** 건너뛰었다. 이제 파일을 받아 안의 자료생성년월(DATA_CRT_YM — data_ym 의
    #      권위값)로 해석하고, (uddi · 수정일) 키로 캐시해 같은 판을 매일 다시 받지 않는다. 받은 파일은 적재에 그대로 쓴다.
    all_uddi = list(dict.fromkeys(pks + hist_uddi))
    res_path = os.path.join(TMP, "uddi_month_resolved.json")
    try:
        resolved = json.load(open(res_path, encoding="utf-8")) if os.path.exists(res_path) else {}
    except Exception as ex:
        log(f"NPS: 해석 캐시 판독 실패 {type(ex).__name__} — 새로 만든다"); resolved = {}
    cand, unresolved, probed, fetched, failed, ambiguous = {}, [], [], {}, [], []
    for u in all_uddi:
        if u in known:
            cand.setdefault(known[u], u)
        else:
            unresolved.append(u)
    details = []
    for u in unresolved:                      # manifest 미등재 = 신규 후보만 상세 조회
        try:
            details.append((u, _post(f"{BASE_DG}/tcs/dss/selectDpkDetailInfo.do",
                                     {"publicDataPk": "15083277", "publicDataDetailPk": u})))
        except Exception as ex:
            failed.append(u); log(f"NPS: 상세 조회 실패 {u[:20]} {type(ex).__name__} {str(ex)[:100]}")
    # 등록일 이른 판부터 — 같은 달 판이 둘(정정 판 등)이면 먼저 나온 판을 쓴다(first-release · 먼저 놓인 판이 이긴다).
    details.sort(key=lambda x: (_stamp(x[1], "등록일") or "9999-99-99", x[0]))
    for u, d in details:
        dst = None
        try:
            mm = re.search(r"(20\d\d)년\s*(\d{1,2})월", d)
            if mm:
                cand.setdefault(f"{int(mm.group(1)):04d}-{int(mm.group(2)):02d}", u); continue
            key = f"{u}|{_stamp(d, '수정일') or _stamp(d, '등록일') or 'nostamp'}"
            if key in resolved:
                ym = resolved[key]["data_ym"]
            else:
                dst = os.path.join(TMP, f"_probe_{re.sub(r'[^0-9a-f]', '', u)[:12]}.csv")
                ym = _nps_content_month(d, dst)
                resolved[key] = {"data_ym": ym, "resolved_by": "content:DATA_CRT_YM",
                                 "at": dt.datetime.now().isoformat(timespec="seconds")}
                probed.append(f"{u[5:13]}→{ym}")
            in_l, in_d = ym in have_set, ym in have_data
            if in_l != in_d:
                ambiguous.append(ym)
                log(f"NPS: ★{ym} 라벨 달 {'보유' if in_l else '없음'} · 자료 달 {'보유' if in_d else '없음'} — 공간 불일치 · 넣지 않는다(확인 필요)")
            if in_l or in_d or ym in cand:    # 이미 있는 달 · 같은 달의 늦은 판 — 먼저 들어온 판을 지킨다(first-release)
                if ym in cand and not (in_l or in_d):
                    log(f"NPS: {ym} 판 2개 — 등록일 이른 {cand[ym][5:13]} 유지 · {u[5:13]} 제외(first-release)")
                if dst and os.path.exists(dst):
                    os.remove(dst)
            else:
                cand[ym] = u
                if dst:
                    fetched[ym] = dst
        except Exception as ex:
            failed.append(u); log(f"NPS: uddi 해석 실패 {u[:20]} {type(ex).__name__} {str(ex)[:100]}")
            if dst and os.path.exists(dst):
                os.remove(dst)
    if probed:
        with open(res_path + ".tmp", "w", encoding="utf-8") as f:
            json.dump(resolved, f, ensure_ascii=False, indent=1)
        os.replace(res_path + ".tmp", res_path)
        log(f"NPS: 파일 내용으로 달 해석 {len(probed)}건 — {', '.join(probed)}")
    new = sorted(ym for ym in cand if ym not in have_set)
    log(f"NPS: 현재 {len(pks)} + 이력 uddi {len(hist_uddi)} → 해석 {len(cand)}월 "
        f"(manifest {len(all_uddi) - len(unresolved)} + 신규조회 {len(unresolved)} · 실패 {len(failed)}) / "
        f"보유 {len(have_set)}월 / 신규 {len(new)}월")
    diag = {"resolve_failed": len(failed), "ambiguous_months": sorted(set(ambiguous))}
    if not new:
        return {"source": "nps", "action": "noop", "months_have": len(have_set), **diag}

    xw = pd.read_parquet(os.path.join(SCAF, "firm_crosswalk.parquet"))
    prefixes = set(xw["bizr_no"].astype(str).str.strip().str[:6])
    frames, added = [pd.read_parquet(NPS_OUT)], []
    for ym in new:
        dst = fetched.get(ym) or os.path.join(TMP, f"_ref_{ym}.csv")
        try:
            if ym not in fetched:             # 내용 해석 때 이미 받은 판은 다시 받지 않는다
                html = _post(f"{BASE_DG}/tcs/dss/selectDpkDetailInfo.do",
                             {"publicDataPk": "15083277", "publicDataDetailPk": cand[ym]})
                try:
                    _nps_download(html, dst)
                except ValueError as ex:
                    log(f"NPS {ym}: {ex} skip"); continue
            idx = _resolve_cols(dst)
            df = pd.read_csv(dst, encoding="cp949", usecols=list(idx.values()), dtype=str, low_memory=False)
            df = df.iloc[:, [sorted(idx.values()).index(v) for v in idx.values()]]
            df.columns = NPS_COLS
            df["bizno6"] = df.bizno6.astype(str).str.strip().str.zfill(6)
            df = df[df.bizno6.isin(prefixes)].copy()
            for c in ("hc", "amt", "acq", "lss"):
                df[c] = pd.to_numeric(df[c], errors="coerce")
            df["file_label_ym"] = ym          # data_ym은 파일 내부값 그대로(권위) — 덮어쓰지 않음
            df["wkpl_norm"] = df.wkpl_nm.map(_norm)
            frames.append(df); added.append(ym)
            log(f"NPS {ym}: +{len(df)}행")
        except Exception as ex:
            log(f"NPS {ym}: ERR {type(ex).__name__} {str(ex)[:120]}")
        finally:
            if os.path.exists(dst):
                try: os.remove(dst)
                except Exception: pass
    if added:
        # ★2026-11-10 수리 2건(기존 이력 보존 — first-release):
        #   ① 중복 제거는 **새 달 안에서만** 한다. 구판은 붙인 뒤 전체에 drop_duplicates 를 걸어, 기존 파일의 같은 키 행
        #      8,038개(달 · 사업자 앞자리 · 사업장명이 같은 서로 다른 사업장)를 지웠다 — 덧붙이기가 지난 달을 바꿨다
        #      (새 달이 5개월 들어오지 않아 그동안 발동하지 않았을 뿐).
        #   ② 쓸 때 기존 파일 스키마로 맞춘다 — pandas 3 은 문자열 열을 large_string 으로 쓴다(구 파일 = string).
        import pyarrow as pa
        import pyarrow.parquet as pq
        old = frames[0]
        new_part = pd.concat(frames[1:], ignore_index=True).drop_duplicates(
            subset=["file_label_ym", "bizno6", "wkpl_nm"], keep="first")
        out = pd.concat([old, new_part[list(old.columns)]], ignore_index=True)
        schema = pq.read_schema(NPS_OUT)
        tbl = pa.Table.from_pandas(out[schema.names], preserve_index=False).cast(schema)
        if tbl.num_rows != len(old) + len(new_part):
            raise RuntimeError(f"NPS 덧붙이기 행 수 불일치 {tbl.num_rows} ≠ {len(old)} + {len(new_part)}")
        tmp = NPS_OUT + ".tmp"
        pq.write_table(tbl, tmp)
        os.replace(tmp, NPS_OUT)
        log(f"NPS: {len(added)}월 추가 → 총 {out.file_label_ym.nunique()}월 / {len(out)}행(기존 {len(old)} 그대로 + 새 {len(new_part)})")
    return {"source": "nps", "action": "appended" if added else "noop", "added_months": added, **diag}


# ───────────────────────── 관세청 ─────────────────────────
CUST_BASE = "https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList"
HS2 = [f"{i:02d}" for i in range(1, 98)]


def _cust_fetch(K, hs, y, end_ym):
    url = f"{CUST_BASE}?serviceKey={K}&strtYymm={y}01&endYymm={end_ym}&hsSgn={hs}"
    with urllib.request.urlopen(url, timeout=90) as r:
        return r.read().decode("utf-8", "replace")


def _cust_parse(xml):
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    out = []
    for it in root.iter("item"):
        g = lambda t: (it.findtext(t) or "").strip()
        out.append({"hs": g("hsCode"), "stat_kor": g("statKor"), "ym": g("year"),
                    "exp_usd": pd.to_numeric(g("expDlr"), errors="coerce"),
                    "imp_usd": pd.to_numeric(g("impDlr"), errors="coerce"),
                    "exp_wgt": pd.to_numeric(g("expWgt"), errors="coerce"),
                    "imp_wgt": pd.to_numeric(g("impWgt"), errors="coerce")})
    return out


def refresh_customs(lookback_years=2):
    """★개정이 무기한 반복되므로 '최신판 덮어쓰기'는 금지. 매 pull = append-only 스냅샷."""
    today = dt.date.today()
    tag = today.strftime("%Y%m%d")
    snap_path = os.path.join(VSTORE, f"customs_hs_{tag}.parquet")
    existing = sorted(f for f in os.listdir(VSTORE) if f.startswith("customs_hs_"))
    # 멱등: 같은 달 스냅샷이 이미 있으면 no-op (규약상 월 1회 축적이면 충분)
    same_month = [f for f in existing if f[len("customs_hs_"):len("customs_hs_") + 6] == today.strftime("%Y%m")]
    if same_month:
        log(f"관세청: 이번 달 스냅샷 존재({same_month[-1]}) — no-op")
        return {"source": "customs", "action": "noop", "snapshots": len(existing)}

    K = urllib.parse.quote(_key(), safe="")
    years = range(today.year - lookback_years, today.year + 1)
    rows, fail = [], []
    for hs in HS2:
        for y in years:
            end_ym = f"{y}12" if y < today.year else today.strftime("%Y%m")
            try:
                rows.extend(_cust_parse(_cust_fetch(K, hs, y, end_ym)))
            except Exception as ex:
                fail.append([hs, y, type(ex).__name__])
            time.sleep(0.03)
    if not rows:
        log(f"관세청: 수집 0행 (실패 {len(fail)}) — 스냅샷 미생성")
        return {"source": "customs", "action": "fail", "failures": len(fail)}

    df = pd.DataFrame(rows)
    df = df[df.ym.str.len() == 7]
    df["ym"] = df.ym.str.replace(".", "-", regex=False)
    df = df.drop_duplicates(subset=["hs", "ym"])
    df["pull_date"] = tag
    df["vintage_basis"] = "revised_asof_pull"     # PIT_plan_fq073 §2-b1 라벨 의무
    df.to_parquet(snap_path, index=False)
    log(f"관세청: 스냅샷 {len(df)}행 / HS {df.hs.nunique()} / {df.ym.min()}~{df.ym.max()} → {os.path.basename(snap_path)}")

    # latest revised (분석 편의용) — 스냅샷이 권위, 이 파일은 파생
    if os.path.exists(CUST_LATEST):
        base = pd.read_parquet(CUST_LATEST)
        merged = pd.concat([base[~base.set_index(["hs", "ym"]).index.isin(
            df.set_index(["hs", "ym"]).index)], df], ignore_index=True)
    else:
        merged = df
    merged.to_parquet(CUST_LATEST, index=False)

    # §2-c 전향 축적: 스냅샷 2개 이상이면 개정폭 실측
    rev = None
    snaps = sorted(f for f in os.listdir(VSTORE) if f.startswith("customs_hs_"))
    if len(snaps) >= 2:
        a = pd.read_parquet(os.path.join(VSTORE, snaps[-2]))[["hs", "ym", "exp_usd"]]
        b = df[["hs", "ym", "exp_usd"]]
        j = a.merge(b, on=["hs", "ym"], suffixes=("_prev", "_new")).dropna()
        j = j[j.exp_usd_prev != 0]
        j["rel"] = (j.exp_usd_new - j.exp_usd_prev).abs() / j.exp_usd_prev.abs()
        rev = {"pair": [snaps[-2], os.path.basename(snap_path)], "n_cells": int(len(j)),
               "changed_share": float((j.rel > 1e-9).mean()),
               "rel_p50": float(j.rel.median()), "rel_p95": float(j.rel.quantile(.95)),
               "rel_max": float(j.rel.max())}
        json.dump(rev, open(os.path.join(FQ073, "revision_magnitude.json"), "w"),
                  ensure_ascii=False, indent=2)
        log(f"관세청 개정폭: 변경셀 비율 {rev['changed_share']:.4f} / 상대차 p50 {rev['rel_p50']:.6f} p95 {rev['rel_p95']:.6f}")
    return {"source": "customs", "action": "snapshot", "rows": int(len(df)),
            "snapshots": len(snaps), "revision": rev, "failures": len(fail)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default="all", choices=["nps", "customs", "all"])
    a = ap.parse_args()
    out = {"ran_at": dt.datetime.now().isoformat(timespec="seconds"), "results": []}
    if a.source in ("nps", "all"):
        try: out["results"].append(refresh_nps())
        except Exception as ex: out["results"].append({"source": "nps", "action": "error", "err": str(ex)[:200]})
    if a.source in ("customs", "all"):
        try: out["results"].append(refresh_customs())
        except Exception as ex: out["results"].append({"source": "customs", "action": "error", "err": str(ex)[:200]})
    json.dump(out, open(STATUS, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    log(f"status → {STATUS}")


if __name__ == "__main__":
    main()
