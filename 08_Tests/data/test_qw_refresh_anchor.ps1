#==============================================================================
# test_qw_refresh_anchor.ps1 — 퀀티 Update_File 드라이버 B5 앵커(F2) 양방향 검사 (2026-11-06 · 2차 수리 2026-11-06)
#
# 왜 (04_Research/01_reports/quantiwise_data_expansion_20261106/PLAN.md §3.0 F2 · §5.1):
#   구판 qw_refresh.ps1 은 책당 대표 parquet 1개의 max+1 을 B5 로 썼다 — 대표가 앞서면 뒤처진 시트를 건너뛰어 구멍이 났다.
#   11-06 실측: us_sector_lv2 10-19 인데 us_k200 11-05 라 'cache already >= target' · 수급 개인/기타법인 10-19 인데 investor_all
#   max 10-30 → B5=20261031 · 컨센서스 4지표 10-16 인데 eps_1y 10-19 → B5=20261020.
#   수리 = 출력 전부의 min(max)+1 · 출력 하나라도 판단 불가면 keep(기존 B5) · 'done' 은 모든 출력이 목표일에 닿았을 때만.
# 무엇을 재나 (단말 · Excel · 대화상자 감시 · 상태 파일 · 운영 .cache 무접촉):
#   실제 qw_refresh.ps1 에서 앵커 함수 6개만 AST 로 꺼내 모래상자(%TEMP%) parquet 로 돌린다.
#   A~Q  앵커 사례 — 양성 대조(출력 max 가 다를 때 B5 = min+1 · 전부 목표일 이상이면 done · 경계 = 목표일 당일은 받는다)
#        + 위반 주입(출력 파일 부재 · 깨짐 · 행 0 · Date 열 없음 · 그룹 행 부재 → keep)
#   N    계기 사망 주입 — python 부재 · 기동 실패 → keep (판단 불가가 'done' 으로 새지 않는다)
#   R    Refresh-One 분기 — done → ok · b5/keep → 시작줄 · -FromOverride 가 done 보다 먼저($WhatIf 로 Excel 앞에서 멈춘다)
#        + WARN 줄(2차) — 뒤처진 출력이 앵커를 붙잡으면 창 일수와 함께 · keep 이면 경고 · done · 고른 출력이면 경고 없음
#   S    책 표 구조 — 순서 · 경로(구판 $FILES 와 같음) · OHLCVS = qw_base · Benchmark 출력 = benchmark.parquet 하나(indices 제외 사유는 드라이버 주석)
#   G    표 ↔ 적재기 · 파서 **값** 대조(2차 — 원문 모양 무관): R 구문 분석기(parse · 평가는 c()/list() 상수식만)와 python ast 로
#        CONSENSUS_METRICS 값 · UNIVERSE_SUPPORT_SHEET_META 의 cache_name · SHEETS 2번째 칸 · 'investor_all.parquet' 을 쓰는 적재기 함수의
#        sheet_map 값과 InvestorType 열 생성 · 적재기 ↔ 파서 연결(정본 상수 참조 또는 파서 파일 호출 — 둘 중 하나)과 출력 이름
#        ("consensus" · "us_%s.parquet" · "investor_stock")을 뽑아 표와 대조한다. 출력 이름 문자열은 표에서 뽑는다(표가 바뀌면 같이 따라간다).
#        G1~G3 = 실제 저장소 · GV = 같은 값을 다른 모양(c()/list() · <- = -> · 줄바꿈 · 주석 속 가짜 대입 · 한글 이름 · := / $<- / 이름 인수 ·
#        범위 밖 함수의 sheet_map)으로 쓴 합성 사본 → 통과해야 · GN = 값이 갈라진 합성 사본 → 그 축만 정해진 사유로 실패해야(나머지 둘은 통과).
#        ★1차 판은 원문 모양(sheet_map <- list( · 'InvestorType := sheet_map' 리터럴 · 줄머리 괄호)에 묶여, 적재기가 같은 값을
#          c() · := itype 로 다시 쓰자(F3) 거짓 실패했다 — 그 교훈으로 이 축을 다시 짰다.
#   P    그룹 판독 등가(2차 — 드라이버의 행 그룹 가지치기): 행 그룹 여럿 · 날짜 뒤섞임 · 통계 없음 · 시각형 + 결측 · 그룹 부재 · 열 부재 · 행 0
#        자료에서 Get-OutputMaxes 결과 = 이 시험이 자료 행에서 직접 계산한 그룹별 max(독립 기준) · 가지치기가 실제로 일어남(읽은 행 그룹 수)
#   M1~M16 뮤테이션 — 소스 텍스트 치환(치환 1회 성사 단정) 사본에서 지정 검사가 실제로 실패해야 한다(검출력).
# 사전 점검(카나리아): python 기능 프로브(pyarrow · pandas import) · 함수 6개 추출 · 알려진 max 1건 판독 + 부재 1건 판독 ·
#   R/python 사실 추출기 카나리아(모양이 제각각인 합성 파일 → 기대값 · 시작/끝 표지 · 작업 수 일치).
#   실패하면 사례 결과를 내지 않고 preflight 로 끊는다(0/N 을 '검거 실패'로 오독하지 않게).
# 사용: powershell -NoProfile -ExecutionPolicy Bypass -File 08_Tests/data/test_qw_refresh_anchor.ps1 [-Src <qw_refresh.ps1>] [-RepoRoot <저장소 루트>]
#   검사 주입(환경변수): QW_ANCHOR_RSCRIPT = Rscript 경로(지정하면 그것만 쓴다 — 죽은 R 주입용 · 수동 지정)
#   배터리: run_all_hooks.sh 는 확장자로 실행기를 고른다 — 이 파일은 bash 래퍼 08_Tests/data/test_qw_refresh_anchor.sh 로 편입한다.
# 마지막 줄: {"test":"test_qw_refresh_anchor","pass":N,"fail":M} · 종료 코드 0 = 실패 0
# ★주의: PowerShell 변수 이름은 대소문자를 가리지 않는다 — 드라이버가 쓰는 $ROOT 와 겹치지 않게 저장소 루트는 $RepoRoot 다
#   (첫 판이 $Root 로 써서 $script:ROOT = $null 에 덮였고, 그 예외로 검사 0건인 채 pass=0 fail=0 rc=0 을 냈다 → 아래 catch · '검사 0건' 가드).
#==============================================================================
param([string]$Src = '', [string]$RepoRoot = '')
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$TEST = 'test_qw_refresh_anchor'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
if (-not $Src)  { $Src  = Join-Path $RepoRoot '02_Infrastructure\ops\qw_refresh.ps1' }
$script:PASS = 0; $script:FAIL = 0
function Say([string]$m) { [Console]::Out.WriteLine($m) }
function Mark([bool]$ok, [string]$id, [string]$desc, [string]$got) {
  if ($ok) { $script:PASS++; Say "  [PASS] $id - $desc" } else { $script:FAIL++; Say "  [FAIL] $id - $desc :: $got" }
}

# ---- 시험 보호막 — 꺼낸 함수가 Excel(COM)로 새지 않게. 정상 경로는 $WhatIf 로 그 앞에서 멈춘다. 이 시험 코드는 New-Object 를 쓰지 않는다 ----
function New-Object { throw 'TEST GUARD: New-Object blocked (no COM / Excel in this test)' }
# Write-Host 를 가로채 드라이버 로그 줄을 모은다(함수가 cmdlet 보다 먼저 해석된다)
$script:HOSTLOG = [System.Collections.Generic.List[string]]::new()
function Write-Host { param([Parameter(ValueFromRemainingArguments = $true)] $Object) $script:HOSTLOG.Add((@($Object) -join ' ')) }

# ---- 드라이버가 기대하는 스크립트 범위 변수(시험 값) ----
$script:FROM_OVR = @{}
$script:WhatIf   = $true
$script:ROOT     = $null
$script:PY       = $null
$script:VR       = 'C:\qw_anchor_vroot'   # 표 구조 검사용 가상 루트(존재하지 않아도 된다 · Join-Path 는 드라이브만 확인)
$script:FACTS    = @{}

$FN_NAMES = @('New-QwBookTable', 'Get-OutputMaxes', 'Add-OneDay', 'Get-BookAnchor', 'Get-QwBaseNext', 'Refresh-One')
function Import-Fns([string]$text) {
  # 소스 텍스트에서 함수 6개를 AST 로 꺼내 스크립트 범위에 정의한다('function script:<이름>' 으로 바꿔 이 함수 밖에서도 보이게)
  $tok = $null; $err = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tok, [ref]$err)
  if ($err -and $err.Count -gt 0) { return ('parse_error: ' + $err[0].Message) }
  $h = @{}
  foreach ($fd in $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $h[$fd.Name] = $fd.Extent.Text }
  $miss = @($FN_NAMES | Where-Object { -not $h.ContainsKey($_) })
  if ($miss.Count -gt 0) { return ('missing: ' + ($miss -join ',')) }
  $re = [regex]'^function\s+'
  foreach ($n in $FN_NAMES) { . ([scriptblock]::Create($re.Replace($h[$n], 'function script:', 1))) }
  return 'ok'
}

# ---- 모래상자 parquet 생성기(python · 한 번에 전 사례) ----
$GEN_PY = @'
import sys, os, json, datetime
import pyarrow as pa, pyarrow.parquet as pq
spec = json.load(open(sys.argv[1], encoding='utf-8-sig'))
D = datetime.date.fromisoformat
def upto(mx, n=3):
    d = D(mx)
    return [d - datetime.timedelta(days=k) for k in range(n - 1, -1, -1)]
def aslist(v):
    return [] if v is None else ([v] if isinstance(v, str) else list(v))
n = 0
for it in spec:
    p = it['path']
    os.makedirs(os.path.dirname(p), exist_ok=True)
    k = it['kind']
    if k == 'file':
        open(p, 'wb').close()
    elif k == 'corrupt':
        with open(p, 'wb') as fh: fh.write(b'not a parquet file')
    elif k == 'empty':
        pq.write_table(pa.table({'Date': pa.array([], pa.date32()), 'Ticker': pa.array([], pa.string())}), p)
    elif k == 'nodate':
        pq.write_table(pa.table({'Ticker': pa.array(['A']), 'Value': pa.array([1.0])}), p)
    elif k == 'dates':
        ds = upto(it['max'])
        if it.get('ts'):
            col = pa.array([datetime.datetime(d.year, d.month, d.day) for d in ds], pa.timestamp('us'))
        else:
            col = pa.array(ds, pa.date32())
        pq.write_table(pa.table({'Date': col, 'Ticker': pa.array(['A'] * len(ds)), 'Value': pa.array([1.0] * len(ds))}), p)
    elif k == 'groups':
        dd, tt, gg = [], [], []
        for g, mx in it['groups'].items():
            for d in upto(mx):
                for tk in ('A', 'B'):
                    dd.append(d); tt.append(tk); gg.append(g)
        pq.write_table(pa.table({'Date': pa.array(dd, pa.date32()), 'Ticker': pa.array(tt),
                                 'NetBuy': pa.array([1.0] * len(dd)), it['group_col']: pa.array(gg)}), p)
    elif k == 'grows':
        # 행을 파일 순서 그대로 쓴다('날짜|그룹' · 날짜 '' = 결측 · ts = 시각형) — 행 그룹 크기 · 통계 유무 · 열 구성을 지정한다
        rows = aslist(it.get('rows')); cols = aslist(it.get('cols')) or ['Date', it['group_col']]
        ts = bool(it.get('ts')); stats = it.get('stats'); stats = True if stats is None else bool(stats)
        sp = [r.split('|', 1) for r in rows]
        def pdate(s):
            if not s: return None
            return datetime.datetime.fromisoformat(s) if ts else D(s[:10])
        data = {}
        if 'Date' in cols: data['Date'] = pa.array([pdate(a) for a, _ in sp], pa.timestamp('us') if ts else pa.date32())
        data['Ticker'] = pa.array(['A'] * len(sp), pa.string())
        if it['group_col'] in cols: data[it['group_col']] = pa.array([b for _, b in sp], pa.string())
        pq.write_table(pa.table(data), p, row_group_size=(it.get('rg_size') or None), write_statistics=stats)
        # 픽스처가 주장대로인가(행 그룹 수 · 통계 유무) — 아니면 사례가 재려는 것을 못 재므로 생성 실패로 끊는다
        md = pq.ParquetFile(p).metadata
        er = it.get('expect_rg')
        if er is not None and md.num_row_groups != int(er):
            raise SystemExit('fixture %s: row groups %d != %s' % (p, md.num_row_groups, er))
        if 'Date' in cols and md.num_rows > 0:
            di = [j for j in range(md.num_columns) if md.schema.column(j).path == 'Date'][0]
            st = md.row_group(0).column(di).statistics
            if (st is not None and st.has_min_max) != stats:
                raise SystemExit('fixture %s: statistics present=%s expected=%s' % (p, st is not None, stats))
    elif k == 'calendar':
        rows = [r.split('|') for r in it['rows']]
        pq.write_table(pa.table({'Date': pa.array([D(r[0]) for r in rows], pa.date32()),
                                 'source': pa.array([r[1] for r in rows])}), p)
    else:
        raise SystemExit('unknown kind ' + k)
    n += 1
