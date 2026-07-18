# ---------------------------------------------------------------------------
# Reader for basil binary solution files (FD.sols/<name>).
#
# Format: gfortran unformatted *sequential* records, all data 4-byte
# (Int32 / Float32), one group of records per saved timestep, written by
# subroutine WRITESTORE in basilsrc/kdvaux.f (v1.8.2). The IVARS/RVARS index
# tables live in basilsrc/indices.parameters (and sybilsrc/data.h). Each
# Fortran record is framed by a leading and trailing Int32 byte count; byte
# order is detected from the first frame (the header record is always 128
# bytes).
# ---------------------------------------------------------------------------

# IVARS indices, 1-based (= sybilsrc/data.h defines + 1)
const IVARS_INDEX = (
    NX=1, NY=2, IMSH=3, NCOMP=4, ICR=5, IVIS=6, IDEN=7, ILAG=8, IFLT=9,
    IGRAV=10, NE=11, NN=12, NMP=13, NUP=14, NBP=15, NBP2=16, NUP2=17,
    NUVP=18, IDATA=19, IVV=20, KSTEP=21, ISAVE=22, IDT0=23, KEXIT=24,
    ITSTOP=25, IPRINT=26, IWRITE=27, KSAVE=28, INDFIX=29, MPDEF=30,
    LFLAT=31, JLV=32, IDEFTYP=33, MROWS=34, NXMAX=35, NYMAX=36, NFP=37,
    IFCASE=38, NELLEP=39, IPOLY=40, IBCMOD=41, NEL=42, NUL=43, NSM=44, NPM=45,
    NBL=46, NRM=47, MSINDX=48, IMREG=49, IRHEOTYP=50, IVOLD=51, ITEMP=52,
    IDENS=53, ITOPO=54, NSEG=55, ITHDI=56, IPOLE=57, IVRESET=58,
    INFPF3=59, IKPBC=60,
)

# RVARS indices, 1-based (= basilsrc/indices.parameters)
const RVARS_INDEX = (
    XLEN=1, YLEN=2, WFIT=3, AC=4, TIME=5, BIG=6, SE=7, HLENSC=8, ARGAN=9,
    ARGANP=10, BRGAN=11, BRGANP=12, THRESH=13, AREA=14, VOLUM=15,
    VISCD=16, DVMX=17, AREFM=18, ACNL=19, TSAVE=20, TEXIT=21, BANGL=22,
    ERA=23, OMTOT=24, DEFV1=25, DEFV2=26, DEFV3=27, DEFV4=28, DEFV5=29,
    BCV1=30, BCV2=31, BCV3=32, BCV4=33, BCV5=34, RHOG1=35, RHOG2=36,
    RHOG3=37, RHOG4=38, RHOG5=39, VISP1=40, VISP2=41, VISP3=42, VISP4=43,
    VISP5=44, YLDSTR=45, VELXO=46, VELYO=47, TBXOFF=48, TBYOFF=49,
    STELPR=50, BDEPSC=51, TDIFF=52, ALPHA=53, RISOST=54, REFLEV=55,
    XREFM=56, YREFM=57, GAMMA=58, ELAREA=59, ELSEG=60, ELQUAL=61,
    BETA=62, TREF=63, VC=64,
)

"""
    BasilRecord

One saved timestep of a basil solution file. Fields mirror the Fortran arrays
of `WRITESTORE` (basilsrc/kdvaux.f); optional blocks are `nothing` when the
run did not produce them.

Prefer the accessor functions ([`coordinates`](@ref), [`triangles`](@ref),
[`velocity`](@ref), [`thickness`](@ref), [`markers`](@ref), …) over raw
fields: basil stores nodal coordinates in a different node order than the
solution vector (`ex[nor[j]]` pairs with `uvp[j]`), and the accessors resolve
that indirection.
"""
struct BasilRecord
    namew::String            # solution name as written
    ndate::String            # run date
    namer::String            # name of solution originally read in (restarts)
    comment::String
    ivars::Vector{Int32}     # 64 integer scalars, see IVARS_INDEX
    rvars::Vector{Float32}   # 64 real scalars,    see RVARS_INDEX
    # mandatory mesh / boundary blocks
    lem::Matrix{Int32}       # 6 × NE quadratic-triangle connectivity (j-space)
    nor::Vector{Int32}       # NUP: solution index j -> coordinate index
    ibc::Vector{Int32}       # NBP boundary node list
    ibngh::Vector{Int32}     # NBP2
    ibctyp::Vector{Int32}    # NBP2 boundary condition types
    # mandatory solution blocks
    ex::Vector{Float32}      # NUP x-coordinates (coordinate order)
    ey::Vector{Float32}      # NUP y-coordinates (coordinate order)
    uvp::Vector{Float32}     # NUVP: ux(1:NUP), uy(NUP+1:2NUP), pressure rows
    qbnd::Vector{Float32}    # NBP2 boundary values
    # optional blocks (nothing when absent; presence depends on IVARS flags)
    ielfix::Union{Nothing,Vector{Int32}}
    ssq::Union{Nothing,Vector{Float32}}    # NUP log(layer thickness), ICR ∈ (1,2)
    frot::Union{Nothing,Vector{Float32}}   # NUP rotation, ICR ∈ (1,3)
    vhb::Union{Nothing,Matrix{Float32}}    # 8 × NE viscosity parameters
    dens::Union{Nothing,Matrix{Float32}}   # 7 × NE density parameters
    tempt::Union{Nothing,Vector{Float32}}  # NUP temperature
    lagrange::Union{Nothing,NamedTuple}    # Lagrangian mesh and/or strain markers
    faults::Union{Nothing,NamedTuple}      # fault index arrays
    extras::NamedTuple                     # series/ielle/ipolyn/vold/imat/iseg
