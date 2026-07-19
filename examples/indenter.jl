# The classic indenter experiment (Houseman & England 1986), model INn3A0 of
# the upstream basil examples/indenter suite (power-law exponent n=3, Argand
# number 0), run end-to-end from Julia and visualized with CairoMakie.
# From this directory:
#
#     julia --project=.. -e 'include("indenter.jl")'
#
# (requires CairoMakie in your environment, e.g. `julia> ] add CairoMakie`)
#
# The input lives in examples/inputs/, and all outputs go to
# examples/outputs/ (committed to the repo so the expected results can be
# inspected without running anything):
#   outputs/FD.sols/INn3A0        binary solution, one record per SAVE
#   outputs/FD.out/INn3A0.out     basil run log
#   outputs/indenter_XXX.png      composite figure (mesh, crustal thickness,
#                                 velocity + strain markers) per saved record
# (basil runs inside a single working directory, so the input is copied
# into outputs/ for the run and removed afterwards)

using Basil
using CairoMakie

workdir = mkpath(joinpath(@__DIR__, "outputs"))
cp(joinpath(@__DIR__, "inputs", "INn3A0"), joinpath(workdir, "INn3A0"); force=true)

result = run_basil(joinpath(workdir, "INn3A0"); force=true)
rm(joinpath(workdir, "INn3A0"))     # run finished; drop the input copy
recs = read_solution(result.solution)
println("saved $(length(recs)) records: t = ", solution_time.(recs))

# composite figure: deformed mesh | crustal thickness | velocity + markers
function composite(rec)
    t = round(solution_time(rec); digits=3)
    fig = Figure(size=(1200, 420))

    ax1 = Axis(fig[1, 1]; aspect=DataAspect(), title="mesh, t=$t")
    plotmesh!(ax1, rec)

    ax2 = Axis(fig[1, 2]; aspect=DataAspect(), title="crustal thickness")
    plt = plotfield!(ax2, rec, thickness(rec); colormap=:turbo)
    Colorbar(fig[1, 3], plt)

    ax3 = Axis(fig[1, 4]; aspect=DataAspect(), title="velocity + strain markers")
    plotvelocity!(ax3, rec; decimate=6, lengthscale=0.06)
    mx, my = markers(rec)
    for m in axes(mx, 2)
        lines!(ax3, mx[:, m], my[:, m]; color=:gray)
    end
    return fig
end

for (i, rec) in enumerate(recs)
    file = joinpath(workdir, "indenter_$(lpad(i, 3, '0')).png")
    save(file, composite(rec))
    println("figure: ", file)
end
