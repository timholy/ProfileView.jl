using Compose

function prepare_compose(data; C = false, lidict = nothing, colorgc = true, combine = true)
    bt, counts = Profile.tree_aggregate(data)
    if isempty(counts)
        Profile.warning_empty()
        return
    end
    len = Int[length(x) for x in bt]
    keep = len .> 0
    if length(data) == Profile.maxlen_data()
        keep[end] = false
    end
    bt = bt[keep]
    counts = counts[keep]
    # Do code address lookups on all unique instruction pointers
    uip = unique(vcat(bt...))
    nuip = length(uip)
    if lidict == nothing
        lkup = [Profile.lookup(ip) for ip in uip]
        lidict = Dict(uip, lkup)
    else
        lkup = [lidict[ip] for ip in uip]
    end
    isjl = Dict(uip, [!lkup[i].fromC for i = 1:nuip])
    isgc = Dict(uip, [lkup[i].func == "jl_gc_collect" for i = 1:nuip])
    isjl[uint(0)] = false  # needed for root below
    isgc[uint(0)] = false
    p = Profile.liperm(lkup)
    rank = similar(p)
    rank[p] = 1:length(p)
    ip2so = Dict(uip, rank)
    so2ip = Dict(rank, uip)
    # Build the graph
    level = 0
    w = sum(counts)
    root = Tree.Node(PVData(1:w))
    PVTree.buildgraph!(root, bt, counts, 0, ip2so, so2ip, lidict)
    PVTree.setstatus!(root, isgc)
#     Tree.showedges(STDOUT, root, x -> string(get(lidict, x.ip, "root"), ", hspan = ", x.hspan, ", status = ", x.status))
#     Tree.showedges(STDOUT, root, x -> string(get(lidict, x.ip, "root"), ", status = ", x.status))
#     Tree.showedges(STDOUT, root, x -> x.status == 0 ? nothing : string(get(lidict, x.ip, "root"), ", status = ", x.status))
#     checkidentity(ip2so, so2ip)
#     checkcontains(root, ip2so, so2ip, lidict)
#     checkstatus(root, isgc, isjl, C, lidict)
    counts = zeros(Int, length(uip))
    if !C
        PVTree.prunegraph!(root, isjl, lidict, ip2so, counts)
    end
#     Tree.showedges(STDOUT, root, x -> string(get(lidict, x.ip, "root"), ", status = ", x.status))

    depth = getTreeDepth(root)

    return lidict, root, depth

    # Generate a "tagged" image
    # rowtags = {fill(TAGNONE, w)}
    # buildtags!(rowtags, root, 1)
    # imgtags = hcat(rowtags...)
    # img = buildimg(imgtags, colors, bkg, gccolor, colorgc, combine, lidict)
    # img, lidict, imgtags, root
end

function compose_view(data = Profile.fetch(); C = false, lidict = nothing, colorgc = true, fontsize = 12, combine = true, backend = nothing)
    lidict, root, depth = prepare_compose(data, C=C, lidict=lidict, colorgc=colorgc, combine=combine)

    if backend == nothing
        img = SVGJS(10inch, (depth + 5)*0.25inch) # Add space for text
    else
        img = backend
    end

    draw(img, compose(context(), compose_tree(root.child, root, 1, lidict, 1.0/depth)))
end

function compose_tree(node, parent, level, lidict, Δh)
    nspan = node.data.hspan
    pspan = parent.data.hspan

    x0 = (first(nspan) - first(pspan))/length(pspan)
    Δx = length(nspan)/length(pspan)
    pcontext = context(x0, 0, Δx, 1)
    ccontexts = Array(Context, 0)
    lineinfo = lidict[node.data.ip]
    
    # Should probably be handled by javascript.  That way
    # the text can automatically fill in as the user zooms in.
    str = @sprintf("%s in %s: %d", lineinfo.func, lineinfo.file, lineinfo.line)
    if length(nspan) < 3
        str = ""
    elseif length(nspan) < length(str)
        str =  str[1:int(length(nspan) - 3)] * "..."
    end

    if node.child == node
        return compose(pcontext,
        (context(0, 0, 1, 1), text(1mm, 1-(level-0.5)*Δh, str, hleft, vcenter), fontsize(4)),
        (context(0, 0, 1, 1), rectangle(0, 1-level*Δh, 1, Δh), fill("white"), stroke("black")))
    end 
    
    for child in node
        push!(ccontexts, compose_tree(child, node, level+1, lidict, Δh))
    end
    
    return compose(pcontext,
        (context(0, 0, 1, 1), text(1mm, 1-(level-0.5)*Δh, str, hleft, vcenter), fontsize(4)),
        (context(0, 0, 1, 1), rectangle(0, 1-level*Δh, 1, Δh), fill("white"), stroke("black")),
        ccontexts...)
end

function getTreeDepth(parent)
    if isleaf(parent)
        return 0
    end

    depth = 0
    for c in parent
        depth = max(depth, getTreeDepth(c))
    end
    return depth + 1
end
