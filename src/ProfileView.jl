module ProfileView

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@optlevel"))
    @eval Base.Experimental.@optlevel 1
end

using Profile
using FlameGraphs
using Base.StackTraces: StackFrame
using InteractiveUtils
using Gtk.ShortNames, GtkReactive, Colors, FileIO, IntervalSets
import Cairo
using Graphics

using FlameGraphs: Node, NodeData
using Gtk.GConstants.GdkModifierType: SHIFT, CONTROL, MOD1

export @profview

svgwrite(args...; kwargs...) = error("SVG support has moved to the ProfileSVG package")

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
        Profile.clear()
        @profile $(esc(ex))
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
    nothing
end

const window_wrefs = WeakKeyDict{Gtk.GtkWindowLeaf,Nothing}()

"""
    ProfileView.view([fcolor], data=Profile.fetch(); lidict=nothing, C=false, recur=:off, fontsize=14, kwargs...)

View profiling results. `data` and `lidict` must be a matched pair from `Profile.retrieve()`.
You have several options to control the output, of which the major ones are:

- `fcolor`: an optional coloration function. The main options are `FlameGraphs.FlameColors`
  and `FlameGraphs.StackFrameCategory`.
- `C`: if true, the graph will include stackframes from C code called by Julia.
- `recur`: on Julia 1.4+, collapse recursive calls (see `Profile.print` for more detail)

See [FlameGraphs](https://github.com/timholy/FlameGraphs.jl) for more information.
"""
function view(fcolor, data::Vector{UInt64}; lidict=nothing, C=false, combine=true, recur=:off, pruned=FlameGraphs.defaultpruned, kwargs...)
    g = flamegraph(data; lidict=lidict, C=C, combine=combine, recur=recur, pruned=pruned)
    g === nothing && return nothing
    return view(fcolor, g; data=data, lidict=lidict, kwargs...)
end
function view(fcolor; kwargs...)
    data, lidict = Profile.retrieve()
    view(fcolor, data; lidict=lidict, kwargs...)
end
function view(data::Vector{UInt64}; lidict=nothing, kwargs...)
    view(FlameGraphs.default_colors, data; lidict=lidict, kwargs...)
end
function view(; kwargs...)
    data, lidict = Profile.retrieve()
    view(FlameGraphs.default_colors, data; lidict=lidict, kwargs...)
end

# This method allows user to open a *.jlprof file
view(::Nothing; kwargs...) = view(FlameGraphs.default_colors, Node(NodeData(StackTraces.UNKNOWN, 0, 1:0)); kwargs...)

function view(g::Node{NodeData}; kwargs...)
    view(FlameGraphs.default_colors, g; kwargs...)
end
function view(fcolor, g::Node{NodeData}; data=nothing, lidict=nothing, kwargs...)
    gsig = Signal(g)  # allow substitution by the open dialog
    # Display in a window
    c = canvas(UserUnit)
    set_gtk_property!(widget(c), :expand, true)
    f = Frame(c)
    tb = Toolbar()
    bx = Box(:v)
    push!(bx, tb)
    push!(bx, f)
    tb_open = ToolButton("gtk-open")
    tb_save_as = ToolButton("gtk-save-as")
    push!(tb, tb_open)
    push!(tb, tb_save_as)
    # FIXME: likely have to do `allkwargs` in the two below (add in C, combine, recur)
    signal_connect(open_cb, tb_open, "clicked", Nothing, (), false, (widget(c),gsig,kwargs))
    signal_connect(save_as_cb, tb_save_as, "clicked", Nothing, (), false, (widget(c),data,lidict))
    win = Window("Profile", 800, 600)
    push!(win, bx)
    GtkReactive.gc_preserve(win, c)
    # Register the window with closeall
    window_wrefs[win] = nothing
    signal_connect(win, :destroy) do w
        delete!(window_wrefs, win)
    end

    fdraw = viewprof(fcolor, c, gsig; kwargs...)
    GtkReactive.gc_preserve(win, fdraw)

    # Ctrl-w and Ctrl-q destroy the window
    signal_connect(win, "key-press-event") do w, evt
        if evt.state == CONTROL && (evt.keyval == UInt('q') || evt.keyval == UInt('w'))
            @async destroy(w)
            nothing
        end
    end

    Gtk.showall(win)
end