print('GEN_OK', n)
'@

# ---- 사실 추출기 ① python ast — 최상위 대입 <sym> 의 값(literal_eval)에서 튜플 칸 <idx> 를 뽑는다(원문 모양 무관 · 실행하지 않는다) ----
$PYFACTS_PY = @'
import sys, ast
jobs = [l.rstrip('\r\n').split('\t') for l in open(sys.argv[1], encoding='utf-8') if l.strip()]
print('PYFACTS_BEGIN')
for jid, f, sym, idx in jobs:
    try:
        tree = ast.parse(open(f, encoding='utf-8').read())
        found = []
        for node in tree.body:
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == sym for t in node.targets):
                found.append(node.value)
            elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == sym and node.value is not None:
                found.append(node.value)
        if not found:
            print('F\t%s\tnot_found\t' % jid); continue
        vals = [[str(t[int(idx)]) for t in ast.literal_eval(v)] for v in found]
        if any(sorted(x) != sorted(vals[0]) for x in vals):
            print('F\t%s\tambiguous\t' % jid); continue
        if any((',' in x) or ('\t' in x) for x in vals[0]):
            print('F\t%s\tbad_value\t' % jid); continue
        print('F\t%s\tok\t%s' % (jid, ','.join(vals[0])))
    except Exception as e:
        print('F\t%s\terror:%s\t' % (jid, type(e).__name__))
print('PYFACTS_END %d' % len(jobs))
'@

# ---- 사실 추출기 ② R 구문 분석기 — 파서 · 적재기의 값(원문 모양 무관 · 읽기만 · 평가는 c()/list() 상수식만) ----
$RFACTS_R = @'
## test_qw_refresh_anchor 사실 추출기 — 인수 1 = 작업 파일(UTF-8 · 줄 = id <TAB> kind <TAB> file <TAB> a1 <TAB> a2 <TAB> a3)
## 출력 = RFACTS_BEGIN · 'F <TAB> id <TAB> status <TAB> payload' 줄들 · RFACTS_END <작업 수>
##   kind: top_values(file, sym) · top_field(file, sym, field) · fn_scope(file, anchor_str, sym, col → id.fns · id.vals · id.col) ·
##         file_sym(file, sym) · file_str(file, str)
args <- commandArgs(trailingOnly = TRUE)
jobs <- readLines(args[1], encoding = "UTF-8", warn = FALSE)
jobs <- jobs[nzchar(jobs)]
cat("RFACTS_BEGIN\n")
.px <- new.env()
.parsed <- function(f) {
  if (!exists(f, envir = .px, inherits = FALSE))
    assign(f, tryCatch(parse(f, keep.source = FALSE, encoding = "UTF-8"), error = function(e) e), envir = .px)
  get(f, envir = .px, inherits = FALSE)
}
## 원소를 지역 변수에 담지 않는다 — x[, j] 의 빈 칸(빈 인수)을 변수에 담으면 그 변수를 읽을 때 'argument is missing' 오류가 난다
.walk <- function(e, visit) {
  visit(e)
  if (is.call(e) || is.pairlist(e)) { n <- length(e); if (n > 0L) for (i in seq_len(n)) .walk(e[[i]], visit) }
}
.is_sym <- function(x, s) is.symbol(x) && identical(as.character(x), s)
.is_str <- function(x, s) is.character(x) && length(x) == 1L && !is.na(x) && x == s
.is_asg <- function(x) is.call(x) && length(x) == 3L && is.symbol(x[[1]]) && as.character(x[[1]]) %in% c("<-", "=", "<<-")
## '<sym> <- v' · '<sym> = v' · '<sym> <<- v' · 'v -> <sym>'(구문 분석기가 <- 로 바꾼다) → list(v) · 아니면 NULL
.asg_rhs <- function(x, sym) if (.is_asg(x) && .is_sym(x[[2]], sym)) list(x[[3]]) else NULL
## 상수식 = NULL · 길이 1 원자값 · 그것들만 든 c() / list() — 이것만 평가한다(남의 코드를 실행하지 않는다)
.const <- function(e) {
  if (is.null(e)) return(TRUE)
  if (is.atomic(e)) return(length(e) <= 1L)
  if (is.call(e) && is.symbol(e[[1]]) && as.character(e[[1]]) %in% c("c", "list")) {
    n <- length(e)
    if (n > 1L) for (i in 2:n) if (!.const(e[[i]])) return(FALSE)
    return(TRUE)
  }
  FALSE
}
.vals <- function(rhs) {
  if (!.const(rhs)) stop("nonconst")
  as.character(unlist(eval(rhs, envir = baseenv()), use.names = FALSE))
}
.pay <- function(v) { if (any(grepl("[,\t\r\n]", v))) stop("bad_value"); paste(v, collapse = ",") }
.emit <- function(id, status, payload = "") cat("F\t", id, "\t", gsub("[\t\r\n]", " ", status), "\t", payload, "\n", sep = "")
.top_fns <- function(ex) {
  out <- list()
  for (k in seq_along(ex)) {
    x <- ex[[k]]
    if (.is_asg(x) && is.symbol(x[[2]]) && is.call(x[[3]]) && .is_sym(x[[3]][[1]], "function"))
      out[[as.character(x[[2]])]] <- x[[3]]
  }
  out
}
.has_str <- function(e, s) { hit <- FALSE; .walk(e, function(x) if (!hit && .is_str(x, s)) hit <<- TRUE); hit }
## 열 생성 = ':=' 왼쪽(기호 · 문자열) · x$col <- · x[["col"]] <- · 이름 인수 col = (data.table() · list() · `:=`(col = ) 등) · set()/setnames() 문자열 인수
.makes_col <- function(e, col) {
  hit <- FALSE
  .walk(e, function(x) {
    if (hit || !is.call(x)) return(invisible(NULL))
    if (.is_sym(x[[1]], ":=") && length(x) >= 2L && (.is_sym(x[[2]], col) || .is_str(x[[2]], col))) { hit <<- TRUE; return(invisible(NULL)) }
    if (.is_asg(x) && is.call(x[[2]]) && length(x[[2]]) >= 3L && (.is_sym(x[[2]][[1]], "$") || .is_sym(x[[2]][[1]], "[[")) &&
        (.is_sym(x[[2]][[3]], col) || .is_str(x[[2]][[3]], col))) { hit <<- TRUE; return(invisible(NULL)) }
    nm <- names(x)
    if (!is.null(nm) && col %in% nm[-1L]) { hit <<- TRUE; return(invisible(NULL)) }
    if ((.is_sym(x[[1]], "set") || .is_sym(x[[1]], "setnames")) && length(x) >= 2L)
      for (i in 2:length(x)) if (.is_str(x[[i]], col)) { hit <<- TRUE; return(invisible(NULL)) }
    invisible(NULL)
  })
  hit
}
n <- 0L
for (ln in jobs) {
  n <- n + 1L
  f <- strsplit(ln, "\t", fixed = TRUE)[[1]]
  id <- f[1]; kind <- f[2]; file <- f[3]; a <- f[-(1:3)]
  tryCatch({
    ex <- .parsed(file)
    if (inherits(ex, "error")) {
      st <- paste0("parse_error:", conditionMessage(ex))
      if (identical(kind, "fn_scope")) for (sfx in c(".fns", ".vals", ".col")) .emit(paste0(id, sfx), st) else .emit(id, st)
    } else if (kind %in% c("top_values", "top_field")) {
      rhs <- list(); for (k in seq_along(ex)) rhs <- c(rhs, .asg_rhs(ex[[k]], a[1]))
      if (!length(rhs)) .emit(id, "not_found") else {
        vs <- tryCatch(lapply(rhs, function(r) {
          if (!.const(r)) stop("nonconst")
          v <- eval(r, envir = baseenv())
          if (identical(kind, "top_field")) {
            if (!is.list(v)) stop("not_list")
            unname(vapply(v, function(e) { x <- e[[a[2]]]; if (!is.character(x) || length(x) != 1L) stop("bad_field"); x }, ""))
          } else as.character(unlist(v, use.names = FALSE))
        }), error = function(e) e)
        if (inherits(vs, "error")) .emit(id, conditionMessage(vs))
        else if (length(unique(lapply(vs, sort))) > 1L) .emit(id, "ambiguous")
        else .emit(id, "ok", .pay(vs[[1]]))
      }
    } else if (identical(kind, "fn_scope")) {
      fns <- .top_fns(ex)
      sel <- names(fns)[vapply(fns, .has_str, logical(1), s = a[1])]
      .emit(paste0(id, ".fns"), "ok", paste(sel, collapse = ","))
      rhs <- list(); for (nm in sel) .walk(fns[[nm]], function(x) { r <- .asg_rhs(x, a[2]); if (!is.null(r)) rhs <<- c(rhs, r) })
      if (!length(rhs)) .emit(paste0(id, ".vals"), "not_found") else {
        vs <- tryCatch(lapply(rhs, .vals), error = function(e) e)
        if (inherits(vs, "error")) .emit(paste0(id, ".vals"), conditionMessage(vs))
        else if (length(unique(lapply(vs, sort))) > 1L) .emit(paste0(id, ".vals"), "ambiguous", paste(vapply(vs, paste, "", collapse = "+"), collapse = ";"))
        else .emit(paste0(id, ".vals"), "ok", .pay(vs[[1]]))
      }
      .emit(paste0(id, ".col"), "ok", if (any(vapply(sel, function(nm) .makes_col(fns[[nm]], a[3]), logical(1)))) "TRUE" else "FALSE")
    } else if (identical(kind, "file_sym")) {
      .emit(id, "ok", if (any(vapply(seq_along(ex), function(k) a[1] %in% all.names(ex[[k]]), logical(1)))) "TRUE" else "FALSE")
    } else if (identical(kind, "file_str")) {
      .emit(id, "ok", if (any(vapply(seq_along(ex), function(k) .has_str(ex[[k]], a[1]), logical(1)))) "TRUE" else "FALSE")
    } else .emit(id, "unknown_kind")
  }, error = function(e) .emit(id, paste0("error:", conditionMessage(e))))
}
cat("RFACTS_END ", n, "\n", sep = "")
'@

