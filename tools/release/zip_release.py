#!/usr/bin/env python3
"""zip_release.py -- build the release zips (release naming scheme).

The Zenodo layout: exactly ONE zip per top-level folder of the release root (60 archives), plus
Sample.zip, plus the loose files. Each zip is named <folder>.zip and holds that folder as its
top-level entry:

  DIAG_Healthy.zip                          DIAG_Healthy/...
  DIAG_Fxx_<code>.zip          x 42         DIAG_Fxx_<code>/...
  DIAG_DualFault.zip                        DIAG_DualFault/DIAG_DualFault_<combo>/...  (21 scenarios)
  DIAG_TripleFault.zip                      (14)
  DIAG_QuadFault.zip                        (11)
  RTF_Fxx_<code>.zip           x 13         RTF_Fxx_<code>/...
  DiagnosisTurndown.zip                     DiagnosisTurndown/TD_<...>/...         (89 scenarios, flat)
  Sample.zip                                Sample/<same layout as the release>/<file>

Zips and the sample are written to an OUTPUT folder outside the data root (default build:
<out>/zips/*.zip + MANIFEST.csv, <out>/Sample/); the tool refuses an output folder inside the data
root, which may be read-only. There is NO Code.zip: the code is released on GitHub.

Loose (unzipped) upload files: README.md, the dataset-description PDF, fault_catalogue.csv,
channel_dictionary.csv (paths configurable in config.txt: AVON_README_PATH,
AVON_DESCRIPTION_PDF_PATH, AVON_CHANNEL_DICT_PATH) and MANIFEST.csv, which this script writes
(one row per zip: zip_name, family, scenarios, record_count, bytes, sha256). A missing loose file
is a WARNING in --list mode and a hard error in the uploader.

Fault codes and the RTF membership are read from <repo>/FaultReference/fault_catalogue.csv
(see release_naming.py), not hand-maintained. Standard library only.

Default compression is ZIP_DEFLATED (measured ~25 % of raw on real pipeline HDF5); --stored forces
ZIP_STORED, --measure re-checks the ratio on a real folder.

Usage:
    zip_release.py --list [--data-root D] [--out-dir O]   # print the catalogue + loose files, build nothing
    zip_release.py                              # build every zip (resumable)
    zip_release.py --only "RTF_*"                # build a subset (fnmatch glob on zip name)
    zip_release.py --measure PATH_TO_FOLDER      # compare STORED vs DEFLATED on real data
"""

import argparse
import csv
import fnmatch
import hashlib
import json
import os
import sys
import tempfile
import time
import zipfile

import release_naming as rn

TOOLS_DIR = rn.TOOLS_DIR
RELEASE_ROOT = rn.RELEASE_ROOT


# ---------------------------------------------------------------------------
# Catalogue
# ---------------------------------------------------------------------------

def build_zip_catalog(data_root, out_dir, include_turndown=True):
    """List of dicts: zip_name, family, scenarios (scenario/mechanism folders inside the zip),
    base (directory the archive paths are relative to), source_subdirs (relative to base). One
    entry per top-level folder of the data root (60), then Sample.zip, whose base is the output
    folder (the sample is built there, never inside the data root)."""
    cat = []
    for e in rn.top_level_entries(data_root):
        if e["name"] == "DiagnosisTurndown" and not include_turndown:
            continue
        cat.append({"zip_name": f"{e['name']}.zip", "family": e["family"], "scenarios": e["scenarios"],
                    "base": data_root, "source_subdirs": [e["name"]]})
    cat.append({"zip_name": "Sample.zip", "family": "Sample", "scenarios": ["Sample"],
                "base": out_dir, "source_subdirs": ["Sample"]})
    return cat


# ---------------------------------------------------------------------------
# Zip building
# ---------------------------------------------------------------------------

