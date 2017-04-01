# First do the following from src/
#  include("tree.jl")
#  include("pvtree.jl")

# Make a tree like this:
# 0J
# 1C   2J   3C        4J    # children of 0
# 7C        5J   6J         # children of 1 and 3
# J = julia, C = C-code
# Node 7 is a garbage-collection
# With C == false, it should resolve to the following tree:
# 0J
# 2J   5J   6J   4J

node(ip::Integer) = PVTree.PVData(UInt(ip), 1:0)

isjl = Dict(zip(map(UInt, 0:7),[true,false,true,false,true,true,true,false]))
isgc = Dict(zip(map(UInt, 0:7),[falses(7);true]))

function buildraw()
    root = Tree.Node(node(0))
    c1 = Tree.addchild(root, node(1))
    Tree.addchild(root, node(2))
    c3 = Tree.addchild(root, node(3))
    Tree.addchild(root, node(4))
    Tree.addchild(c3, node(5))
    Tree.addchild(c3, node(6))
    Tree.addchild(c1, node(7))
    root
end

# Run it with C == false
root = buildraw()
PVTree.setstatus!(root, isgc)
PVTree.prunegraph!(root, isjl, (), (), (), [])

@assert root.data.status == 1
c = root.child
@assert c.data.ip == 2
@assert c.data.status == 0
c = c.sibling
@assert c.data.ip == 5
@assert c.data.status == 0
c = c.sibling
@assert c.data.ip == 6
@assert c.data.status == 0
c = c.sibling
@assert c.data.ip == 4
@assert c.data.status == 0
@assert c == c.sibling

# Now do it again, with C == true
root = buildraw()
PVTree.setstatus!(root, isgc)
# PVTree.prunegraph!(root, isjl)

@assert root.data.status == 0
c = root.child
c1 = c
@assert c.data.ip == 1
@assert c.data.status == 0
c = c.sibling
@assert c.data.ip == 2
@assert c.data.status == 0
c = c.sibling
c3 = c
@assert c.data.ip == 3
@assert c.data.status == 0
c = c.sibling
@assert c.data.ip == 4
@assert c.data.status == 0
@assert c == c.sibling
c = c3.child
@assert c.data.ip == 5
@assert c.data.status == 0
c = c.sibling
@assert c.data.ip == 6
@assert c.data.status == 0
@assert c == c.sibling
c = c1.child
@assert c.data.ip == 7
@assert c.data.status == 1
@assert Tree.isleaf(c)
@assert c == c.sibling
