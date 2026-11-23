#!/usr/bin/env python3
"""release_naming.py -- the release's naming grammar, shared by zip_release.py and build_sample.py.

Release layout (2026-11-23; must match GenerateScenarioInfo.m / RTFUnitPath.m). The data root IS
the release tree:

    <root>/DIAG_Healthy/DIAG_Healthy_E0001.h5
    <root>/DIAG_F01_<code>/DIAG_F01_E0001.h5                         (42 single-fault folders)
    <root>/DIAG_DualFault/DIAG_DualFault_F01F05/DIAG_F01F05_E0001.h5 (DIAG_TripleFault/, DIAG_QuadFault/)
    <root>/RTF_F02_<code>/RTF_F02_U0001.h5 (+ RTF_F02_U0001_refchecks.csv)
    <root>/DiagnosisTurndown/TD_Healthy/..., TD_F01_<code>/..., TD_DualFault_F01F05/TD_F01F05_E100001.h5
                                         (turndown multi-fault folders are NOT grouped)

One zip per top-level folder of the root: 60 archives (see top_level_entries) plus Sample.zip.

The fault <code> tokens and the RTF membership are NOT hand-maintained here: they are read from
fault_catalogue.csv (columns fault_id, code, rtf_member), the naming source of truth that ships with
the code at <repo>/FaultReference/fault_catalogue.csv (fallback: <data root>/FaultReference/). The 46 multi-fault combinations are not
in the catalogue (they come from GetFaultDefinitions.m / multifault_design_output.txt) so they stay as
a table below, asserted for shape against the catalogue's fault ids.

Standard library only.
"""

import csv
import os

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
RELEASE_ROOT = os.path.dirname(os.path.dirname(TOOLS_DIR))   # repository root (tools/release/ -> two levels up)

DUAL_COMBOS = [
    "F01F05", "F02F26", "F03F32", "F04F19", "F06F42", "F07F40", "F08F16",
    "F09F25", "F10F41", "F11F17", "F12F30", "F13F18", "F14F22", "F15F21",
    "F20F37", "F23F36", "F24F38", "F27F33", "F28F35", "F29F39", "F31F34",
]
TRIPLE_COMBOS = [
    "F01F20F36", "F02F32F37", "F03F22F34", "F04F19F38", "F05F10F41",
    "F06F27F29", "F07F17F39", "F08F16F28", "F09F25F40", "F11F15F23",
    "F12F14F30", "F13F18F42", "F21F24F35", "F26F31F33",
]
QUAD_COMBOS = [
    "F01F06F20F34", "F02F05F20F37", "F03F10F32F41", "F04F07F16F17",
    "F08F12F14F28", "F09F16F33F40", "F11F15F21F35", "F13F19F30F39",
    "F18F27F31F42", "F22F23F25F36", "F24F26F29F38",
]
assert (len(DUAL_COMBOS), len(TRIPLE_COMBOS), len(QUAD_COMBOS)) == (21, 14, 11)
MULTI_FAULT_COMBOS = DUAL_COMBOS + TRIPLE_COMBOS + QUAD_COMBOS

# Loose (unzipped) upload files: name -> (config.txt key, default path relative to repository root/).
# fault_catalogue.csv and MANIFEST.csv are resolved from the data root instead (see loose_files).
LOOSE_CONFIG_KEYS = {
    "README.md": ("AVON_README_PATH", os.path.join("upload_extras", "README.md")),
    "Avon_Dataset_Description.pdf": ("AVON_DESCRIPTION_PDF_PATH", os.path.join("upload_extras", "Avon_Dataset_Description.pdf")),
    "channel_dictionary.csv": ("AVON_CHANNEL_DICT_PATH", os.path.join("upload_extras", "channel_dictionary.csv")),
}


def read_config():
    """config.txt as a dict (KEY=VALUE, '#' comments). Environment variables override it."""
    cfg = {}
    path = os.path.join(RELEASE_ROOT, "config.txt")
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() and v.strip():
                    cfg[k.strip()] = v.strip()
    for k in list(cfg) + [v[0] for v in LOOSE_CONFIG_KEYS.values()] + ["AVON_DATA_ROOT", "AVON_RELEASE_OUT_DIR"]:
        if os.environ.get(k):
            cfg[k] = os.environ[k]
    return cfg


def resolve_data_root(cli_value=None):
    """--data-root, else $AVON_DATA_ROOT, else AVON_DATA_ROOT in config.txt."""
    if cli_value:
        return os.path.abspath(cli_value)
    value = read_config().get("AVON_DATA_ROOT")
    if not value:
        raise SystemExit("AVON_DATA_ROOT is not set: pass --data-root, set the environment variable, "
                         "or put AVON_DATA_ROOT=... in config.txt.")
    return os.path.abspath(value)


CODE_CATALOGUE = os.path.join(RELEASE_ROOT, "FaultReference", "fault_catalogue.csv")


def fault_catalogue_path(data_root):
    """The code tree's catalogue (the data root, being a pure release tree, does not carry one);
    falls back to <data root>/FaultReference/ if the catalogue is not in the repository."""
    if os.path.isfile(CODE_CATALOGUE):
        return CODE_CATALOGUE
    return os.path.join(data_root, "FaultReference", "fault_catalogue.csv")


