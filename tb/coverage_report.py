import gzip
import xml.etree.ElementTree as ET
from collections import defaultdict
import os

def build_file_id_map(metric='line'):
    """Build file_id -> source file name mapping."""
    shape_file = f'simv.cm.vdb/snps/coverage/db/shape/{metric}.verilog.shape.xml'

    file_id_to_bbsig = defaultdict(list)
    with gzip.open(shape_file, 'rb') as f:
        root = ET.fromstring(f.read().decode('utf-8', errors='replace'))

    if metric == 'line':
        for elem in root.iter('linebb'):
            fid = elem.get('file_id', '')
            lnum = elem.get('line_num', '')
            bbsig = elem.get('bbsig', '')
            ignore = elem.get('line_ignore', '0')
            if ignore != '1':
                file_id_to_bbsig[fid].append((lnum, bbsig))
    elif metric == 'branch':
        for elem in root.iter('branch_expr'):
            fid = elem.get('file_id', '')
            lnum = elem.get('true_clause_line', elem.get('false_clause_line', ''))
            expr = elem.get('exprstr', '')
            file_id_to_bbsig[fid].append((lnum, expr))
    elif metric == 'cond':
        for elem in root.iter('condspec'):
            fid = elem.get('file_id', '')
            lnum = elem.get('line_num', '')
            sig = elem.get('sig', '')
            file_id_to_bbsig[fid].append((lnum, sig))

    # Find source files
    rtl_dirs = ['../rtl', '../tb', '../lib']
    src_files = []
    for rtl_dir in rtl_dirs:
        if os.path.isdir(rtl_dir):
            for root_dir, dirs, files in os.walk(rtl_dir):
                for f in files:
                    if f.endswith(('.v', '.sv', '.svh', '.vh')):
                        src_files.append(os.path.join(root_dir, f))

    src_content = {}
    for sf in src_files:
        try:
            with open(sf, 'r', errors='replace') as f:
                src_content[sf] = f.readlines()
        except:
            pass

    file_id_to_filename = {}
    for fid in file_id_to_bbsig:
        entries = file_id_to_bbsig[fid][:5]
        for lnum, sig in entries:
            try:
                l = int(lnum)
            except:
                continue
            for sf, lines in src_content.items():
                if 0 < l <= len(lines):
                    line_content = lines[l-1].strip()
                    if sig.strip() and sig.strip() in line_content:
                        short_name = sf.replace('../', '').replace('\\', '/').split('/')[-1]
                        file_id_to_filename[fid] = short_name
                        break
            if fid in file_id_to_filename:
                break

    return file_id_to_filename


def parse_coverage(metric='line'):
    """Parse VCS coverage data for a given metric."""
    shape_file = f'simv.cm.vdb/snps/coverage/db/shape/{metric}.verilog.shape.xml'
    data_file = f'simv.cm.vdb/snps/coverage/db/testdata/test_all/{metric}.verilog.data.xml'

    file_map = build_file_id_map(metric)

    # Shape: group entries by parent def chksum
    chksum_to_entries = defaultdict(list)

    try:
        with gzip.open(shape_file, 'rb') as f:
            root = ET.fromstring(f.read().decode('utf-8', errors='replace'))

        if metric == 'line':
            for linedef in root.iter('linedef'):
                lchksum = linedef.get('chksum', '')
                for linebb in linedef.iter('linebb'):
                    ignore = linebb.get('line_ignore', '0')
                    if ignore != '1':
                        fid = linebb.get('file_id', '')
                        lnum = linebb.get('line_num', '')
                        chksum_to_entries[lchksum].append((fid, lnum))
        elif metric == 'branch':
            for branch_def in root.iter('branch_def'):
                bchksum = branch_def.get('chksum', '')
                # branch_expr entries represent individual branches to cover
                for expr in branch_def.iter('branch_expr'):
                    # Check for skip annotation on the parent branch_spec
                    # Each branch_expr has true/false, count as 2 entries
                    fid = expr.get('file_id', '')
                    lnum_t = expr.get('true_clause_line', '')
                    lnum_f = expr.get('false_clause_line', '')
                    chksum_to_entries[bchksum].append((fid, lnum_t, 'T'))
                    chksum_to_entries[bchksum].append((fid, lnum_f, 'F'))
        elif metric == 'cond':
            for conddef in root.iter('conddef'):
                cchksum = conddef.get('chksum', '')
                for condspec in conddef.iter('condspec'):
                    fid = condspec.get('file_id', '')
                    lnum = condspec.get('line_num', '')
                    # Check if monitored
                    is_monitored = any(
                        cs.get('line_num', '') == lnum
                        for cs in conddef.iter('expr_monitored')
                    ) or True  # Assume monitored if in condspec
                    chksum_to_entries[cchksum].append((fid, lnum))

    except Exception as e:
        print(f"Shape parse error ({metric}): {e}")
        return defaultdict(lambda: {'total': 0, 'covered': 0, 'lines': []})

    # Data: instance_data has bit strings
    stats = defaultdict(lambda: {'total': 0, 'covered': 0, 'lines': []})

    try:
        with gzip.open(data_file, 'rb') as f:
            root = ET.fromstring(f.read().decode('utf-8', errors='replace'))

        for inst in root.iter('instance_data'):
            chksum = inst.get('chksum', '')
            bits = inst.get('value', '')

            if chksum not in chksum_to_entries:
                continue

            entries = chksum_to_entries[chksum]
            for pos, entry in enumerate(entries):
                fid = entry[0]
                lnum = entry[1]
                fname = file_map.get(fid, f'unknown_{fid}')

                stats[fname]['total'] += 1
                if pos < len(bits) and bits[pos] == '1':
                    stats[fname]['covered'] += 1
                else:
                    stats[fname]['lines'].append(lnum)

    except Exception as e:
        print(f"Data parse error ({metric}): {e}")

    return stats


