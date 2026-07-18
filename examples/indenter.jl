# The classic indenter experiment (Houseman & England 1986), run end-to-end
# from Julia and visualized with CairoMakie. From this directory:
#
#     julia --project=.. -e 'include("indenter.jl")'
#
# (requires CairoMakie in your environment, e.g. `julia> ] add CairoMakie`)

using Basil
using CairoMakie

workdir = mktempdir()
cp(example_input(:indenter), joinpath(workdir, "indenter.in"))

result = run_basil(joinpath(workdir, "indenter.in"))
recs = read_solution(result.solution)
println("saved $(length(recs)) records: t = ", solution_time.(recs))

rec = recs[end]
t = round(solution_time(rec); digits=3)

fig = Figure(size=(1200, 420))
ax1 = Axis(fig[1, 1]; aspect=DataAspect(), title="mesh, t=$t")
plotmesh!(ax1, rec)

ax2 = Axis(fig[1, 2]; aspect=DataAspect(), title="crustal thickness")
plt = plotfield!(ax2, rec, thickness(rec); colormap=:turbo)
Colorbar(fig[1, 3], plt)

ax4 = Axis(fig[1, 4]; aspect=DataAspect(), title="velocity")
plotvelocity!(ax4, rec; decimate=6, lengthscale=0.06)
mx, my = markers(rec)
for m in axes(mx, 2)
    lines!(ax4, mx[:, m], my[:, m]; color=:gray)
end

save(joinpath(workdir, "indenter.png"), fig)
println("figure: ", joinpath(workdir, "indenter.png"))
