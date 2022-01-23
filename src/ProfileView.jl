module ProfileView

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@optlevel"))
    @eval Base.Experimental.@optlevel 1
end

using Profile
using FlameGraphs
using FlameGraphs.IndirectArrays
using Base.StackTraces: StackFrame
using MethodAnalysis
using InteractiveUtils
using Gtk.ShortNames, GtkObservables, Colors, FileIO, IntervalSets
import Cairo
using Graphics
using Preferences

using FlameGraphs: Node, NodeData
using Gtk.GConstants.GdkModifierType: SHIFT, CONTROL, MOD1

export @profview, warntype_last

const clicked = Ref{Any}(nothing)   # for getting access to the clicked bar

const _graphtype = Ref{Symbol}(Symbol(@load_preference("graphtype", "flame")))

function set_graphtype!(graphtype::String)
    if !(graphtype in ("flame", "icicle"))
        throw(ArgumentError("Invalid graphtype: $graphtype. Valid options are :flame or :icicle"))
    end
    @set_preferences! "graphtype" => graphtype
    _graphtype[] = Symbol(graphtype)
    @info "Default graphtype set to $(repr(graphtype))"
    nothing
end
set_graphtype!(graphtype::Symbol) = set_graphtype!(string(graphtype))

"""
    warntype_last()
    warntype_last(io::IO; kwargs...)

Show `code_warntype` for the most recently-clicked bar.

Optionally direct output to stream `io`. Keyword arguments are passed to `code_warntype`.
"""
function warntype_last(io::IO=stdout; kwargs...)
    st = clicked[]
    if st === nothing || st.linfo === nothing
        @warn "click on a non-inlined bar to see `code_warntype` info"
        return nothing
    end
    return code_warntype(io, call_type(st.linfo.specTypes)...; kwargs...)
end

mutable struct ZoomCanvas
    bb::BoundingBox  # in user-coordinates
    c::Canvas
end

"""
    @profview f(args...)

Clear the Profile buffer, profile `f(args...)`, and view the result graphically.
"""
macro profview(ex)
    return quote
        # pause the eventloop while profiling
        Gtk.pause_eventloop() do
            Profile.clear()
            @profile $(esc(ex))
        end
        view()
    end
end

"""
    ProfileView.closeall()

Closes all windows opened by ProfileView.
"""
function closeall()
    for (w, _) in window_wrefs
        destroy(w)
    end
    empty!(window_wrefs)   # see precompile.jl's usage of closeall
    return nothing
end

const window_wrefs = WeakKeyDict{Gtk.GtkWindowLeaf,Nothing}()
const tabname_allthreads = Symbol("All Threads")
const tabname_alltasks = Symbol("All Tasks")

NestedGraphDict = Dict{Symbol,Dict{Symbol,Node{NodeData}}}
"""
    ProfileView.view([fcolor], data=Profile.fetch(); lidict=nothing, C=false, recur=:off, fontsize=14, windowname="Profile", kwargs...)

View profiling results. `data` and `lidict` must be a matched pair from `Profile.retrieve()`.
You have several options to control the output, of which the major ones are:

- `fcolor`: an optional coloration function. The main options are `FlameGraphs.FlameColors`
  and `FlameGraphs.StackFrameCategory`.
- `C::Bool = false`: if true, the graph will include stackframes from C code called by Julia.
- `recur`: on Julia 1.4+, collapse recursive calls (see `Profile.print` for more detail)
- `expand_threads::Bool = true`: Break down profiling by thread (true by default)
- `expand_tasks::Bool = false`: Break down profiling of each thread by task (false by default)
- `graphtype::Symbol = :default`: Control how the graph is shown. `:flame` displays from the bottom up, `:icicle` from
  from the top down. The default type can be changed via e.g. `ProfileView.set_graphtype!(:icicle)`, which
  is stored as a preference for the active environment via `Preferences.jl`.

See [FlameGraphs](https://github.com/timholy/FlameGraphs.jl) for more information.
"""
function view(fcolor, data::Vector{UInt64}; lidict=nothing, C=false, combine=true, recur=:off, pruned=FlameGraphs.defaultpruned,
                expand_threads::Bool=true, expand_tasks::Bool=false, kwargs...)
    g = flamegraph(data; lidict=lidict, C=C, combine=combine, recur=recur, pruned=pruned)
    g === nothing && return nothing
    # Dict of dicts. Outer is threads, inner is tasks
    # Don't report the tasks at the "all threads" level because their id is thread-specific, so it's not useful
    # to track them across thread TODO: Perhaps fix that in base, so tasks keep the same id across threads?
    gdict = NestedGraphDict(tabname_allthreads => Dict{Symbol,Node{NodeData}}(tabname_alltasks => g))
    if expand_threads && isdefined(Profile, :has_meta) && Profile.has_meta(data)
        for threadid in Profile.get_thread_ids(data)
            g = flamegraph(data; lidict=lidict, C=C, combine=combine, recur=recur, pruned=pruned, threads = threadid)
            gdict_inner = Dict{Symbol,Node{NodeData}}(tabname_alltasks => g)
            if expand_tasks
                taskids = Profile.get_task_ids(data, threadid)
                if length(taskids) > 1
                    # skip when there's only one task as it will be the same as "all tasks"
                    for taskid in taskids
                        g = flamegraph(data; lidict=lidict, C=C, combine=combine, recur=recur, pruned=pruned, threads = threadid, tasks = taskid)
                        gdict_inner[Symbol(taskid)] = g
                    end
                end
            end
            gdict[Symbol(threadid)] = gdict_inner
        end
    end
    return view(fcolor, gdict; data=data, lidict=lidict, kwargs...)
