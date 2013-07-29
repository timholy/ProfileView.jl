root = Tree.Node(0)
@assert Tree.isroot(root)
@assert Tree.isleaf(root)
nchildren = 0
for c in root
    nchildren += 1
end
@assert nchildren == 0
c1 = Tree.addchild(root, 1)
c2 = Tree.addchild(root, 2)
c3 = Tree.addsibling(c2, 3)
@assert Tree.lastsibling(c1) == c3
c21 = Tree.addchild(c2, 4)
c22 = Tree.addchild(c2, 5)
@assert Tree.isroot(root)
@assert !Tree.isleaf(root)
nchildren = 0
for c in root
    @assert !Tree.isroot(c)
    nchildren += 1
end
@assert nchildren == 3
@assert Tree.isleaf(c1)
@assert !Tree.isleaf(c2)
@assert Tree.isleaf(c3)
for c in c2
    @assert !Tree.isroot(c)
    @assert Tree.isleaf(c)
end
children2 = [c21,c22]
i = 0
for c in c2
    @assert c == children2[i+=1]
end
