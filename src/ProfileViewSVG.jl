VERSION >= v"0.4.0-dev+6521" && __precompile__()

module ProfileViewSVG

function __init__()
    eval(Expr(:import, :ProfileView))
end

function view(data = Profile.fetch(); C = false, lidict = nothing, colorgc = true, fontsize = 12, combine = true)
    img, lidict, imgtags = ProfileView.prepare(data, C=C, lidict=lidict, colorgc=colorgc, combine=combine)
    ProfileView.ProfileData(img, lidict, imgtags, fontsize)
end

end