end
function view(fcolor; kwargs...)
    data, lidict = Profile.retrieve()
    view(fcolor, data; lidict=lidict, kwargs...)
end
function view(data::Vector{UInt64}; lidict=nothing, kwargs...)
    view(FlameGraphs.default_colors, data; lidict=lidict, kwargs...)
end
function view(; kwargs...)
    # pausing the event loop here to facilitate a fast retrieve
    data, lidict = Gtk.pause_eventloop() do
        Profile.retrieve()
    end
    view(FlameGraphs.default_colors, data; lidict=lidict, kwargs...)
end

# This method allows user to open a *.jlprof file
viewblank() = (FlameGraphs.default_colors, Node(NodeData(StackTraces.UNKNOWN, 0, 1:0)))
view(::Nothing; kwargs...) = view(viewblank()...; kwargs...)

function view(g::Node{NodeData}; kwargs...)
    view(FlameGraphs.default_colors, g; kwargs...)
end
function view(fcolor, g::Node{NodeData}; data=nothing, lidict=nothing, kwargs...)
    win, _ = viewgui(fcolor, g; data=data, lidict=lidict, kwargs...)
    Gtk.showall(win)
end
function view(g_or_gdict::Union{Node{NodeData},NestedGraphDict}; kwargs...)
    view(FlameGraphs.default_colors, g_or_gdict; kwargs...)
end
function view(fcolor, g_or_gdict::Union{Node{NodeData},NestedGraphDict}; data=nothing, lidict=nothing, kwargs...)
    win, _ = viewgui(fcolor, g_or_gdict; data=data, lidict=lidict, kwargs...)
    Gtk.showall(win)
end

function viewgui(fcolor, g::Node{NodeData}; kwargs...)
    gdict = NestedGraphDict(tabname_allthreads => Dict{Symbol,Node{NodeData}}(tabname_alltasks => g))
    viewgui(fcolor, gdict; kwargs...)
