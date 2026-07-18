# ---------------------------------------------------------------------------
# Running the basil / sybilps executables from basil_jll.
#
# basil's working-directory contract (see examples/*/README in the basil repo):
#   - it is run *inside* a directory that must already contain FD.sols/ and
#     FD.out/ subdirectories;
#   - the binary solution is written to FD.sols/<name>, the ASCII log to
#     FD.out/<name>.out (name = input file basename, unless OUTPUT BIN=...);
#   - auxiliary files referenced by the input (.poly, topography .xyz) are
#     resolved relative to that directory.
# We therefore always launch the subprocess with `Cmd(...; dir=workdir)` and
# never change the Julia process's own working directory.
# ---------------------------------------------------------------------------

"""
    run_basil(inputfile; workdir=dirname(inputfile), name=basename(inputfile),
              verbose=true, force=false)
        -> (; solution, log, output)

Run the basil solver from basil_jll on `inputfile`.

Creates `FD.sols/` and `FD.out/` inside `workdir`, runs `basil <name>` with
`workdir` as the working directory, and returns paths to the binary solution
file (`solution`), the ASCII run log (`log`), and the captured process output
(`output::String`).

Note basil writes the solution under the *input file's basename* unless the
input contains an `OUTPUT BIN=...` command — pass `name` if you used one.
With `force=true` a pre-existing solution file of the same name is deleted
first (recommended: rerunning otherwise mixes records of different runs).

basil does not always exit with a nonzero status on input errors, so this
function additionally checks that the solution file was produced and raises an
error including the tail of the run log if not.
"""
function run_basil(inputfile::AbstractString;
                   workdir::AbstractString=dirname(abspath(inputfile)),
                   name::AbstractString=basename(inputfile),
                   verbose::Bool=true,
                   force::Bool=false)
    inputpath = joinpath(workdir, basename(inputfile))
    isfile(inputpath) ||
        error("input file $(inputpath) not found (the input must live inside workdir)")

    mkpath(joinpath(workdir, "FD.sols"))
    mkpath(joinpath(workdir, "FD.out"))

    solution = joinpath(workdir, "FD.sols", name)
    logfile  = joinpath(workdir, "FD.out", name * ".out")
    if force
        rm(solution; force=true)
        rm(logfile; force=true)
    elseif isfile(solution)
        error("solution file $solution already exists; " *
              "pass force=true to overwrite, or use a fresh workdir")
    end

    cmd = Cmd(`$(basil_jll.basil()) $(basename(inputfile))`; dir=workdir)
    out = IOBuffer()
    ok = success(pipeline(cmd; stdout=out, stderr=out))
    output = String(take!(out))
    verbose && !isempty(output) && print(output)

    if !ok || !isfile(solution)
        logtail = isfile(logfile) ? join(last(readlines(logfile), 20), "\n") : "(no log file)"
        error("basil run failed (exit ok = $ok, solution file present = $(isfile(solution))).\n" *
              "Process output:\n$output\nEnd of $(basename(logfile)):\n$logtail")
    end
    return (; solution, log=logfile, output)
end

"""
    basil_version() -> String

Version of the bundled basil solver. Uses `basil -v` when it reports one
(builds up to v1.8.2 print nothing there), otherwise the basil_jll package
version.
"""
function basil_version()
    v = strip(read(`$(basil_jll.basil()) -v`, String))
    return isempty(v) ? string(pkgversion(basil_jll)) : v
end

"""
    run_sybilps(logfile; output="sybil.ps", workdir=dirname(logfile), verbose=true)
        -> path of the PostScript file

Run the bundled batch plotter `sybilps` on a sybil `.log` command file
(see the basil documentation / `man sybil` for the log format). This is the
"native" visualization path producing the classic PostScript figures; for
interactive plots use the Makie extension instead.

The interactive X11 GUI `sybil` is *not* included in basil_jll.
"""
function run_sybilps(logfile::AbstractString;
                     output::AbstractString="sybil.ps",
                     workdir::AbstractString=dirname(abspath(logfile)),
                     verbose::Bool=true)
    isfile(joinpath(workdir, basename(logfile))) ||
        error("log file $(joinpath(workdir, basename(logfile))) not found")
    cmd = Cmd(`$(basil_jll.sybilps()) -i $(basename(logfile)) -o $output`; dir=workdir)
    out = IOBuffer()
    ok = success(pipeline(cmd; stdout=out, stderr=out))
    verbose && print(String(take!(out)))
    pspath = joinpath(workdir, output)
    (ok && isfile(pspath)) || error("sybilps failed to produce $pspath")
    return pspath
end