# ---- 사실 추출기 카나리아(모양이 제각각인 합성 파일 → 기대값). 실패 = preflight ----
$CANARY_R = @'
## 사실 추출기 카나리아 — 모양이 제각각이어도 값만 나와야 한다
X_LIST = list(a = "p", `b` = "q")   # 주석 (괄호 · X_LIST <- c("가짜")
c("r",
  "s") -> X_ARROW
f_canary <- function(x, y = 2) {
  m <- c("가" = "u",
         "나" = "v")
  d[, COLX := m[[1]]]
  z <- d[, j]
  file.path(x, "canary_anchor.parquet")
}
g_other <- function() { m <- c("w"); d[, COLX := 1]; NULL }
'@
$CANARY_PY = @'
# 사실 추출기 카나리아
SHEETS = (  # (괄호 주석 · SHEETS = [("x", "fake")]
    ("A", "a1", 1),
    ('B',
     'b1', 2),
)
'@
$CANARY_EXPECT = [ordered]@{
  'canary.list' = 'ok|p,q'; 'canary.arrow' = 'ok|r,s'; 'canary.fn.fns' = 'ok|f_canary'; 'canary.fn.vals' = 'ok|u,v'; 'canary.fn.col' = 'ok|TRUE'
  'canary.sym' = 'ok|TRUE'; 'canary.nosym' = 'ok|FALSE'; 'canary.str' = 'ok|TRUE'; 'canary.py' = 'ok|a1,b1'
}

$TD = '2026-11-05'; $script:T = '20261105'   # 사례 공통 목표일(벤치 최신일 역할)
# 앵커 사례 — data = 모래상자 하위 폴더 · def = 지정 안 한 출력의 max · over = 출력 id 별 값(날짜 · MISSING · CORRUPT · EMPTY · NODATE · TS:날짜)
$CASES = @(
  @{ id = 'A_U_lag'; book = 'Universe_Support'; def = $TD; over = @{ 'us_sector_lv2' = '2026-10-19' }; mode = 'b5'; b5 = '20261020'
     desc = 'Universe_Support 7개 목표일 · us_sector_lv2 만 10-19(11-06 실측형) -> B5=20261020 (구판 = done 으로 구멍)' }
  @{ id = 'B_I_lag'; book = 'Investor_Act'; def = $TD
     over = @{ 'investor_all[Foreign]' = '2026-10-30'; 'investor_all[Institutional]' = '2026-10-30'; 'investor_all[Individual]' = '2026-10-19'; 'investor_all[OtherCorp]' = '2026-10-19' }
     mode = 'b5'; b5 = '20261020'; desc = 'Investor_Act 외인/기관 10-30 · 개인/기타법인 10-19 -> B5=20261020 (구판 = 전체 max 로 20261031)' }
  @{ id = 'C_C_lag'; book = 'Consensus'; def = '2026-10-19'
     over = @{ 'coverage' = '2026-10-16'; 'esbr' = '2026-10-16'; 'escr' = '2026-10-16'; 'op_profit_fy1' = '2026-10-16'; 'revenue_fy1' = 'TS:2026-10-19' }
     mode = 'b5'; b5 = '20261017'; desc = 'Consensus 8지표 10-19 · 4지표 10-16(Date=timestamp 1개 섞음) -> B5=20261017 (구판 = eps_1y 로 20261020)' }
  @{ id = 'D_C_single'; book = 'Consensus'; def = $TD; over = @{ 'coverage' = '2026-10-16' }; mode = 'b5'; b5 = '20261017'
     desc = 'Consensus 11지표 목표일 · coverage 하나만 10-16 -> B5=20261017 (표에서 한 지표가 빠지면 done 으로 숨는다)' }
  @{ id = 'E_U_missing'; book = 'Universe_Support'; def = $TD; over = @{ 'us_float' = 'MISSING' }; mode = 'keep'
     desc = '[위반 주입] us_float.parquet 부재(나머지 목표일) -> keep · done 아님' }
  @{ id = 'F_I_grp_missing'; book = 'Investor_Act'; def = $TD; over = @{ 'investor_all[OtherCorp]' = 'MISSING' }; mode = 'keep'
     desc = '[위반 주입] investor_all 에 OtherCorp 행 0(나머지 목표일) -> keep · done 아님' }
  @{ id = 'G_C_corrupt'; book = 'Consensus'; def = $TD; over = @{ 'esbr' = 'CORRUPT' }; mode = 'keep'
     desc = '[위반 주입] esbr.parquet 깨짐 -> keep' }
  @{ id = 'H_C_empty'; book = 'Consensus'; def = $TD; over = @{ 'dps_1y' = 'EMPTY' }; mode = 'keep'
     desc = '[위반 주입] dps_1y.parquet 행 0 -> keep' }
  @{ id = 'I_C_nodate'; book = 'Consensus'; def = $TD; over = @{ 'sue' = 'NODATE' }; mode = 'keep'
     desc = '[위반 주입] sue.parquet Date 열 없음 -> keep' }
  @{ id = 'J_U_done'; book = 'Universe_Support'; def = $TD; over = @{}; mode = 'done'; b5 = '20261106'
     desc = '[양성] Universe_Support 8개 전부 목표일 -> done (cache already >= target)' }
  @{ id = 'K_C_boundary'; book = 'Consensus'; def = $TD; over = @{ 'eps_chg_3m' = '2026-11-04' }; mode = 'b5'; b5 = '20261105'
     desc = '[경계] 가장 뒤처진 출력 = 목표일 전날 -> B5 = 목표일(받는다 · done 아님)' }
  @{ id = 'L_B_done'; book = 'Benchmark'; def = $TD; over = @{}; mode = 'done'; b5 = '20261106'
     desc = 'Benchmark(출력 1개) 목표일 -> done (구판과 같은 동작 · B5 를 쓰지 않는다)' }
  @{ id = 'M_O_qwbase'; book = 'OHLCVS'; def = $TD; over = @{}; target = '20260101'; mode = 'b5'; b5 = '20260328'
     desc = 'OHLCVS = qw_base(달력 quantiwise max 03-27 +1) · 목표일보다 뒤여도 done 없음(구판 cache=null 과 같음)' }
  @{ id = 'Q_U_even'; book = 'Universe_Support'; def = '2026-10-30'; over = @{}; mode = 'b5'; b5 = '20261031'
     desc = '[양성] Universe_Support 8개 전부 10-30(목표일 전 · 뒤처진 출력 없음) -> B5=20261031' }
)
$CASE_BY_ID = @{}; foreach ($c in $CASES) { $CASE_BY_ID[$c.id] = $c }

# 그룹 판독 등가 사례(P) — rows = 파일 순서의 '날짜|그룹'(날짜 '' = 결측) · rg = 행 그룹 크기 · expect_rg = 픽스처 행 그룹 수(생성기가 단정)
#   rgread = 읽어야 하는 행 그룹 수(가지치기 고정) · 기대 결과는 이 시험이 rows 에서 직접 계산한다(Get-PExpect — 드라이버 · pyarrow 와 독립)
$GRP4 = @('Foreign', 'Institutional', 'Individual', 'OtherCorp')
$P1ROWS = @('2026-01-05|Foreign', '2026-01-05|Institutional', '2026-01-05|Individual', '2026-01-05|OtherCorp',
            '2026-10-14|OtherCorp', '2026-10-15|OtherCorp', '2026-10-16|OtherCorp', '2026-10-17|Individual',
            '2026-10-18|Individual', '2026-10-19|Individual', '2026-10-20|Foreign', '2026-10-21|Institutional',
            '2026-11-03|Foreign', '2026-11-04|Institutional', '2026-11-05|Foreign', '2026-11-05|Institutional')
$PCASES = [ordered]@{
  'P1_sorted'   = @{ rows = $P1ROWS; rg = 4; expect_rg = 4
                     desc = '그룹 판독 = 독립 기준 — 날짜순 행 그룹 4개 · 그룹마다 끝나는 행 그룹이 다름(기타법인 · 개인은 앞쪽에서 끝남)' }
  'P2_shuffled' = @{ rows = @('2026-01-02|Foreign', '2026-11-05|Individual', '2026-01-03|Institutional', '2026-01-04|OtherCorp',
                              '2026-05-01|Foreign', '2026-05-02|Institutional', '2026-05-03|Individual', '2026-05-04|OtherCorp',
                              '2026-10-01|Foreign', '2026-10-02|Institutional', '2026-10-03|Individual', '2026-10-04|OtherCorp')
                     rg = 4; expect_rg = 3; rgread = '2/3'
                     desc = '날짜 뒤섞인 행 그룹 3개(개인 최신일 11-05 가 첫 행 그룹에) -> 그 행 그룹까지 읽어 개인 11-05 · 2/3 읽음(가운데는 건너뜀)' }
  'P3_nostats'  = @{ rows = $P1ROWS; rg = 4; expect_rg = 4; stats = $false; rgread = '4/4'
                     desc = '통계 없는 파일(write_statistics=False) -> 가지치기 없이 4/4 읽고 P1 과 같은 결과' }
  'P4_ts_null'  = @{ rows = @('2026-11-05T15:30|Foreign', '|Institutional', '2026-10-19T09:00|Individual',
                              '2026-11-04T23:59|Institutional', '2026-10-16|OtherCorp', '|Foreign')
                     rg = 3; expect_rg = 2; ts = $true
                     desc = 'Date = timestamp + 결측 섞임 · 행 그룹 2개 -> 결측 무시 · 날짜 단위 max(외인 11-05 는 앞 행 그룹)' }
  'P5_absent'   = @{ rows = @('2026-11-05|Foreign', '2026-11-05|Institutional', '2026-10-19|Individual', '2026-10-01|Foreign'); rg = 2; expect_rg = 2
                     desc = '요청 그룹 하나(기타법인) 부재 -> 그 출력 empty · 나머지 ok' }
  'P6_nogrpcol' = @{ rows = @('2026-11-05|Foreign', '2026-11-04|Individual'); rg = 2; cols = @('Date')
                     desc = '그룹 열(InvestorType) 없는 파일 -> 4출력 모두 error(판단 불가 = keep 쪽)' }
  'P7_nodate'   = @{ rows = @('2026-11-05|Foreign', '2026-11-04|Individual'); rg = 2; cols = @('InvestorType')
                     desc = 'Date 열 없는 그룹 파일 -> 4출력 모두 error' }
  'P8_zero'     = @{ rows = @(); rg = 0
                     desc = '행 0 그룹 파일 -> 4출력 모두 empty' }
}

