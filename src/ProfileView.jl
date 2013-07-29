module ProfileView

include("tree.jl")
include("pvtree.jl")

using .Tree
using .PVTree

using Tk, Color, Base.Graphics
import Cairo

import Base: isequal, show

# TODO: implement zoom

immutable TagData
    ip::Uint
    status::Int
end
TagData(ip::Integer, status::Integer) = TagData(uint(ip), int(status))
const TAGNONE = TagData(0, -1)

const bkg = color("black")
const fontcolor = color("white")
const gccolor = color("red")
const colors = distinguishable_colors(13, [bkg,fontcolor,gccolor])[4:end]

function view(data = Profile.fetch(); C = false, colorgc = true, fontsize = 12, combine = true)
    bt, counts = Profile.tree_aggregate(data)
    if isempty(counts)
        Profile.warning_empty()
        return
    end
    len = Int[length(x) for x in bt]
    keep = len .> 0
    bt = bt[keep]
    counts = counts[keep]
    # Do code address lookups on all unique instruction pointers
    uip = unique(vcat(bt...))
    nuip = length(uip)
    lkupdict = Dict(uip, 1:nuip)
    lkupC = [Profile.lookup(ip, true) for ip in uip]
    lkupJ = [Profile.lookup(ip, false) for ip in uip]
    lidict = Dict(uip, lkupC)
    isjl = Dict(uip, [lkupC[i].line == lkupJ[i].line for i = 1:nuip])
    isgc = Dict(uip, [lkupC[i].func == "jl_gc_collect" for i = 1:nuip])
    isjl[uint(0)] = false  # needed for root below
    isgc[uint(0)] = false
    p = Profile.liperm(lkupC)
    rank = similar(p)
    rank[p] = 1:length(p)
    ip2so = Dict(uip, rank)
    so2ip = Dict(rank, uip)
    # Build the graph
    level = 0
    w = sum(counts)
    root = Tree.Node(PVData(1:w))
    PVTree.buildgraph!(root, bt, counts, 0, ip2so, so2ip, lidict)
#     Tree.showedges(STDOUT, root, x -> string(get(lidict, x.ip, "root"), ", hspan = ", x.hspan, ", status = ", x.status))
    PVTree.prunegraph!(root, C, isjl, isgc)
#     println("\nPruned:")
#     Tree.showedges(STDOUT, root, x -> string(get(lidict, x.ip, "root"), " status = ", x.status))
    # Generate a "tagged" image
    rowtags = {fill(TAGNONE, w)}
    buildtags!(rowtags, root, 1)
    imgtags = hcat(rowtags...)
    img = buildimg(imgtags, colors, bkg, gccolor, colorgc, combine, lidict)
    img24 = [convert(Uint32, convert(RGB24, img[i,j])) for i = 1:size(img,1), j = size(img,2):-1:1]'
    imw = size(img24,2)
    imh = size(img24,1)
    # Display in a window
    win = Toplevel("Profile", 300, 300)
    f = Frame(win)
    pack(f, expand = true, fill = "both")
    c = Canvas(f)
    pack(c, expand = true, fill = "both")    
    function redraw(c)
        ctx = getgc(c)
        w = width(c)
        h = height(c)
        set_coords(ctx, 0, 0, w, h, 0, imw, 0, imh)
        # We largely reimplement Cairo.image() here because we always want to use FILTER_NEAREST
        surf = Cairo.CairoRGBSurface(img24)
        rectangle(ctx, 0, 0, imw, imh)
        save(ctx)
        scale(ctx, imw/surf.width, imh/surf.height)
        set_source(ctx, surf)
        p = Cairo.get_source(ctx)
        Cairo.pattern_set_filter(p, Cairo.CAIRO_FILTER_NEAREST)
        fill_preserve(ctx)
        restore(ctx)
    end
    # From a given position, find the underlying tag
    function gettag(xu, yu)
        x = iceil(xu)
        y = iceil(yu)
        Y = size(imgtags, 2)
        x = max(1, min(x, size(imgtags, 1)))
        y = max(1, min(y, Y))
        imgtags[x,Y-y+1]
    end
    c.resize = function (_)
        redraw(c)
        reveal(c)
        Tk.update()
    end
    # Hover over a block and see the source line
    c.mouse.motion = function (c, xd, yd)
        # Repair image from ovewritten text
        redraw(c)
        # Write the info
        ctx = getgc(c)
        xu, yu = device_to_user(ctx, xd, yd)
        tag = gettag(xu, yu)
        if tag != TAGNONE
            li = lidict[tag.ip]
            str = string(basename(li.file), ", ", li.func, ": line ", li.line)
            set_source(ctx, fontcolor)
            Cairo.set_font_face(ctx, "sans-serif $(fontsize)px")
            Cairo.text(ctx, xu, yu, str, fontsize, xu < imw/3 ? "left" : xu < 2imw/3 ? "center" : "right", "bottom", 0, latex=false)
        end
        reveal(c)
        Tk.update()
    end
    # Right-click prints the full path, function, and line to the console
    c.mouse.button3press = function (c, xd, yd)
        ctx = getgc(c)
        xu, yu = device_to_user(ctx, xd, yd)
        tag = gettag(xu, yu)
        if tag != TAGNONE
            li = lidict[tag.ip]
            println(li.file, ", ", li.func, ": line ", li.line)
        end
    end
    set_size(win, 300, 300)
    c.resize(c)
    nothing
end

function buildtags!(rowtags, parent, level)
    if isleaf(parent)
        return
    end
    w = length(rowtags[1])
    if length(rowtags) < level
        push!(rowtags, fill(TAGNONE, w))
    end
    t = rowtags[level]
    for c in parent
        t[c.data.hspan] = TagData(c.data.ip, c.data.status)
        buildtags!(rowtags, c, level+1)
    end
end

function buildimg(imgtags, colors, bkg, gccolor, colorgc::Bool, combine::Bool, lidict)
    w = size(imgtags,1)
    h = size(imgtags,2)
    img = fill(bkg, w, h)
    colorlen = int(length(colors)/2)
    for j = 1:h
        coloroffset = colorlen*iseven(j)
        colorindex = 1
        lasttag = TAGNONE
        status = 0
        first = 0
        nextcolor = colors[coloroffset + colorindex]
        for i = 1:w
            t = imgtags[i,j]
            if t != TAGNONE
                status |= t.status
                if t != lasttag && (lasttag == TAGNONE || !(combine && lidict[lasttag.ip] == lidict[t.ip]))
                    if first != 0
                        colorindex = fillrow!(img, j, first:i-1, colorindex, colorlen, nextcolor, gccolor, status & colorgc)
                        nextcolor = colors[coloroffset + colorindex]
                        status = t.status
                    end
                    first = i
                    lasttag = t
                end
            else
                if first != 0
                    # We transitioned from tag->none, render the previous range
                    colorindex = fillrow!(img, j, first:i-1, colorindex, colorlen, nextcolor, gccolor, status & colorgc)
                    nextcolor = colors[coloroffset + colorindex]
                    first = 0
                    lasttag = TAGNONE
                end
            end
        end
        if first != 0
            # We got to the end of a row, render the previous range
            fillrow!(img, j, first:w, colorindex, colorlen, nextcolor, gccolor, status & colorgc)
        end
    end
    img
end

function fillrow!(img, j, rng::Range1{Int}, colorindex, colorlen, regcolor, gccolor, status)
    if status > 0
        img[rng,j] = gccolor
        return colorindex
    else
        img[rng,j] = regcolor
        return mod1(colorindex+1, colorlen)
    end
end

end
