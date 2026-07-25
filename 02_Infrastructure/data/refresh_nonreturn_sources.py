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


def refresh_nps():
    if not os.path.exists(NPS_OUT):
        log("NPS: 기존 패널 부재 — 최초 전량 수집은 pull_nps_files.py로 수행할 것. skip")
        return {"source": "nps", "action": "skip_no_base"}

    have = pd.read_parquet(NPS_OUT, columns=["file_label_ym"])
    have_set = set(have.file_label_ym.unique())

    landing = urllib.request.urlopen(
        urllib.request.Request(f"{BASE_DG}/data/15083277/fileData.do", headers=UA), timeout=60
    ).read().decode("utf-8", "replace")
    pks = list(dict.fromkeys(re.findall(r"uddi:[0-9a-f\-]+(?:_\d+)?", landing)))
    hist = _post(f"{BASE_DG}/tcs/dss/selectHistAndCsvData.do",
                 {"publicDataPk": "15083277", "publicDataDetailPk": pks[0]})
    # 이력 블록에서 (uddi, 연월 타이틀) 쌍 추출
    pairs = re.findall(r"(uddi:[0-9a-f\-]+(?:_\d+)?)(.{0,400}?)(20\d\d)년\s*(\d{1,2})월", hist, re.S)
    cand = {}
    for uddi, _mid, y, m in pairs:
        cand.setdefault(f"{int(y):04d}-{int(m):02d}", uddi)
    new = sorted(ym for ym in cand if ym not in have_set)
    log(f"NPS: 이력 {len(cand)}월 / 보유 {len(have_set)}월 / 신규 {len(new)}월")
    if not new:
        return {"source": "nps", "action": "noop", "months_have": len(have_set)}

    xw = pd.read_parquet(os.path.join(SCAF, "firm_crosswalk.parquet"))
    prefixes = set(xw["bizr_no"].astype(str).str.strip().str[:6])
    frames, added = [pd.read_parquet(NPS_OUT)], []
    for ym in new:
        dst = os.path.join(TMP, f"_ref_{ym}.csv")
        try:
            html = _post(f"{BASE_DG}/tcs/dss/selectDpkDetailInfo.do",
                         {"publicDataPk": "15083277", "publicDataDetailPk": cand[ym]})
            m = re.search(r"fn_fileDataDown\(\s*'15083277'\s*,\s*'[^']*'\s*,\s*'(FILE_\d+)'\s*,\s*'(\d+)'", html)
            if not m:
                log(f"NPS {ym}: atchFileId 미검출 skip"); continue
            url = f"{BASE_DG}/cmm/cmm/fileDownload.do?atchFileId={m.group(1)}&fileDetailSn={m.group(2)}&insertDataPrcus=N"
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=900) as r, open(dst, "wb") as f:
                while True:
                    ch = r.read(1 << 20)
                    if not ch:
                        break
                    f.write(ch)
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
        out = pd.concat(frames, ignore_index=True)
        out = out.drop_duplicates(subset=["file_label_ym", "bizno6", "wkpl_nm"], keep="first")
        out.to_parquet(NPS_OUT, index=False)
        log(f"NPS: {len(added)}월 추가 → 총 {out.file_label_ym.nunique()}월 / {len(out)}행")
    return {"source": "nps", "action": "appended" if added else "noop", "added_months": added}


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
