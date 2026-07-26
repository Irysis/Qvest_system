"""FQ-073 관세청 품목별 수출입실적 pull + ★first-release vintage 스냅샷 스토어.

PIT_plan_fq073.md §2 의 코드 구현체. 산문 규약이 아니라 **실행되는 계약**이다.

핵심 규약 (§2-b):
  1. 매 pull 은 vintage_store/customs_hs_<PULLDATE>.parquet 로 **append-only 스냅샷**.
     같은 날짜 스냅샷이 이미 있으면 **덮어쓰지 않고 중단**(개정판이 원본을 삼키는 것 차단).
  2. 정본 패널 customs_hs_monthly.parquet 은 최신 스냅샷 = vintage_basis="revised_asof_pull".
  3. --build-first-release: 스냅샷 2개 이상 축적 시 (hs_code, data_ym) 별 **최초 관측 스냅샷**
     값만 모아 customs_hs_monthly_firstrelease.parquet (vintage_basis="first_release") 생성.
  4. --revision-report: 스냅샷 간 동일 (hs_code, data_ym) 차분 → revision_magnitude.json.

실행:
  cd stage_artifacts/method_frontier/firm_level_scaffold/fq073
  ../../../../.venv_qvest_ml/Scripts/python.exe pull_customs_hs.py --from 2010 --to 2026
  ../../../../.venv_qvest_ml/Scripts/python.exe pull_customs_hs.py --build-first-release
  ../../../../.venv_qvest_ml/Scripts/python.exe pull_customs_hs.py --revision-report

★키는 .env DATA_GO_API_KEY 에서만 읽고 출력은 전부 마스킹한다(로그·예외 메시지 포함).
★HTTP 403 이면 활용신청 미승인 → 즉시 중단(가짜 데이터 생성 금지).
"""
import argparse, json, os, re, ssl, sys, time, urllib.parse, urllib.request, urllib.error
from datetime import date

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
PULL = os.path.join(HERE, "data_pull")
VSTORE = os.path.join(HERE, "vintage_store")
os.makedirs(PULL, exist_ok=True)
os.makedirs(VSTORE, exist_ok=True)

