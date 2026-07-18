# Basil.jl

A thin Julia wrapper around [basil_jll](https://github.com/JuliaBinaryWrappers/basil_jll.jl),
the precompiled binary distribution of [basil](https://github.com/greg-houseman/basil) —
the 2-D finite-element viscous-flow code by G.A. Houseman, T.D. Barr and L.A. Evans
(plane-strain, thin viscous sheet, thin viscous shell and axisymmetric deformation
of a viscous medium, with crustal-thickness evolution, faults and strain markers).

basil_jll ships the solver as **executables** (no shared library), so this package:

1. helps you **build basil input files** from Julia,
2. **runs the solver** as a subprocess (no compiler, no `make` — the binary is
   downloaded automatically for Linux, macOS and FreeBSD), and
3. **reads the binary solution files** (`FD.sols/*`, Fortran unformatted records)
   back into Julia and **plots** them via a [Makie](https://docs.makie.org)
   extension.

![Indenter example: deformed mesh, crustal thickness and velocity/strain markers](docs/img/indenter.png)
*The bundled indenter example (Houseman & England 1986) at t = 0.24: deformed
finite-element mesh, crustal thickness, and velocity field with strain-marker
ellipses — produced by `examples/indenter.jl`.*

> **Platforms**: basil_jll has no Windows build — use WSL on Windows.
> All basil quantities are dimensionless; see `man basil` in the upstream repo.

## Installation

Until the package is registered:

```julia
julia> ]
pkg> add https://github.com/wenrongcao/Basil.jl
```

## Quick start: the indenter problem

```julia
using Basil

# 1. build an input file (Houseman & England 1986 indenter, coarsened)
inp = BasilInput("indenter demo")
command!(inp, "MESH";     TYPE=0, NX=32, FAULT=0, AREA=0.05, QUALITY=15)
command!(inp, "GEOMETRY"; XZERO=0.0, XLEN=1.0, YZERO=0.0, YLEN=1.0, NCOMP=0, IGRAV=4)
command!(inp, "VISDENS";  SE=3.0)
command!(inp, "LAYER";    THICKNESS=nothing, HLENSC=50.0, BDEPSC=0.35,
                          ARGAN=0.0, THRESH=10.0, BRGAN=0.0, RISOST=0.0628)
command!(inp, "BCOND")
command!(inp, "LAGRANGE"; MARKERS=nothing)
command!(inp, "SOLVE";    AC=5.0e-7, ACNL=5.0e-6, ITSTOP=1000)
command!(inp, "STEPSIZE"; TYPE="RK", IDT0=40, MPDEF=10)
command!(inp, "SAVE";     KSAVE=20, TSAVE=0.06)
command!(inp, "STOP";     KEXIT=100, TEXIT=0.24, IWRITE=200)
raw!(inp,
     "ON X = 0.0 : UX = 0.0",
     "ON X = 0.0 : TY = 0.0",
     "ON X = 1.0 : UX = 0.0",
     "ON X = 1.0 : UY = 0.0",
     "ON Y = 1.0 : UX = 0.0",
     "ON Y = 1.0 : UY = 0.0",
     "ON Y = 0.0 : UX = 0.0",
     "ON Y = 0.0 : UY = 0.0",
     "ON Y = 0.0 FOR X = 0.0 TO 0.25 : UY = 1.0",
     "ON Y = 0.0 FOR X = 0.25 TO 0.5 : UY = 1.0 TO 0.0 : TP = 2")
command!(inp, "MARKERS"; ROWS=6, COLS=6, R=0.025,
                         XMIN=0.1, XMAX=0.6, YMIN=0.1, YMAX=0.6)

workdir = mktempdir()
write_input(joinpath(workdir, "indent1"), inp)

# 2. run the solver (creates FD.sols/ and FD.out/ inside workdir)
result = run_basil(joinpath(workdir, "indent1"))

# 3. read all saved timesteps
recs = read_solution(result.solution)
rec  = recs[end]
solution_time(rec)          # dimensionless model time
x, y   = coordinates(rec)   # nodal positions (deformed mesh)
ux, uy = velocity(rec)      # nodal velocities
th     = thickness(rec)     # crustal thickness (exp of stored log-thickness)
mx, my = markers(rec)       # strain-marker ellipses

# 4. plot (loading any Makie backend activates the extension)
using CairoMakie
plotmesh(rec)                                   # FE mesh (deformed)
plotfield(rec, thickness(rec); title="crustal thickness, t=$(solution_time(rec))")
plotvelocity(rec; decimate=4)                   # velocity arrows
```

Prefer editing classic basil input files directly? `example_input(:indenter)`
returns a bundled template; `run_basil` works on any existing input file. The
classic PostScript plotter is also wrapped: `run_sybilps("figure.log")` (the
interactive X11 `sybil` GUI is not part of basil_jll).

## API

| function | purpose |
|---|---|
| `BasilInput`, `command!`, `raw!`, `write_input`, `example_input` | build input files |
| `run_basil(input; workdir, name, verbose, force)` | run the solver |
| `run_sybilps(log; output)`, `basil_version()` | auxiliary executables |
| `read_solution(path)`, `read_record(path, i)` | read `FD.sols` binaries |
| `coordinates`, `triangles`, `velocity`, `pressure`, `thickness`, `rotation`, `viscosity`, `density`, `markers`, `solution_time` | field accessors on a `BasilRecord` |
| `ivar(rec, :NUP)`, `rvar(rec, :TIME)` | named access to basil's 64 integer / 64 real header scalars |
| `plotmesh`, `plotfield`, `plotvelocity` (+ `!` variants) | Makie extension |

`BasilRecord` also exposes the raw arrays (`lem`, `nor`, `uvp`, `qbnd`,
`vhb`, …) exactly as basil stores them; note coordinates are stored in a
different node order than the solution vector (`ex[nor[j]]` pairs with
`uvp[j]`) — the accessors handle this for you.

## How it relates to FastScape.jl

The design follows [FastScape.jl](https://github.com/boriskaus/FastScape.jl)
in spirit (thin wrapper over an Yggdrasil-built Fortran code), but FastScape's
JLL exposes a shared library that Julia can `ccall`, while basil_jll exposes
executables — hence the file-based subprocess interface here.

## Development / publishing checklist

See [PLAN.md](PLAN.md) for the full design document, registration steps and
known pitfalls (record-format coupling to basil v1.8.2, Windows absence,
GPL-3.0 licensing, etc.).

## License

GPL-3.0, same as basil itself (the bundled example input derives from the
basil repository).
