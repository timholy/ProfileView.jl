# ProfileView.jl

[![Build Status](https://travis-ci.org/timholy/ProfileView.jl.svg)](https://travis-ci.org/timholy/ProfileView.jl)
[![codecov](https://codecov.io/gh/timholy/ProfileView.jl/branch/master/graph/badge.svg?token=pDJCNZ7uGg)](https://codecov.io/gh/timholy/ProfileView.jl)
[![PkgEval][pkgeval-img]][pkgeval-url]

**NOTE**: Jupyter/IJulia and SVG support has migrated to the [ProfileSVG](https://github.com/timholy/ProfileSVG.jl) package.

# Introduction

This package contains tools for visualizing and interacting with profiling data collected
with [Julia's][Julia] built-in sampling
[profiler][Profiling]. It
can be helpful for getting a big-picture overview of the major
bottlenecks in your code, and optionally highlights lines that trigger
garbage collection as potential candidates for optimization.

This type of plot is known as a [flame
graph](https://github.com/brendangregg/FlameGraph).
The main logic is handled by the [FlameGraphs][FlameGraphs] package; this package is just a visualization front-end.

Compared to other flamegraph viewers, ProfileView adds interactivity features, such as:

- zoom, pan for exploring large flamegraphs
- right-clicking to take you to the source code for a particular statement
- analyzing inference problems via `code_warntype` for specific, user-selected calls

These features are described in detail below.

## Installation

Within Julia, use the [package manager][pkg]:
```julia
using Pkg
Pkg.add("ProfileView")
```

## Tutorial: usage and visual interpretation

To demonstrate ProfileView, first we have to collect some profiling
data. Here's a simple test function for demonstration:

```julia
function profile_test(n)
    for i = 1:n
        A = randn(100,100,20)
        m = maximum(A)
        Am = mapslices(sum, A; dims=2)
        B = A[:,:,5]
        Bsort = mapslices(sort, B; dims=1)
        b = rand(100)
        C = B.*b
    end
end

using ProfileView
@profview profile_test(1)  # run once to trigger compilation (ignore this one)
@profview profile_test(10)
```

`@profview f(args...)` is just shorthand for `Profile.clear(); @profile f(args...); ProfileView.view()`.
(These commands require that you first say `using Profile`, the Julia profiling standard library.)

> If you use ProfileView from VSCode you'll get an error `UndefVarError: @profview not defined`.
> This is because VSCode defines its own `@profview`, which conflicts with ProfileView's.
> Fix it by using `ProfileView.@profview`.

If you're following along, you may see something like this:

![ProfileView](readme_images/pv1.png)

(Note that collected profiles can vary by Julia version and from run-to-run, so don't be alarmed
if you get something different.)
This plot is a visual representation of the *call graph* of the code that you just profiled.
The "root" of the tree is at the bottom; if you move your mouse along the long horizontal
bar at the bottom, you'll see a tooltip that's something like
```
boot.jl, eval: 330
```
This refers to one of Julia's own source files, [base/boot.jl][bootjl].
`eval` is the name of the function being executed, and `330` is the line number of the file.
This is the function that evaluated your `profile_test(10)` command that you typed at the REPL.
(Indeed, to reduce the amount of internal "overhead" in the flamegraph, some of these internals are truncated; see the `norepl` option of `FlameGraphs.flamegraph`.)
If you move your mouse upwards, you'll then see bars corresponding to the function(s) you ran with `@profview` (in this case, `profile_test`).
Thus, the vertical axis represents nesting depth: bars lie on top of the bars that called them.

The horizontal axis represents the amount of time (more precisely, the
number of backtraces) spent at each line.  The row at which the single
long bar breaks up into multiple different-colored bars corresponds
to the execution of different lines from `profile_test`.
The fact that
they are all positioned on top of the lower peach-colored bar means that all
of these lines are called by the same "parent" function. Within a
block of code, they are sorted in order of increasing line number, to
make it easier for you to compare to the source code.

From this visual representation, we can very quickly learn several
things about this function:

- On the right side, you see a stack of calls to functions in `sort.jl`.
  This is because sorting is implemented using recursion (functions that call themselves).

- `mapslices(sum, A; dims=2)` is considerably more expensive (the corresponding bar is horizontally wider) than
  `mapslices(sort, B; dims=1)`. This is because it has to process more
  data.

It is also worth noting that red is (by default) a special color: it is reserved for function
calls that have to be resolved at run-time.
Because run-time dispatch (aka, dynamic dispatch, run-time method lookup, or
a virtual call) often has a significant
impact on performance, ProfileView highlights the problematic call in red. It's
worth noting that some red is unavoidable; for example, the REPL can't
predict in advance the return types from what users type at the
prompt, and so the bottom `eval` call is red.
Red bars are problematic only when they account for a sizable
fraction of the top of a call stack, as only in such cases are they likely to be
the source of a significant performance bottleneck.
In the image above, can see that `mapslices` relied on run-time dispatch;
from the absence of pastel-colored bars above much of the red, we
might guess that this made a substantial
contribution to its total run time.
(Your version of Julia may show different results.)
See [Solving type-inference problems](solving-type-inference-problems) below
for tips on how to efficiently diagnose the nature of the problem.

Yellow is also a special color: it indicates a site of garbage collection, which can be
triggered at a site of memory allocation. You may find that such bars lead you to lines
whose performance can be improved by reducing the amount of temporary memory allocated
by your program. One common example is to consider using `@views(A[:, i] .* v)` instead
of `A[:, i] .* v`; the latter creates a new column-vector from `A`, whereas the former
just creates a reference to it.
Julia's [memory profiler](https://docs.julialang.org/en/v1/stdlib/Profile/#Memory-profiling)
may provide much more information about the usage of memory in your program.

## GUI features

### Customizable defaults:

Some default settings can be changed and retained across settings through a
`LocalPreferences.toml` file that is added to the active environment.

- Default color theme: The default is `:light`.
  Alternatively `:dark` can be set.
  Use `ProfileView.set_theme!(:dark)` to change the default.

- Default graph type: The default is `:flame` which displays from the bottom up.
  Alternatively `:icicle` displays from the top down.
  Use `ProfileView.set_graphtype!(:icicle)` to change the default.

### Gtk Interface

- Ctrl-q and Ctrl-w close the window. You can also use
  `ProfileView.closeall()` to close all windows opened by ProfileView.

- Left-clicking on a bar will cause information about this line to be
  printed in the REPL. This can be a convenient way to "mark" lines
  for later investigation.

- Right-clicking on a bar calls the `edit()` function to open the line
  in an editor.  (On a trackpad, use a 2-fingered tap.)

- CTRL-clicking and dragging will zoom in on a specific region of the image.  You
  can also control the zoom level with CTRL-scroll (or CTRL-swipe up/down).

  CTRL-double-click to restore the full view.

- You can pan the view by clicking and dragging, or by scrolling your
  mouse/trackpad (scroll=vertical, SHIFT-scroll=horizontal).

- The toolbar at the top contains two icons to load and save profile
  data, respectively.  Clicking the save icon will prompt you for a
  filename; you should use extension `*.jlprof` for any file you save.
  Launching `ProfileView.view(nothing)` opens a blank
  window, which you can populate with saved data by clicking on the
  "open" icon.

- After clicking on a bar, you can type `warntype_last` and see the
  result of `code_warntype` for the call represented by that bar.

- `ProfileView.view(windowname="method1")` allows you to name your window,
  which can help avoid confusion when opening several ProfileView windows
  simultaneously.

- On Julia 1.8 ProfileView.view(expand_tasks=true) creates one tab per task.
  Expanding by thread is on by default and can be disabled with `expand_threads=false`.

**NOTE**: ProfileView does not support the old JLD-based `*.jlprof` files anymore.
Use the format provided by FlameGraphs v0.2 and higher.


## Solving type-inference problems

[Cthulhu.jl](https://github.com/JuliaDebug/Cthulhu.jl) is a powerful tool for
diagnosing problems of type inference. Let's do a simple demo:

```julia
function profile_test_sort(n, len=100000)
    for i = 1:n
        list = []
        for _ in 1:len
            push!(list, rand())
        end
        sort!(list)
    end
end

julia> profile_test_sort(1)  # to force compilation

julia> @profview profile_test_sort(10)
```

Notice that there are lots of individual red bars (`sort!` is recursive) along the top
row of the image. To determine the nature of the inference problem(s) in a red bar, left-click on it
and then enter

```julia
julia> using Cthulhu

julia> descend_clicked()
```

You may see something like this:

![ProfileView](readme_images/descend.png)

You can see the source code of the running method, with "problematic" type-inference
results highlighted in red. (By default, non-problematic type inference results are
suppressed, but you can toggle their display with `'h'`.)

For this example, you can see that objects extracted from `v` have type `Any`: that's because in
`profile_test_sort`, we created `list` as `list = []`, which makes it a `Vector{Any}`;
in this case, a better option might be `list = Float64[]`. Notice that the *cause* of the performance
problem is quite far-removed from the place where it manifests, because it's only when
the low-level operations required by `sort!` get underway that the consequence of our choice
of container type become an issue. Often it's necessary to "chase" these performance issues
backwards to a caller; for that, `ascend_clicked()` can be useful:

```julia
julia> ascend_clicked()
Choose a call for analysis (q to quit):
 >   partition!(::Vector{Any}, ::Int64, ::Int64, ::Int64, ::Base.Order.ForwardOrdering, ::Vector{Any}, ::Bool, ::Vector{Any}, ::Int64)
       #_sort!#25(::Vector{Any}, ::Int64, ::Bool, ::Bool, ::typeof(Base.Sort._sort!), ::Vector{Any}, ::Base.Sort.ScratchQuickSort{Missing, Missing, Base.Sort.Insertio
         kwcall(::NamedTuple{(:t, :offset, :swap, :rev), Tuple{Vector{Any}, Int64, Bool, Bool}}, ::typeof(Base.Sort._sort!), ::Vector{Any}, ::Base.Sort.ScratchQuickSo
           #_sort!#25(::Vector{Any}, ::Int64, ::Bool, ::Bool, ::typeof(Base.Sort._sort!), ::Vector{Any}, ::Base.Sort.ScratchQuickSort{Missing, Missing, Base.Sort.Inse
           #_sort!#25(::Nothing, ::Nothing, ::Bool, ::Bool, ::typeof(Base.Sort._sort!), ::Vector{Any}, ::Base.Sort.ScratchQuickSort{Missing, Missing, Base.Sort.Insert
             _sort!(::Vector{Any}, ::Base.Sort.ScratchQuickSort{Missing, Missing, Base.Sort.InsertionSortAlg}, ::Base.Order.ForwardOrdering, ::NamedTuple{(:scratch, :
               _sort!(::Vector{Any}, ::Base.Sort.StableCheckSorted{Base.Sort.ScratchQuickSort{Missing, Missing, Base.Sort.InsertionSortAlg}}, ::Base.Order.ForwardOrde
                 _sort!(::Vector{Any}, ::Base.Sort.IsUIntMappable{Base.Sort.Small{40, Base.Sort.InsertionSortAlg, Base.Sort.CheckSorted{Base.Sort.ComputeExtrema{Base.
                   _sort!(::Vector{Any}, ::Base.Sort.IEEEFloatOptimization{Base.Sort.IsUIntMappable{Base.Sort.Small{40, Base.Sort.InsertionSortAlg, Base.Sort.CheckSor
v                    _sort!(::Vector{Any}, ::Base.Sort.Small{10, Base.Sort.InsertionSortAlg, Base.Sort.IEEEFloatOptimization{Base.Sort.IsUIntMappable{Base.Sort.Small{
```

This is an interactive menu showing each "callee" above the "caller": use the up and down arrows to pick a call to `descend` into. If you scroll to the bottom
you'll see the `profile_test_sort` call that triggered the whole cascade.

You can also see type-inference results without using Cthulhu: just enter

```
julia> warntype_clicked()
```

at the REPL. You'll see the result of Julia's `code_warntype` for the call you clicked on.

These commands all use `ProfileView.clicked[]`, which stores a stackframe entry for the most recently clicked
bar.

## Command-line options

The `view` command has the following syntax:
```
function view([fcolor,] data = Profile.fetch(); lidict = nothing, C = false, fontsize = 14, kwargs...)
```
Here is the meaning of the different arguments:

- `fcolor` optionally allows you to control the scheme used to select
  bar color. This can be quite extensively customized; see [FlameGraphs](https://timholy.github.io/FlameGraphs.jl/stable/) for details.

- `data` is the vector containing backtraces. You can use `using Profile; data1 =
  copy(Profile.fetch()); Profile.clear()` to store and examine results
  from multiple profile runs simultaneously.

- `lidict` is a dictionary containing "line information." This is obtained together with
  `data` from `using Profile; data, lidict = Profile.retrieve()`. Computing `lidict` is
  the slow step in displaying profile data, so calling `retrieve` can speed up repeated
  visualizations of the same data.

- `C` is a flag controlling whether lines corresponding to C and Fortran
  code are displayed. (Internally, ProfileView uses the information
  from C backtraces to learn about garbage-collection and to
  disambiguate the call graph).

- `fontsize` controls the size of the font displayed as a tooltip.

- `expand_threads` controls whether a page is created for each thread (requires julia 1.8, enabled by default)

- `expand_tasks` controls whether a page is shown for each task (requires julia 1.8, off by default)

- `graphtype::Symbol = :default` controls how the graph is shown. `:flame` displays from the bottom up, `:icicle`
  displays from the top down. The default is `:flame` which can be changed via e.g. `ProfileView.set_graphtype!(:icicle)`.

These are the main options, but there are others; see FlameGraphs for more details.

## Source locations & Revise (new in ProfileView 0.5.3)

Profiling and [Revise](https://github.com/timholy/Revise.jl) are natural partners,
as together they allow you to iteratively improve the performance of your code.
If you use Revise and are tracking the source files (either as a package or with `includet`),
the source locations (file and line number) reported by ProfileView
will match the current code at the time the window is created.


[Julia]: http://julialang.org "Julia"
[Profiling]: https://docs.julialang.org/en/v1/manual/profile/
[FlameGraphs]: https://github.com/timholy/FlameGraphs.jl
[pkg]: https://docs.julialang.org/en/latest/stdlib/Pkg/
[bootjl]: https://github.com/JuliaLang/julia/blob/2e6715c045042e1c8ae9adc7a578340649b0ad5a/base/boot.jl#L330
[pkgeval-img]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/P/ProfileView.svg
[pkgeval-url]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/report.html
