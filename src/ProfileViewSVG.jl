VERSION >= v"0.4.0-dev+6521" && __precompile__()

module ProfileViewSVG

function __init__()
    eval(Expr(:import, :ProfileView))
end

function view(data = Profile.fetch(); C = false, lidict = nothing, colorgc = true, fontsize = 12, combine = true, colorfun = (ip, lidict, irow, index, colorgc) -> ProfileView.default_colorfun(ip, lidict, irow, index, colorgc, ProfileView.colors, ProfileView.gccolor))
    img, lidict, imgtags = ProfileView.prepare(data, C=C, lidict=lidict, colorgc=colorgc, combine=combine, colorfun=colorfun)
    ProfileView.ProfileData(img, lidict, imgtags, fontsize)
end

end