end

"""
    ivar(rec, name::Symbol) -> Int
    rvar(rec, name::Symbol) -> Float32

Named access to basil's IVARS/RVARS header scalars, e.g. `ivar(rec, :NUP)`,
`rvar(rec, :TIME)`. Valid names are the keys of `Basil.IVARS_INDEX` /
`Basil.RVARS_INDEX` (from sybilsrc/data.h).
"""
ivar(rec::BasilRecord, name::Symbol) = Int(rec.ivars[getproperty(IVARS_INDEX, name)])
rvar(rec::BasilRecord, name::Symbol) = rec.rvars[getproperty(RVARS_INDEX, name)]

nnodes(rec::BasilRecord) = ivar(rec, :NUP)
nelements(rec::BasilRecord) = ivar(rec, :NE)

"Dimensionless model time of the record (`RVARS(TIME)`)."
solution_time(rec::BasilRecord) = Float64(rvar(rec, :TIME))

Base.show(io::IO, rec::BasilRecord) =
    print(io, "BasilRecord(\"", strip(rec.namew), "\", step ", ivar(rec, :KSTEP),
          ", t=", round(solution_time(rec); sigdigits=5),
          ", ", nnodes(rec), " nodes, ", nelements(rec), " elements)")

# ------------------------------------------------------------------ accessors

"""
    coordinates(rec) -> (x, y)

Nodal coordinates in *solution order* `j = 1:nnodes(rec)` (the order of
[`velocity`](@ref) and [`thickness`](@ref)), i.e. `ex[nor[j]]`.
"""
function coordinates(rec::BasilRecord)
    x = [rec.ex[rec.nor[j]] for j in 1:nnodes(rec)]
    y = [rec.ey[rec.nor[j]] for j in 1:nnodes(rec)]
    return (x=x, y=y)
end

"""
    triangles(rec; order=:corner) -> Matrix{Int}

Element connectivity into solution-order node indices, size 3×NE for
`order=:corner` (vertex nodes of the quadratic triangles) or 6×NE for
`order=:quadratic`.
"""
function triangles(rec::BasilRecord; order::Symbol=:corner)
    order === :corner    && return Int.(rec.lem[1:3, :])
    order === :quadratic && return Int.(rec.lem)
    error("order must be :corner or :quadratic")
end

"""
    velocity(rec) -> (ux, uy)

Nodal velocities in solution order (`uvp[j]`, `uvp[j+NUP]`).
"""
function velocity(rec::BasilRecord)
    nup = nnodes(rec)
    return (ux=rec.uvp[1:nup], uy=rec.uvp[nup+1:2nup])
end

"Pressure rows of the solution vector (`uvp[2NUP+1:NUVP]`, element-based dofs)."
pressure(rec::BasilRecord) = rec.uvp[2nnodes(rec)+1:ivar(rec, :NUVP)]

"Log of layer (crustal) thickness, solution order (`SSQ`; requires a LAYER run)."
function crustal_log_thickness(rec::BasilRecord)
    rec.ssq === nothing &&
        error("record has no crustal-thickness block (run had no LAYER command)")
    return rec.ssq
end

"Layer (crustal) thickness `exp.(SSQ)`, solution order (requires a LAYER run)."
thickness(rec::BasilRecord) = exp.(crustal_log_thickness(rec))

"Vertical-axis rotation array `FROT` (requires a LAYER run)."
function rotation(rec::BasilRecord)
    rec.frot === nothing &&
        error("record has no rotation block (run had no LAYER command)")
    return rec.frot
end

"8×NE viscosity parameter array `VHB` (present when viscosity varies)."
function viscosity(rec::BasilRecord)
    rec.vhb === nothing && error("record has no viscosity block (VHB not saved)")
    return rec.vhb
end