def print_report(stats, metric_name, filter_keywords=None):
    """Print formatted coverage report."""
    print()
    print("=" * 90)
    print(f"{metric_name:^90s}")
    print("=" * 90)
    print(f"{'File':<45s} {'Covered':>10s} {'Total':>8s} {'%':>8s}")
    print("-" * 90)

    files_sorted = sorted(stats.keys(), key=lambda x: (
        0 if (filter_keywords and
              any(k in x.lower() for k in filter_keywords))
        else 1, x
    ))

    total_all = 0
    covered_all = 0
    total_filtered = 0
    covered_filtered = 0
    shown = 0

    for fname in files_sorted:
        s = stats[fname]
        if s['total'] == 0:
            continue
        pct = (100.0 * s['covered'] / s['total']) if s['total'] > 0 else 0

        total_all += s['total']
        covered_all += s['covered']

        is_filtered = filter_keywords and any(k in fname.lower() for k in filter_keywords)
        if is_filtered:
            total_filtered += s['total']
            covered_filtered += s['covered']

        # Show ludp/fpga/testbench files or first 15
        should_show = (is_filtered or
                       'ludp' in fname.lower() or
                       'fpga' in fname.lower() or
                       'tb_' in fname.lower() or
                       shown < 15)

        if should_show:
            shown += 1
            marker = '  '
            print(f"{marker}{fname:<45s} {s['covered']:>10d} {s['total']:>8d} {pct:>8.1f}%")

    print("=" * 90)
    pct_all = (100.0 * covered_all / total_all) if total_all > 0 else 0
    print(f"{'OVERALL TOTAL':<45s} {covered_all:>10d} {total_all:>8d} {pct_all:>8.1f}%")

    if filter_keywords:
        pct_f = (100.0 * covered_filtered / total_filtered) if total_filtered > 0 else 0
        print(f"{'FILTERED (' + ','.join(filter_keywords) + ')':<45s} {covered_filtered:>10d} {total_filtered:>8d} {pct_f:>8.1f}%")
    print("=" * 90)

    # Uncovered lines for key files
    print()
    print(f"UNCOVERED LINES (ludp/fpga modules) - {metric_name}")
    print("=" * 90)

    for fname in sorted(stats.keys()):
        if ('ludp' in fname.lower() or 'fpga' in fname.lower()):
            s = stats[fname]
            if s['total'] > 0 and len(s['lines']) > 0:
                try:
                    lines = sorted(set(int(x) for x in s['lines'] if x.isdigit()))
                except:
                    continue
                ranges = []
                if lines:
                    start = lines[0]
                    prev = lines[0]
                    for l in lines[1:]:
                        if l - prev > 1:
                            ranges.append((start, prev))
                            start = l
                        prev = l
                    ranges.append((start, prev))

                pct = (100.0 * s['covered'] / s['total'])
                print(f"\n  {fname}: {len(s['lines'])}/{s['total']} uncovered ({pct:.1f}%):")
                line_strs = []
                for r in ranges[:30]:
                    if r[0] == r[1]:
                        line_strs.append(str(r[0]))
                    else:
                        line_strs.append(f"{r[0]}-{r[1]}")
                extra = f" (+{len(ranges)-30} more ranges)" if len(ranges) > 30 else ""
                print(f"    {', '.join(line_strs)}{extra}")
    print()


# ===== MAIN =====
print("=" * 90)
print(f"{'VCS COVERAGE REPORT':^90s}")
print("=" * 90)

line_stats = parse_coverage('line')
branch_stats = parse_coverage('branch')
cond_stats = parse_coverage('cond')

filter_kws = ['ludp', 'fpga', 'tb_']

print_report(line_stats, 'LINE COVERAGE', filter_kws)
print_report(branch_stats, 'BRANCH COVERAGE', filter_kws)
print_report(cond_stats, 'CONDITION COVERAGE', filter_kws)

# Overall summary
print()
print("=" * 90)
print("SUMMARY")
print("=" * 90)

def calc_overall(stats, keywords):
    t = sum(v['total'] for k, v in stats.items()
            if any(kw in k.lower() for kw in keywords))
    c = sum(v['covered'] for k, v in stats.items()
            if any(kw in k.lower() for kw in keywords))
    return c, t

for metric, stats in [('Line', line_stats), ('Branch', branch_stats), ('Condition', cond_stats)]:
    c_all = sum(v['covered'] for v in stats.values())
    t_all = sum(v['total'] for v in stats.values())
    p_all = (100.0 * c_all / t_all) if t_all > 0 else 0

    c_f, t_f = calc_overall(stats, filter_kws)
    p_f = (100.0 * c_f / t_f) if t_f > 0 else 0

    print(f"  {metric:>10s}: Overall {c_all}/{t_all} = {p_all:.1f}% | "
          f"ludp+fpga {c_f}/{t_f} = {p_f:.1f}%")

print("=" * 90)