end
function viewgui(fcolor, gdict::NestedGraphDict; data=nothing, lidict=nothing, windowname="Profile", graphtype = :default, kwargs...)
    _c, _fdraw, _tb_open, _tb_save_as = nothing, nothing, nothing, nothing # needed to be returned for precompile helper
    if graphtype == :default
        graphtype = _graphtype[]
    end
    thread_tabs = collect(keys(gdict))
    nb_threads = Notebook() # for holding the per-thread pages
    Gtk.GAccessor.scrollable(nb_threads, true)
    Gtk.GAccessor.show_tabs(nb_threads, length(thread_tabs) > 1)
    sort!(thread_tabs, by = s -> something(tryparse(Int, string(s)), 0)) # sorts thread_tabs as [all threads, 1, 2, 3 ....]

    for thread_tab in thread_tabs
        gdict_thread = gdict[thread_tab]
        task_tabs = collect(keys(gdict_thread))
        sort!(task_tabs, by = s -> s == tabname_alltasks ? "" : string(s)) # sorts thread_tabs as [all threads, 0xds ....]

        nb_tasks = Notebook() # for holding the per-task pages
        Gtk.GAccessor.scrollable(nb_tasks, true)
        Gtk.GAccessor.show_tabs(nb_tasks, length(task_tabs) > 1)
        task_tab_num = 1
        for task_tab in task_tabs
            g = gdict_thread[task_tab]
            gsig = Observable(g)  # allow substitution by the open dialog
            c = canvas(UserUnit)
            set_gtk_property!(widget(c), :expand, true)

            f = Frame(c)
            tb = Toolbar()
            tb_open = ToolButton("gtk-open")
            Gtk.GAccessor.tooltip_text(tb_open, "open")
            tb_save_as = ToolButton("gtk-save-as")
            Gtk.GAccessor.tooltip_text(tb_save_as, "save")
            tb_zoom_fit = ToolButton("gtk-zoom-fit")
            Gtk.GAccessor.tooltip_text(tb_zoom_fit, "zoom to fit")
            tb_zoom_in = ToolButton("gtk-zoom-in")
            Gtk.GAccessor.tooltip_text(tb_zoom_in, "zoom in")
            tb_zoom_out = ToolButton("gtk-zoom-out")
            Gtk.GAccessor.tooltip_text(tb_zoom_out, "zoom out")
            tb_info = ToolButton("gtk-info")
            Gtk.GAccessor.tooltip_text(tb_info, "ProfileView tips")
            tb_text_item = ToolItem()
            Gtk.GAccessor.expand(tb_text_item, true)
            tb_text = Entry()
            Gtk.GAccessor.sensitive(tb_text, false)
            push!(tb_text_item, tb_text)

            push!(tb, tb_open)
            push!(tb, tb_save_as)
            push!(tb, SeparatorToolItem())
            push!(tb, tb_zoom_fit)
            push!(tb, tb_zoom_out)
            push!(tb, tb_zoom_in)
            push!(tb, SeparatorToolItem())
            push!(tb, tb_info)
            push!(tb, SeparatorToolItem())
            push!(tb, tb_text_item)
            # FIXME: likely have to do `allkwargs` in the open/save below (add in C, combine, recur)
            signal_connect(open_cb, tb_open, "clicked", Nothing, (), false, (widget(c),gsig,kwargs))
            signal_connect(save_as_cb, tb_save_as, "clicked", Nothing, (), false, (widget(c),data,lidict,g))
            signal_connect(info_cb, tb_info, "clicked", Nothing, (), false, ())

            bx = Box(:v)
            push!(bx, tb)
            push!(bx, f)
            # don't use the actual taskid as the tab as it's very long
            push!(nb_tasks, bx, task_tab_num == 1 ? task_tab : Symbol(task_tab_num - 1))
            fdraw = viewprof(fcolor, c, gsig, (tb_zoom_fit, tb_zoom_out, tb_zoom_in, tb_text), graphtype; kwargs...)
            GtkObservables.gc_preserve(nb_threads, c)
            GtkObservables.gc_preserve(nb_threads, fdraw)
            _c, _fdraw, _tb_open, _tb_save_as = c, fdraw, tb_open, tb_save_as
            task_tab_num += 1
        end
        push!(nb_threads, nb_tasks, string(thread_tab))
    end

    bx = Box(:v)
    push!(bx, nb_threads)

    # Defer creating the window until here because Window includes a `show` that will unpause the Gtk eventloop
    win = Window(windowname, 800, 600)
    push!(win, bx)

    # Register the window with closeall
    window_wrefs[win] = nothing
    signal_connect(win, :destroy) do w
        delete!(window_wrefs, win)
    end

    # Ctrl-w and Ctrl-q destroy the window
    signal_connect(win, "key-press-event") do w, evt
        if evt.state == CONTROL && (evt.keyval == UInt('q') || evt.keyval == UInt('w'))
            @async destroy(w)
            nothing
        end
    end

    return win, _c, _fdraw, (_tb_open, _tb_save_as)
end

function viewprof(fcolor, c, gsig, tb_items, graphtype; fontsize=14)
    obs = on(gsig) do g
        viewprof_func(fcolor, c, g, fontsize, tb_items, graphtype)
    end
    gsig[] = gsig[]
    return obs
end