# 표 ↔ 적재기 · 파서 값 대조의 합성 사본(GV = 같은 값 · 다른 모양 → 통과 / GN = 값이 갈라짐 → target 만 실패 · why 가 사유에 있어야)
$GVARS = @(
  @{ id = 'GV1_shapes'; cons = 'c_lines'; meta = 'nested'; sheets = 'list_tuples'; map = 'c'; col = 'walrus_itype'
     desc = '같은 값 · 다른 모양 ① c() 줄바꿈 · 중첩 list() · 튜플 목록 · c() + := itype · 범위 밖 함수의 sheet_map 무시 -> G1~G3 통과' }
  @{ id = 'GV2_shapes'; cons = 'list_eq'; meta = 'oneline_eq'; sheets = 'tuple_comments'; map = 'list_eq'; col = 'dollar'
     desc = '같은 값 · 다른 모양 ② list() + = 대입 · 주석 속 가짜 대입 · 역따옴표 한글 이름 · 튜플 + 주석 · $<- 열 -> G1~G3 통과' }
  @{ id = 'GV3_shapes'; cons = 'c_arrow_kr'; meta = 'arrow'; sheets = 'annassign'; map = 'arrow'; col = 'walrus_map'
     desc = '같은 값 · 다른 모양 ③ -> 대입 · 한글 이름 · 주석 괄호 · 주석형 대입(SHEETS: list =) · 1차 판 모양 := sheet_map[[s]] -> G1~G3 통과' }
  @{ id = 'GV4_shapes'; cons = 'c_lines'; meta = 'nested'; sheets = 'list_tuples'; map = 'wrapped'; col = 'named_arg'
     desc = '같은 값 · 다른 모양 ④ 줄바꿈 · 주석 속 가짜 sheet_map · data.table(InvestorType = ) 이름 인수 -> G1~G3 통과' }
  @{ id = 'GV5_head_shape'; cons_body = 'src_parser'; univ_body = 'src_parser'
     desc = '같은 값 · 다른 모양 ⑤ HEAD 판 적재기 모양(정본 상수 대신 파서 파일을 source 하고 산출 파일 순회 · get("...META")) -> G1~G3 통과' }
  @{ id = 'GN1_cons_extra'; cons_add = 'new_metric'; target = 'G1'; why = 'new_metric'
     desc = '[위반 주입] 파서 지표 1개 추가(new_metric · 표엔 없음) -> G1 만 실패' }
  @{ id = 'GN2_univ_py_drop'; py_drop = $true; target = 'G2'; why = ''
     desc = '[위반 주입] SHEETS 에서 시트 1개 누락(R META 는 그대로) -> G2 만 실패' }
  @{ id = 'GN3_univ_r_rename'; um_ren = $true; target = 'G2'; why = '_x'
     desc = '[위반 주입] META cache_name 1개 이름 변경(_x) -> G2 만 실패' }
  @{ id = 'GN4_inv_extra'; inv_add = 'Pension'; target = 'G3'; why = 'Pension'
     desc = '[위반 주입] sheet_map 에 유형 추가(Pension) -> G3 만 실패' }
  @{ id = 'GN5_inv_col'; col = 'wrong'; target = 'G3'; why = 'col=False'
     desc = '[위반 주입] 열 이름 InvestorType -> Investor(범위 밖 함수엔 InvestorType := 남김) -> G3 만 실패(col=False)' }
  @{ id = 'GN6_inv_nonconst'; map = 'nonconst'; target = 'G3'; why = 'nonconst'
     desc = '[위반 주입] sheet_map = 함수 호출(평가하지 않는다) -> G3 만 실패(nonconst)' }
  @{ id = 'GN7_inv_nofn'; inv_file = 'investors.parquet'; target = 'G3'; why = 'fns=[]'
     desc = '[위반 주입] investor_all.parquet 을 쓰는 함수 없음(파일 이름 변경) -> G3 만 실패(fns=[])' }
  @{ id = 'GN8_inv_ambig'; map = 'ambig'; target = 'G3'; why = 'ambiguous'
     desc = '[위반 주입] 한 함수 안 sheet_map 대입 둘(값 다름) -> G3 만 실패(ambiguous)' }
  @{ id = 'GN9_cons_noref'; cons_body = 'noref'; target = 'G1'; why = 'loader_link=False'
     desc = '[위반 주입] 적재기가 CONSENSUS_METRICS 를 참조하지도 consensus_parser.R 을 부르지도 않음 -> G1 만 실패(loader_link=False)' }
  @{ id = 'GN10_univ_noref'; univ_body = 'noref'; target = 'G2'; why = 'loader_link=False'
     desc = '[위반 주입] 적재기가 META 를 참조하지도 파서 파일을 부르지도 않음 -> G2 만 실패(loader_link=False)' }
)
$GVAR_BY_ID = @{}; foreach ($g in $GVARS) { $GVAR_BY_ID[$g.id] = $g }

function Add-BookSpec($items, [string]$root, [string]$book, [string]$def, [hashtable]$over) {
  $tbl = @(New-QwBookTable $root)
  foreach ($b in $tbl) { [void]$items.Add(@{ kind = 'file'; path = $b.path }) }   # 책 xlsx 자리 = 빈 파일(Refresh-One 의 Test-Path 만 통과 · 열지 않는다)
  $bk = $tbl | Where-Object { $_.name -eq $book } | Select-Object -First 1
  $grp = @{}
  foreach ($o in @($bk.outputs)) {
    $v = if ($over.ContainsKey($o.id)) { $over[$o.id] } else { $def }
    if ($o.group_col) {
      if (-not $grp.ContainsKey($o.path)) { $grp[$o.path] = @{ kind = 'groups'; path = $o.path; group_col = $o.group_col; groups = @{} } }
      if ($v -ne 'MISSING') { $grp[$o.path].groups[$o.group] = $v }
    }
    elseif ($v -eq 'MISSING') { }
    elseif ($v -in @('CORRUPT', 'EMPTY', 'NODATE')) { [void]$items.Add(@{ kind = $v.ToLower(); path = $o.path }) }
    elseif ($v -like 'TS:*') { [void]$items.Add(@{ kind = 'dates'; path = $o.path; max = $v.Substring(3); ts = $true }) }
    else { [void]$items.Add(@{ kind = 'dates'; path = $o.path; max = $v; ts = $false }) }
  }
  foreach ($g in @($grp.Values)) { [void]$items.Add($g) }
}

function Invoke-AnchorCase($c, [string]$data) {
  if (-not $data) { $data = $c.id }
  $root = Join-Path $script:CASES_DIR $data
  $script:ROOT = $root
  $bk = @(New-QwBookTable $root) | Where-Object { $_.name -eq $c.book } | Select-Object -First 1
  if (-not $bk) { return @{ ok = $false; got = "book $($c.book) not in table" } }
  $tg = if ($c.target) { $c.target } else { $script:T }
  $a = Get-BookAnchor $bk $tg
  $ok = ("$($a.mode)" -eq $c.mode)
  if ($c.mode -eq 'keep') { $ok = $ok -and (-not $a.b5) } else { $ok = $ok -and ("$($a.b5)" -eq $c.b5) }
  return @{ ok = $ok; got = "mode=$($a.mode) b5=$($a.b5) | $($a.detail)" }
}

function Invoke-RCase([string]$data, [string]$book, [hashtable]$ovr, [string]$expRet, [string]$expLog, [string]$notLog = '') {
  $root = Join-Path $script:CASES_DIR $data
  $script:ROOT = $root
  $script:FROM_OVR = $ovr
  $script:HOSTLOG.Clear()
  try {
    $bk = @(New-QwBookTable $root) | Where-Object { $_.name -eq $book } | Select-Object -First 1
    $ret = Refresh-One $bk $script:T
  } finally { $script:FROM_OVR = @{} }
  $log = ($script:HOSTLOG -join ' || ')
  $ok = (("$ret" -eq $expRet) -and $log.Contains($expLog))
  if ($notLog) { $ok = $ok -and (-not $log.Contains($notLog)) }
  return @{ ok = $ok; got = "ret=$ret log=$log" }
}

