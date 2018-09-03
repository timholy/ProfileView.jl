module ProfileViewSVG

function __init__()
    @eval import ProfileView
end

function view(data = Profile.fetch(); C = false, lidict = nothing, colorgc = true, fontsize = 12, combine = true, pruned = true)
    img, lidict, imgtags = ProfileView.prepare(data, C=C, lidict=lidict, colorgc=colorgc, combine=combine, pruned=pruned)
    ProfileView.ProfileData(img, lidict, imgtags, fontsize)
end

end