function viewprof_func(fcolor, c, g, fontsize, tb_items, graphtype)
    if !in(graphtype, (:flame, :icicle))
        throw(ArgumentError("Invalid option for `graphtype`: `$(repr(graphtype))`. Valid options are `:flame` and `:icicle`"))
    end
    tb_zoom_fit, tb_zoom_out, tb_zoom_in, tb_text = tb_items
    # From a given position, find the underlying tag
    function gettag(tagimg, xu, yu)
        x = ceil(Int, Float64(xu))
        y = ceil(Int, Float64(yu))
        Y = size(tagimg, 2)
        x = max(1, min(x, size(tagimg, 1)))
        y = max(1, min(y, Y))
        tagimg[x,Y-y+1]
    end
    function device_bb(c)
        if graphtype == :icicle
            BoundingBox(0, Graphics.width(c), Graphics.height(c), 0)
        elseif graphtype == :flame
            BoundingBox(0, Graphics.width(c), 0, Graphics.height(c))
        end
    end

    isempty(g.data.span) && return nothing
    img = flamepixels(fcolor, g)
    tagimg = flametags(g, img)
    # The first column corresponds to the bottom row, which is our fake root node. Get rid of it.
    img, tagimg = img[:,2:end], discardfirstcol(tagimg)
    img24 = RGB24.(img)
    img24 = img24[:,end:-1:1]
    fv = XY(0.0..size(img24,1), 0.0..size(img24,2))
    zr = Observable(ZoomRegion(fv, fv))
    signal_connect(zoom_fit_cb, tb_zoom_fit, "clicked", Nothing, (), false, (zr))
    signal_connect(zoom_out_cb, tb_zoom_out, "clicked", Nothing, (), false, (zr))
    signal_connect(zoom_in_cb, tb_zoom_in, "clicked", Nothing, (), false, (zr))
    sigrb = init_zoom_rubberband(c, zr)
    sigpd = init_pan_drag(c, zr)
    sigzs = init_zoom_scroll(c, zr)
    sigps = init_pan_scroll(c, zr)
    surf = Cairo.CairoImageSurface(img24)
    append!(c.preserved, Any[sigrb, sigpd, sigzs, sigps])
    let tagimg=tagimg    # julia#15276
        sigredraw = draw(c, zr) do widget, r
            ctx = getgc(widget)
            set_coordinates(ctx, device_bb(ctx), BoundingBox(r.currentview))
            rectangle(ctx, BoundingBox(r.currentview))
            set_source(ctx, surf)
            p = Cairo.get_source(ctx)
            Cairo.pattern_set_filter(p, Cairo.FILTER_NEAREST)
            fill(ctx)
        end
        lasttextbb = Ref(BoundingBox(1,0,1,0))
        sigmotion = on(c.mouse.motion) do btn
            # Repair image from ovewritten text
            if c.widget.is_realized && c.widget.is_sized
                ctx = getgc(c)
                if Graphics.width(lasttextbb[]) > 0
                    r = zr[]
                    set_coordinates(ctx, device_bb(ctx), BoundingBox(r.currentview))
                    rectangle(ctx, lasttextbb[])
                    set_source(ctx, surf)
                    p = Cairo.get_source(ctx)
                    Cairo.pattern_set_filter(p, Cairo.FILTER_NEAREST)
                    fill(ctx)
                end
                # Write the info
                xu, yu = btn.position.x, btn.position.y
                sf = gettag(tagimg, xu, yu)
                if sf != StackTraces.UNKNOWN
                    str_long = long_info_str(sf)
                    Gtk.GAccessor.text(tb_text, str_long)
                    str = string(basename(string(sf.file)), ", ", sf.func, ": line ", sf.line)
                    set_source(ctx, fcolor(:font))
                    Cairo.set_font_face(ctx, "sans-serif $(fontsize)px")
                    xi = zr[].currentview.x
                    xmin, xmax = minimum(xi), maximum(xi)
                    lasttextbb[] = deform(Cairo.text(ctx, xu, yu, str, halign = xu < (2xmin+xmax)/3 ? "left" : xu < (xmin+2xmax)/3 ? "center" : "right"), -2, 2, -2, 2)
                else
                    Gtk.GAccessor.text(tb_text, "")
                end
                reveal(c)
            end
        end
        # Left-click prints the full path, function, and line to the console
        # Right-click calls the edit() function
        sigshow = on(c.mouse.buttonpress) do btn
            if btn.button == 1 || btn.button == 3
                ctx = getgc(c)
                xu, yu = btn.position.x, btn.position.y
                sf = gettag(tagimg, xu, yu)
                clicked[] = sf
                if sf != StackTraces.UNKNOWN
                    if btn.button == 1
                        println(long_info_str(sf))
                    elseif btn.button == 3
                        edit(string(sf.file), sf.line)
                    end
                end
            end
        end
        append!(c.preserved, Any[sigredraw, sigmotion, sigshow])
    end
    return nothing
