module ProfileViewGtk

using InteractiveUtils
using Gtk.ShortNames, GtkReactive, Colors, FileIO, IntervalSets
import Cairo
using Graphics

using Gtk.GConstants.GdkModifierType: SHIFT, CONTROL, MOD1

mutable struct ZoomCanvas
    bb::BoundingBox  # in user-coordinates
    c::Canvas
end

function __init__()
    @eval import ProfileView
end

function closeall()
    for (w, _) in window_wrefs
        destroy(w)
    end
    nothing
end

const window_wrefs = WeakKeyDict{Gtk.GtkWindowLeaf,Nothing}()

function view(data = Profile.fetch(); lidict=nothing, kwargs...)
    bt, uip, counts, lidict, lkup = ProfileView.prepare_data(data, lidict)
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
    signal_connect(open_cb, tb_open, "clicked", Nothing, (), false, (widget(c),kwargs))
    signal_connect(save_as_cb, tb_save_as, "clicked", Nothing, (), false, (widget(c),data,lidict,kwargs))
    win = Window(bx, "Profile")
    GtkReactive.gc_preserve(win, c)
    # Register the window with closeall
    window_wrefs[win] = nothing
    signal_connect(win, :destroy) do w
        delete!(window_wrefs, win)
    end

    if data != nothing && !isempty(data)
        viewprof(c, bt, uip, counts, lidict, lkup; kwargs...)
    end

    # Ctrl-w and Ctrl-q destroy the window
    signal_connect(win, "key-press-event") do w, evt
        if evt.state == CONTROL && (evt.keyval == UInt('q') || evt.keyval == UInt('w'))
            @async destroy(w)
            nothing
        end
    end

    Gtk.showall(win)
end

function viewprof(c, bt, uip, counts, lidict, lkup; C = false, colorgc = true, fontsize = 12, combine = true, pruned=[])
    img, lidict, imgtags = ProfileView.prepare_image(bt, uip, counts, lidict, lkup, C, colorgc, combine, pruned)
    img24 = Matrix(UInt32[reinterpret(UInt32, convert(RGB24, img[i,j])) for i = 1:size(img,1), j = size(img,2):-1:1]')
    fv = XY(0.0..size(img24,2), 0.0..size(img24,1))
    zr = Signal(ZoomRegion(fv, fv))
    sigrb = init_zoom_rubberband(c, zr)
    sigpd = init_pan_drag(c, zr)
    sigzs = init_zoom_scroll(c, zr)
    sigps = init_pan_scroll(c, zr)
    surf = Cairo.CairoRGBSurface(img24)
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
            tag = gettag(xu, yu)
            if tag != ProfileView.TAGNONE
                li = lidict[tag.ip]
                str = ""
                for l in li
                    str = string(str, string(basename(string(l.file)), ", ", l.func, ": line ", l.line), "; ")
                end
                set_source(ctx, ProfileView.fontcolor)
                Cairo.set_font_face(ctx, "sans-serif $(fontsize)px")
                xi = value(zr).currentview.x
                xmin, xmax = minimum(xi), maximum(xi)
                lasttextbb = deform(Cairo.text(ctx, xu, yu, str, halign = xu < (2xmin+xmax)/3 ? "left" : xu < (xmin+2xmax)/3 ? "center" : "right"), -2, 2, -2, 2)
            end
            reveal(c)
        end
    end
    # From a given position, find the underlying tag
    function gettag(xu, yu)
        x = ceil(Int, Float64(xu))
        y = ceil(Int, Float64(yu))
        Y = size(imgtags, 2)
        x = max(1, min(x, size(imgtags, 1)))
        y = max(1, min(y, Y))
        imgtags[x,Y-y+1]
    end
    # Hover over a block and see the source line
    # Left-click prints the full path, function, and line to the console
    # Right-click calls the edit() function
    sigshow = map(c.mouse.buttonpress) do btn
        if btn.button == 1 || btn.button == 3
            ctx = getgc(c)
            xu, yu = btn.position.x, btn.position.y
            tag = gettag(xu, yu)
            if tag != ProfileView.TAGNONE
                li = lidict[tag.ip]
                if btn.button == 1
                    firstline = true
                    for l in li
                        if !firstline
                            print("  ")
                        else
                            firstline = false
                        end
                        println(l.file, ", ", l.func, ": line ", l.line)
                    end
                elseif btn.button == 3
                    if !isempty(li)
                        l = first(li)
                        edit(string(l.file),l.line)
                    end
                end
            end
        end
    end
    append!(c.preserved, [sigrb, sigpd, sigzs, sigps, sigredraw, sigmotion, sigshow])
    nothing
end

function open_cb(::Ptr, settings::Tuple)
    c, kwargs = settings
    selection = open_dialog("Load profile data", toplevel(c), ("*.jlprof","*"))
    isempty(selection) && return nothing
    data, lidict = load(File(format"JLD", selection), "li", "lidict")
    bt, uip, counts, lidict, lkup = ProfileView.prepare_data(data, lidict)
    viewprof(c, bt, uip, counts, lidict, lkup; kwargs...)
    nothing
end

function save_as_cb(::Ptr, profdata::Tuple)
    c, data, lidict = profdata
    selection = save_dialog("Save profile data as JLD file", toplevel(c), ("*.jlprof",))
    isempty(selection) && return nothing
    FileIO.save(File(format"JLD", selection), "li", data, "lidict", lidict)
    nothing
end

end
