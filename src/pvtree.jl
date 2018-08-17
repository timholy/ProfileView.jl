module PVTree

using ..Tree

export PVData, buildgraph!, prunegraph!

# ProfileView data we need attached to each node of the graph:
mutable struct PVData
    ip::UInt           # the instruction pointer
    hspan::UnitRange{Int} # horizontal span (used as the x-axis in display)
    status::Int        # nonzero for special handling, (e.g., gc events)
end
PVData(hspan::UnitRange{Int}) = PVData(UInt(0), hspan, 0)
PVData(ip::UInt, hspan::UnitRange{Int}) = PVData(ip, hspan, 0)

# Suppose we have several dicts:
#    isjl[ip]: true/false depending on whether it's a Julia function rather than C/Fortran
#    isgc[ip]: true if a garbage-collection event. Also have flaggc=true/false; if flaggc==true, display parent Julia call in red
#    ip2so[ip]: an integer giving the "sortorder", the rank in a sorted list of strings associated with unique ip's. Note this mapping can implement "combine".
#    so2ip[so]: convert the sortorder back into an instruction pointer.
#    lidict[ip]: the line information (func, file, line #)

# Build the whole graph. Later we'll prune it depending on C=true/false
# ("peeking ahead" for gc events will be easier if we have the whole thing)
# lidict is just for debugging
function buildgraph!(parent::Node, bt::Vector{Vector{UInt}}, counts::Vector{Int}, level::Int, ip2so::Dict, so2ip::Dict, lidict)
    # Organize backtraces into groups that are identical up to this level
    dorder = Dict{Int,Vector{Int}}()
    for i = 1:length(bt)
        ip = bt[i][level+1]
        so = ip2so[ip]
        indx = Base.ht_keyindex(dorder, so)
        if indx == -1
            dorder[so] = [i]
        else
            push!(dorder.vals[indx], i)
        end
    end
    ngroups = length(dorder)
    group = Vector{Vector{Int}}(undef, ngroups)  # indices in bt that have the same sortorder
    n = Array{Int}(undef, ngroups)              # aggregated counts for this group
    order = Array{Int}(undef, ngroups)
    i = 1
    for (key, v) in dorder
        order[i] = key
        group[i] = v
        n[i] = sum(counts[v])
        i += 1
    end
    # Order the line information
    p = sortperm(order)
    order = order[p]
    group = group[p]
    n = n[p]
#     if length(order) > 1
#         print(get(lidict, parent.data.ip, "root"), " has children:")
#         for i = 1:length(order)
#             print("  ", lidict[so2ip[order[i]]])
#         end
#         println("\n")
#     end
    # Generate the children
    hstart = first(parent.data.hspan)
    c = addchild(parent, PVData(so2ip[order[1]], hstart:(hstart+n[1]-1)))
    hstart += n[1]
    for i = 2:ngroups
        c = addsibling(c, PVData(so2ip[order[i]], hstart:(hstart+n[i]-1)))
        hstart += n[i]
    end
    # Recurse to the next level
    len = Int[length(x) for x in bt]
    i = 0
    for c in parent
        idx = group[i+=1]
        keep = len[idx] .> level+1
        if any(keep)
            idx = idx[keep]
            buildgraph!(c, bt[idx], counts[idx], level+1, ip2so, so2ip, lidict)
        end
    end
end

function setstatus!(parent::Node, isgc::Dict)
    if isgc[parent.data.ip]
        parent.data.status = 1
    end
    for c in parent
        setstatus!(c, isgc)
    end
end

# The last three inputs are just for debugging
function prunegraph!(parent::Node, isjl::Dict, lidict, ip2so, counts,
                     pruned_set)
    if parent.data.ip != 0 && !isempty(counts)
        counts[ip2so[parent.data.ip]] += 1
    end
    if parent.data.ip != 0 && parent.data.ip in pruned_set
        parent.child = parent
    end
    c = parent.child
    if parent == c
        return
    end
    parent.child = parent  # mark as a leaf unless we keep some children
    lastc = c
    isfirst = true
    while true
        prunegraph!(c, isjl, lidict, ip2so, counts, pruned_set)
        if !isjl[c.data.ip]
            parent.data.status |= c.data.status
            if !isleaf(c)
                # It has Julia children, splice them in
                if isfirst
                    parent.child = c.child
                    isfirst = false
                else
                    lastc.sibling = c.child
                end
                lastc = lastsibling(c.child)
            end
        else
            if isfirst
                parent.child = c
            else
                lastc.sibling = c
            end
            isfirst = false
            lastc = c
        end
        if c.sibling == c
            lastc.sibling = lastc.sibling
            break
        end
        c = c.sibling
    end
end


end
