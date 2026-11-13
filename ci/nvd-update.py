#!/usr/bin/env python3
"""Update Yocto's CVE database from the official NIST API, outside of a build.

Does not reimplement poky's logic: it extracts the download/import functions
(update_db_file and the ones it depends on) from cve-update-nvd2-native.bb and
runs them with a fake datastore. Schema, content, and behavior match a build's.

  nvd-update.py -r <recipe.bb> -o <db>          incremental if the db exists, full otherwise
  nvd-update.py -r <recipe.bb> -o <db> --full   download everything into a new file

Like poky, the incremental update starts from the file's mtime. Unlike poky,
at the end the mtime is set back to the START of the request, not the end:
so any changes published while the update was running get picked up on the
next run instead of being lost.

The update works on a copy and replaces the file only if it succeeded and the
database is consistent: a NIST outage leaves the previous database untouched.
The recipe must come from the same poky that will read the database.
"""
import argparse, datetime, json, os, pathlib, re, shutil, sqlite3, sys, tempfile, time, types

FUNCS = ("nvd_request_wait", "nvd_request_next", "update_db_file",
         "initialize_db", "parse_node_and_insert", "update_db")


def load(recipe, log):
    lines = pathlib.Path(recipe).read_text().split("\n")
    out = []
    for name in FUNCS:
        try:
            i = next(n for n, l in enumerate(lines) if l.startswith(f"def {name}("))
        except StopIteration:
            sys.exit(f"function {name} not found in {recipe}: the recipe has changed")
        j = i + 1
        while j < len(lines) and (lines[j].startswith((" ", "\t")) or not lines[j].strip()):
            j += 1
        out.append("\n".join(lines[i:j]))

    class PH:
        def __init__(self, d): self.last = -10
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def update(self, pct):
            if pct - self.last >= 10:
                self.last = pct
                log(f"    {pct:5.1f}%")

    class _bb:
        class progress:
            ProgressHandler = PH
        class utils:
            @staticmethod
            def mkdirhier(p): os.makedirs(p, exist_ok=True)
        # Thousands of "has no configurations" lines and one per request: noise.
        note = staticmethod(lambda m: None if m.startswith("Requesting") or "no configurations" in m
                            else log("    " + m))
        warn = staticmethod(lambda m: log("    WARN " + m))
        error = staticmethod(lambda m: log("    ERROR " + m))
        debug = plain = staticmethod(lambda *a, **k: None)

    # update_db_file does `import bb.utils, bb.progress`: needs a real module in sys.modules.
    mod = types.ModuleType("bb")
    for k, v in vars(_bb).items():
        if not k.startswith("__"):
            setattr(mod, k, v)
    for sub in ("utils", "progress"):
        m = types.ModuleType(f"bb.{sub}")
        for k, v in vars(getattr(_bb, sub)).items():
            if not k.startswith("__"):
                setattr(m, k, v)
        setattr(mod, sub, m)
        sys.modules[f"bb.{sub}"] = m
    sys.modules["bb"] = mod
    _bb = mod

    ns = {"sqlite3": sqlite3, "json": json, "datetime": datetime, "os": os,
          "time": time, "bb": _bb}
    exec("\n".join(out), ns)
    return ns


class Data:
    """The minimal bitbake datastore that update_db_file reads."""
    def __init__(self, tmp, api_key):
        self.v = {
            "TMPDIR": tmp,
            "NVDCVE_URL": "https://services.nvd.nist.gov/rest/json/cves/2.0",
            "NVDCVE_API_KEY": api_key or "",
            "CVE_DB_UPDATE_ATTEMPTS": "5",
            "CVE_DB_INCR_UPDATE_AGE_THRES": "10368000",   # 120 days, NIST's maximum
        }
    def getVar(self, k): return self.v.get(k)


def check(db, min_cve):
    c = sqlite3.connect(db)
    try:
        if c.execute("pragma integrity_check").fetchone()[0] != "ok":
            return "integrity_check not ok"
        n = c.execute("select count(*) from NVD").fetchone()[0]
        p = c.execute("select count(*) from PRODUCTS").fetchone()[0]
    finally:
        c.close()
    if n < min_cve:
        return f"only {n} CVEs (threshold {min_cve}): database incomplete"
    return f"{n} CVE, {p} product rows"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-r", "--recipe", required=True)
    ap.add_argument("-o", "--out", type=pathlib.Path, required=True)
    ap.add_argument("--full", action="store_true", help="ignore the existing database")
    ap.add_argument("--api-key-file", type=pathlib.Path)
    ap.add_argument("--min-cve", type=int, default=300000)
    a = ap.parse_args()

    def log(m): print(time.strftime("%F %T"), m, flush=True)

    api_key = a.api_key_file.read_text().strip() if a.api_key_file else None
    fns = load(a.recipe, log)

    out = a.out
    out.parent.mkdir(parents=True, exist_ok=True)
    start = time.time()
    database_time = 0
    if out.exists() and not a.full:
        database_time = os.path.getmtime(out)
        log(f"incremental from {datetime.datetime.fromtimestamp(database_time, datetime.timezone.utc):%FT%TZ}")
    else:
        log("full download")

    tmpdb = out.with_name(out.name + ".updating")
    for p in (tmpdb, tmpdb.with_name(tmpdb.name + "-journal")):
        p.unlink(missing_ok=True)
    if database_time:
        shutil.copy2(out, tmpdb)

    with tempfile.TemporaryDirectory() as td:
        d = Data(td, api_key)
        ok = fns["update_db_file"](str(tmpdb), d, database_time)
    if ok is not True:
        tmpdb.unlink(missing_ok=True)
        sys.exit("update failed: the previous database was left untouched")

    verdict = check(tmpdb, a.min_cve)
    if not re.match(r"^\d+ CVE", verdict):
        tmpdb.unlink(missing_ok=True)
        sys.exit(f"database discarded: {verdict}")

    os.utime(tmpdb, (start, start))
    os.replace(tmpdb, out)
    log(f"done: {out}  {out.stat().st_size/1048576:.0f} MB, {verdict}, in {time.time()-start:.0f} s")


if __name__ == "__main__":
    main()
