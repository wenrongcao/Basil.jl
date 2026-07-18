using Basil
using Test

@testset "Basil.jl" begin

@testset "executables" begin
    v = basil_version()
    @test occursin(r"[0-9]+\.[0-9]+"i, v)
end

@testset "input builder" begin
    inp = BasilInput("test model")
    command!(inp, "MESH"; TYPE=0, NX=8, AREA=0.05, QUALITY=15)
    command!(inp, "stepsize"; TYPE="RK", IDT0=20)
    raw!(inp, "ON X = 0.0 : UX = 0.0", "# a comment")
    s = string(inp)
    @test startswith(s, " LABEL    test model")
    @test occursin(" MESH     TYPE=0, NX=8, AREA=0.05, QUALITY=15", s)
    @test occursin(" STEPSIZE TYPE=RK, IDT0=20", s)   # names are upper-cased
    @test occursin("\n ON X = 0.0 : UX = 0.0\n", s)
    @test occursin("\n# a comment\n", s)
    @test isfile(example_input(:indenter))
    @test_throws ErrorException example_input(:doesnotexist)
end

# A coarse version of the classic indenter problem (Houseman & England 1986):
# thin viscous sheet with crustal-thickness layer and strain markers, so the
# solution file exercises the mandatory + ICR + ILAG blocks of the reader.
function indenter_input(; nx=16, kexit=4)
    inp = BasilInput("coarse indenter test")
    command!(inp, "MESH"; TYPE=0, NX=nx, FAULT=0, AREA=0.05, QUALITY=15)
    command!(inp, "GEOMETRY"; XZERO=0.0, XLEN=1.0, YZERO=0.0, YLEN=1.0,
             NCOMP=0, IGRAV=4)
    command!(inp, "VISDENS"; SE=1.0)
    command!(inp, "LAYER"; THICKNESS="", HLENSC=50.0, BDEPSC=0.35, ARGAN=0.0,
             THRESH=10.0, BRGAN=0.0, RISOST=0.0628)
    command!(inp, "BCOND")
    command!(inp, "LAGRANGE"; MARKERS="")
    command!(inp, "SOLVE"; AC=5.0e-7, ACNL=5.0e-6, ITSTOP=1000)
    command!(inp, "STEPSIZE"; TYPE="RK", IDT0=40, MPDEF=10)
    command!(inp, "SAVE"; KSAVE=2)
    command!(inp, "STOP"; KEXIT=kexit, TEXIT=0.24, IWRITE=200)
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
    command!(inp, "MARKERS"; ROWS=4, COLS=4, R=0.025,
             XMIN=0.1, XMAX=0.6, YMIN=0.1, YMAX=0.6)
    return inp
end

@testset "end-to-end run + read" begin
    workdir = mktempdir()
    input = joinpath(workdir, "coarse1")
    write_input(input, indenter_input())

    result = run_basil(input; verbose=false)
    @test isfile(result.solution)
    @test isfile(result.log)

    # rerun protection
    @test_throws ErrorException run_basil(input; verbose=false)
    result = run_basil(input; verbose=false, force=true)

    recs = read_solution(result.solution)
    @test length(recs) >= 2

    rec = recs[end]
    nup, ne = nnodes(rec), nelements(rec)
    @test ivar(rec, :NX) == 16
    @test nup > 100 && ne > 50
    @test size(rec.lem) == (6, ne)
    @test length(rec.nor) == nup

    # time advances across saved records
    ts = solution_time.(recs)
    @test issorted(ts) && ts[end] > ts[1]

    # geometry sane: initial record spans the unit square
    x, y = coordinates(recs[1])
    @test isapprox(minimum(x), 0; atol=1e-6) && isapprox(maximum(x), 1; atol=1e-6)
    @test isapprox(minimum(y), 0; atol=1e-6) && isapprox(maximum(y), 1; atol=1e-6)

    # connectivity indices are valid solution-node indices
    tri = triangles(rec)
    @test size(tri, 1) == 3
    @test extrema(tri)[1] >= 1 && extrema(tri)[2] <= nup

    # boundary condition honored: uy ≈ 1 on the indented segment of y=0
    x1, y1 = coordinates(recs[1])
    ux, uy = velocity(recs[1])
    ind = findall(j -> y1[j] < 1e-6 && x1[j] < 0.24, 1:nup)
    @test !isempty(ind)
    @test all(abs.(uy[ind] .- 1) .< 1e-3)
    fixed = findall(j -> y1[j] > 1 - 1e-6, 1:nup)
    @test all(abs.(uy[fixed]) .< 1e-6)

    # LAYER run: initial thickness is uniform 1/HLENSC, thickens under indenter
    th0 = thickness(recs[1])
    @test length(th0) == nup
    @test all(isapprox.(th0, 1 / rvar(recs[1], :HLENSC); rtol=1e-5))
    @test maximum(thickness(rec)) > maximum(th0)

    # markers present (LAGRANGE MARKERS)
    mx, my = markers(rec)
    @test size(mx) == size(my) && !isempty(mx)

    # byte-swapped (big-endian) copy parses identically
    raw = read(result.solution)
    swapped = collect(reinterpret(UInt8, bswap.(reinterpret(Int32, raw))))
    swfile = joinpath(workdir, "swapped")
    write(swfile, swapped)
    recs2 = read_solution(swfile)
    @test length(recs2) == length(recs)
    @test recs2[end].uvp == recs[end].uvp
    @test recs2[end].lem == recs[end].lem

    # indexed read
    @test read_record(result.solution, 1) isa BasilRecord
    @test solution_time(read_record(result.solution, -1)) == ts[end]

    # plotting stubs give a helpful error without Makie
    @test_throws ErrorException plotmesh(rec)
end

end
