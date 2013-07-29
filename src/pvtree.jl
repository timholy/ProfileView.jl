module PVTree

using ..Tree

export PVData, buildgraph!, prunegraph!

# ProfileView data we need attached to each node of the graph:
type PVData
    ip::Uint           # the instruction pointer
    hspan::Range1{Int} # horizontal span (used as the x-axis in display)
    status::Int        # nonzero for special handling, (e.g., gc events)
end
PVData(hspan::Range1{Int}) = PVData(uint(0), hspan, 0)
PVData(ip::Uint, hspan::Range1{Int}) = PVData(ip, hspan, 0)

# Suppose we have several dicts:
#    isjl[ip]: true/false depending on whether it's a Julia function rather than C/Fortran
#    isgc[ip]: true if a garbage-collection event. Also have flaggc=true/false; if flaggc==true, display parent Julia call in red
#    ip2so[ip]: an integer giving the "sortorder", the rank in a sorted list of strings associated with unique ip's. Note this mapping can implement "combine".
#    so2ip[so]: convert the sortorder back into an instruction pointer. It's possible that so2ip[ip2so[ip]] != ip, but they do resolve to the same lineinfo
#    lineinfo[ip]: the line information (func, file, line #)

# Build the whole graph. Later we'll prune it depending on C=true/false
# ("peeking ahead" for gc events will be easier if we have the whole thing)
function buildgraph!(parent::Node, bt::Vector{Vector{Uint}}, counts::Vector{Int}, level::Int, ip2so::Dict, so2ip::Dict, lidict)
    # Organize backtraces into groups that are identical up to this level
    dorder = (Int=>Vector{Int})[]
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
    group = Array(Vector{Int}, ngroups)  # indices in bt that have the same sortorder
    n = Array(Int, ngroups)              # aggregated counts for this group
    order = Array(Int, ngroups)
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

# Updates the status and, if C == false, prunes any "C" children
function prunegraph!(parent::Node, C::Bool, isjl::Dict, isgc::Dict)
    pisjl = isjl[parent.data.ip]
    firstchild = true
    prevchild = parent.child
    for c in parent
        if isgc[c.data.ip] && (pisjl || !C)
            parent.data.status = 1  # marks parent as triggering garbage collection
        end
        if !C
            newc = prunegraph!(c, C, isjl, isgc)
            if newc != parent
                # newc is a valid child
                if firstchild
                    parent.child = newc
                    firstchild = false
                else
                    prevchild.sibling = newc
                end
                # one child might have become several children
                prevchild = (newc == c) ? newc : lastsibling(newc)
            elseif firstchild
                # mark it tentatively as a leaf so it can be clipped
                parent.child = parent
            end
        end
    end
    if !C && !pisjl
        if isleaf(parent)
            # Prune entirely
            parent.parent.data.status |= parent.data.status
            return parent.parent
        else
            return parent.child
        end
    end
    parent
end

end
