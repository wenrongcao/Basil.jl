module BasilMakieExt

using Basil
using Basil: BasilRecord
using Makie

import Basil: plotmesh, plotmesh!, plotfield, plotfield!, plotvelocity, plotvelocity!

function _points(rec::BasilRecord)
    x, y = coordinates(rec)
    return Point2f.(x, y)
end

# unique corner-node edges of the triangulation, for wireframe drawing
function _edges(rec::BasilRecord)
    tri = triangles(rec)
    seen = Set{Tuple{Int,Int}}()
    for e in axes(tri, 2), (a, b) in ((1, 2), (2, 3), (3, 1))
        i, j = tri[a, e], tri[b, e]
        push!(seen, i < j ? (i, j) : (j, i))
    end
    return collect(seen)
end

function _axis(fig)
    return Makie.Axis(fig[1, 1]; aspect=Makie.DataAspect(),
                      xlabel="x", ylabel="y")
end

# ------------------------------------------------------------------ mesh

function plotmesh!(ax, rec::BasilRecord; color=:black, linewidth=0.5, kwargs...)
    pts = _points(rec)
    segs = [(pts[i], pts[j]) for (i, j) in _edges(rec)]
    linesegments!(ax, segs; color, linewidth, kwargs...)
    return ax
end

function plotmesh(rec::BasilRecord; kwargs...)
    fig = Figure()
    ax = _axis(fig)
    plotmesh!(ax, rec; kwargs...)
    return fig
end

# ------------------------------------------------------------------ field

function plotfield!(ax, rec::BasilRecord, vals::AbstractVector; kwargs...)
    length(vals) == nnodes(rec) ||
        error("field has length $(length(vals)), expected nnodes = $(nnodes(rec))")
    faces = permutedims(triangles(rec))          # NE × 3
    return mesh!(ax, _points(rec), faces; color=Float32.(vals),
                 shading=NoShading, kwargs...)
end

function plotfield(rec::BasilRecord, vals::AbstractVector;
                   colormap=:viridis, colorbar=true, title="", kwargs...)
    fig = Figure()
    ax = _axis(fig)
    isempty(title) || (ax.title = title)
    plt = plotfield!(ax, rec, vals; colormap, kwargs...)
    colorbar && Colorbar(fig[1, 2], plt)
    return fig
end

# ------------------------------------------------------------------ velocity

function plotvelocity!(ax, rec::BasilRecord; decimate::Integer=1, kwargs...)
    x, y = coordinates(rec)
    ux, uy = velocity(rec)
    idx = 1:decimate:nnodes(rec)
    if isdefined(Makie, :arrows2d!)
        arrows2d!(ax, x[idx], y[idx], ux[idx], uy[idx]; kwargs...)
    else
        arrows!(ax, x[idx], y[idx], ux[idx], uy[idx]; kwargs...)
    end
    return ax
end

function plotvelocity(rec::BasilRecord; kwargs...)
    fig = Figure()
    ax = _axis(fig)
    plotvelocity!(ax, rec; kwargs...)
    return fig
end

end # module
