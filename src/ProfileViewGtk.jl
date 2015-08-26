VERSION >= v"0.4.0-dev+6521" && __precompile__()

module ProfileViewGtk

using Gtk.ShortNames, GtkUtilities, Colors
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

function view(data = Profile.fetch(); C = false, lidict = nothing, colorgc = true, fontsize = 12, combine = true)
    img, lidict, imgtags = ProfileView.prepare(data, C=C, lidict=lidict, colorgc=colorgc, combine=combine)
    img24 = Uint32[convert(Uint32, convert(RGB24, img[i,j])) for i = 1:size(img,1), j = size(img,2):-1:1]'
    surf = Cairo.CairoRGBSurface(img24)
    imw = size(img24,2)
    imh = size(img24,1)
    # Display in a window
    c = @Canvas()
    f = @Frame(c)
    win = @Window(f, "Profile")
    czoom = ZoomCanvas(BoundingBox(0, imw, 0, imh), c)
    c.mouse.button1press = (widget, event) -> begin
        if event.event_type == Gtk.GdkEventType.BUTTON_PRESS
            c.mouse.motion = (c, event) -> nothing
            rubberband_start(c, event.x, event.y, (c, bb) -> zoom_bb(czoom, bb))
        elseif event.event_type == Gtk.GdkEventType.DOUBLE_BUTTON_PRESS
            zoom_reset(czoom)
        end
    end
    lasttextbb = BoundingBox(1,0,1,0)
    imgbb = BoundingBox(0, imw, 0, imh)
    standard_motion = function (c, event)
        # Repair image from ovewritten text
        ctx = getgc(c)
        w = width(c)
        if width(lasttextbb) > 0
            h = height(c)
            winbb = BoundingBox(0, w, 0, h)
            set_coords(ctx, winbb, czoom.bb)
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
            str = string(basename(li.file), ", ", li.func, ": line ", li.line)
            set_source(ctx, ProfileView.fontcolor)
            Cairo.set_font_face(ctx, "sans-serif $(fontsize)px")
            lasttextbb = deform(Cairo.text(ctx, xu, yu, str, halign = xd < w/3 ? "left" : xd < 2w/3 ? "center" : "right"), -2, 2, -2, 2)
        end
        reveal(c)
    end
    c.mouse.motion = standard_motion
    function zoom_bb(czoom::ZoomCanvas, bb::BoundingBox)
        czoom.bb = bb & imgbb
        redraw(czoom.c)
        reveal(czoom.c)
        c.mouse.motion = standard_motion
    end
    function zoom_reset(czoom::ZoomCanvas)
        czoom.bb = imgbb
        redraw(czoom.c)
        reveal(czoom.c)
        c.mouse.motion = standard_motion
    end
    function redraw(c)
        ctx = getgc(c)
        w = width(c)
        h = height(c)
        cbb = czoom.bb
        winbb = BoundingBox(0, w, 0, h)
        set_coords(ctx, winbb, cbb)
        rectangle(ctx, cbb)
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
    c.resize = function (_)
        redraw(c)
        reveal(c)
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
    showall(win)
    nothing
end

end
