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
*Model `INn3A0` from the upstream basil `examples/indenter` suite — the basic
Cartesian indenter of Houseman & England (1986) with power-law exponent n = 3
(`SE=3.0`) and Argand number Ar = 0 (`ARGAN=0.0`, no buoyancy) — at t = 0.24:
deformed finite-element mesh, crustal thickness, and velocity field with
strain-marker ellipses. Produced by `examples/indenter.jl` from the bundled
copy of this input (`example_input(:indenter)`).*

> **Platforms**: basil_jll has no Windows build — use WSL on Windows.
> All basil quantities are dimensionless — see the *Units* section below.

## Installation

```julia
julia> ]
pkg> add Basil
```

## Quick start: run an existing basil input file

`run_basil` works on any classic basil input file you already have. Here we
use the bundled `INn3A0` indenter template (`example_input(:indenter)`) —
substitute the path to your own input file.

```julia
using Basil

# 1. put the input file in a working directory — all outputs will land there
#    (use mktempdir() instead if you just want a throwaway test)
workdir = mkpath(joinpath(pwd(), "outputs"))
inputfile = joinpath(workdir, "INn3A0")   # same name as in the basil examples
cp(example_input(:indenter), inputfile)

# 2. run the solver — following basil's own convention, the binary solution
#    goes to <workdir>/FD.sols/INn3A0 and the log to <workdir>/FD.out/INn3A0.out
result = run_basil(inputfile)       # add force=true to overwrite a previous run
result.solution                     # full path of the solution file
result.log                          # full path of the run log

# 3. read all saved timesteps from the binary solution file
recs = read_solution(result.solution)
rec  = recs[end]                    # final state
solution_time(rec)          # dimensionless model time
x, y   = coordinates(rec)   # nodal positions (deformed mesh)
ux, uy = velocity(rec)      # nodal velocities
th     = thickness(rec)     # crustal thickness (exp of stored log-thickness)
mx, my = markers(rec)       # strain-marker ellipses

# 4. plot (loading any Makie backend activates the extension)
#    each call plots ONE saved record — pick it by index first
using CairoMakie
rec = recs[3]        # e.g. the 3rd saved record; recs[1] is the initial
                     # state (t=0), recs[end] the final state
plotmesh(rec)                                   # FE mesh (deformed)
plotfield(rec, thickness(rec); title="crustal thickness, t=$(solution_time(rec))")
plotvelocity(rec; decimate=4)                   # velocity arrows

# to plot every saved timestep, loop over the records; saving into the
# same outputs folder keeps everything from the run together
for (i, r) in enumerate(recs)
    save(joinpath(workdir, "thickness_$(lpad(i, 3, '0')).png"),
         plotfield(r, thickness(r); title="t = $(solution_time(r))"))
end
```

A complete, committed run of this workflow lives in
[`examples/`](examples): the input file (`inputs/INn3A0`), the driver script
(`indenter.jl`), and the resulting solution, log and figures (`outputs/`),
so you can inspect the expected outputs without running anything.

## Units

**TL;DR — scaling back to real values.** Pick your length scale `D` (physical
size of the unit mesh) and velocity scale `V₀` (physical velocity of a unit
boundary condition), then multiply:

```text
real length      = value × D            (indenter: × 5000 km)
real velocity    = value × V₀           (indenter: × 50 mm/yr)
real time        = value × D/V₀         (indenter: × 100 Myr → t = 0.24 ⇒ 24 Myr)
real strain rate = value × V₀/D         (indenter: × 3.2e-16 s⁻¹)
crustal thickness = thickness(rec) × D × BDEPSC
                                        (indenter: 0.02 × 5000 km × 0.35 = 35 km)
```

The details:

basil works entirely in **normalized (dimensionless) quantities** — nothing
returned by this package is in SI or geological units. For a velocity-driven
model, choose a length scale `D` (the physical size of the unit mesh
dimension) and a velocity scale `V₀` (the physical velocity of a boundary
condition of 1); dimensional values are then recovered as:

| quantity | dimensionless value × |
|---|---|
| length (`coordinates`, `thickness`) | `D` |
| velocity (`velocity`) | `V₀` |
| time (`solution_time`) | `D/V₀` |
| strain rate | `V₀/D` |

For the bundled indenter model `INn3A0` the scaling is defined in
[Houseman & England (1986)](https://github.com/greg-houseman/basil/blob/main/examples/indenter/Houseman_England_1986b.pdf),
Table 1: `D = 5000 km`, `V₀ = 50 mm/yr`, lithosphere thickness
`L = 100 km`, initial crustal thickness `S₀ = 35 km`. Concretely:

- **time unit** `D/V₀ = 100 Myr`, so `solution_time(rec) = 0.24` is **24 Myr**
  (the final composite figure corresponds to the "24 Ma" panels of the
  paper's Figure 3; the paper's 40-Myr runs correspond to t = 0.4, i.e.
  2000 km of India–Asia convergence);
- with `UY = 1` on the unit mesh, `solution_time` also equals the fractional
  indentation of the domain (t = 0.24 ⇒ the indenter has advanced 24 % of D
  = 1200 km);
- **thickness**: `HLENSC = 50 = D/L`, so `thickness(rec)` starts at
  `1/HLENSC = 0.02`, which × D gives the 100-km sheet thickness;
  `BDEPSC = 0.35 = S₀/L` sets the crust at 0.35 × 100 km = 35 km. To compare
  with the paper's crustal-thickness contours (in units of L, starting at
  0.35), use `BDEPSC * thickness(rec) * HLENSC`;
- **strain rate unit** `V₀/D ≈ 3.2e-16 s⁻¹`;
- stress/viscosity/buoyancy scales enter through the power-law coefficient
  and the **Argand number** (paper's equation 6) — see the paper and
  `man basil` in the upstream repo.

For your own models, substitute your `D` and `V₀`; the table above is all
there is to it.

Already have solution files from earlier basil runs? `read_solution` works on
any `FD.sols/<name>` file directly — no need to rerun the model. The classic
PostScript plotter is also wrapped: `run_sybilps("figure.log")` (the
interactive X11 `sybil` GUI is not part of basil_jll).

## Building input files from Julia (optional)

Input files can also be composed programmatically — `command!` serializes any
basil keyword command, `raw!` adds free-form lines (boundary conditions,
regions):

```julia
inp = BasilInput("my model")
command!(inp, "MESH";     TYPE=0, NX=32, AREA=0.05, QUALITY=15)
command!(inp, "GEOMETRY"; XZERO=0.0, XLEN=1.0, YZERO=0.0, YLEN=1.0, NCOMP=0)
command!(inp, "VISDENS";  SE=3.0)
command!(inp, "SOLVE";    AC=5.0e-7, ACNL=5.0e-6, ITSTOP=1000)
command!(inp, "STEPSIZE"; TYPE="RK", IDT0=40, MPDEF=10)
command!(inp, "STOP";     KEXIT=100, TEXIT=0.24)
raw!(inp,
     "ON X = 0.0 : UX = 0.0",
     "ON Y = 0.0 FOR X = 0.0 TO 0.25 : UY = 1.0")
write_input(joinpath(workdir, "mymodel"), inp)
```

See the bundled template (`example_input(:indenter)`) and `man basil` in the
upstream repo for the full command vocabulary.

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

## Notes for developers

- The solution reader implements the record layout written by `WRITESTORE`
  (`basilsrc/kdvaux.f`) of basil v1.8.2 and validates every record's byte
  count, so an incompatible future format fails loudly; keep the `basil_jll`
  compat bound in sync when the jll is updated.
- basil_jll has no Windows build, and the interactive `sybil` X11 GUI is not
  part of the jll (batch `sybilps` is wrapped instead).

## License

GPL-3.0, same as basil itself (the bundled example input derives from the
basil repository).