function Same-Set($a, $b) { return ((@($a | Sort-Object) -join ',') -eq (@($b | Sort-Object) -join ',')) }
function Rel([string]$p) { return $p.Substring($script:VR.Length).TrimStart('\') }
function Tbl([string]$name) { return (@(New-QwBookTable $script:VR) | Where-Object { $_.name -eq $name } | Select-Object -First 1) }

# ---- P: 그룹 판독 등가 ----
function Get-PExpect($pc) {
  # 독립 기준 — 자료 행에서 그룹별 max 날짜(결측 제외 · 날짜 단위)를 직접 센다. 열이 없으면 error · 행이 없으면 empty
  $cols = if ($pc.cols) { @($pc.cols) } else { @('Date', 'InvestorType') }
  $e = @{}
  foreach ($g in $GRP4) {
    if (-not ($cols -contains 'Date') -or -not ($cols -contains 'InvestorType')) { $e[$g] = 'error'; continue }
    $ds = @(@($pc.rows) | ForEach-Object { $q = "$_" -split '\|', 2; if ($q[1] -eq $g -and $q[0]) { $q[0].Substring(0, 10).Replace('-', '') } } | Sort-Object)
    $e[$g] = if ($ds.Count -gt 0) { 'ok/' + $ds[-1] } else { 'empty' }
  }
  return $e
}
function Get-POuts([string]$id) {
  $path = Join-Path $script:PDIR "$id.parquet"
  return @($GRP4 | ForEach-Object { @{ id = "p[$_]"; path = $path; group_col = 'InvestorType'; group = $_ } })
}
function Invoke-PCase([string]$id) {
  $pc = $PCASES[$id]
  $rows = @(Get-OutputMaxes (Get-POuts $id))
  $exp = Get-PExpect $pc
  $act = @{}
  foreach ($r in $rows) {
    $g = $r.id.Substring(2, $r.id.Length - 3)
    $act[$g] = if ($r.status -eq 'ok') { "ok/$($r.ymd)" } elseif ("$($r.status)" -like 'error*') { 'error' } else { "$($r.status)" }
  }
  $ok = ($rows.Count -eq $GRP4.Count)
  foreach ($g in $GRP4) { if ("$($act[$g])" -ne "$($exp[$g])") { $ok = $false } }
  $rgGot = if ($rows.Count -gt 0) { "$($rows[0].rg)" } else { '' }
  if ($pc.rgread) { $ok = $ok -and ($rgGot -eq "$id.parquet $($pc.rgread)") }
  $got = 'exp=[' + (($GRP4 | ForEach-Object { "$_=$($exp[$_])" }) -join ' ') + '] got=[' + (($GRP4 | ForEach-Object { "$_=$($act[$_])" }) -join ' ') + "] rg=$rgGot"
  return @{ ok = $ok; got = $got }
}

# ---- G: 사실(R · python 추출기 결과) 조회와 값 대조 ----
function Fact([string]$id) { $f = $script:FACTS[$id]; if ($null -eq $f) { return @{ status = 'absent'; payload = '' } }; return $f }
function Fset([string]$id) { $f = Fact $id; if ($f.status -ne 'ok' -or -not $f.payload) { return @() }; return @("$($f.payload)" -split ',') }
function Fbool([string]$id) { $f = Fact $id; return ($f.status -eq 'ok' -and $f.payload -eq 'TRUE') }
function Test-G1([string]$tag) {
  $b = Tbl 'Consensus'
  $ids = @(@($b.outputs) | ForEach-Object { $_.id })
  $badp = @(@($b.outputs) | Where-Object { (Rel $_.path) -ne ".cache\consensus\$($_.id).parquet" } | ForEach-Object { $_.id })
  $src = Fset "$tag.cm"; $st = (Fact "$tag.cm").status; $str = Fbool "$tag.s_cons"
  # 적재기 ↔ 파서 연결 = 정본 상수를 참조하거나(F3 판 — metrics <- CONSENSUS_METRICS) 파서 파일을 부른다(HEAD 판 — source 후 산출 파일 순회).
  #   둘 중 하나면 적재기가 쓰는 지표 = 파서 지표다. 한쪽 모양만 요구하면 같은 값의 재작성에서 거짓 실패한다(1차 G3 의 교훈).
  $link = ((Fbool "$tag.ref_cm") -or (Fbool "$tag.s_cp"))
  return @{ ok = ($src.Count -gt 0 -and (Same-Set $ids $src) -and $badp.Count -eq 0 -and $link -and $str)
            got = "table=[$($ids -join ',')] parser($st)=[$($src -join ',')] badpath=[$($badp -join ',')] loader_link=$link(ref=$(Fbool "$tag.ref_cm") src=$(Fbool "$tag.s_cp")) loader_str=$str" }
}
function Test-G2([string]$tag) {
  $b = Tbl 'Universe_Support'
  $names = @(@($b.outputs) | ForEach-Object { $_.id -replace '^us_', '' })
  $badp = @(@($b.outputs) | Where-Object { (Rel $_.path) -ne ".cache\universe_support\$($_.id).parquet" -or $_.id -notlike 'us_*' } | ForEach-Object { $_.id })
  $py = Fset "$tag.sheets"; $pst = (Fact "$tag.sheets").status
  $rm = Fset "$tag.um"; $rst = (Fact "$tag.um").status
  $str = Fbool "$tag.s_us"
  $link = ((Fbool "$tag.ref_um") -or (Fbool "$tag.s_up") -or (Fbool "$tag.s_upy"))   # 정본 상수 참조 또는 파서 파일(R · python) 호출
  return @{ ok = ($py.Count -gt 0 -and $rm.Count -gt 0 -and (Same-Set $names $py) -and (Same-Set $names $rm) -and $badp.Count -eq 0 -and $link -and $str)
            got = "table=[$($names -join ',')] py($pst)=[$($py -join ',')] R($rst)=[$($rm -join ',')] badpath=[$($badp -join ',')] loader_link=$link loader_str=$str" }
}
function Test-G3([string]$tag) {
  $b = Tbl 'Investor_Act'
  $grps = @(@($b.outputs) | ForEach-Object { $_.group })
  $badp = @(@($b.outputs) | Where-Object { (Rel $_.path) -ne '.cache\investor_stock\investor_all.parquet' -or $_.group_col -ne 'InvestorType' } | ForEach-Object { $_.id })
  $ff = Fact "$tag.inv.fns"; $fns = "$($ff.payload)"; $fnOk = ($ff.status -eq 'ok' -and $fns -ne '')
  $src = Fset "$tag.inv.vals"; $vst = (Fact "$tag.inv.vals").status
  $col = Fbool "$tag.inv.col"; $dir = Fbool "$tag.s_inv"
  return @{ ok = ($fnOk -and $src.Count -gt 0 -and (Same-Set $grps $src) -and $col -and $badp.Count -eq 0 -and $dir)
            got = "table=[$($grps -join ',')] loader($vst)=[$($src -join ',')] fns=[$fns] col=$col badpath=[$($badp -join ',')] loader_dir=$dir" }
}
function Invoke-GVar($g) {
  $r = @{ G1 = (Test-G1 $g.id); G2 = (Test-G2 $g.id); G3 = (Test-G3 $g.id) }
  $sum = (@('G1', 'G2', 'G3') | ForEach-Object { "{0}={1}" -f $_, $(if ($r[$_].ok) { 'pass' } else { 'FAIL' }) }) -join ' '
  if (-not $g.target) { $ok = ($r.G1.ok -and $r.G2.ok -and $r.G3.ok) }
  else {
    $t = $r[$g.target]
    $others = @(@('G1', 'G2', 'G3') | Where-Object { $_ -ne $g.target -and -not $r[$_].ok })
    $ok = ((-not $t.ok) -and ((-not $g.why) -or "$($t.got)".Contains($g.why)) -and $others.Count -eq 0)
  }
  return @{ ok = $ok; got = "$sum || " + ((@('G1', 'G2', 'G3') | ForEach-Object { "$($_): $($r[$_].got)" }) -join ' || ') }
}

# ---- 합성 사본(GV · GN) 생성 — 값은 원본 표에서 뽑고(표가 바뀌면 따라간다) 모양만 바꾼다 ----
function Write-Utf8([string]$path, [string]$text) {
  $d = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Force -Path $d }
  [IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}
function Join-Lines($L) { return ((@($L) -join "`n") + "`n") }
function Gen-Cons([string]$shape, [string[]]$v) {
  $n = $v.Count; $L = [System.Collections.Generic.List[string]]::new()
  switch ($shape) {
    'c_lines' {
      $L.Add('CONSENSUS_METRICS <- c(')
      for ($i = 0; $i -lt $n; $i++) { $L.Add(('  "K{0}" = "{1}"{2}' -f $i, $v[$i], $(if ($i -lt $n - 1) { ',' } else { '' }))) }
      $L.Add(')')
    }
    'list_eq' {
      $L.Add('# 한 줄 · 괄호 ( 든 주석 · CONSENSUS_METRICS <- c("가짜" = "fake")')
      $L.Add('CONSENSUS_METRICS = list(' + ((0..($n - 1) | ForEach-Object { 'K{0} = "{1}"' -f $_, $v[$_] }) -join ', ') + ')')
    }
    'c_arrow_kr' {
      $L.Add('c(')
      for ($i = 0; $i -lt $n; $i++) {
        $sep = $(if ($i -lt $n - 1) { ',' } else { '' })
        if ($i % 2 -eq 0) { $L.Add(('  "가{0}" =   # 주석 ( 괄호' -f $i)); $L.Add(('    "{0}"{1}' -f $v[$i], $sep)) }
        else { $L.Add(('  `나{0}` = "{1}"{2}' -f $i, $v[$i], $sep)) }
      }
      $L.Add(') -> CONSENSUS_METRICS')
    }
  }
  return (Join-Lines $L)
}
function Gen-Meta([string]$shape, [string[]]$v) {
  $n = $v.Count; $L = [System.Collections.Generic.List[string]]::new()
  switch ($shape) {
    'nested' {
      $L.Add('UNIVERSE_SUPPORT_SHEET_META <- list(')
      for ($i = 0; $i -lt $n; $i++) {
        $L.Add(('  S{0} = list(' -f $i)); $L.Add(('    cache_name = "{0}",' -f $v[$i])); $L.Add('    value_type = "numeric"')
        $L.Add($(if ($i -lt $n - 1) { '  ),' } else { '  )' }))
      }
      $L.Add(')')
    }
    'oneline_eq' {
      $L.Add('UNIVERSE_SUPPORT_SHEET_META = list(' + ((0..($n - 1) | ForEach-Object { '`가{0}` = list(value_col = "X{0}", cache_name = "{1}")' -f $_, $v[$_] }) -join ', ') + ')')
    }
    'arrow' {
      $L.Add('list(' + ((0..($n - 1) | ForEach-Object { 'S{0} = list(cache_name = "{1}")' -f $_, $v[$_] }) -join ",`n     ") + ') -> UNIVERSE_SUPPORT_SHEET_META')
    }
  }
  return (Join-Lines $L)
}
function Gen-Sheets([string]$shape, [string[]]$v) {
  $n = $v.Count; $L = [System.Collections.Generic.List[string]]::new()
  switch ($shape) {
    'list_tuples' {
      $L.Add('SHEETS = [')
      for ($i = 0; $i -lt $n; $i++) { $L.Add(('    ("S{0}", "{1}", "C{0}", True),' -f $i, $v[$i])) }
      $L.Add(']')
    }
    'tuple_comments' {
      $L.Add('SHEETS = (  # (괄호 주석 · SHEETS = [("x", "fake")]')
      for ($i = 0; $i -lt $n; $i++) { $L.Add(('    (''가{0}'',' -f $i)); $L.Add(('     ''{0}'', ''C{1}'', False),  # )' -f $v[$i], $i)) }
      $L.Add(')')
    }
    'annassign' {
      $L.Add('SHEETS: list = [' + ((0..($n - 1) | ForEach-Object { '("S{0}", "{1}", "C{0}", True)' -f $_, $v[$_] }) -join ', ') + ']')
    }
  }
  return (Join-Lines $L)
}
function Gen-Map([string]$shape, [string[]]$v) {
  $n = $v.Count
  switch ($shape) {
    'c'        { return '  sheet_map <- c(' + ((0..($n - 1) | ForEach-Object { '"가{0}" = "{1}"' -f $_, $v[$_] }) -join ', ') + ')' }
    'list_eq'  { return '  sheet_map = list(' + ((0..($n - 1) | ForEach-Object { 'S{0} = "{1}"' -f $_, $v[$_] }) -join ', ') + ')' }
    'arrow'    { return '  c(' + ((0..($n - 1) | ForEach-Object { 'S{0} = "{1}"' -f $_, $v[$_] }) -join ', ') + ') -> sheet_map' }
    'wrapped'  {
      $L = [System.Collections.Generic.List[string]]::new()
      $L.Add('  sheet_map <- c(  # 주석 ( 괄호 · sheet_map <- c("가짜" = "Fake")')
      for ($i = 0; $i -lt $n; $i++) { $L.Add(('    "가{0}" =' -f $i)); $L.Add(('      "{0}"{1}' -f $v[$i], $(if ($i -lt $n - 1) { ',' } else { '' }))) }
      $L.Add('  )')
      return ($L -join "`n")
    }
    'nonconst' { return '  sheet_map <- .investor_sheets()' }
    'ambig'    { return (Gen-Map 'c' $v) + "`n  if (FALSE) " + (Gen-Map 'c' @($v | Select-Object -First ($n - 1))).TrimStart() }
  }
}
$LOADER_TPL = @'
## 합성 적재기(test_qw_refresh_anchor GV/GN 사본 · 값 대조 전용 · 실행하지 않는다)
incremental_consensus <- function() {
  d <- file.path(CACHE_DIR, "<CONS_DIR>")
  <CONS_BODY>
}
incremental_universe_support <- function(cache_dir = UNIVERSE_SUPPORT_CACHE) {
  <UNIV_BODY>
  sprintf("<US_FMT>", vapply(metas, function(m) m$cache_name, ""))
}
incremental_investor <- function(cache_dir = file.path(CACHE_DIR, "<INV_DIR>")) {
  all_file <- file.path(cache_dir, "<INV_FILE>")
<MAP>
  for (s in names(sheet_map)) {
    itype <- sheet_map[[s]]
    long <- dt[, j]
    <COL>
  }
  invisible(all_file)
}
## 범위 밖 함수 — <INV_FILE> 를 쓰지 않는다 → G3 는 여기 sheet_map · 열 생성을 보면 안 된다
.other_loader <- function() {
  sheet_map <- c("X" = "Zzz")
  long[, <INV_COL> := "Zzz"]
}
'@
$COLS = @{ walrus_itype = 'long[, <INV_COL> := itype]'; walrus_map = 'long[, <INV_COL> := sheet_map[[s]]]'; dollar = 'long$<INV_COL> <- itype'
           named_arg = 'long <- data.table(Date = long$Date, <INV_COL> = itype)'; wrong = 'long[, Investor := itype]' }
function Gen-Loader($g, [string[]]$iv) {
  $consBody = switch ("$($g.cons_body)") {
    'noref'      { 'for (m in c("eps_1y")) file.path(d, paste0(m, ".parquet"))' }
    'src_parser' { 'source(file.path(DATA_DIR, "consensus_parser.R")); consensus_build_cache(force = TRUE); for (tf in list.files(tmp_dir, pattern = "\\.parquet$", full.names = TRUE)) file.path(d, basename(tf))' }
    default      { 'for (m in unname(CONSENSUS_METRICS)) file.path(d, paste0(m, ".parquet"))' }
  }
  $univBody = switch ("$($g.univ_body)") {
    'noref'      { 'metas <- list()' }
    'src_parser' { 'if (!exists("UNIVERSE_SUPPORT_SHEET_META")) source(file.path(DATA_DIR, "parse_universe_support.R")); metas <- get("UNIVERSE_SUPPORT_SHEET_META")' }
    default      { 'metas <- UNIVERSE_SUPPORT_SHEET_META' }
  }
  $map = Gen-Map $(if ($g.map) { $g.map } else { 'c' }) $iv
  $col = $COLS[$(if ($g.col) { $g.col } else { 'walrus_itype' })]
  $invFile = if ($g.inv_file) { $g.inv_file } else { $script:TV.inv_file }
  $t = $LOADER_TPL.Replace('<CONS_BODY>', $consBody).Replace('<UNIV_BODY>', $univBody).Replace('<MAP>', $map).Replace('<COL>', $col)
  $t = $t.Replace('<CONS_DIR>', $script:TV.cons_dir).Replace('<US_FMT>', $script:TV.us_fmt).Replace('<INV_DIR>', $script:TV.inv_dir)
  return $t.Replace('<INV_FILE>', $invFile).Replace('<INV_COL>', $script:TV.inv_col)
}
function New-GVariant($g, [string]$root) {
  $d = Join-Path $root '02_Infrastructure\data'
  $cv = @($script:TV.cons | ForEach-Object { $_ }); if ($g.cons_add) { $cv += $g.cons_add }
  $pv = @($script:TV.us | ForEach-Object { $_ }); if ($g.py_drop) { $pv = @($pv | Select-Object -First ($pv.Count - 1)) }
  $uv = @($script:TV.us | ForEach-Object { $_ }); if ($g.um_ren) { $uv[0] = $uv[0] + '_x' }
  $iv = @($script:TV.inv | ForEach-Object { $_ }); if ($g.inv_add) { $iv += $g.inv_add }
  Write-Utf8 (Join-Path $d 'consensus_parser.R') (Gen-Cons $(if ($g.cons) { $g.cons } else { 'c_lines' }) $cv)
  Write-Utf8 (Join-Path $d 'parse_universe_support.R') (Gen-Meta $(if ($g.meta) { $g.meta } else { 'nested' }) $uv)
  Write-Utf8 (Join-Path $d 'us_update_stream_parse.py') (Gen-Sheets $(if ($g.sheets) { $g.sheets } else { 'list_tuples' }) $pv)
  Write-Utf8 (Join-Path $d 'incremental_update_file.R') (Gen-Loader $g $iv)
}
function Add-RepoJobs($rj, $pj, [string]$tag, [string]$root) {
  # 저장소(실물 · 합성 사본) 하나의 사실 작업 — 출력 이름 문자열은 원본 표에서 뽑은 값($script:TV)
  $d = Join-Path $root '02_Infrastructure\data'; $L = Join-Path $d 'incremental_update_file.R'
  [void]$rj.Add(("{0}.cm`ttop_values`t{1}`tCONSENSUS_METRICS" -f $tag, (Join-Path $d 'consensus_parser.R')))
  [void]$rj.Add(("{0}.um`ttop_field`t{1}`tUNIVERSE_SUPPORT_SHEET_META`tcache_name" -f $tag, (Join-Path $d 'parse_universe_support.R')))
  [void]$rj.Add(("{0}.inv`tfn_scope`t{1}`t{2}`tsheet_map`t{3}" -f $tag, $L, $script:TV.inv_file, $script:TV.inv_col))
  [void]$rj.Add(("{0}.ref_cm`tfile_sym`t{1}`tCONSENSUS_METRICS" -f $tag, $L))
  [void]$rj.Add(("{0}.ref_um`tfile_sym`t{1}`tUNIVERSE_SUPPORT_SHEET_META" -f $tag, $L))
  [void]$rj.Add(("{0}.s_cons`tfile_str`t{1}`t{2}" -f $tag, $L, $script:TV.cons_dir))
  [void]$rj.Add(("{0}.s_us`tfile_str`t{1}`t{2}" -f $tag, $L, $script:TV.us_fmt))
  [void]$rj.Add(("{0}.s_inv`tfile_str`t{1}`t{2}" -f $tag, $L, $script:TV.inv_dir))
  [void]$rj.Add(("{0}.s_cp`tfile_str`t{1}`tconsensus_parser.R" -f $tag, $L))
  [void]$rj.Add(("{0}.s_up`tfile_str`t{1}`tparse_universe_support.R" -f $tag, $L))
  [void]$rj.Add(("{0}.s_upy`tfile_str`t{1}`tus_update_stream_parse.py" -f $tag, $L))
  [void]$pj.Add(("{0}.sheets`t{1}`tSHEETS`t1" -f $tag, (Join-Path $d 'us_update_stream_parse.py')))
}
function Read-FactLines($lines, [string]$begin, [string]$endTag, [int]$n, [hashtable]$into) {
  # 시작 표지 · 끝 표지(작업 수 일치)가 있어야 결과를 믿는다 — 죽은 프로세스(출력 0 · 중간 사망)를 '사실 없음'으로 접지 않는다
  $b = $false; $e = $null
  foreach ($ln in @($lines)) {
    $s = "$ln".TrimEnd("`r", "`n")
    if ($s -eq $begin) { $b = $true; continue }
    if ($s.StartsWith("$endTag ")) { $e = $s.Substring($endTag.Length + 1).Trim(); continue }
    if ($b -and $s.StartsWith("F`t")) {
      $p = $s.Split("`t")
      if ($p.Count -ge 3) { $into[$p[1]] = @{ status = $p[2]; payload = $(if ($p.Count -ge 4) { $p[3] } else { '' }) } }
    }
  }
  if (-not $b) { return 'no_begin_marker' }
  if ("$e" -ne "$n") { return "end_marker_mismatch(end=$e jobs=$n)" }
  return 'ok'
}
function Get-RscriptCands {
  if ($env:QW_ANCHOR_RSCRIPT) { return @($env:QW_ANCHOR_RSCRIPT) }   # 지정하면 그것만(죽은 R 주입이 다른 R 로 조용히 넘어가지 않게)
  $c = [System.Collections.Generic.List[string]]::new()
  $gc = Get-Command Rscript.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($gc -and $gc.Source) { $c.Add($gc.Source) }
  if ($env:ProgramFiles) {
    foreach ($f in @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'R\R-*\bin\Rscript.exe') -ErrorAction SilentlyContinue |
        Sort-Object { $v = [version]'0.0'; [void][version]::TryParse(($_.FullName -replace '^.*\\R-([0-9.]+)\\bin\\.*$', '$1'), [ref]$v); $v } -Descending)) {
      if (-not $c.Contains($f.FullName)) { $c.Add($f.FullName) }
    }
  }
  return @($c)
}
function Invoke-RFacts([string]$rs) {
  # --vanilla(사이트 · 사용자 Renviron/Rprofile 무시) + R_ENVIRON_USER = 빈 파일(~/.Renviron QM_ROOT 덮어쓰기 회피 · 시험 규약)
  $saved = $env:R_ENVIRON_USER; $env:R_ENVIRON_USER = $script:EMPTY_RENV
  try { return @(& $rs --vanilla $script:RFACTS_PATH $script:RJOBS_PATH 2>&1 | ForEach-Object { "$_" }) }
  catch { return @("INVOKE_EXCEPTION $($_.Exception.Message)") }
  finally { if ($null -eq $saved) { Remove-Item Env:\R_ENVIRON_USER -ErrorAction SilentlyContinue } else { $env:R_ENVIRON_USER = $saved } }
}