def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(16 * 1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def iter_files(root_dir, arc_base):
    """Yield (full_path, arcname) for every file under root_dir; arcname is relative to arc_base
    with forward slashes (so it starts at the family folder when arc_base is the data root)."""
    for dirpath, _dirnames, filenames in os.walk(root_dir):
        for fn in sorted(filenames):
            full = os.path.join(dirpath, fn)
            yield full, os.path.relpath(full, arc_base).replace(os.sep, "/")


def entry_files(entry):
    """All (full, arc) pairs for a catalogue entry, and the list of missing source folders."""
    files, missing = [], []
    for sub in entry["source_subdirs"]:
        d = os.path.join(entry["base"], sub)
        if not os.path.isdir(d):
            missing.append(d)
            continue
        files.extend(iter_files(d, entry["base"]))
    return files, missing


def existing_zip_matches_source(zip_path, files):
    """Resumability: does an existing zip hold exactly these files (count + total bytes)?"""
    if not os.path.isfile(zip_path) or not files:
        return False
    src_bytes = sum(os.path.getsize(f) for f, _ in files)
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            infos = zf.infolist()
            return len(infos) == len(files) and sum(i.file_size for i in infos) == src_bytes
    except zipfile.BadZipFile:
        return False


def build_one_zip(zip_path, files, method):
    tmp_path = zip_path + ".partial"
    with zipfile.ZipFile(tmp_path, "w", compression=method) as zf:
        for full, arc in files:
            zf.write(full, arcname=arc)
    os.replace(tmp_path, zip_path)
    return len(files), os.path.getsize(zip_path), sha256_of(zip_path)


# ---------------------------------------------------------------------------
# --measure
# ---------------------------------------------------------------------------

def measure_compression(folder):
    folder = os.path.abspath(folder)
    if not os.path.isdir(folder):
        print(f"Not a directory: {folder}")
        return 1
    files = list(iter_files(folder, folder))
    if not files:
        print(f"No files found under {folder}")
        return 1
    raw_total = sum(os.path.getsize(f) for f, _ in files)
    with tempfile.TemporaryDirectory() as td:
        res = {}
        for label, method, kw in (("STORED", zipfile.ZIP_STORED, {}), ("DEFLATED", zipfile.ZIP_DEFLATED, {"compresslevel": 6})):
            p = os.path.join(td, label + ".zip")
            t0 = time.time()
            with zipfile.ZipFile(p, "w", compression=method, **kw) as zf:
                for full, arc in files:
                    zf.write(full, arcname=arc)
            res[label] = (os.path.getsize(p), time.time() - t0)
    ratio = res["DEFLATED"][0] / res["STORED"][0] if res["STORED"][0] else float("nan")
    print(f"Folder:          {folder}\nFiles:           {len(files)}\nRaw bytes:       {raw_total}")
    print(f"STORED   zip:    {res['STORED'][0]} bytes  ({res['STORED'][1]:.2f}s)")
    print(f"DEFLATED zip:    {res['DEFLATED'][0]} bytes  ({res['DEFLATED'][1]:.2f}s)")
    print(f"Deflate / stored ratio: {ratio:.6f}  ({(1 - ratio) * 100:+.2f} % size change vs stored)")
    print("RESULT: deflate wins by more than 10% -- default should be DEFLATED for this data."
          if (1 - ratio) * 100 > 10 else "RESULT: deflate does NOT win by more than 10% -- STORED default stands.")
    return 0


# ---------------------------------------------------------------------------
# release_files.py (read by the uploaders)
# ---------------------------------------------------------------------------

def write_release_files_module(existing_names, loose, zips_dir, out_path, catalog_total):
    lines = [
        '"""release_files.py -- AUTO-GENERATED by tools/release/zip_release.py (or .ps1). Do not hand-edit.',
        "",
        "RELEASE_FILES: the zips that ACTUALLY EXIST in ZIPS_DIR as of the last zip_release run",
        f"(--list included), so the uploader never queues a zip that is not there yet. The full catalogue",
        f"is {catalog_total} archives; run 'zip_release --list' to see it.",
        "LOOSE_FILES: the unzipped upload files (name -> absolute path), whether or not they exist yet;",
        "the uploader FAILS in upload mode if any is missing.",
        '"""',
        "",
        f"ZIPS_DIR = {json.dumps(zips_dir)}",
        "",
        f"RELEASE_FILES = {json.dumps(existing_names, indent=4)}",
        "",
        f"LOOSE_FILES = {json.dumps({n: p for n, p, _ in loose}, indent=4)}",
        "",
    ]
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def regenerate_release_files(catalog_full, loose, zips_dir, release_files_path):
    existing = [c["zip_name"] for c in catalog_full if os.path.isfile(os.path.join(zips_dir, c["zip_name"]))]
    if not os.path.isdir(os.path.dirname(release_files_path)):
        return existing   # no UploadToZenodo folder in this tree: there is no uploader to feed
    write_release_files_module(existing, loose, zips_dir, release_files_path, len(catalog_full))
    return existing


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-root", default=None, help="the release tree (DIAG_*, RTF_*, DiagnosisTurndown directly inside it); read-only here (default: $AVON_DATA_ROOT or config.txt)")
    ap.add_argument("--out-dir", default=None, help="output folder OUTSIDE the data root (default: $AVON_RELEASE_OUT_DIR, config.txt, else build); zips go to <out>/zips")
    ap.add_argument("--list", action="store_true", help="print the full catalogue and loose files and exit; build nothing")
    ap.add_argument("--only", default=None, help="fnmatch glob on zip name, e.g. 'RTF_*'")
    ap.add_argument("--no-turndown", action="store_true", help="exclude DiagnosisTurndown.zip from the catalogue")
    ap.add_argument("--stored", action="store_true", help="use ZIP_STORED instead of ZIP_DEFLATED")
    ap.add_argument("--measure", default=None, metavar="FOLDER", help="compare STORED vs DEFLATED on a real folder; build nothing else")
    args = ap.parse_args()

    if args.measure:
        return measure_compression(args.measure)

    data_root = rn.resolve_data_root(args.data_root)
    out_dir = rn.resolve_out_dir(args.out_dir, data_root)
    zips_dir = os.path.join(out_dir, "zips")
    full_catalog = build_zip_catalog(data_root, out_dir, include_turndown=True)
    catalog = build_zip_catalog(data_root, out_dir, include_turndown=not args.no_turndown)
    if args.only:
        catalog = [c for c in catalog if fnmatch.fnmatch(c["zip_name"], args.only)]
    loose = rn.loose_files(data_root, zips_dir)
    release_files_path = os.path.join(RELEASE_ROOT, "UploadToZenodo", "release_files.py")
    existing_now = regenerate_release_files(full_catalog, loose, zips_dir, release_files_path)

    if args.list:
        print(f"Data root: {data_root}")
        print(f"Out dir:   {out_dir}")
        print(f"Zips dir:  {zips_dir}")
        print(f"Archives in CATALOGUE: {len(catalog)}")
        by_family = {}
        for c in catalog:
            by_family[c["family"]] = by_family.get(c["family"], 0) + 1
        for fam, n in by_family.items():
            print(f"  {fam}: {n}")
        for c in catalog:
            print(f"  [zip]   {c['zip_name']}  ({len(c['scenarios'])} folder(s))")
        print(f"Loose files: {len(loose)}")
        n_missing = 0
        for name, path, how in loose:
            ok = os.path.isfile(path)
            n_missing += (not ok)
            print(f"  [loose] {name}  <- {path}  [{how}]" + ("" if ok else "   WARNING: NOT FOUND"))
        print(f"TOTAL catalogue entries: {len(catalog) + len(loose)} ({len(catalog)} archives + {len(loose)} loose files)")
        if n_missing:
            print(f"WARNING: {n_missing} loose file(s) missing -- the uploader will refuse to upload until they exist.")
        print(f"\n{len(existing_now)} zip(s) found on disk (of {len(full_catalog)} in the full catalogue)")
        return 0

    method = zipfile.ZIP_STORED if args.stored else zipfile.ZIP_DEFLATED
    os.makedirs(zips_dir, exist_ok=True)
    manifest_path = os.path.join(zips_dir, "MANIFEST.csv")
    manifest_rows = []
    built = skipped = missing_source = 0

    for entry in catalog:
        zip_name = entry["zip_name"]
        zip_path = os.path.join(zips_dir, zip_name)
        files, missing = entry_files(entry)
        if missing or not files:
            missing_source += 1
            print(f"[skip] {zip_name}: source not found ({len(missing)} missing folder(s), e.g. {missing[0] if missing else 'no files'})")
            continue
        if existing_zip_matches_source(zip_path, files):
            skipped += 1
            print(f"[skip-exists] {zip_name}  size={os.path.getsize(zip_path)}")
        else:
            n, size, digest = build_one_zip(zip_path, files, method)
            built += 1
            print(f"[built] {zip_name}  files={n}  size={size}  sha256={digest[:12]}...")
        manifest_rows.append({
            "zip_name": zip_name, "family": entry["family"],
            "scenarios": len(entry["scenarios"]) if entry["family"] != "Sample" else len(rn.scenarios(data_root, "DIAG_")),
            "record_count": sum(1 for _, arc in files if arc.endswith(".h5")),
            "bytes": os.path.getsize(zip_path), "sha256": sha256_of(zip_path),
        })

    with open(manifest_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["zip_name", "family", "scenarios", "record_count", "bytes", "sha256"])
        w.writeheader()
        w.writerows(manifest_rows)

    regenerate_release_files(full_catalog, loose, zips_dir, release_files_path)
    print(f"\nBuilt: {built}  Skipped (already correct): {skipped}  Missing source: {missing_source}")
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
