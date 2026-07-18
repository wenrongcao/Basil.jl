# ---------------------------------------------------------------------------
# Thin builder for basil ASCII input files.
#
# basil input (parsed by basilsrc/input.f) is a sequence of lines:
#   - keyword commands:  ` MESH     TYPE=0 NX=32 AREA=0.05`
#   - boundary-condition / region lines: ` ON X = 0.0 : UX = 0.0`
#   - `&` continues a line, `#` in column one comments a line,
#     non-keyword lines are ignored (treated as comments).
#
# The builder is deliberately generic: `command!` serializes any command name
# with KEY=value pairs, so new basil keywords need no wrapper changes. Use
# `raw!` for BC (`ON ...`), region (`REG ...`) and any other free-form lines.
# ---------------------------------------------------------------------------

"""
    BasilInput(label::AbstractString = "basil run")

Accumulates lines of a basil input file. Add keyword commands with
[`command!`](@ref), free-form lines (boundary conditions, regions, comments)
with [`raw!`](@ref), then serialize with [`write_input`](@ref) or `string`.

# Example
```julia
inp = BasilInput("Indenter, coarse")
command!(inp, "MESH"; TYPE=0, NX=16, AREA=0.05, QUALITY=15)
command!(inp, "GEOMETRY"; XZERO=0.0, XLEN=1.0, YZERO=0.0, YLEN=1.0, NCOMP=0)
command!(inp, "VISDENS"; SE=1.0)
command!(inp, "BCOND")
command!(inp, "SOLVE"; AC=5.0e-7, ACNL=5.0e-6, ITSTOP=1000)
command!(inp, "STEPSIZE"; TYPE="RK", IDT0=40, MPDEF=10)
command!(inp, "STOP"; KEXIT=5, IWRITE=200)
raw!(inp, "ON X = 0.0 : UX = 0.0")
write_input("myrun", inp)
```
"""
struct BasilInput
    label::String
    lines::Vector{String}
end

BasilInput(label::AbstractString="basil run") = BasilInput(String(label), String[])

_isflag(v) = v === nothing || (v isa AbstractString && isempty(v))

_fmtval(v::AbstractString) = String(v)
_fmtval(v::Integer) = string(v)
_fmtval(v::Real) = string(Float64(v))
_fmtval(v::Symbol) = string(v)

"""
    command!(inp::BasilInput, name; kwargs...)

Append the keyword command `name` (upper-cased) with `KEY=value` parameters.
A keyword with value `nothing` or `""` is emitted as a bare flag word (e.g.
`command!(inp, "LAYER"; THICKNESS=nothing, HLENSC=50)` gives
`LAYER THICKNESS HLENSC=50.0`). Long lines are wrapped with basil's `&`
continuation. Keyword order is preserved. Returns `inp`.
"""
function command!(inp::BasilInput, name::AbstractString; kwargs...)
    parts = [_isflag(v) ? uppercase(String(k)) :
             "$(uppercase(String(k)))=$(_fmtval(v))" for (k, v) in kwargs]
    push!(inp.lines, _wrap(rpad(uppercase(String(name)), 9) * join(parts, ", ")))
    return inp
end

"""
    raw!(inp::BasilInput, line...)

Append verbatim lines: boundary conditions (`"ON X = 0.0 : UX = 0.0"`),
regions (`"REG A ..."`), or `#` comments. Returns `inp`.
"""
function raw!(inp::BasilInput, lines::AbstractString...)
    append!(inp.lines, String.(lines))
    return inp
end

# basil's input scanner reads fixed-size line buffers; wrap conservatively.
function _wrap(line::AbstractString, width::Int=78)
    length(line) <= width && return String(line)
    out = ""
    cur = ""
    for word in split(line)
        candidate = isempty(cur) ? word : cur * " " * word
        if length(candidate) > width - 2 && !isempty(cur)
            out *= cur * " &\n          "
            cur = String(word)
        else
            cur = String(candidate)
        end
    end
    return out * cur
end

function Base.string(inp::BasilInput)
    io = IOBuffer()
    println(io, " LABEL    ", inp.label)
    for l in inp.lines
        # keyword/BC lines need a leading blank so column one is never
        # accidentally a comment character
        println(io, startswith(l, "#") ? l : " " * lstrip(l))
    end
    return String(take!(io))
end

Base.show(io::IO, ::MIME"text/plain", inp::BasilInput) = print(io, string(inp))

"""
    write_input(path::AbstractString, inp::BasilInput) -> path

Write the input file. Note that basil names its outputs after this file's
basename (unless an `OUTPUT BIN=` command overrides it).
"""
function write_input(path::AbstractString, inp::BasilInput)
    open(io -> write(io, string(inp)), path, "w")
    return path
end

# bundled inputs keep their upstream basil filenames; symbols are aliases
const EXAMPLE_INPUTS = Dict(:indenter => "INn3A0")

"""
    example_input(name::Symbol = :indenter) -> String

Path to a bundled, runnable basil input template (copy it into a working
directory, edit, then [`run_basil`](@ref) it). The bundled files keep their
upstream basil filenames; currently available:
`:indenter` (= `:INn3A0`) — model `INn3A0` from the upstream basil
`examples/indenter` suite: the basic Cartesian indenter of Houseman &
England (1986), power-law exponent n = 3 (`SE=3.0`), Argand number 0
(`ARGAN=0.0`, no buoyancy).
"""
function example_input(name::Symbol=:indenter)
    file = get(EXAMPLE_INPUTS, name, string(name))
    path = joinpath(@__DIR__, "..", "examples", "inputs", file)
    isfile(path) || error("no bundled example input named $name")
    return abspath(path)
end