$CHECK_DESC = [ordered]@{}
foreach ($c in $CASES) { $CHECK_DESC[$c.id] = $c.desc }
$CHECK_DESC['N1_PY_absent']      = '[계기 사망] python 경로 부재 -> 결과 줄 0 -> keep (전 출력 목표일 자료여도 done 으로 새지 않는다)'
$CHECK_DESC['N2_PY_dead']        = '[계기 사망] python 기동 실패(PYTHONHOME 오염 · 출력 0 · rc!=0) -> keep'
$CHECK_DESC['R1_done_ok']        = 'Refresh-One: 전 출력 목표일 -> ok + "-> done" (Excel 안 띄움)'
$CHECK_DESC['R2_lag_b5']         = 'Refresh-One: 뒤처진 출력 -> 시작줄 B5=20261020'
$CHECK_DESC['R3_missing_keep']   = 'Refresh-One: 출력 부재 -> done 아님 · 시작줄 B5=keep'
$CHECK_DESC['R3w_keep_warn']     = 'Refresh-One: keep -> WARN 줄(남은 B5 가 판단 불가 출력을 덮는다는 보장 없음 · 결정 사항)'
$CHECK_DESC['R4_override']       = 'Refresh-One: -FromOverride Universe_Support=20261030 이 done 보다 먼저 -> 시작줄 B5=20261030'
$CHECK_DESC['R5_override_other'] = 'Refresh-One: 다른 책 지정(Consensus=...)은 이 책 판정을 바꾸지 않는다 -> done'
$CHECK_DESC['R6_warn_lag']       = 'Refresh-One: 뒤처진 출력이 앵커를 붙잡음 -> WARN 줄에 뒤처진 출력 · 창 17일(B5 20261020 .. 목표 20261105)'
$CHECK_DESC['R7_no_warn_done']   = 'Refresh-One: done -> WARN 없음'
$CHECK_DESC['R8_no_warn_even']   = 'Refresh-One: 모든 출력이 같은 날(목표일 전) -> 시작줄 B5=20261031 · WARN 없음'
$CHECK_DESC['S1_order']          = '책 순서 = Benchmark,OHLCVS,Universe_Support,Investor_Act,Consensus (구판 $FILES 와 같음)'
$CHECK_DESC['S2_paths']          = '책 경로 = 구판과 같은 xlsx 5개'
$CHECK_DESC['S3_kinds']          = 'OHLCVS = qw_base(출력 0) · 나머지 = outputs(출력 >= 1)'
$CHECK_DESC['S4_bench_single']   = 'Benchmark 출력 = .cache\benchmark.parquet 하나(indices.parquet 미포함 — 전 이력 질의서 잘림 방지)'
$CHECK_DESC['S5_unique']         = '책마다 출력 id 중복 없음'
$CHECK_DESC['G1_consensus']      = '표 Consensus = consensus_parser.R CONSENSUS_METRICS 값(R 구문 분석) · 적재기가 그 정본을 참조하거나 파서를 부름 + "consensus" 출력 폴더 · 표 경로 .cache\consensus\<지표>.parquet'
$CHECK_DESC['G2_universe']       = '표 Universe = us_update_stream_parse.py SHEETS 2번째 칸(python ast) = parse_universe_support.R META cache_name(R) · 적재기가 META 참조 또는 파서 호출 + "us_%s.parquet" · 표 경로 us_<이름>.parquet'
$CHECK_DESC['G3_investor']       = '표 Investor 4그룹 = investor_all.parquet 을 쓰는 적재기 함수의 sheet_map 값(상수식 평가) · 그 함수가 InvestorType 열을 만든다 · "investor_stock" · 표 경로/그룹 열'
foreach ($k in @($PCASES.Keys)) { $CHECK_DESC[$k] = $PCASES[$k].desc }
$CHECK_DESC['P1r_pruned']        = '가지치기 실제 발생 — P1 에서 행 그룹 3/4 만 읽는다(맨 앞 행 그룹은 통계 max <= 4그룹 max 라 건너뜀)'
foreach ($g in $GVARS) { $CHECK_DESC[$g.id] = $g.desc }