"7×NE density parameter array `DENS` (present for density-driven runs)."
function density(rec::BasilRecord)
    rec.dens === nothing && error("record has no density block (DENS not saved)")
    return rec.dens
end

"""
    markers(rec) -> (x, y)

Strain-marker (ellipse) point coordinates as NPM×NSM matrices — one column
per marker (requires `LAGRANGE MARKERS` + a `MARKERS` command in the run).
"""
function markers(rec::BasilRecord)
    (rec.lagrange === nothing || !haskey(rec.lagrange, :stelpx)) &&
        error("record has no strain markers (run needs LAGRANGE MARKERS " *
              "and a MARKERS command)")
    return (x=rec.lagrange.stelpx, y=rec.lagrange.stelpy)
end

# ----------------------------------------------------------------- low level

struct FortranFile
    io::IO
    swap::Bool
end

function _detect_swap(io::IO)
    mark(io)
    n = read(io, Int32)
    reset(io)
    n == 128 && return false
    bswap(n) == 128 && return true
    error("not a basil solution file: first record frame is $n bytes, expected " *
          "128 (also not 128 after byte-swapping). Old 8-byte record markers " *
          "are not supported.")
end

_maybeswap(x, swap) = swap ? bswap.(x) : x

"Read one Fortran sequential record; returns its raw bytes."
function _record(f::FortranFile)
    n1 = _maybeswap(read(f.io, Int32), f.swap)
    payload = read(f.io, n1)
    length(payload) == n1 || error("truncated record: wanted $n1 bytes, got $(length(payload))")
    n2 = _maybeswap(read(f.io, Int32), f.swap)
    n1 == n2 || error("corrupt record framing: leading count $n1 != trailing count $n2")
    return payload
end

"Split a record's bytes into typed arrays of given (Type => length) segments."
function _segments(bytes::Vector{UInt8}, swap::Bool, segs::Pair{DataType,Int}...)
    expected = 4 * sum(last, segs)
    length(bytes) == expected ||
        error("record length mismatch: file has $(length(bytes)) bytes where the " *
              "v1.8.2 layout expects $expected — file may come from an " *
              "incompatible basil version")
    out = Any[]
    offset = 0
    for (T, len) in segs
        seg = reinterpret(T, @view bytes[offset+1:offset+4len])
        push!(out, _maybeswap(Vector{T}(seg), swap))
        offset += 4len
    end
    return out
end

_charfield(bytes, r) = rstrip(String(bytes[r]))

