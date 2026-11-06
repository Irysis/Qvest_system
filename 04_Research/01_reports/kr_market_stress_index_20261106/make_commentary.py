#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""일보 '오늘의 해설' 한 단락 — Claude Sonnet 5.5 가 쓰고, 숫자 자동 검사를 통과해야만 싣는다(도훈 11-06 "해설 단락 붙여 보기").

흐름: make_daily_report.load() 의 파생값 → 데이터 묶음(JSON) → `claude -p`(Sonnet · 도구 없음 · 프로젝트 밖 임시 폴더에서 · 훅/CLAUDE.md 미적재)
      → 검사 ① 숫자: 본문의 모든 숫자가 묶음 값이거나 묶음 값끼리의 차 · 비율 · 상위 기여도 합이어야 한다
             ② 문장: 예측 · 전망 표현 금지(이 지수는 동행 지표) · 마크다운 기호 금지 · 길이
      → 불통과면 사유를 붙여 1회 다시 쓰게 하고, 그래도 불통과면 싣지 않는다(일보는 해설 없이 정상 발행 · 사유 기록).
출력: daily/<기준일>/commentary.json  {passed, text, model, attempts[...], checked_at}
실행: <repo>/.venv_qvest_ml/Scripts/python.exe make_commentary.py [--dry-check "<문장>"]   (--dry-check = 모델 호출 없이 검사기만)
인증: 무인 실행은 사용자 환경 변수 CLAUDE_CODE_OAUTH_TOKEN(기존 무인 레인과 같은 규약 · 값은 출력하지 않는다).
"""
from __future__ import annotations

import datetime as dt
import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
sys.path.insert(0, HERE)
import daily_text as T  # noqa: E402
import make_daily_report as M  # noqa: E402

MODEL = os.environ.get("KRSI_COMMENTARY_MODEL", "claude-sonnet-5-5")
MAX_CHARS = 700
TIMEOUT_SEC = 240

SYSTEM = ("당신은 한국 증권사 리서치센터의 시장 전략 담당자입니다. 임원에게 보내는 일일 스트레스 보고서의 '오늘의 해설' 한 단락을 씁니다. "
          "높임말 · 쉬운 말. 주어진 데이터의 숫자만 씁니다 — 숫자를 지어내거나 어림하지 않습니다. 계산은 데이터 값끼리의 차 · 비율만 허용됩니다. "
          "이 지수는 동행 지표(지금의 상태를 재는 온도계)이므로 앞으로의 방향을 예측하거나 전망하지 않습니다.")

RULES = f"""규칙:
- 한 단락, 4~6문장, {MAX_CHARS}자 이내. 제목 · 글머리표 · 마크다운 기호(*, #, |, `) 없이 평문으로만.
- 점수 · 심각도 · 백분위는 정수로 씁니다(예: 44점, 심각도 95). 기여도는 소수 한 자리(예: 8.3점).
- 다뤄 주실 것: ① 지금 스트레스의 성격(어느 분야가 나쁘고 어디는 평온한가) ② 지난 20거래일 동안 무엇이 바뀌었나 ③ 과거 위기와 견주면 어느 정도인가 ④ 지켜볼 대목(아직 평온한 분야로 번지는지 등 — 데이터에 근거한 관찰로).
- 금지: '~할 것입니다 / ~할 것으로 보입니다 / 전망 / 예상' 같은 예측 표현, 데이터에 없는 사건 · 뉴스 언급, 투자 권유.
- ★본문에 쓴 숫자마다 출처를 밝힙니다(자동 검사기가 다시 계산합니다). 출처 = 아래 '경로' 하나, 또는 계산식:
  `경로 - 경로` · `경로 + 경로` · `경로 / 경로` · `경로 / 경로 * 100` · `sum(경로, 경로, …)`(2~6개) · `count(목록이름.필드 >= 수)`(예: count(분야.심각도 >= 90)).
  상수는 100 만 쓸 수 있습니다. 날짜 · 연도와 '12개 분야 · 34개 지표 · 20거래일 · 60거래일' 같은 고정 수는 출처가 필요 없습니다.
  분야 · 지표 · 봉우리 경로의 숫자는 그 이름을 같은 문장에 함께 써야 합니다.
- 출력은 JSON 하나만: {{"text": "해설 단락", "numbers": [{{"value": "44", "source": "점수.오늘"}}, {{"value": "12", "source": "점수.오늘 - 점수.20거래일전"}}]}}"""


# ── 데이터 묶음 ────────────────────────────────────────────────────────────────
def r(x, k=2):
    return None if x is None or x != x else round(float(x), k)


def build_pack(meta, d, st, eps, cv, nsr):
    lt, lv, ns = meta["latest"], meta["levels"], nsr.get("v1", {})
    axes = meta["axes"]
    t20 = pd.Timestamp(lt["date_20td_ago"])
    return {
        "기준일": meta["last_date"],
        "점수": {"오늘": r(lt["level"], 1), "전일": r(d["level"].iloc[-2], 1), "20거래일전": r(lt["level_20td_ago"], 1), "60거래일전": r(lt["level_60td_ago"], 1),
                "정의": "0~100 · 높을수록 나쁨 · 10×√(CISS 원값)", "역대최고": r(lt["max_level"], 1), "역대최고_날짜": lt["max_score_date"]},
        "역대순위": {"백분위": r(100 * lt["score_pct"], 1), "나쁜순_상위_퍼센트": max(1, round(100 - 100 * lt["score_pct"]))},
        "경보단계": {"오늘": M.tier_of(lt["score_pct"], ns), "주의_점수": r(lv["warn"], 1), "위험_점수": r(lv["risk"], 1)},
        "점수_눈금_기준점": [{"이름": x["label"], "점수": r(x["level"], 1)} for x in meta["ref_marks"]],
        "분해": {"34지표_평균심각도": r(lt["score_linear"], 1), "평균심각도_평상시": r(lv["linear_median"], 1),
                "동행률_퍼센트": r(100 * lt["comove"], 0), "동행률_평상시_퍼센트": r(100 * lv["comove_median"], 0), "동행률_2008정점_퍼센트": r(100 * lv["comove_at_max"], 0)},
        "V_KOSPI200": {"오늘": r(lt["vkospi"], 1), "백분위": r(100 * lt["vkospi_pct"], 0)},
        "분야": [{"이름": T.AXIS_PLAIN[a][0], "심각도": r(100 * lt["axis_pct"][a], 0),
                 "심각도_20거래일전": r(100 * float(d.loc[t20, f"pct_{a}"]), 0) if t20 in d.index else None,
                 "기여도_점": r(lt["contrib_level"][a], 1), "기여도_점_20거래일전": r(lt["contrib_level_20td_ago"][a], 1)} for a in axes],
        "세부지표_심각도80이상": [{"분야": T.AXIS_PLAIN[x.axis][0], "이름": T.IND_PLAIN.get(x.id, x.name), "심각도": r(100 * x.ecdf_pct, 0),
                           "심각도_20거래일전": r(100 * x.ecdf_pct_20td_ago, 0), "자료일": x.last_obs_date}
                          for x in st.sort_values("ecdf_pct", ascending=False).itertuples() if x.ecdf_pct >= 0.8],
        "세부지표_20일새_크게오른것": [{"이름": T.IND_PLAIN.get(x.id, x.name), "심각도_20거래일전": r(100 * x.ecdf_pct_20td_ago, 0), "심각도": r(100 * x.ecdf_pct, 0)}
                              for x in st.assign(dd=st.ecdf_pct - st.ecdf_pct_20td_ago).sort_values("dd", ascending=False).head(5).itertuples()],
        "역대_봉우리": [{"날짜": str(t.date()), "점수": r(v, 1), "상황": T._peak_label(t)} for t, v in M.peaks_of(d)],
        "진행중_급락": [{"코스피200_고점": str(e.peak), "낙폭_퍼센트": r(100 * e.depth, 0)} for e in cv.itertuples() if bool(e.ongoing)],
        "지수의_성격": "동행 지표 — 급락과 거의 동시에 오르고 고점을 앞서지 못함. 점수가 역대 상위 5% 안일 때 이후 60거래일 큰 추가 하락이 평소보다 잦았음(꼬리 위험 정보).",
    }


# ── 검사기 ────────────────────────────────────────────────────────────────────
# ★설계: '숫자 자루' 대조(본문 숫자가 묶음 값 또는 그 차 · 비율인가)는 쓸모가 없다 — 실측 후보 1.3만 개면 1~100 정수 100% · 소수 99% 가 통과한다.
#   그래서 모델이 숫자마다 출처(경로) 또는 계산식(경로 둘 + 연산 하나 · 상위 기여도 합 · 개수 세기)을 함께 내고, 검사기가 그 출처를 다시 계산해
#   표기 자릿수로 일치하는지 본다. 분야 · 지표 출처의 숫자는 그 이름이 같은 문장에 있어야 한다(엉뚱한 분야에 숫자를 붙이는 오류 차단).
def flatten(pack):
    """묶음 → {경로: 값}. 목록 항목은 '이름' (없으면 '날짜')으로 색인: 분야[대형주 시장].기여도_점."""
    flat, labels = {}, {}

    def walk(o, path):
        if isinstance(o, dict):
            for k, v in o.items():
                walk(v, f"{path}.{k}" if path else k)
        elif isinstance(o, list):
            for i, v in enumerate(o):
                key = v.get("이름") or v.get("날짜") or str(i) if isinstance(v, dict) else str(i)
                walk(v, f"{path}[{key}]")
                if isinstance(v, dict):
                    labels[f"{path}[{key}]"] = v.get("이름") or v.get("상황") or ""
        elif isinstance(o, (int, float)) and not isinstance(o, bool) and o is not None:
            flat[path] = float(o)
    walk(pack, "")
    return flat, labels


_PATH = r"[가-힣A-Za-z0-9_]+(?:\[[^\]]+\])?(?:\.[가-힣A-Za-z0-9_]+(?:\[[^\]]+\])?)*"


def evaluate(expr, flat, pack):
    """출처 표현 → 값. 허용: 경로 · 경로 (+|-|*|/) 경로 · 경로 / 경로 * 100 · sum(경로, …) · count(목록.필드 >= 수)."""
    e = expr.strip()
    m = re.fullmatch(r"count\(\s*(" + _PATH + r")\.([가-힣A-Za-z0-9_]+)\s*(>=|<=|>|<)\s*(-?\d+(?:\.\d+)?)\s*\)", e)
    if m:
        lst, fld, op, thr = m.group(1), m.group(2), m.group(3), float(m.group(4))
        items = pack.get(lst)
        if not isinstance(items, list):
            raise KeyError(lst)
        vals = [it.get(fld) for it in items if isinstance(it, dict) and it.get(fld) is not None]
        return float(sum(eval(f"{v} {op} {thr}") for v in vals))
    m = re.fullmatch(r"sum\((.+)\)", e)
    if m:
        parts = [x.strip() for x in m.group(1).split(",")]
        if not 2 <= len(parts) <= 6:
            raise ValueError("sum 은 2~6개")
        return float(sum(flat[x] for x in parts))
    toks = re.split(r"\s+([+\-*/])\s+", e)
    if len(toks) not in (1, 3, 5):
        raise ValueError("연산은 최대 두 번")
    vals = []
    for t in toks[0::2]:
        if re.fullmatch(r"-?\d+(?:\.\d+)?", t):
            if float(t) not in (100.0,):
                raise ValueError(f"상수 {t} 금지(100 만 허용)")
            vals.append(float(t))
        else:
            vals.append(flat[t])
    out = vals[0]
    for op, v in zip(toks[1::2], vals[1:]):
        out = out + v if op == "+" else out - v if op == "-" else out * v if op == "*" else out / v
    return float(out)


# 출처 없이 쓸 수 있는 고정 수 — ★단위 문맥까지 맞아야 한다(숫자만 같으면 지어낸 값이 고정 수로 위장해 통과한다 · 양성 대조 ⑥ 실측)
CONST_CTX = [r"(?:12|34)\s*개", r"(?:20|60|65|250)\s*거래일", r"18\s*개월", r"0\s*~\s*100", r"/\s*100", r"100\s*점\s*만점",
             r"(?:심각도|백분위)\s*(?:60|80|90)\s*(?:이상|이하|을|를|선|안팎)", r"(?:60|80|90)\s*(?:이상|이하)(?:인|이|의)?\s*(?:분야|지표)", r"상위\s*\d+\s*개"]


def _const_ok(text, start, end):
    """그 자리의 숫자가 고정 수 문맥 안에 있는가(문맥 일치 구간이 숫자 위치를 덮어야 한다 — 근처의 다른 '20거래일'로 위장 불가)."""
    for pat in CONST_CTX:
        for m in re.finditer(pat, text):
            if m.start() <= start and end <= m.end():
                return True
    return False


_DATE = re.compile(r"\d{4}\s*년|\d{1,2}\s*월\s*\d{1,2}\s*일|\d{1,2}\s*월|\d{4}-\d{2}-\d{2}")


def _sentences(text):
    return [x for x in re.split(r"(?<=[다요])\.\s+|(?<=[.!?])\s+", text) if x.strip()]


def check_claim(text, claims, pack):
    """→ (ok, 사유). claims = [{"value": "44", "source": "점수.오늘"}, …]"""
    flat, labels = flatten(pack)
    why = []
    body = _DATE.sub(lambda m: " " * len(m.group(0)), text)          # 길이 보존(위치로 문맥을 본다)
    written = [(m.group(0), m.start(), m.end()) for m in re.finditer(r"(?<![\w.])-?\d+(?:\.\d+)?", body)]
    claimed = {}
    for c in claims or []:
        v, src = str(c.get("value", "")).strip(), str(c.get("source", "")).strip()
        try:
            x = evaluate(src, flat, pack)
        except Exception as e:  # noqa: BLE001
            why.append(f"출처 해석 실패 {v} ← {src} ({type(e).__name__}: {e})")
            continue
        k = len(v.split(".")[1]) if "." in v else 0
        if abs(round(abs(x), k) - abs(float(v))) > 1e-9:
            why.append(f"값 불일치 {v} ← {src} = {x:.4g}")
            continue
        # 분야 · 지표 · 봉우리 출처면 그 이름이 숫자와 같은 문장에 있어야 한다
        need = [labels[p] for p in labels if p in src and labels[p]]
        if need:
            sents = [s for s in _sentences(text) if re.search(r"(?<![\w.])" + re.escape(v) + r"(?![\d])", _DATE.sub(" ", s))]
            short = [n.split(" · ")[0].split("(")[0] for n in need]
            if sents and not any(all(sh in s for sh in short) for s in sents):
                why.append(f"출처 이름과 문장 불일치 {v} ← {src}(문장에 '{', '.join(short)}' 없음)")
                continue
        claimed.setdefault(v, src)
    for w, i0, i1 in written:
        if w in claimed or w.lstrip("-") in claimed:
            continue
        if _const_ok(body, i0, i1):
            continue
        why.append(f"출처 없는 숫자 {w}")
    pred = re.findall(r"[가-힣]*\s*것(?:입니다|으로\s*(?:보입|예상|전망))|전망|예상(?:됩|합|되)", text)
    if pred:
        why.append("예측 · 전망 표현: " + ", ".join(dict.fromkeys(p.strip() for p in pred)))
    if re.search(r"[*#|`]", text):
        why.append("마크다운 기호 사용")
    if not 120 <= len(text) <= MAX_CHARS + 80:
        why.append(f"길이 {len(text)}자(120~{MAX_CHARS})")
    return (not why), list(dict.fromkeys(why))


def check_text(text, pack):          # 호환용 — 출처 없이 부르면 모든 숫자가 '출처 없음'
    return check_claim(text, [], pack)


# ── 모델 호출 ─────────────────────────────────────────────────────────────────
def _env():
    env = dict(os.environ)
    env.update({"PYTHONUTF8": "1", "QVEST_UNATTENDED_LANE": "1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"})
    if not env.get("CLAUDE_CODE_OAUTH_TOKEN"):      # 세션 · 예약 작업 셸엔 없을 수 있다 — 사용자 환경 변수에서(값은 출력하지 않음)
        try:
            tok = subprocess.run(["powershell", "-NoProfile", "-Command",
                                  "[Environment]::GetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN','User')"],
                                 capture_output=True, text=True, timeout=30).stdout.strip()
            if tok.startswith("sk-ant-"):
                env["CLAUDE_CODE_OAUTH_TOKEN"] = tok
        except Exception:
            pass
    return env


def call_model(prompt):
    exe = shutil.which("claude") or shutil.which("claude.cmd")
    if not exe:
        raise RuntimeError("claude CLI 를 찾지 못함")
    with tempfile.TemporaryDirectory(prefix="krsi_commentary_") as wd:     # 프로젝트 밖 — 프로젝트 훅 · CLAUDE.md 를 싣지 않는다
        cmd = [exe, "-p", "--model", MODEL, "--tools", "", "--output-format", "json", "--no-session-persistence",
               "--strict-mcp-config", "--system-prompt", SYSTEM]
        p = subprocess.run(cmd, input=prompt, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=TIMEOUT_SEC, cwd=wd, env=_env())
    if p.returncode != 0:
        raise RuntimeError(f"claude rc={p.returncode}: {(p.stderr or p.stdout)[-300:]}")
    out = json.loads(p.stdout)
    if out.get("is_error"):
        raise RuntimeError(f"claude error: {str(out.get('result'))[:300]}")
    return out.get("result", "").strip(), out.get("total_cost_usd")


def clean(text):
    t = text.strip().strip('"').strip()
    t = re.sub(r"\s*\n\s*", " ", t)
    return t


def prompt_data(pack):
    """모델에 주는 데이터 = '경로 = 값' 목록(출처를 그대로 베껴 쓰게) + 숫자 아닌 참고."""
    flat, _ = flatten(pack)
    notes = {"점수_정의": pack["점수"]["정의"], "지수의_성격": pack["지수의_성격"], "경보단계_오늘": pack["경보단계"]["오늘"],
             "역대최고_날짜": pack["점수"]["역대최고_날짜"], "기준일": pack["기준일"],
             "세부지표_자료일": [(x["이름"], x["자료일"]) for x in pack["세부지표_심각도80이상"]],
             "봉우리_상황": [(x["날짜"], x["상황"]) for x in pack["역대_봉우리"]], "진행중_급락_고점": [x["코스피200_고점"] for x in pack["진행중_급락"]]}
    return "경로 = 값\n" + "\n".join(f"{k} = {v:g}" for k, v in flat.items()) + "\n\n참고(숫자 출처 아님):\n" + json.dumps(notes, ensure_ascii=False, indent=1)


def main():
    meta, d, st, eps, cv, nsr, rob, bm = M.load()
    pack = build_pack(meta, d, st, eps, cv, nsr)
    if "--dry-check" in sys.argv:
        s = sys.argv[sys.argv.index("--dry-check") + 1]
        claims = json.loads(sys.argv[sys.argv.index("--dry-check") + 2]) if len(sys.argv) > sys.argv.index("--dry-check") + 2 else []
        ok, why = check_claim(s, claims, pack)
        print(json.dumps({"ok": ok, "why": why}, ensure_ascii=False))
        sys.exit(0 if ok else 1)
    day = meta["last_date"]
    folder = f"{M.DAILY}/{day}"
    os.makedirs(folder, exist_ok=True)
    data = prompt_data(pack)
    prompt = f"데이터:\n{data}\n\n{RULES}"
    attempts, final = [], None
    for i in range(2):
        try:
            text, cost = call_model(prompt)
        except Exception as e:  # noqa: BLE001 — 해설 실패는 일보를 막지 않는다
            attempts.append({"n": i + 1, "error": str(e)[:400]})
            break
        try:
            obj = json.loads(re.sub(r"^```(?:json)?|```$", "", text.strip()).strip())
            text, claims = clean(obj.get("text", "")), obj.get("numbers", [])
            ok, why = check_claim(text, claims, pack)
        except Exception as e:  # noqa: BLE001
            claims, ok, why = [], False, [f"JSON 해석 실패: {e}"]
        attempts.append({"n": i + 1, "text": text, "numbers": claims, "ok": ok, "why": why, "cost_usd": cost})
        print(f"[commentary] 시도 {i + 1}: {'통과' if ok else '불통과 — ' + ' / '.join(why)}", flush=True)
        if ok:
            final = text
            break
        prompt = (f"데이터:\n{data}\n\n{RULES}\n\n직전 초안이 자동 검사를 통과하지 못했습니다 — 사유: {' / '.join(why)}.\n"
                  f"직전 초안:\n{text}\n\n사유를 고친 JSON 하나만 출력하십시오.")
    res = {"day": day, "passed": final is not None, "text": final, "model": MODEL, "checked_at": dt.datetime.now().isoformat(timespec="seconds"),
           "attempts": attempts}
    json.dump(res, open(f"{folder}/commentary.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"[commentary] {'실음' if final else '싣지 않음'} → {folder}/commentary.json", flush=True)


if __name__ == "__main__":
    main()
