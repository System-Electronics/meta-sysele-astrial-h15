#!/usr/bin/env python3
"""Aggiorna il database CVE di Yocto dalle API ufficiali del NIST, fuori da una build.

Non riscrive la logica di poky: estrae da cve-update-nvd2-native.bb le funzioni che
scaricano e importano (update_db_file e quelle da cui dipende) e le esegue con un
finto datastore. Schema, contenuto e comportamento sono quelli di una build.

  nvd-update.py -r <ricetta.bb> -o <db>            incrementale se il db esiste, completo altrimenti
  nvd-update.py -r <ricetta.bb> -o <db> --full     scarica tutto in un file nuovo

Come poky, l'incrementale parte dalla data di modifica (mtime) del file. A differenza
di poky, a fine aggiornamento il mtime e' rimesso all'ISTANTE DI INIZIO della richiesta,
non a quello di fine: cosi' le modifiche pubblicate mentre l'aggiornamento girava
vengono riprese al giro dopo invece di andare perse.

L'aggiornamento lavora su una copia e sostituisce il file solo se e' andato a buon
fine e il database e' coerente: un NIST che si interrompe lascia intatto quello che c'era.
La ricetta va presa dalla stessa poky che poi legge il database.
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
            sys.exit(f"funzione {name} non trovata in {recipe}: la ricetta e' cambiata")
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
        # Migliaia di righe "has no configurations" e una per richiesta: non dicono nulla.
        note = staticmethod(lambda m: None if m.startswith("Requesting") or "no configurations" in m
                            else log("    " + m))
        warn = staticmethod(lambda m: log("    WARN " + m))
        error = staticmethod(lambda m: log("    ERROR " + m))
        debug = plain = staticmethod(lambda *a, **k: None)

    # update_db_file fa `import bb.utils, bb.progress`: serve un modulo vero in sys.modules.
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
    """Il minimo del datastore di bitbake che update_db_file legge."""
    def __init__(self, tmp, api_key):
        self.v = {
            "TMPDIR": tmp,
            "NVDCVE_URL": "https://services.nvd.nist.gov/rest/json/cves/2.0",
            "NVDCVE_API_KEY": api_key or "",
            "CVE_DB_UPDATE_ATTEMPTS": "5",
            "CVE_DB_INCR_UPDATE_AGE_THRES": "10368000",   # 120 giorni, il massimo del NIST
        }
    def getVar(self, k): return self.v.get(k)


def check(db, min_cve):
    c = sqlite3.connect(db)
    try:
        if c.execute("pragma integrity_check").fetchone()[0] != "ok":
            return "integrity_check non ok"
        n = c.execute("select count(*) from NVD").fetchone()[0]
        p = c.execute("select count(*) from PRODUCTS").fetchone()[0]
    finally:
        c.close()
    if n < min_cve:
        return f"solo {n} CVE (soglia {min_cve}): database incompleto"
    return f"{n} CVE, {p} righe prodotto"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-r", "--recipe", required=True)
    ap.add_argument("-o", "--out", type=pathlib.Path, required=True)
    ap.add_argument("--full", action="store_true", help="ignora il database esistente")
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
        log(f"incrementale da {datetime.datetime.fromtimestamp(database_time, datetime.timezone.utc):%FT%TZ}")
    else:
        log("download completo")

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
        sys.exit("aggiornamento fallito: il database precedente e' rimasto com'era")

    verdict = check(tmpdb, a.min_cve)
    if not re.match(r"^\d+ CVE", verdict):
        tmpdb.unlink(missing_ok=True)
        sys.exit(f"database scartato: {verdict}")

    os.utime(tmpdb, (start, start))
    os.replace(tmpdb, out)
    log(f"fatto: {out}  {out.stat().st_size/1048576:.0f} MB, {verdict}, in {time.time()-start:.0f} s")


if __name__ == "__main__":
    main()
