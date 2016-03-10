VERSION >= v"0.4.0-dev+6521" && __precompile__()

module ProfileViewGtk

using Gtk.ShortNames, GtkUtilities, Colors, FileIO
import Cairo
if VERSION < v"0.4.0-dev+3275"
    using Base.Graphics
else
    using Graphics
end

type ZoomCanvas
    bb::BoundingBox  # in user-coordinates
    c::Canvas
end

function __init__()
    eval(Expr(:import, :ProfileView))
end

function view(data = Profile.fetch(); lidict=nothing, kwargs...)
    bt, uip, counts, lidict, lkup = ProfileView.prepare_data(data, lidict)
    # Display in a window
    c = @Canvas()
    setproperty!(c, :expand, true)
    f = @Frame(c)
    tb = @Toolbar()
    bx = @Box(:v)
    push!(bx, tb)
    push!(bx, f)
    tb_open = @ToolButton("gtk-open")
    tb_save_as = @ToolButton("gtk-save-as")
    push!(tb, tb_open)
    push!(tb, tb_save_as)
    signal_connect(open_cb, tb_open, "clicked", Void, (), false, (c,kwargs))
    signal_connect(save_as_cb, tb_save_as, "clicked", Void, (), false, (c,data,lidict,kwargs))
    win = @Window(bx, "Profile")
    if data != nothing && !isempty(data)
        viewprof(c, bt, uip, counts, lidict, lkup; kwargs...)
    end
    showall(win)
end

function viewprof(c, bt, uip, counts, lidict, lkup; C = false, colorgc = true, fontsize = 12, combine = true)
    img, lidict, imgtags = ProfileView.prepare_image(bt, uip, counts, lidict, lkup, C, colorgc, combine)
    img24 = UInt32[convert(UInt32, convert(RGB24, img[i,j])) for i = 1:size(img,1), j = size(img,2):-1:1]'
    surf = Cairo.CairoRGBSurface(img24)
    imw = size(img24,2)
    imh = size(img24,1)
    panzoom(c, (0,imw), (0,imh))
    panzoom_mouse(c)
    panzoom_key(c)
    lasttextbb = BoundingBox(1,0,1,0)
    standard_motion = function (c, event)
        # Repair image from ovewritten text
        ctx = getgc(c)
        w = width(c)
        if width(lasttextbb) > 0
            h = height(c)
            xview, yview = guidata[c, :xview], guidata[c, :yview]
            set_coords(ctx, xview, yview)
            rectangle(ctx, lasttextbb)
            set_source(ctx, surf)
            p = Cairo.get_source(ctx)
            Cairo.pattern_set_filter(p, Cairo.FILTER_NEAREST)
            fill(ctx)
        end
        # Write the info
        xd, yd = event.x, event.y
        xu, yu = device_to_user(ctx, xd, yd)
        tag = gettag(xu, yu)
        if tag != ProfileView.TAGNONE
            li = lidict[tag.ip]
            str = string(basename(string(li.file)), ", ", li.func, ": line ", li.line)
            set_source(ctx, ProfileView.fontcolor)
            Cairo.set_font_face(ctx, "sans-serif $(fontsize)px")
            lasttextbb = deform(Cairo.text(ctx, xu, yu, str, halign = xd < w/3 ? "left" : xd < 2w/3 ? "center" : "right"), -2, 2, -2, 2)
        end
        reveal(c)
    end
    c.mouse.motion = standard_motion
    draw(c) do widget
        ctx = getgc(widget)
        w = width(widget)
        h = height(widget)
        xview, yview = guidata[c, :xview], guidata[c, :yview]
        set_coords(ctx, xview, yview)
        rectangle(ctx, xview.min, yview.min, width(xview), width(yview))
        set_source(ctx, surf)
        p = Cairo.get_source(ctx)
        Cairo.pattern_set_filter(p, Cairo.FILTER_NEAREST)
        fill(ctx)
    end
    # From a given position, find the underlying tag
    function gettag(xu, yu)
        x = ceil(Int, xu)
        y = ceil(Int, yu)
        Y = size(imgtags, 2)
        x = max(1, min(x, size(imgtags, 1)))
        y = max(1, min(y, Y))
        imgtags[x,Y-y+1]
    end
    # Hover over a block and see the source line
    # Right-click prints the full path, function, and line to the console
    c.mouse.button3press = function (c, event)
        ctx = getgc(c)
        xd, yd = event.x, event.y
        xu, yu = device_to_user(ctx, xd, yd)
        tag = gettag(xu, yu)
        if tag != ProfileView.TAGNONE
            li = lidict[tag.ip]
            println(li.file, ", ", li.func, ": line ", li.line)
        end
    end
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
