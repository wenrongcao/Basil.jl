# Basil.jl — a thin Julia wrapper for basil_jll

## Context

[basil](https://github.com/greg-houseman/basil) is a 2-D finite-element viscous-flow
code (Houseman, Barr & Evans) written in Fortran 77 + C. It has been packaged as a
binary artifact **basil_jll v1.8.2** via Yggdrasil (PR #14172), which ships **nine
`ExecutableProduct`s** (`basil`, `sybilps`, `xpoly`, `polyfix`, `selvect`, `mdcomp`,
`basinv`, `circles`, `corotate`) for 14 platforms. The interactive X11 GUI `sybil`
is deliberately **not** in the JLL.

Goal: a thin wrapper package **Basil.jl** that makes it easy, from Julia, to

1. build/prepare basil input files,
2. run the solver, and
3. read the binary solution files and visualize results natively in Julia
   (plus drive the bundled `sybilps` for classic PostScript figures).

## Key architectural fact (differs from FastScape.jl)

FastScape.jl wraps **Fastscapelib_jll**, which exposes a *shared library*
(`libfastscapelib`), so FastScape.jl `ccall`s Fortran routines in-process and
exchanges arrays directly. **basil_jll exposes only executables — no
`LibraryProduct`** — so Basil.jl must:

- run `basil` as a **subprocess** (via `basil_jll.basil()`, which handles
  `LD_LIBRARY_PATH`/`libgfortran` setup automatically), and
- exchange data through **files**: ASCII keyword input files in, Fortran
  unformatted binary solution files (`FD.sols/<name>`) out.

This is the classic "driver wrapper" pattern (like Ipopt's AmplNLWriter, or
Gnuplot.jl). It is robust and requires no changes to the Fortran code, at the cost
of file I/O per run. In-process `ccall` would require re-engineering basil into a
library in Yggdrasil first (future work, out of scope).

## basil facts the wrapper relies on (verified in /home/wenrongc/basil)

- **Invocation** (`basilsrc/basmain.c:118-183`): `basil FILE [FILE2 …]`; with no
  args it reads filenames from `basil.in`; `basil -v` prints version.
- **Working directory contract**: CWD must contain `FD.sols/` and `FD.out/`
  before the run; solution binary goes to `FD.sols/<BIN>` (BIN defaults to the
  input filename), ASCII log to `FD.out/<BIN>.out`, optional time series to
  `FD.out/<BIN>.dat`. All quantities are dimensionless.
- **Input format** (`basilsrc/input.f`, `input.parameters`): ASCII, one UPPERCASE
  keyword command per line with `KEY=value` pairs, `&` continuation, `#` comment;
  BC lines like `ON Y = 0.0 FOR X = 0.0 TO 0.25 : UY = 1.0`. Templates:
  `examples/indenter/INn3A0`, `examples/tibet/JF1.1`.
- **Output format** (`basilsrc/r4write.f`, subroutine `WRITERECORD`; reference
  reader `sybilsrc/sybfile.c` + index constants `sybilsrc/data.h`):
  gfortran **unformatted sequential** records, all 4-byte data, one group of
  records per saved timestep:

  | # | record contents | size |
  |---|-----------------|------|
  | 1 | NAMEW(16), NDATE(16), NAMER(16), COMMEN(80) chars | 128 B |
  | 2 | IVARS — 64 × Int32 | 256 B |
  | 3 | RVARS — 64 × Float32 | 256 B |
  | 4 | LEM(6,NE), NOR(NUP), IBC(NBP), IBNGH(NBP2), IBCTYP(NBP2) — Int32 |
  | 5 | EX(NUP), EY(NUP), UVP(NUVP), QBND(NBP2) — Float32 |
  | 6* | if ICR≠0: IELFIX(NUP) Int32; then SSQ(NUP), FROT(NUP) Float32 (2 records) |
  | 7* | if IVIS≠0: VHB(8,NE) Float32 |
  | 8* | if IDEN≠0: DENS(7,NE) Float32 |
  | 9* | if ILAG≠0: LGEM(6,NEL), LGIBC(NBL), LGIBCF(NBL) Int32; then EXLG, EYLG, UXLG, UYLG (NUL each), STELPX, STELPY (NPM×NSM) Float32 (2 records) |
  | 10* | if IFLT≠0: IFBC, IFBC2, IFEQV, JFBC1, JFBC2 (NFP each) Int32 |

  Array sizes and flags come from IVARS (1-based Julia index = C define + 1,
  from `data.h`): NE=11, NN=12, NUP=14, NBP=15, NBP2=16, NUVP=18, NFP=37,
  NEL=42, NUL=43, NSM=44, NPM=45, NBL=46; flags ICR=5, IVIS=6, IDEN=7, ILAG=8,
  IFLT=9; mesh NX=1, NY=2, NCOMP=4. RVARS: XLEN=1, YLEN=2, TIME=5, SE=7,
  HLENSC=8, ARGAN=9 … (full table in `data.h`).
- **Indexing scheme** (verified in `sybilsrc/plmesh.f:149`, `arrow.f:342-365`):
  solution node `j ∈ 1:NUP` has coordinates `EX[NOR[j]], EY[NOR[j]]`, velocity
  `UX=UVP[j], UY=UVP[j+NUP]`; `LEM[k,e]` holds j-space node numbers of the
  6-node (quadratic) triangles, corners `k=1:3`; SSQ (log crustal thickness)
  is indexed by `j` like UVP.

## Package design

Name **Basil.jl** (module `Basil`), repo `wenrongcao/Basil.jl`, license
**GPL-3.0** (same as basil; lets us bundle example inputs derived from the basil
repo — see pitfalls).

```
basil_jl/
├── Project.toml            # deps: basil_jll, Printf; weakdeps: Makie
├── LICENSE                 # GPL-3.0
├── README.md               # usage + publishing guide
├── PLAN.md                 # this file
├── src/
│   ├── Basil.jl            # module, exports, extension stubs
│   ├── input.jl            # BasilInput builder → ASCII input file
│   ├── run.jl              # run_basil, run_sybilps, workdir mgmt
│   └── reader.jl           # FD.sols reader → BasilRecord
├── ext/BasilMakieExt.jl    # plotmesh / plotfield / plotvelocity via Makie
├── examples/
│   ├── indenter.jl         # end-to-end demo
│   └── inputs/INn3A0     # bundled template (from basil examples, GPL)
├── test/runtests.jl
└── .github/workflows/      # CI.yml, TagBot.yml, CompatHelper.yml
```

### API (thin by design)

- **Input**: `BasilInput(label)` collects command lines; `command!(inp, "MESH";
  TYPE=0, NX=32)` serializes any keyword command generically (no hardcoded
  grammar → future basil keywords work automatically); `raw!(inp, "ON X = 0.0 :
  UX = 0.0")` for BC/REG lines; `write_input(path, inp)`. Plus
  `example_input(:indenter)` returning a bundled, runnable template.
- **Run**: `run_basil(inputfile; workdir=pwd(), verbose=true)` — creates
  `FD.sols/`+`FD.out/`, `cd`s via `Cmd(dir=…)`, streams/captures output, errors
  with log tail on failure, returns paths of products.
  `basil_version()`, `run_sybilps(logfile; output)`.
- **Read**: `read_solution(path) -> Vector{BasilRecord}` (all saved steps) and
  `read_record(path, i)`. `BasilRecord` stores raw arrays + named properties:
  `time(rec)`, `coordinates(rec)`, `triangles(rec; order=:corner|:quadratic)`,
  `velocity(rec)`, `thickness(rec)` (`exp.(SSQ)` per basil convention),
  `viscosity(rec)`, `markers(rec)`, `pressure(rec)`.
- **Visualize** (ext, loaded with `using GLMakie`/`CairoMakie`):
  `plotmesh(rec)`, `plotfield(rec, thickness(rec))` (triangular mesh color
  plot), `plotvelocity(rec)` (arrows), and `animate(records, field; file)`.

### Reader robustness

Read each record as: Int32 length marker → payload → matching trailing marker;
verify both markers agree and match the expected byte count computed from IVARS.
Auto-detect byte order by sanity-checking the first marker (must equal 128).
This mirrors `sybfile.c:read_data_blk` including its byteswap handling.

## Testing & verification

1. `Pkg.develop` the package in a temp env on this machine (aarch64-linux-gnu is
   a supported jll platform), `basil_version()` sanity check.
2. End-to-end test: write a small indenter-style input (coarse mesh, few steps),
   `run_basil`, then `read_solution` and assert: marker/size consistency,
   NX/NY/NUP/NE agree with mesh command, time increases across records,
   velocities match BCs (e.g., `UY≈1` on indented segment).
3. Makie extension smoke test (CairoMakie, headless) — gated so core tests pass
   without it.
4. CI matrix: ubuntu/macos/windows × Julia 1.9/lts/release/pre… **minus
   windows** (basil_jll has no Windows build — see pitfalls) → ubuntu + macos
   (x64, aarch64).

## Publishing the package (step by step)

1. **Repo**: push to GitHub `wenrongcao/Basil.jl` (public). Keep `Project.toml`
   `name = "Basil"`, fresh UUID, `version = "0.1.0"`.
2. **Compat bounds** (required for General registry auto-merge): `julia = "1.9"`,
   `basil_jll = "1.8.2"`, `Makie = "0.20, 0.21, 0.22, 0.24"` (weakdep needs
   compat too).
3. **CI green + tests** on supported platforms; add TagBot and CompatHelper
   workflows.
4. **Register** with one of:
   - *JuliaRegistrator GitHub app* (recommended): install the app on the repo,
     then comment `@JuliaRegistrator register` on the commit/PR to release; or
   - *JuliaHub* "register package" UI.
   This opens a PR against JuliaRegistries/General. Auto-merge (~15 min–3 days)
   requires: valid compat entries for all deps, name guidelines (≥5 chars —
   "Basil" is exactly 5 ✓), tests passing not required but expected.
5. **TagBot** then creates the git tag `v0.1.0` + GitHub release automatically.
6. **Subsequent releases**: bump `version` in Project.toml (semver), comment
   `@JuliaRegistrator register` again.
7. **Docs** (optional, later): Documenter.jl + `docs/` + gh-pages deploy key;
   or start with a README-driven package (FastScape.jl itself is unregistered
   and README-only — registering Basil.jl is already a step further).
8. **Before registering, decide the name** — see pitfall #1.

## Pitfalls

1. **Package-name review**: General registry AutoMerge checks name similarity;
   "Basil" is short and close to existing names (e.g., "Basis"), which can
   trigger manual review (delay, not rejection). Alternative: `BasilFEM.jl`.
   Decision: try `Basil.jl` first; renaming before first registration is cheap.
2. **No Windows build of basil_jll** — the platform list is Linux/macOS/FreeBSD
   only. Basil.jl must declare this (error politely on Windows, skip CI there,
   note WSL as the workaround). FastScape_jll, by contrast, has Windows.
3. **Executables, not a library**: each run pays process + file I/O overhead and
   there is no in-memory stepping/callback control (FastScape.jl can step and
   inspect arrays每 timestep; Basil.jl can only densify `SAVE` output). Don't
   promise a `ccall` API.
4. **Binary format fragility**: the reader hard-codes the v1.8.2 record layout
   from `r4write.f`. A future basil release can add IVARS flags/blocks; the
   reader must therefore *verify record lengths against markers* and fail loudly
   with the record index, not silently misparse. Pin `basil_jll` compat to
   `"1.8"` and revisit on jll bumps.
5. **NOR indirection**: coordinates are stored in a different node order than
   the solution vector (`EX[NOR[j]]` vs `UVP[j]`). Plotting without applying
   `NOR` produces scrambled meshes — this exact area also had the upstream
   regression fixed in the jll patch. Unit-test that BC nodes land where the
   input put them.
6. **Working-directory contract**: basil writes relative paths (`FD.sols/…`)
   and reads auxiliary files (`.poly`, `tibet.xyz`) from CWD. The wrapper must
   run with `Cmd(...; dir=workdir)` and never `cd()` the whole Julia session
   (thread-unsafe). Missing `FD.sols/` silently loses output on some paths —
   always pre-create.
7. **basil doesn't reliably set nonzero exit codes** on input errors (F77 STOP
   paths) — success must additionally be judged by the existence/growth of the
   `FD.sols/<BIN>` file and by scanning `FD.out/<BIN>.out` for error strings.
8. **Overwrite semantics**: rerunning the same input appends/overwrites
   `FD.sols/<BIN>` records. Wrapper should offer `force=true`/unique workdirs to
   avoid mixing records from different runs.
9. **Licensing**: basil is GPL-3.0. A subprocess wrapper *could* be MIT, but we
   bundle example inputs from the basil repo and may later port reader logic
   from `sybfile.c` — GPL-3.0 for Basil.jl is the safe, friction-free choice
   (FastScape.jl is also GPL-3.0).
10. **Dimensionless units**: all basil quantities are scaled (H, L, viscosity
    scales). The wrapper should expose values as-is and document scaling rather
    than guessing units.
11. **Makie compat churn**: Makie releases breaking versions often; keep it a
    weakdep with a generous compat range, and keep core (run+read) usable
    without any plotting backend. Optionally add a Plots.jl recipe later.
12. **aarch64 quirk from packaging**: the jll aarch64 build needed an auditor
    retry in Yggdrasil; if an artifact is broken on some platform, the fix goes
    through Yggdrasil (bug reports to Yggdrasil, not the wrapper).
13. **`sybil` GUI is not in the jll** — interactive exploration must be Makie
    based; only batch `sybilps` (PostScript) is available, and its `.log`
    scripting format is a separate mini-language (`examples/indenter/Fig4n3.log`).