def resolve_out_dir(cli_value, data_root):
    """Where zips (<out>/zips) and the sample (<out>/Sample) are written: --out-dir, else
    $AVON_RELEASE_OUT_DIR / config.txt, else build. Refuses any location inside (or
    equal to) the data root, which may be read-only and must stay a pure release tree."""
    out = cli_value or read_config().get("AVON_RELEASE_OUT_DIR") or os.path.join(RELEASE_ROOT, "build")
    out = os.path.abspath(out)
    dr = os.path.normcase(os.path.abspath(data_root)).rstrip("\/")
    o = os.path.normcase(out).rstrip("\/")
    if o == dr or o.startswith(dr + os.sep):
        raise SystemExit(f"Refusing to write inside the data root: out dir {out} is within {data_root}. "
                         "Pass --out-dir outside the data root (default: build).")
    return out


def load_fault_catalogue(data_root):
    """fault_catalogue.csv -> list of 42 dict rows (fault_id 'F01'.., code, rtf_member 'yes'/'no', ...)."""
    path = fault_catalogue_path(data_root)
    if not os.path.isfile(path):
        raise SystemExit(f"fault_catalogue.csv not found: {path}")
    with open(path, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 42, f"fault_catalogue.csv must have 42 rows, got {len(rows)}"
    assert [r["fault_id"] for r in rows] == [f"F{n:02d}" for n in range(1, 43)], "fault_catalogue.csv rows out of order"
    for combo in MULTI_FAULT_COMBOS:
        for i in range(0, len(combo), 3):
            assert combo[i:i + 3] in {r["fault_id"] for r in rows}, f"combo {combo} names an unknown fault"
    return rows


def combo_group(combo):
    return {2: "DualFault", 3: "TripleFault", 4: "QuadFault"}[len(combo) // 3]


def combo_folder(combo):
    return f"{combo_group(combo)}_{combo}"


def scenarios(data_root, prefix):
    """The 89 diagnosis-shaped scenarios, in canonical order, as dicts:
    {folder (with prefix), token (file stem token), kind: healthy|single|dual|triple|quad,
     rel_dir: folder path relative to the family root -- for the DIAG_ family the multi-fault
     folders sit under their group folder (DIAG_DualFault/DIAG_DualFault_F01F05); TD_ is flat}."""
    rows = load_fault_catalogue(data_root)
    out = [{"folder": f"{prefix}Healthy", "token": "Healthy", "kind": "healthy", "rel_dir": f"{prefix}Healthy"}]
    for r in rows:
        f = f"{prefix}{r['fault_id']}_{r['code']}"
        out.append({"folder": f, "token": r["fault_id"], "kind": "single", "rel_dir": f})
    for kind, combos in (("dual", DUAL_COMBOS), ("triple", TRIPLE_COMBOS), ("quad", QUAD_COMBOS)):
        for c in combos:
            f = f"{prefix}{combo_folder(c)}"
            rel = f if prefix == "TD_" else f"{prefix}{combo_group(c)}/{f}"
            out.append({"folder": f, "token": c, "kind": kind, "rel_dir": rel})
    assert len(out) == 89
    return out


def rtf_folders(data_root):
    rows = load_fault_catalogue(data_root)
    out = [f"RTF_{r['fault_id']}_{r['code']}" for r in rows if r["rtf_member"] == "yes"]
    assert len(out) == 13, f"expected 13 RTF mechanisms in the catalogue, got {len(out)}"
    return out


def top_level_entries(data_root):
    """The 60 top-level folders of the release root, each of which is exactly one zip
    (<name>.zip, with <name>/ as the top-level entry): DIAG_Healthy, 42 DIAG_Fxx_<code>,
    DIAG_DualFault, DIAG_TripleFault, DIAG_QuadFault, 13 RTF_Fxx_<code>, DiagnosisTurndown.
    Dicts: name, family, scenarios (list of scenario/mechanism folder names inside it)."""
    diag = scenarios(data_root, "DIAG_")
    out = [{"name": "DIAG_Healthy", "family": "Diagnosis", "scenarios": ["DIAG_Healthy"]}]
    for s in diag:
        if s["kind"] == "single":
            out.append({"name": s["folder"], "family": "Diagnosis", "scenarios": [s["folder"]]})
    for kind, grp in (("dual", "DIAG_DualFault"), ("triple", "DIAG_TripleFault"), ("quad", "DIAG_QuadFault")):
        out.append({"name": grp, "family": "Diagnosis",
                    "scenarios": [s["folder"] for s in diag if s["kind"] == kind]})
    for folder in rtf_folders(data_root):
        out.append({"name": folder, "family": "RunToFailure", "scenarios": [folder]})
    out.append({"name": "DiagnosisTurndown", "family": "DiagnosisTurndown",
                "scenarios": [s["folder"] for s in scenarios(data_root, "TD_")]})
    assert len(out) == 60, len(out)
    return out


def diag_filename(prefix, token, epoch):
    return f"{prefix}{token}_E{epoch:04d}.h5"


def loose_files(data_root, zips_dir):
    """The loose (unzipped) upload files: list of (name, absolute path, how_resolved)."""
    cfg = read_config()
    out = []
    for name, (key, default_rel) in LOOSE_CONFIG_KEYS.items():
        p = cfg.get(key) or os.path.join(RELEASE_ROOT, default_rel)
        if not os.path.isabs(p):
            p = os.path.join(RELEASE_ROOT, p)
        out.append((name, os.path.abspath(p), key))
    out.append(("fault_catalogue.csv", os.path.abspath(fault_catalogue_path(data_root)), "<repo>/FaultReference"))
    out.append(("MANIFEST.csv", os.path.abspath(os.path.join(zips_dir, "MANIFEST.csv")), "written by zip_release"))
    return out
