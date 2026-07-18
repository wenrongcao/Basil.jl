"""
    Basil

Thin Julia wrapper around [basil_jll](https://github.com/JuliaBinaryWrappers/basil_jll.jl),
the binary distribution of the 2-D finite-element viscous-flow code
[basil](https://github.com/greg-houseman/basil) by Houseman, Barr & Evans.

basil_jll ships executables only (no shared library), so this package drives the
`basil` solver as a subprocess and reads its Fortran-unformatted solution files
back into Julia for analysis and plotting.

Workflow:

```julia
using Basil

inp = BasilInput("my run")
command!(inp, "MESH"; TYPE=0, NX=32)
# ... more commands / raw BC lines ...
write_input("run1", inp)

result = run_basil("run1")
recs   = read_solution(result.solution)

using GLMakie                    # activates the Makie extension
plotfield(recs[end], thickness(recs[end]))
```
"""
module Basil

using basil_jll: basil_jll

export BasilInput, command!, raw!, write_input, example_input
export run_basil, run_sybilps, basil_version
export BasilRecord, read_solution, read_record
export nnodes, nelements, coordinates, triangles, velocity, pressure,
       thickness, crustal_log_thickness, rotation, viscosity, density,
       markers, solution_time, ivar, rvar
export plotmesh, plotmesh!, plotfield, plotfield!, plotvelocity, plotvelocity!

include("input.jl")
include("run.jl")
include("reader.jl")

# ---------------------------------------------------------------------------
# Plotting API — implemented in ext/BasilMakieExt.jl, activated by `using Makie`
# (or any Makie backend such as GLMakie / CairoMakie).
# ---------------------------------------------------------------------------

"""
    plotmesh(rec::BasilRecord; kwargs...) -> Figure

Draw the finite-element mesh of a solution record. Requires a Makie backend to
be loaded (e.g. `using CairoMakie`).
"""
function plotmesh end
function plotmesh! end

"""
    plotfield(rec::BasilRecord, values; kwargs...) -> Figure

Color plot of a nodal field (length `nnodes(rec)`, e.g. `thickness(rec)` or a
velocity component) on the deformed mesh. Requires a Makie backend.
"""
function plotfield end
function plotfield! end

"""
    plotvelocity(rec::BasilRecord; decimate=1, kwargs...) -> Figure

Arrow plot of the velocity field. Requires a Makie backend.
"""
function plotvelocity end
function plotvelocity! end

function _makie_hint()
    error("This plotting function is provided by the Makie extension. " *
          "Load a Makie backend first, e.g. `using CairoMakie` or `using GLMakie`.")
end

# Catch-all fallbacks (the Makie extension adds more specific methods, so these
# must stay strictly less specific to avoid method overwriting at precompile).
plotmesh(args...; kwargs...) = _makie_hint()
plotfield(args...; kwargs...) = _makie_hint()
plotvelocity(args...; kwargs...) = _makie_hint()

end # module