"""
    read_record(f::FortranFile) -> BasilRecord

Read one timestep group of records; internal — use [`read_solution`](@ref).
"""
function read_record(f::FortranFile)
    hdr = _record(f)
    length(hdr) == 128 || error("header record is $(length(hdr)) bytes, expected 128")
    namew  = _charfield(hdr, 1:16)
    ndate  = _charfield(hdr, 17:32)
    namer  = _charfield(hdr, 33:48)
    commen = _charfield(hdr, 49:128)

    (ivars,) = _segments(_record(f), f.swap, Int32 => 64)
    (rvars,) = _segments(_record(f), f.swap, Float32 => 64)

    iv(n) = Int(ivars[getproperty(IVARS_INDEX, n)])
    ne, nup, nbp, nbp2 = iv(:NE), iv(:NUP), iv(:NBP), iv(:NBP2)
    nuvp = iv(:NUVP)

    lemv, nor, ibc, ibngh, ibctyp = _segments(_record(f), f.swap,
        Int32 => 6ne, Int32 => nup, Int32 => nbp, Int32 => nbp2, Int32 => nbp2)
    lem = reshape(lemv, 6, ne)

    ex, ey, uvp, qbnd = _segments(_record(f), f.swap,
        Float32 => nup, Float32 => nup, Float32 => nuvp, Float32 => nbp2)

    ielfix = ssq = frot = vhb = dens = tempt = lagrange = faults = nothing
    extras = NamedTuple()

    # optional blocks, in WRITESTORE order (basilsrc/kdvaux.f, v1.8.2)
    icr = iv(:ICR)
    if icr == 1
        (ielfix,) = _segments(_record(f), f.swap, Int32 => nup)
        ssq, frot = _segments(_record(f), f.swap, Float32 => nup, Float32 => nup)
    elseif icr == 2
        (ielfix,) = _segments(_record(f), f.swap, Int32 => nup)
        (ssq,) = _segments(_record(f), f.swap, Float32 => nup)
    elseif icr == 3
        (frot,) = _segments(_record(f), f.swap, Float32 => nup)
    elseif icr != 0
        error("unknown ICR flag $icr in solution file")
    end
    if iv(:IVIS) != 0
        (vhbv,) = _segments(_record(f), f.swap, Float32 => 8ne)
        vhb = reshape(vhbv, 8, ne)
    end
    if iv(:IDEN) != 0
        (densv,) = _segments(_record(f), f.swap, Float32 => 7ne)
        dens = reshape(densv, 7, ne)
    end
    if iv(:ITEMP) != 0
        (tempt,) = _segments(_record(f), f.swap, Float32 => nup)
    end
    ilag = iv(:ILAG)
    if ilag != 0
        ilag in (1, 2, 3) || error("unknown ILAG flag $ilag in solution file")
        nel, nul, nbl = iv(:NEL), iv(:NUL), iv(:NBL)
        npm, nsm = iv(:NPM), iv(:NSM)
        mesh = markerpts = nothing
        if ilag in (1, 3)   # Lagrangian mesh present
            lgemv, lgibc, lgibcf = _segments(_record(f), f.swap,
                Int32 => 6nel, Int32 => nbl, Int32 => nbl)
            mesh = (lgem=reshape(lgemv, 6, nel), lgibc=lgibc, lgibcf=lgibcf)
        end
        if ilag == 1        # mesh + markers in one record
            exlg, eylg, uxlg, uylg, spx, spy = _segments(_record(f), f.swap,
                Float32 => nul, Float32 => nul, Float32 => nul, Float32 => nul,
                Float32 => npm * nsm, Float32 => npm * nsm)
            lagrange = (mesh..., ex=exlg, ey=eylg, ux=uxlg, uy=uylg,
                        stelpx=reshape(spx, npm, nsm),
                        stelpy=reshape(spy, npm, nsm))
        elseif ilag == 2    # markers only
            spx, spy = _segments(_record(f), f.swap,
                Float32 => npm * nsm, Float32 => npm * nsm)
            lagrange = (stelpx=reshape(spx, npm, nsm),
                        stelpy=reshape(spy, npm, nsm))
        else                # ilag == 3: mesh only
            exlg, eylg, uxlg, uylg = _segments(_record(f), f.swap,
                Float32 => nul, Float32 => nul, Float32 => nul, Float32 => nul)
            lagrange = (mesh..., ex=exlg, ey=eylg, ux=uxlg, uy=uylg)
        end
    end
    if iv(:IFLT) != 0
        nfp = iv(:NFP)
        ifbc, ifbc2, ifeqv, jfbc1, jfbc2 = _segments(_record(f), f.swap,
            Int32 => nfp, Int32 => nfp, Int32 => nfp, Int32 => nfp, Int32 => nfp)
        faults = (; ifbc, ifbc2, ifeqv, jfbc1, jfbc2)
    end
    if iv(:MSINDX) != 0
        n = iv(:MSINDX)
        measur, msnode = _segments(_record(f), f.swap, Int32 => n, Int32 => n)
        extras = merge(extras, (series=(; measur, msnode),))
    end
    if iv(:NELLEP) != 0
        (ielle,) = _segments(_record(f), f.swap, Int32 => iv(:NELLEP))
        extras = merge(extras, (; ielle))
    end
    if iv(:IPOLY) != 0
        (ipolyn,) = _segments(_record(f), f.swap, Int32 => ne)
        extras = merge(extras, (; ipolyn))
    end
    if iv(:IVOLD) != 0
        (voldv,) = _segments(_record(f), f.swap, Float32 => 8ne)
        extras = merge(extras, (vold=reshape(voldv, 8, ne),))
    end
    if iv(:IMREG) != 0
        (imat,) = _segments(_record(f), f.swap, Int32 => ne)
        extras = merge(extras, (; imat))
    end
    if iv(:NSEG) > 0
        (isegv,) = _segments(_record(f), f.swap, Int32 => 3 * iv(:NSEG))
        extras = merge(extras, (iseg=reshape(isegv, 3, iv(:NSEG)),))
    end

    return BasilRecord(namew, ndate, namer, commen, ivars, rvars,
                       lem, nor, ibc, ibngh, ibctyp, ex, ey, uvp, qbnd,
                       ielfix, ssq, frot, vhb, dens, tempt, lagrange, faults,
                       extras)
end

"""
    read_solution(path) -> Vector{BasilRecord}

Read every saved timestep from a basil binary solution file
(`FD.sols/<name>`, as produced by [`run_basil`](@ref)). Handles both byte
orders; all data are `Int32`/`Float32` per basil's r4write format.

    read_record(path, i) -> BasilRecord

Read only the `i`-th saved record (1-based; `i` may be negative to count from
the end, e.g. `read_record(path, -1)` for the final state — note this still
scans the file from the start).
"""
function read_solution(path::AbstractString)
    open(path, "r") do io
        f = FortranFile(io, _detect_swap(io))
        records = BasilRecord[]
        while !eof(io)
            push!(records, read_record(f))
        end
        return records
    end
end

function read_record(path::AbstractString, i::Integer)
    records = read_solution(path)   # records vary in size; no random access
    return records[i > 0 ? i : end + 1 + i]
end