function Invoke-Check([string]$id) {
  try {
    if ($CASE_BY_ID.ContainsKey($id)) { return Invoke-AnchorCase $CASE_BY_ID[$id] }
    if ($PCASES.Contains($id)) { return Invoke-PCase $id }
    if ($GVAR_BY_ID.ContainsKey($id)) { return Invoke-GVar $GVAR_BY_ID[$id] }
    switch ($id) {
      'N1_PY_absent' {
        $saved = $script:PY; $script:PY = Join-Path $script:SB 'no_such_dir\python.exe'
        try { return Invoke-AnchorCase @{ book = 'Universe_Support'; mode = 'keep' } 'J_U_done' } finally { $script:PY = $saved }
      }
      'N2_PY_dead' {
        $saved = $env:PYTHONHOME; $env:PYTHONHOME = Join-Path $script:SB 'no_such_home'
        try { return Invoke-AnchorCase @{ book = 'Universe_Support'; mode = 'keep' } 'J_U_done' } finally { $env:PYTHONHOME = $saved }
      }
      'R1_done_ok'        { return Invoke-RCase 'J_U_done' 'Universe_Support' @{} 'ok' '-> done' }
      'R2_lag_b5'         { return Invoke-RCase 'A_U_lag' 'Universe_Support' @{} 'skip' 'refresh start (B5=20261020' }
      'R3_missing_keep'   { return Invoke-RCase 'E_U_missing' 'Universe_Support' @{} 'skip' 'refresh start (B5=keep' }
      'R3w_keep_warn'     { return Invoke-RCase 'E_U_missing' 'Universe_Support' @{} 'skip' '[Universe_Support] WARN anchor keep' }
      'R4_override'       { return Invoke-RCase 'J_U_done' 'Universe_Support' @{ 'Universe_Support' = '20261030' } 'skip' 'refresh start (B5=20261030' }
      'R5_override_other' { return Invoke-RCase 'J_U_done' 'Universe_Support' @{ 'Consensus' = '20261019' } 'ok' '-> done' }
      'R6_warn_lag'       { return Invoke-RCase 'A_U_lag' 'Universe_Support' @{} 'skip' '[Universe_Support] WARN anchor held back by lagging outputs [us_sector_lv2=20261019] - window 17d (B5 20261020 .. target 20261105)' }
      'R7_no_warn_done'   { return Invoke-RCase 'J_U_done' 'Universe_Support' @{} 'ok' '-> done' 'WARN' }
      'R8_no_warn_even'   { return Invoke-RCase 'Q_U_even' 'Universe_Support' @{} 'skip' 'refresh start (B5=20261031' 'WARN' }
      'S1_order' {
        $n = (@(New-QwBookTable $script:VR) | ForEach-Object { $_.name }) -join ','
        return @{ ok = ($n -eq 'Benchmark,OHLCVS,Universe_Support,Investor_Act,Consensus'); got = $n }
      }
      'S2_paths' {
        $p = (@(New-QwBookTable $script:VR) | ForEach-Object { Rel $_.path }) -join ','
        $e = '03_Universe\Benchmark_price.xlsx,03_Universe\Update_File\OHLCVS_update.xlsx,03_Universe\Update_File\Universe_Support_update.xlsx,03_Universe\Update_File\Investor_Act_update.xlsx,03_Universe\Update_File\Consensus_update.xlsx'
        return @{ ok = ($p -eq $e); got = $p }
      }
      'S3_kinds' {
        $bad = @(@(New-QwBookTable $script:VR) | Where-Object {
          if ($_.name -eq 'OHLCVS') { -not ($_.anchor -eq 'qw_base' -and @($_.outputs).Count -eq 0) }
          else { -not ($_.anchor -eq 'outputs' -and @($_.outputs).Count -ge 1) } } | ForEach-Object { $_.name })
        return @{ ok = ($bad.Count -eq 0); got = "bad=[$($bad -join ',')]" }
      }
      'S4_bench_single' {
        $b = Tbl 'Benchmark'
        $ps = @(@($b.outputs) | ForEach-Object { Rel $_.path })
        return @{ ok = ($ps.Count -eq 1 -and $ps[0] -eq '.cache\benchmark.parquet'); got = ($ps -join ',') }
      }
      'S5_unique' {
        $dup = @(@(New-QwBookTable $script:VR) | Where-Object { $ids = @(@($_.outputs) | ForEach-Object { $_.id }); @($ids | Select-Object -Unique).Count -ne $ids.Count } | ForEach-Object { $_.name })
        return @{ ok = ($dup.Count -eq 0); got = "dup=[$($dup -join ',')]" }
      }
      'G1_consensus' { return Test-G1 'real' }
      'G2_universe'  { return Test-G2 'real' }
      'G3_investor'  { return Test-G3 'real' }
      'P1r_pruned' {
        $rows = @(Get-OutputMaxes (Get-POuts 'P1_sorted'))
        $rg = if ($rows.Count -gt 0) { "$($rows[0].rg)" } else { '' }
        return @{ ok = ($rg -eq 'P1_sorted.parquet 3/4'); got = "rg=$rg" }
      }
      default { return @{ ok = $false; got = "unknown check $id" } }
    }
  } catch { return @{ ok = $false; got = "exception: $($_.Exception.Message)" } }
}

# 뮤테이션 — old 는 소스에 정확히 1번 있어야 하고(치환 성사 단정), expect 의 검사가 **전부** 실패해야 검출로 센다
$MUTS = @(
  @{ id = 'M1'; old = '$lo = $sorted | Select-Object -First 1'; new = '$lo = $sorted | Select-Object -Last 1'
     expect = @('A_U_lag', 'B_I_lag', 'C_C_lag', 'D_C_single', 'R2_lag_b5'); desc = '가장 뒤처진 출력 -> 가장 앞선 출력(max+1)' }
  @{ id = 'M2'; old = '$bad = @($rows | Where-Object { $_.status -ne ''ok'' })'; new = '$bad = @()'
     expect = @('E_U_missing', 'F_I_grp_missing', 'G_C_corrupt', 'H_C_empty', 'I_C_nodate', 'R3_missing_keep'); desc = '판단 불가 출력을 버리고 남은 출력으로 min' }
  @{ id = 'M3'; old = '$rows = @(Get-OutputMaxes $f.outputs)'; new = '$rows = @(Get-OutputMaxes @($f.outputs)[0])'
     expect = @('A_U_lag', 'B_I_lag', 'C_C_lag', 'D_C_single'); desc = '책당 대표 출력 1개(구판 결함 재현)' }
  @{ id = 'M4'; old = 'if ([long]$b5 -gt [long]$target)'; new = 'if ([long]$b5 -ge [long]$target)'
     expect = @('K_C_boundary'); desc = '완료 경계 -gt -> -ge(목표일 당일을 받지 않음)' }
  @{ id = 'M5'; old = '"            v = r[0].get(g)",'; new = '"            v = max(r[0].values())",'
     expect = @('B_I_lag', 'F_I_grp_missing'); desc = '그룹 출력을 그룹 전체 max 로(구판 investor_all 결함 재현)' }
  @{ id = 'M6'; old = "'escr','esbr','coverage','op_profit_fy1'"; new = "'escr','esbr','op_profit_fy1'"
     expect = @('G1_consensus', 'D_C_single'); desc = '표에서 coverage 누락(파서와 갈라짐)' }
  @{ id = 'M7'; old = 'if ($FROM_OVR.ContainsKey($f.name)) {'; new = 'if ($false) {'
     expect = @('R4_override'); desc = '-FromOverride 무시' }
  @{ id = 'M8'; old = "} elseif (`$a.mode -eq 'done') {"; new = "} elseif (`$a.mode -ne 'b5') {"
     expect = @('R3_missing_keep'); desc = 'keep 이 done 으로 샘(판단 불가인데 받지 않음)' }
  @{ id = 'M9'; old = 'all(g in cur and rmax <= cur[g][0] for g in want)'; new = 'any(g in cur and rmax <= cur[g][0] for g in want)'
     expect = @('P1_sorted'); desc = '가지치기 조건 전부 -> 하나라도(아직 못 찾은 그룹이 있는데 건너뜀)' }
  @{ id = 'M10'; old = 'rmax = ymd(st.max) if'; new = 'rmax = ymd(st.min) if'
     expect = @('P2_shuffled'); desc = '가지치기 기준 통계 max -> min(날짜 뒤섞인 파일에서 늦은 날을 놓침)' }
  @{ id = 'M11'; old = 'for r in range(md.num_row_groups - 1, -1, -1):'; new = 'for r in range(md.num_row_groups - 1, md.num_row_groups - 2, -1):'
     expect = @('P1_sorted', 'P2_shuffled'); desc = '마지막 행 그룹만 읽음' }
  @{ id = 'M12'; old = 'if rmax is not None and all('; new = 'if rmax is None or all('
     expect = @('P3_nostats'); desc = '통계 없는 행 그룹을 건너뜀' }
  @{ id = 'M13'; old = 'for g in want): continue'; new = 'for g in want): pass'
     expect = @('P1r_pruned', 'P2_shuffled'); desc = '가지치기 꺼짐(전량 판독 회귀 · 결과는 같아도 읽은 행 그룹 수로 잡는다)' }
  @{ id = 'M14'; old = 'if ($a.warn) { Write-Host'; new = 'if ($false) { Write-Host'
     expect = @('R6_warn_lag', 'R3w_keep_warn'); desc = 'WARN 줄 출력 삭제' }
  @{ id = 'M15'; old = '.Days + 1'; new = '.Days'
     expect = @('R6_warn_lag'); desc = '창 일수 하루 모자람' }
  @{ id = 'M16'; old = 'if ($held) {'; new = 'if ($true) {'
     expect = @('R8_no_warn_even'); desc = '뒤처진 출력 없어도 WARN' }
)

