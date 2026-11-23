#!/usr/bin/env python3
"""build_sample.py -- build the sample subset.

Copies the first N epochs (default 100) of every diagnosis scenario folder
(Healthy + 42 single-fault + 46 multi-fault = 89 folders) from the release tree (the data root)
into <out dir>/Sample/, preserving the release layout (the multi-fault scenarios stay under their
DIAG_DualFault / DIAG_TripleFault / DIAG_QuadFault group folders), so Sample/ is a smaller mirror
of the diagnosis family. The output folder must be OUTSIDE the data root (default build);
the tool refuses otherwise, and never writes into the data root.

Standard library only.

The sample subset is the first 100 epochs of
all 89 scenarios, ~3.81 GB under a 5 GB ceiling, shipped as its
own archive. Severity balance ("exactly 20 per severity") is automatic ONLY
for the 42 single-fault scenarios, where severity is a shuffled permutation
per block of five epochs -- NOT for Healthy (no severity) or the 46
multi-fault combos (independent per-fault severity draws).
This script does not compute or claim severity balance; it
only copies files.

Usage:
    build_sample.py [--data-root PATH] [--out-dir PATH] [--epochs N] [--dry-run]
"""

import argparse
import os
import shutil
import sys

import release_naming as rn

# Naming scheme: scenario folders are DIAG_Healthy, DIAG_Fxx_<code>,
# DIAG_DualFault_<combo> / TripleFault_ / QuadFault_; files are DIAG_<token>_E####.h5 where <token> is
# Healthy / Fxx / the combo (so the file prefix is NOT the folder name). The fault codes come from
# <data root>/FaultReference/fault_catalogue.csv via release_naming.py -- nothing is hand-maintained.
# Sample/ mirrors the release layout: Sample/<rel_dir>/<file>, rel_dir as in release_naming.scenarios.

# Measured per-record size ( figures table, decimal MB).
MEASURED_MB_PER_RECORD = 0.3063

DEFAULT_EPOCHS = 100
DEFAULT_RTF_UNITS = 3  # first 3 units of each RTF mechanism, with their _refchecks.csv


def plan(data_root, out_dir, epochs):
    """Returns a list of (folder, epoch, src_path, dst_path)."""
    src_root = data_root
    dst_root = os.path.join(out_dir, "Sample")
    items = []
    for sc in rn.scenarios(data_root, "DIAG_"):
        for epoch in range(1, epochs + 1):
            fname = rn.diag_filename("DIAG_", sc["token"], epoch)
            items.append((
                sc["folder"], epoch,
                os.path.join(src_root, sc["rel_dir"], fname),
                os.path.join(dst_root, sc["rel_dir"], fname),
            ))
    return items


def plan_rtf(data_root, out_dir, units):
    """RTF part of the sample: (folder, unit, src, dst) for U0001..U<units> .h5 and _refchecks.csv."""
    dst_root = os.path.join(out_dir, "Sample")
    items = []
    for folder in rn.rtf_folders(data_root):
        fid = folder.split("_")[1]
        for u in range(1, units + 1):
            for suffix in (".h5", "_refchecks.csv"):
                fname = f"RTF_{fid}_U{u:04d}{suffix}"
                items.append((folder, u, os.path.join(data_root, folder, fname),
                              os.path.join(dst_root, folder, fname)))
    return items


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-root", default=None, help="the release tree, read-only here (default: $AVON_DATA_ROOT or config.txt)")
    ap.add_argument("--out-dir", default=None, help="output folder OUTSIDE the data root; Sample/ is created inside it (default: build)")
    ap.add_argument("--epochs", type=int, default=DEFAULT_EPOCHS, help=f"epochs per scenario (default {DEFAULT_EPOCHS})")
    ap.add_argument("--rtf-units", type=int, default=DEFAULT_RTF_UNITS, help=f"RTF units per mechanism (default {DEFAULT_RTF_UNITS}; 0 = diagnosis only)")
    ap.add_argument("--dry-run", action="store_true", help="list what would be copied and the projected size; copy nothing")
    args = ap.parse_args()

    data_root = rn.resolve_data_root(args.data_root)
    out_dir = rn.resolve_out_dir(args.out_dir, data_root)
    items = plan(data_root, out_dir, args.epochs)
    if args.rtf_units > 0:
        items += plan_rtf(data_root, out_dir, args.rtf_units)

    print(f"Data root:        {data_root}")
    print(f"Source:            {data_root}  (DIAG_* folders)")
    print(f"Destination:       {os.path.join(out_dir, 'Sample')}")
    print(f"Scenario folders:  {len(rn.scenarios(data_root, 'DIAG_'))} (Healthy + 42 single + 46 multi)")
    print(f"Epochs/scenario:   {args.epochs}")
    print(f"Planned files:     {len(items)}")
    print()
    print("Note: 'exactly 20 per severity' is true for the 42")
    print("single-fault scenarios only, not for Healthy or the 46 multi-fault combos.")
    print()

    found = 0
    missing = 0
    copied = 0
    skipped_existing = 0
    found_bytes = 0

    for folder, epoch, src, dst in items:
        exists = os.path.isfile(src)
        if exists:
            found += 1
            found_bytes += os.path.getsize(src)
        else:
            missing += 1
            continue

        if args.dry_run:
            continue

        if os.path.isfile(dst) and os.path.getsize(dst) == os.path.getsize(src):
            skipped_existing += 1
            continue

        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1

    projected_mb = (
        (found_bytes / (1024 * 1024)) if found_bytes > 0
        else (len(items) * MEASURED_MB_PER_RECORD)
    )
    projected_gb = projected_mb / 1024
    basis = "measured (files found on disk)" if found_bytes > 0 else "projected (0.3063 MB/record -- no source files found yet)"

    print(f"Source files found:    {found} / {len(items)}")
    print(f"Source files missing:  {missing}")
    print(f"Projected size:        {projected_gb:.3f} GB  [{basis}]")

    if args.dry_run:
        print("\n--dry-run: nothing copied.")
        return 0

    print(f"Copied:                {copied}")
    print(f"Skipped (already present, same size): {skipped_existing}")
    if missing:
        print(f"\nWARNING: {missing} source file(s) not found -- Sample/ is partial "
              f"until the diagnosis family finishes generating those records.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
