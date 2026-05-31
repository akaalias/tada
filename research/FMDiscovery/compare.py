#!/usr/bin/env python3
"""compare.py "<task>" — run the on-device model and cloud Claude Sonnet IN PARALLEL
on the same raw task, then print their seven clarifying questions side by side.
Questions only (no reasoning). Needs ANTHROPIC_API_KEY in the environment for the
cloud column. e.g.:  ./research/FMDiscovery/compare.py "train for a half marathon"
"""
import sys, os, re, subprocess, textwrap, shutil, pathlib, concurrent.futures

PKG = pathlib.Path(__file__).resolve().parent
# column width: fill the terminal — each row is "| <W> | <W> |" = 2*W + 7 chars
W = max(24, (shutil.get_terminal_size(fallback=(110, 24)).columns - 7) // 2)


def ask(agent, task):
    p = subprocess.run(["swift", "run", "--package-path", str(PKG), "fmresearch",
                        "inspect", task, "--agent", agent],
                       capture_output=True, text=True, env=os.environ)
    # parse only the "  N. <question>" lines (skip the indented description lines)
    return re.findall(r"^  \d+\.\s+(.*)$", p.stdout, re.M), p.stderr


def main():
    if len(sys.argv) < 2:
        sys.exit('usage: compare.py "<task>"')
    task = sys.argv[1]
    print(f'task: "{task}"  — running on-device + cloud in parallel…\n')
    subprocess.run(["swift", "build", "--package-path", str(PKG)],
                   capture_output=True, text=True)            # build once to avoid a race
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        f_dev = ex.submit(ask, "exp056", task)
        f_cloud = ex.submit(ask, "cloud_sonnet", task)
        dev, dev_err = f_dev.result()
        cloud, cloud_err = f_cloud.result()
    if not dev:
        print("on-device produced no questions:\n" + dev_err[-400:]);
    if not cloud:
        print("cloud produced no questions (API key set?):\n" + cloud_err[-400:])

    col = lambda i, s: textwrap.wrap(f"{i}. {s}", W, subsequent_indent="   ") or [f"{i}."]
    bar = "+" + "-" * (W + 2) + "+" + "-" * (W + 2) + "+"
    print(bar)
    print(f'| {"On-device · Apple FM 3B (exp056)":<{W}} | {"Cloud · Claude Sonnet 4.6":<{W}} |')
    print(bar)
    for i in range(7):
        L = col(i + 1, dev[i]) if i < len(dev) else [""]
        R = col(i + 1, cloud[i]) if i < len(cloud) else [""]
        for k in range(max(len(L), len(R))):
            l = L[k] if k < len(L) else ""
            r = R[k] if k < len(R) else ""
            print(f"| {l:<{W}} | {r:<{W}} |")
    print(bar)


if __name__ == "__main__":
    main()