$SB = Join-Path ([IO.Path]::GetTempPath()) ('qw_anchor_' + [guid]::NewGuid().ToString('N').Substring(0, 10))
$script:SB = $SB
$script:CASES_DIR = Join-Path $SB 'cases'
$script:PDIR = Join-Path $SB 'pcases'
$preflight = $null
try {
  $null = New-Item -ItemType Directory -Force -Path $script:CASES_DIR
  Say "== $TEST  src=$Src"
  Say "   sandbox=$SB"

  # ---- 사전 점검 1: python 기능 프로브(실행 가능 여부가 아니라 필요한 모듈 import) ----
  $cands = @((Join-Path $RepoRoot '.venv_qvest_ml\Scripts\python.exe'))
  if ($env:QM_ROOT) { $cands += (Join-Path $env:QM_ROOT '.venv_qvest_ml\Scripts\python.exe') }
  if ($env:QVEST_PY) { $cands += $env:QVEST_PY }
  foreach ($cand in $cands) {
    if (-not (Test-Path -LiteralPath $cand)) { continue }
    $o = & $cand -c "import pyarrow.parquet, pyarrow.compute, pandas; print('PROBE_OK')" 2>$null
    if ("$o" -match 'PROBE_OK') { $script:PY = $cand; break }
  }
  if (-not $script:PY) { $preflight = 'python_probe_failed(pyarrow/pandas import) candidates=' + ($cands -join ';') }

  # ---- 사전 점검 2: 함수 6개 추출(실제 소스) ----
  if (-not $preflight) {
    if (-not (Test-Path -LiteralPath $Src)) { $preflight = "src_absent $Src" }
    else {
      $ORIG = [IO.File]::ReadAllText($Src)
      $st = Import-Fns $ORIG
      if ($st -ne 'ok') { $preflight = "extract_failed $st" }
    }
  }

  # ---- 모래상자 자료 생성(원본 표 기준 · 한 번) + 사전 점검 3: 카나리아 판독 ----
  if (-not $preflight) {
    $items = [System.Collections.ArrayList]::new()
    foreach ($c in $CASES) { Add-BookSpec $items (Join-Path $script:CASES_DIR $c.id) $c.book $c.def $c.over }
    [void]$items.Add(@{ kind = 'calendar'; path = (Join-Path $script:CASES_DIR 'M_O_qwbase\.cache\trading_calendar.parquet')
                        rows = @('2026-03-26|quantiwise', '2026-03-27|quantiwise', '2026-03-30|benchmark') })
    foreach ($k in @($PCASES.Keys)) {
      $pc = $PCASES[$k]
      [void]$items.Add(@{ kind = 'grows'; path = (Join-Path $script:PDIR "$k.parquet"); group_col = 'InvestorType'; rows = @($pc.rows); rg_size = [int]$pc.rg
                          stats = $(if ($null -ne $pc.stats) { [bool]$pc.stats } else { $true }); ts = [bool]$pc.ts
                          cols = $(if ($pc.cols) { @($pc.cols) } else { @('Date', 'InvestorType') }); expect_rg = $pc.expect_rg })
    }
    $canary = Join-Path $SB 'canary\c.parquet'
    [void]$items.Add(@{ kind = 'dates'; path = $canary; max = '2026-10-19'; ts = $false })
    $specPath = Join-Path $SB 'spec.json'; $genPath = Join-Path $SB 'gen.py'
    [IO.File]::WriteAllText($specPath, (ConvertTo-Json -InputObject @($items) -Depth 8), [System.Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($genPath, $GEN_PY, [System.Text.UTF8Encoding]::new($false))
    $gen = @(& $script:PY $genPath $specPath 2>&1 | ForEach-Object { "$_" })
    if (-not (($gen -join ' ') -match 'GEN_OK')) { $preflight = 'sandbox_gen_failed: ' + (($gen | Select-Object -Last 3) -join ' / ') }
    else {
      $cr = @(Get-OutputMaxes @(@{ id = 'canary'; path = $canary }, @{ id = 'absent'; path = (Join-Path $SB 'canary\none.parquet') }))
      $cOk = ($cr.Count -eq 2 -and $cr[0].status -eq 'ok' -and $cr[0].ymd -eq '20261019' -and $cr[1].status -eq 'missing')
      if (-not $cOk) { $preflight = 'canary_failed: ' + (($cr | ForEach-Object { "$($_.id)=$($_.status)/$($_.ymd)" }) -join ' ') }
      else { Say "   preflight OK - python=$($script:PY) · 함수 6개 추출 · 자료 $($items.Count)건 · 카나리아 20261019/missing 판독" }
    }
  }

  # ---- 사전 점검 4: 사실 추출기(R · python) — 원본 표의 값 · 합성 사본 · 카나리아 → 한 번에 추출 ----
  if (-not $preflight) {
    $tc = Tbl 'Consensus'; $tu = Tbl 'Universe_Support'; $ti = Tbl 'Investor_Act'
    $o0 = @($ti.outputs)[0]
    $script:TV = @{
      cons = @(@($tc.outputs) | ForEach-Object { $_.id }); us = @(@($tu.outputs) | ForEach-Object { $_.id -replace '^us_', '' })
      inv = @(@($ti.outputs) | ForEach-Object { $_.group }); inv_col = "$($o0.group_col)"; inv_file = (Split-Path -Leaf $o0.path)
      inv_dir = (Split-Path -Leaf (Split-Path -Parent $o0.path)); cons_dir = (Split-Path -Leaf (Split-Path -Parent @($tc.outputs)[0].path))
      us_fmt = ((@($tu.outputs)[0].id -replace '^(us_).*$', '$1') + '%s.parquet')
    }
    $fdir = Join-Path $SB 'facts'; $null = New-Item -ItemType Directory -Force -Path $fdir
    $script:EMPTY_RENV = Join-Path $fdir 'empty.Renviron'; Write-Utf8 $script:EMPTY_RENV ''
    $script:RFACTS_PATH = Join-Path $fdir 'rfacts.R'; Write-Utf8 $script:RFACTS_PATH $RFACTS_R
    $pyFactsPath = Join-Path $fdir 'pyfacts.py'; Write-Utf8 $pyFactsPath $PYFACTS_PY
    $cR = Join-Path $fdir 'canary.R'; Write-Utf8 $cR $CANARY_R
    $cP = Join-Path $fdir 'canary.py'; Write-Utf8 $cP $CANARY_PY
    $rj = [System.Collections.ArrayList]::new(); $pj = [System.Collections.ArrayList]::new()
    [void]$rj.Add("canary.list`ttop_values`t$cR`tX_LIST"); [void]$rj.Add("canary.arrow`ttop_values`t$cR`tX_ARROW")
    [void]$rj.Add("canary.fn`tfn_scope`t$cR`tcanary_anchor.parquet`tm`tCOLX")
    [void]$rj.Add("canary.sym`tfile_sym`t$cR`tX_LIST"); [void]$rj.Add("canary.nosym`tfile_sym`t$cR`tNOPE_SYM")
    [void]$rj.Add("canary.str`tfile_str`t$cR`tcanary_anchor.parquet")
    [void]$pj.Add("canary.py`t$cP`tSHEETS`t1")
    Add-RepoJobs $rj $pj 'real' $RepoRoot
    foreach ($g in $GVARS) { $gr = Join-Path $SB ("grepo\" + $g.id); New-GVariant $g $gr; Add-RepoJobs $rj $pj $g.id $gr }
    $script:RJOBS_PATH = Join-Path $fdir 'rjobs.tsv'; Write-Utf8 $script:RJOBS_PATH (($rj -join "`n") + "`n")
    $pJobs = Join-Path $fdir 'pyjobs.tsv'; Write-Utf8 $pJobs (($pj -join "`n") + "`n")
    # python 사실(검증된 python · -I 격리)
    $pf = @{}
    $pst = Read-FactLines @(& $script:PY -I $pyFactsPath $pJobs 2>&1 | ForEach-Object { "$_" }) 'PYFACTS_BEGIN' 'PYFACTS_END' $pj.Count $pf
    # R 사실 — 후보마다 카나리아까지 맞아야 채택(죽은 R · 엉뚱한 R 은 다음 후보로 · QW_ANCHOR_RSCRIPT 지정 시 그것만)
    $whyR = @(); $rf = $null
    foreach ($rs in @(Get-RscriptCands)) {
      if (-not (Test-Path -LiteralPath $rs)) { $whyR += "absent:$rs"; continue }
      $f1 = @{}
      $rst = Read-FactLines (Invoke-RFacts $rs) 'RFACTS_BEGIN' 'RFACTS_END' $rj.Count $f1
      if ($rst -ne 'ok') { $whyR += "$rst@$rs"; continue }
      $bad = @($CANARY_EXPECT.Keys | Where-Object { $_ -ne 'canary.py' } | Where-Object { $x = $f1[$_]; -not $x -or ("{0}|{1}" -f $x.status, $x.payload) -ne $CANARY_EXPECT[$_] })
      if ($bad.Count -gt 0) { $whyR += ("canary@{0}: {1}" -f $rs, (($bad | ForEach-Object { $x = $f1[$_]; "$_=$(if ($x) { "$($x.status)|$($x.payload)" } else { 'absent' })" }) -join ' ')); continue }
      $rf = $f1; $script:RS = $rs; break
    }
    $pyCan = $pf['canary.py']
    if ($pst -ne 'ok') { $preflight = "pyfacts_failed: $pst" }
    elseif (-not $pyCan -or ("{0}|{1}" -f $pyCan.status, $pyCan.payload) -ne $CANARY_EXPECT['canary.py']) { $preflight = 'pyfacts_canary_failed: ' + $(if ($pyCan) { "$($pyCan.status)|$($pyCan.payload)" } else { 'absent' }) }
    elseif (-not $rf) { $preflight = 'rfacts_failed: ' + $(if ($whyR.Count) { $whyR -join ' ; ' } else { 'no Rscript candidate' }) }
    else {
      foreach ($k in $pf.Keys) { $script:FACTS[$k] = $pf[$k] }
      foreach ($k in $rf.Keys) { $script:FACTS[$k] = $rf[$k] }
      Say "   preflight OK - Rscript=$($script:RS) · 사실 R $($rj.Count)건 · python $($pj.Count)건 · 카나리아 $($CANARY_EXPECT.Count)건 일치 · 합성 사본 $($GVARS.Count)벌"
    }
  }

  if (-not $preflight) {
    # ---- 원본: 전 검사 ----
    Say '-- 원본 qw_refresh.ps1'
    foreach ($id in @($CHECK_DESC.Keys)) { $r = Invoke-Check $id; Mark ([bool]$r.ok) $id $CHECK_DESC[$id] $r.got }

    # ---- 뮤테이션 ----
    Say '-- 뮤테이션(소스 텍스트 치환 사본)'
    foreach ($m in $MUTS) {
      $cnt = ([regex]::Matches($ORIG, [regex]::Escape($m.old))).Count
      $mut = $ORIG.Replace($m.old, $m.new)
      if ($cnt -ne 1 -or $mut -eq $ORIG -or -not $mut.Contains($m.new)) { Mark $false "$($m.id)" "$($m.desc) - 치환 성사" "old 출현 $cnt 회(1 이어야 함)"; continue }
      $st = Import-Fns $mut
      if ($st -ne 'ok') { Mark $false "$($m.id)" "$($m.desc) - 사본 추출" $st; continue }
      $alive = @(); $detail = @()
      foreach ($id in $m.expect) { $r = Invoke-Check $id; if ($r.ok) { $alive += $id }; $detail += ("{0}:{1}" -f $id, $(if ($r.ok) { 'pass' } else { 'FAIL' })) }
      Mark ($alive.Count -eq 0) "$($m.id)" "$($m.desc) -> 검출 [$($detail -join ' ')]" "미검출(통과해 버린 검사) = $($alive -join ',')"
    }
    $st = Import-Fns $ORIG
    # 복원 확인(원본으로 되돌린 뒤 대표 사례 1건이 다시 통과)
    $r = Invoke-Check 'A_U_lag'
    Mark ([bool]($st -eq 'ok' -and $r.ok)) 'Z_restore' '뮤테이션 뒤 원본 함수 복원 -> A_U_lag 다시 통과' "$st / $($r.got)"
  }
} catch {
  $aborted = 'test_exception: ' + $_.Exception.Message
} finally {
  Remove-Item -LiteralPath $SB -Recurse -Force -ErrorAction SilentlyContinue
}

if ($preflight) {
  Say "  [PREFLIGHT] $preflight"
  Say ('{"test":"' + $TEST + '","pass":0,"fail":1,"preflight":"' + ($preflight -replace '[\\"]', '/' -replace '[\x00-\x1f]', ' ') + '"}')
  exit 1
}
# 계기 사망 가드 — 예외로 중단됐거나 검사가 한 건도 안 돌았으면 실패로 센다(pass=0 fail=0 을 성공으로 내지 않는다)
if (-not $aborted -and ($script:PASS + $script:FAIL) -eq 0) { $aborted = 'no_checks_ran' }
if ($aborted) { $script:FAIL++; Say "  [ABORT] $aborted" }
Say ("결과: PASS={0} FAIL={1}" -f $script:PASS, $script:FAIL)
Say ('{"test":"' + $TEST + '","pass":' + $script:PASS + ',"fail":' + $script:FAIL + '}')
if ($script:FAIL -gt 0) { exit 1 }
exit 0
