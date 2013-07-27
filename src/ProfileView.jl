module ProfileView

using Tk, Color, Base.Graphics
import Cairo

import Base: first, show

export profview

function profview(data = Profile.fetch(); C = true)
    bt, counts = Profile.tree_aggregate(data)
    if isempty(counts)
        Profile.warning_empty()
        return
    end
    level = 0
    len = Int[length(x) for x in bt]
    keep = len .> 0
    bt = bt[keep]
    counts = counts[keep]
    # Initialize the graph
    w = sum(counts)
    g = Node(1:w)
    # Build the graph recursively
    buildgraph!(g, bt, counts, 0, C)
    # Generate a "tagged" image
    ls = linspace(0,100,15)
    cs = linspace(-100,100,15)
    hs = linspace(0,340,20)
    bkg = color("black")
    fontcolor = color("white")
    colors = convert(Array{RGB}, distinguishable_colors(20, identity, bkg, ls, cs, hs))
    rows = {fill(bkg, w)}
    tags = {fill(0, w)}
    nodelist = Array(Node, 0)
    buildimg!(rows, tags, nodelist, g, 1, colors[2:end], bkg)
    img = hcat(rows...)
    imgtags = hcat(tags...)
    img32 = [convert(Uint32, convert(RGB24, img[i,j])) for i = 1:size(img,1), j = size(img,2):-1:1]'
    imw = size(img32,2)
    imh = size(img32,1)
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
        # We do much of the work in Cairo.image() because we want to use FILTER_NEAREST
        surf = Cairo.CairoRGBSurface(img32)
        rectangle(ctx, 0, 0, imw, imh)
        save(ctx)
        scale(ctx, imw/surf.width, imh/surf.height)
        set_source(ctx, surf)
        p = Cairo.get_source(ctx)
        Cairo.pattern_set_filter(p, Cairo.CAIRO_FILTER_NEAREST)
        fill_preserve(ctx)
        restore(ctx)
    end
    function gettag(xu, yu)
        x = iround(xu)
        y = iround(yu)
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
    c.mouse.motion = function (c, xd, yd)
        # Repair image from ovewritten text
        redraw(c)
        # Write the info
        ctx = getgc(c)
        xu, yu = device_to_user(ctx, xd, yd)
        indx = gettag(xu, yu)
        if indx > 0
            node = nodelist[indx]
            str = string(node.file, ", ", node.func, ": line ", node.line)
            set_source(ctx, fontcolor)
            Cairo.text(ctx, xu, yu, str, 10, xu < imw/3 ? "left" : xu < 2imw/3 ? "center" : "right", "bottom", 0)
        end
        reveal(c)
        Tk.update()
    end
    set_size(win, 300, 300)
    c.resize(c)
end

type Node
    hspan::Range1{Int}  # horizontal span in one row of the graph
    file::ASCIIString
    func::ASCIIString
    line::Int
    parent::Node
    children::Vector{Node}
    
    # Contructor for the head of the tree
    function Node(r::Range1{Int})
        n = new(r, "", "", 0)
        n.parent = n
        n.children = Array(Node, 0)
        n
    end
    
    # Constructor for children
    function Node(r::Range1{Int}, file::ASCIIString, func::ASCIIString, line::Int, p::Node)
        n = new(r, file, func, line, p, Array(Node, 0))
    end
end

first(n::Node) = first(n.hspan)

function show(io::IO, n::Node)
    println(io, "Profile node:")
    println(io, "  file: ", n.file)
    println(io, "  function: ", n.func)
    println(io, "  line: ", n.line)
    println(io, "  hspan: ", n.hspan)
    if n.parent == n
        println(io, "  <root>")
    end
    len = length(n.children)
    println(io, "  ", len, len == 1 ? " child" : " children")
end

function buildgraph!(g::Node, bt::Vector{Vector{Uint}}, counts::Vector{Int}, level::Int, doCframes::Bool)
    # Organize backtraces into groups that are identical up to this level
    # This is like combine=true in the text-based display
    d = (Profile.LineInfo=>Vector{Int})[]
    for i = 1:length(bt)
        ip = bt[i][level+1]
        key = Profile.lookup(ip, doCframes)
        indx = Base.ht_keyindex(d, key)
        if indx == -1
            d[key] = [i]
        else
            push!(d.vals[indx], i)
        end
    end
    # Generate counts
    dlen = length(d)
    lilist = Array(Profile.LineInfo, dlen)
    group = Array(Vector{Int}, dlen)
    n = Array(Int, dlen)
    i = 1
    for (key, v) in d
        lilist[i] = key
        group[i] = v
        n[i] = sum(counts[v])
        i += 1
    end
    # Order the line information
    p = Profile.liperm(lilist)
    lilist = lilist[p]
    group = group[p]
    n = n[p]
    # Generate the children
    s = first(g)
    for i = 1:length(n)
        li = lilist[i]
        push!(g.children, Node(s:(s+n[i]-1), li.file, li.func, li.line, g))
        s += n[i]
    end
    # Recurse to the next level
    len = Int[length(x) for x in bt]
    for i = 1:length(lilist)
        idx = group[i]
        keep = len[idx] .> level+1
        if any(keep)
            idx = idx[keep]
            buildgraph!(g.children[i], bt[idx], counts[idx], level+1, doCframes)
        end
    end
end

function buildimg!(rows, tags, nodelist, g, level, colors, bkg)
    if isempty(g.children)
        return
    end
    w = length(rows[1])
    if length(rows) < level
        push!(rows, fill(bkg, w))
        push!(tags, fill(0, w))
    end
    r = rows[level]
    t = tags[level]
    colorlen = int(length(colors)/2)
    coloroffset = colorlen*iseven(level)
    for i = 1:length(g.children)
        c = g.children[i]
        r[c.hspan] = colors[mod1(i,colorlen)+coloroffset]
        push!(nodelist, c)
        t[c.hspan] = length(nodelist)
        buildimg!(rows, tags, nodelist, c, level+1, colors, bkg)
    end
end

end