BASE = "https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList"
DATASET = "15101609"
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def load_key():
    with open(os.path.join(ROOT, ".env"), "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("DATA_GO_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("DATA_GO_API_KEY not found in .env")


KEY_RAW = load_key()
KEY_DEC = urllib.parse.unquote(KEY_RAW)
KEY_ENC = urllib.parse.quote(KEY_DEC, safe="")


def mask(s):
    """키가 어떤 경로로도 출력되지 않도록 치환 (예외 메시지 포함)."""
    s = str(s)
    for k in (KEY_RAW, KEY_DEC, KEY_ENC):
        if k:
            s = s.replace(k, "<KEY>").replace(urllib.parse.quote(k, safe=""), "<KEY>")
    return s


def call(strt, end, hs=None, timeout=60):
    url = "%s?serviceKey=%s&strtYymm=%s&endYymm=%s" % (BASE, KEY_ENC, strt, end)
    if hs:
        url += "&hsSgn=%s" % hs
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, "EXC %s: %s" % (type(e).__name__, mask(e))


TAGS = ["year", "hsCode", "statKor", "expDlr", "expWgt", "impDlr", "impWgt", "balPayments"]


def parse_items(body):
    rows = []
    for it in re.findall(r"<item>(.*?)</item>", body, flags=re.S):
        rec = {}
        for t in TAGS:
            m = re.search(r"<%s>(.*?)</%s>" % (t, t), it, flags=re.S)
            rec[t] = m.group(1).strip() if m else None
        rows.append(rec)
    return rows


def to_num(x):
    if x is None:
        return None
    x = re.sub(r"[^0-9.\-]", "", str(x))
    try:
        return float(x) if x not in ("", "-", ".") else None
    except ValueError:
        return None


def normalize(rows):
    """API 원문 -> 정본 스키마. `year` 필드의 실제 포맷을 **데이터로 판정**한다(추측 금지)."""
    df = pd.DataFrame(rows)
    if df.empty:
        return df
    yr = df["year"].astype(str).str.replace(r"[^0-9]", "", regex=True)
    lens = yr.str.len().value_counts().to_dict()
    if yr.str.len().eq(6).mean() > 0.9:            # YYYYMM = 월별
        df["data_ym"] = yr.str[:4] + "-" + yr.str[4:6]
    elif yr.str.len().eq(4).mean() > 0.9:          # YYYY = 연간 집계뿐 -> 월별 신호 불가
        raise SystemExit(
            "[fq073-pull] ★STOP: `year` 필드가 연(YYYY) 단위만 반환한다 (분포=%s).\n"
            "  FQ-073 은 월별 패널이 전제다. strtYymm/endYymm 범위를 1개월 창으로 바꿔\n"
            "  월별 분해가 되는지 먼저 실측하라(fq073_probe_after_approval.py)." % lens)
    else:
        raise SystemExit("[fq073-pull] ★STOP: `year` 포맷 판정 불가 (길이분포=%s)" % lens)
    out = pd.DataFrame({
        "data_ym": df["data_ym"],
        # 선행 0 보존: number 반환으로 절단됐으면 홀수 자릿수 -> 좌측 0-pad (러너와 동일 규약)
        "hs_code": df["hsCode"].astype(str).str.replace(r"[^0-9]", "", regex=True)
                     .map(lambda s: ("0" + s) if s and len(s) % 2 == 1 else s),
        "stat_kor": df["statKor"],
        "exp_usd": df["expDlr"].map(to_num),
        "imp_usd": df["impDlr"].map(to_num),
        "exp_wgt": df["expWgt"].map(to_num),
        "imp_wgt": df["impWgt"].map(to_num),
    })
    return out[(out["hs_code"].str.len() > 0) & out["exp_usd"].notna()]


def do_pull(y_from, y_to, chapters, sleep):
    frames, calls, failed = [], 0, []
    keys = chapters if chapters else [None]
    for y in range(y_from, y_to + 1):
        for hs in keys:
            st, body = call("%d01" % y, "%d12" % y, hs)
            calls += 1
            if st == 403:
                raise SystemExit(
                    "[fq073-pull] ★STOP: HTTP 403 Forbidden — data.go.kr org 1220000 활용신청 미승인.\n"
                    "  https://www.data.go.kr/data/%s/openapi.do 에서 [활용신청](개발단계 자동승인).\n"
                    "  가짜 데이터로 진행하지 않는다." % DATASET)
            if st != 200:
                failed.append({"year": y, "hs": hs, "status": st, "body": mask(body)[:200]})
                continue
            rows = parse_items(body)
            if not rows:
                msg = re.search(r"<resultMsg>(.*?)</resultMsg>", body)
                failed.append({"year": y, "hs": hs, "status": 200, "rows": 0,
                               "msg": msg.group(1) if msg else "?"})
                continue
            frames.append(normalize(rows))
            print("  %d hs=%-4s rows=%d" % (y, str(hs), len(rows)))
            time.sleep(sleep)
    if not frames:
        raise SystemExit("[fq073-pull] ★STOP: 수집 0행. 실패기록=%s" % json.dumps(failed[:5], ensure_ascii=False))
    df = pd.concat(frames, ignore_index=True).drop_duplicates(["hs_code", "data_ym"], keep="last")
    pull_date = date.today().isoformat()
    snap = os.path.join(VSTORE, "customs_hs_%s.parquet" % pull_date.replace("-", ""))
    if os.path.exists(snap):
        raise SystemExit("[fq073-pull] ★STOP: 스냅샷 %s 이미 존재 — append-only 규약상 덮어쓰지 않는다 "
                         "(PIT_plan §2-b-2). 재수집이 필요하면 파일명을 바꿔 보존하라." % snap)
    df["pull_date"] = pull_date
    df.to_parquet(snap, index=False)
    df.to_parquet(os.path.join(PULL, "customs_hs_monthly.parquet"), index=False)
    manifest = {
        "dataset": DATASET, "endpoint": BASE, "pull_date": pull_date,
        "vintage_basis": "revised_asof_pull",
        "vintage_basis_note": ("API에 vintage 파라미터가 없어 전 역사가 최신 개정판으로 반환된다. "
                               "과거 first-release 는 소급 복원 불가 (PIT_plan §2-a). "
                               "결과는 '개정판 상한'으로만 해석하고 라벨을 반드시 동반한다."),
        "pin_tag": "customs_%s" % pull_date.replace("-", ""),
        "snapshot": os.path.relpath(snap, HERE),
        "publication_lag": {
            "first_release": "data_ym M 전체 -> M+1월 1일 (잠정)",
            "confirmed": "매월 15일경 전월까지 자료 현행화 (무기한 반복)",
            "evidence": ["publication_lag_evidence.json", "first_release_evidence.json"]},
        "rows": int(len(df)), "hs_codes": int(df["hs_code"].nunique()),
        "ym_min": str(df["data_ym"].min()), "ym_max": str(df["data_ym"].max()),
        "api_calls": calls, "failures": failed[:50],
    }
    with open(os.path.join(PULL, "customs_vintage_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print("\n[fq073-pull] rows=%d hs=%d %s~%s calls=%d fail=%d"
          % (len(df), df["hs_code"].nunique(), df["data_ym"].min(), df["data_ym"].max(), calls, len(failed)))
    print("[fq073-pull] snapshot:", snap)


def snapshots():
    fs = sorted(f for f in os.listdir(VSTORE) if f.startswith("customs_hs_") and f.endswith(".parquet"))
    return [os.path.join(VSTORE, f) for f in fs]


def build_first_release():
    fs = snapshots()
    if len(fs) < 2:
        raise SystemExit("[fq073-pull] ★STOP: 스냅샷 %d개 — first-release 재구성은 2개 이상 필요. "
                         "월 1회 pull 로 축적하라 (PIT_plan §2-c)." % len(fs))
    seen, parts = set(), []
    for f in fs:                                   # 오래된 스냅샷부터 = 최초 관측 우선
        d = pd.read_parquet(f)
        d["snapshot"] = os.path.basename(f)
        key = list(zip(d["hs_code"], d["data_ym"]))
        keep = [k not in seen for k in key]
        seen.update(k for k, m in zip(key, keep) if m)
        parts.append(d[pd.Series(keep, index=d.index)])
    fr = pd.concat(parts, ignore_index=True)
    fr.to_parquet(os.path.join(PULL, "customs_hs_monthly_firstrelease.parquet"), index=False)
    man = {"vintage_basis": "first_release",
           "pin_tag": "customs_firstrelease_%s" % date.today().strftime("%Y%m%d"),
           "snapshots_used": [os.path.basename(f) for f in fs], "rows": int(len(fr)),
           "ym_min": str(fr["data_ym"].min()), "ym_max": str(fr["data_ym"].max()),
           "note": "각 (hs_code, data_ym) 의 **최초 관측 스냅샷** 값. 스냅샷 개시 이전 월은 여전히 개정판."}
    with open(os.path.join(PULL, "customs_vintage_manifest_firstrelease.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, ensure_ascii=False, indent=2)
    print("[fq073-pull] first-release rows=%d (%s~%s) from %d snapshots"
          % (len(fr), fr["data_ym"].min(), fr["data_ym"].max(), len(fs)))


def revision_report():
    fs = snapshots()
    if len(fs) < 2:
        raise SystemExit("[fq073-pull] ★STOP: 스냅샷 %d개 — 개정폭 실측은 2개 이상 필요." % len(fs))
    a = pd.read_parquet(fs[0])[["hs_code", "data_ym", "exp_usd"]]
    b = pd.read_parquet(fs[-1])[["hs_code", "data_ym", "exp_usd"]]
    m = a.merge(b, on=["hs_code", "data_ym"], suffixes=("_old", "_new"))
    m = m[m["exp_usd_old"] > 0]
    m["rel"] = (m["exp_usd_new"] - m["exp_usd_old"]) / m["exp_usd_old"]
    rep = {"snapshot_old": os.path.basename(fs[0]), "snapshot_new": os.path.basename(fs[-1]),
           "n_pairs": int(len(m)),
           "pct_revised": float((m["rel"].abs() > 1e-9).mean()) if len(m) else None,
           "abs_rel_mean": float(m["rel"].abs().mean()) if len(m) else None,
           "abs_rel_p50": float(m["rel"].abs().median()) if len(m) else None,
           "abs_rel_p95": float(m["rel"].abs().quantile(0.95)) if len(m) else None,
           "note": "개정폭이 신호 분산 대비 유의하면 PRIMARY lane 을 first_release 구간으로 제한(PIT_plan §2-c)."}
    with open(os.path.join(HERE, "revision_magnitude.json"), "w", encoding="utf-8") as f:
        json.dump(rep, f, ensure_ascii=False, indent=2)
    print(json.dumps(rep, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--from", dest="y_from", type=int, default=2010)
    p.add_argument("--to", dest="y_to", type=int, default=date.today().year)
    p.add_argument("--chapters", action="store_true",
                   help="hsSgn 을 2자리 chapter(01~99)로 루프 (집계 호출이 절단될 때)")
    p.add_argument("--sleep", type=float, default=0.2)
    p.add_argument("--build-first-release", action="store_true")
    p.add_argument("--revision-report", action="store_true")
    a = p.parse_args()
    try:
        if a.build_first_release:
            build_first_release()
        elif a.revision_report:
            revision_report()
        else:
            ch = ["%02d" % i for i in range(1, 100)] if a.chapters else None
            do_pull(a.y_from, a.y_to, ch, a.sleep)
    except SystemExit:
        raise
    except Exception as e:
        raise SystemExit(mask("[fq073-pull] 예외: %s: %s" % (type(e).__name__, e)))
