module Tree

import Base: iterate, show

export Node,
    addchild,
    addsibling,
    isroot,
    isleaf,
    lastsibling

# "Left-child, right-sibling" tree representation:
# Suppose a particular node, "A", has 3 children, "a", "b", and "c".
#     "a", "b", and "c" link to "A" as their parent.
#     "A" links "a" as its child; "a" links "b" as its sibling, and "b" links "c" as its sibling.
#     Any missing links (e.g., "c" does not have a sibling) link back to itself (c.sibling == c)
# With this organization, no arrays need to be allocated.

mutable struct Node{T}
    data::T
    parent::Node{T}
    child::Node{T}
    sibling::Node{T}
    
    # Constructor for the root of the tree
    function Node{T}(data) where T
        n = new{T}(data)
        n.parent = n
        n.child = n
        n.sibling = n
        n
    end
    # Constructor for all others
    function Node{T}(data, parent::Node) where T
        n = new{T}(data, parent)
        n.child = n
        n.sibling = n
        n
    end
end
Node(data::T) where {T} = Node{T}(data)
Node(data, parent::Node{T}) where {T} = Node{T}(data, parent)

function lastsibling(sib::Node)
    newsib = sib.sibling
    while sib != newsib
        sib = newsib
        newsib = sib.sibling
    end
    sib
end

function addsibling(oldersib::Node{T}, data) where T
    if oldersib.sibling != oldersib
        error("Truncation of sibling list")
    end
    youngersib = Node(data, oldersib.parent)
    oldersib.sibling = youngersib
    youngersib
end

function addchild(parent::Node{T}, data) where T
    newc = Node(data, parent)
    prevc = parent.child
    if prevc == parent
        parent.child = newc
    else
        prevc = lastsibling(prevc)
        prevc.sibling = newc
    end
    newc
end

isroot(n::Node) = n == n.parent
isleaf(n::Node) = n == n.child

show(io::IO, n::Node) = print(io, n.data)

# Iteration over children
# for c in parent
#     # do something
# end
function iterate(n::Node, state = n.child)
    n == state && return nothing
    return state, state == state.sibling ? n : state.sibling
end

function showedges(io::IO, parent::Node, printfunc = identity)
    str = printfunc(parent.data)
    if str != nothing
        if isleaf(parent)
            println(io, str, " has no children")
        else
            print(io, str, " has the following children: ")
            for c in parent
                print(io, printfunc(c.data), "    ")
            end
            print(io, "\n")
            for c in parent
                showedges(io, c, printfunc)
            end
        end
    end
end
showedges(parent::Node) = showedges(stdout, parent)

end