end

function long_info_str(sf)
    if sf.linfo isa Core.MethodInstance
        string(sf.file, ':', sf.line, ", ", sf.linfo)
    else
        string(sf.file, ':', sf.line, ", ", sf.func, " [inlined]")
    end
end

@guarded function open_cb(::Ptr, settings::Tuple)
    c, gsig, kwargs = settings
    selection = open_dialog("Load profile data", toplevel(c), ("*.jlprof","*"))
    isempty(selection) && return nothing
    return _open(gsig, selection; kwargs...)
end

function _open(gsig, selection; kwargs...)
    ret = load(selection)
    if isa(ret, Node{NodeData})
        gsig[] = ret
    else
        data, lidict = ret::Tuple{Vector{UInt64},Profile.LineInfoDict}
        gsig[] = flamegraph(data; lidict=lidict, kwargs...)
    end
    return nothing
end

@guarded function save_as_cb(::Ptr, profdata::Tuple)
    c, data, lidict, g = profdata
    selection = save_dialog("Save profile data as *.jlprof file", toplevel(c), ("*.jlprof",))
    isempty(selection) && return nothing
    if data === nothing && lidict === nothing
        return _save(selection, g)
    end
    return _save(selection, data, lidict)
end

function _save(selection, args...)
    FileIO.save(File{format"JLPROF"}(selection), args...)
    return nothing
end

@guarded function zoom_fit_cb(::Ptr, zr::Observable{ZoomRegion{T}}) where {T}
    zr[] = GtkObservables.reset(zr[])
    return nothing
end

@guarded function zoom_in_cb(::Ptr, zr::Observable{ZoomRegion{T}}) where {T}
    setindex!(zr, zoom(zr[], 1/2))
    return nothing
end

@guarded function zoom_out_cb(::Ptr, zr::Observable{ZoomRegion{T}}) where {T}
    setindex!(zr, zoom(zr[], 2))
    return nothing
end

@guarded function info_cb(::Ptr, ::Tuple)
    # Note: Keep this updated with the readme
    info = """
    ProfileView.jl Interface Tips
    ----------------------------------------------

    `Ctrl-q` and `Ctrl-w` close the window. You can also use `ProfileView.closeall()` to close all windows opened by ProfileView.

    Left-clicking on a bar will cause information about this line to be printed in the REPL. This can be a convenient way to "mark" lines for later investigation.

    Right-clicking on a bar calls the `edit()` function to open the line in an editor. (On a trackpad, use a 2-fingered tap.)

    CTRL-clicking and dragging will zoom in on a specific region of the image. You can also control the zoom level with CTRL-scroll (or CTRL-swipe up/down).

    CTRL-double-click to restore the full view.

    You can pan the view by clicking and dragging, or by scrolling your mouse/trackpad (scroll=vertical, SHIFT-scroll=horizontal).

    The toolbar at the top includes icons to load and save profile data. Clicking the save icon will prompt you for a filename; you should use extension *.jlprof for any file you save. Launching `ProfileView.view(nothing)` opens a blank window, which you can populate with saved data by clicking on the "open" icon.

    After clicking on a bar, you can type `warntype_last()` and see the result of `code_warntype` for the call represented by that bar.

    `ProfileView.view(windowname="method1")` allows you to name your window, which can help avoid confusion when opening several ProfileView windows simultaneously.

    On Julia 1.8 `ProfileView.view(expand_tasks=true)` creates one tab per task. Expanding by thread is on by default and can be disabled with `expand_threads=false`.

    Using the `graphtype` kwarg for `ProfileView.view` controls how the graph is shown. `:flame` displays from the bottom up, `:icicle` from the top down. The default type can be changed via e.g. `ProfileView.set_graphtype!(:icicle)`, which is stored as a preference for the active environment via `Preferences.jl`.
    """
    info_dialog(info)
    return nothing
end

discardfirstcol(A) = A[:,2:end]
discardfirstcol(A::IndirectArray) = IndirectArray(A.index[:,2:end], A.values)

if ccall(:jl_generating_output, Cint, ()) == 1
    include("precompile.jl")
    _precompile_()
end

end