function viewprof(fcolor, c, gsig; fontsize=14)
    # From a given position, find the underlying tag
    function gettag(tagimg, xu, yu)
        x = ceil(Int, Float64(xu))
        y = ceil(Int, Float64(yu))
        Y = size(tagimg, 2)
        x = max(1, min(x, size(tagimg, 1)))
        y = max(1, min(y, Y))
        tagimg[x,Y-y+1]
    end
    map(gsig) do g
        isempty(g.data.span) && return nothing
        img = flamepixels(fcolor, g)
        tagimg = flametags(g, img)
        # The first column corresponds to the bottom row, which is our fake root node. Get rid of it.
        img, tagimg = img[:,2:end], tagimg[:,2:end]
        img24 = reverse(RGB24.(img), dims=2)
        fv = XY(0.0..size(img24,1), 0.0..size(img24,2))
        zr = Signal(ZoomRegion(fv, fv))
        sigrb = init_zoom_rubberband(c, zr)
        sigpd = init_pan_drag(c, zr)
        sigzs = init_zoom_scroll(c, zr)
        sigps = init_pan_scroll(c, zr)
        surf = Cairo.CairoImageSurface(img24)
        sigredraw = draw(c, zr) do widget, r
            ctx = getgc(widget)
            set_coordinates(ctx, r)
            rectangle(ctx, BoundingBox(r.currentview))
            set_source(ctx, surf)
            p = Cairo.get_source(ctx)
            Cairo.pattern_set_filter(p, Cairo.FILTER_NEAREST)
            fill(ctx)
        end
        lasttextbb = BoundingBox(1,0,1,0)
        sigmotion = map(c.mouse.motion) do btn
            # Repair image from ovewritten text
            if c.widget.is_realized && c.widget.is_sized
                ctx = getgc(c)
                if Graphics.width(lasttextbb) > 0
                    r = value(zr)
                    set_coordinates(ctx, r)
                    rectangle(ctx, lasttextbb)
                    set_source(ctx, surf)
                    p = Cairo.get_source(ctx)
                    Cairo.pattern_set_filter(p, Cairo.FILTER_NEAREST)
                    fill(ctx)
                end
                # Write the info
                xu, yu = btn.position.x, btn.position.y
                sf = gettag(tagimg, xu, yu)
                if sf != StackTraces.UNKNOWN
                    str = string(basename(string(sf.file)), ", ", sf.func, ": line ", sf.line)
                    set_source(ctx, fcolor(:font))
                    Cairo.set_font_face(ctx, "sans-serif $(fontsize)px")
                    xi = value(zr).currentview.x
                    xmin, xmax = minimum(xi), maximum(xi)
                    lasttextbb = deform(Cairo.text(ctx, xu, yu, str, halign = xu < (2xmin+xmax)/3 ? "left" : xu < (xmin+2xmax)/3 ? "center" : "right"), -2, 2, -2, 2)
                end
                reveal(c)
            end
        end
        # Left-click prints the full path, function, and line to the console
        # Right-click calls the edit() function
        sigshow = map(c.mouse.buttonpress) do btn
            if btn.button == 1 || btn.button == 3
                ctx = getgc(c)
                xu, yu = btn.position.x, btn.position.y
                sf = gettag(tagimg, xu, yu)
                if sf != StackTraces.UNKNOWN
                    if btn.button == 1
                        if sf.linfo isa Core.MethodInstance
                            println(sf.file, ':', sf.line, ", ", sf.linfo)
                        else
                            println(sf.file, ':', sf.line, ", ", sf.func, " [inlined]")
                        end
                    elseif btn.button == 3
                        edit(string(sf.file), sf.line)
                    end
                end
            end
        end
        append!(c.preserved, [sigrb, sigpd, sigzs, sigps, sigredraw, sigmotion, sigshow])
        return nothing
    end
end

@guarded function open_cb(::Ptr, settings::Tuple)
    c, gsig, kwargs = settings
    selection = open_dialog("Load profile data", toplevel(c), ("*.jlprof","*"))
    isempty(selection) && return nothing
    data, lidict = load(selection)
    push!(gsig, flamegraph(data; lidict=lidict, kwargs...))
    return nothing
end

@guarded function save_as_cb(::Ptr, profdata::Tuple)
    c, data, lidict = profdata
    selection = save_dialog("Save profile data as *.jlprof file", toplevel(c), ("*.jlprof",))
    isempty(selection) && return nothing
    FileIO.save(File(format"JLPROF", selection), data, lidict)
    return nothing
end

# include("precompile.jl")
# _precompile_()

end
