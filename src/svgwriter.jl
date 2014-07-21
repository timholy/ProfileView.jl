const snapsvgjs = Pkg.dir("ProfileView", "templates", "snap.svg-min.js")
const viewerjs = Pkg.dir("ProfileView", "src", "viewer.js")

function escape_script(js::String)
    return replace(js, "]]", "] ]")
end

function svgheader(f::IO, fig_id::String; width=1200, height=706, font="Verdana")

    y_msg = height - 17
    print(f, """<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="$(width)" height="$(height)" viewBox="0 0 $(width) $(height)" xmlns="http://www.w3.org/2000/svg" >
<defs >
    <linearGradient id="background" y1="0" y2="1" x1="0" x2="0" >
        <stop stop-color="#eeeeee" offset="5%" />
        <stop stop-color="#eeeeb0" offset="95%" />
    </linearGradient>
    <clipPath id="$fig_id-image-frame">
      <rect id="$fig_id-clip-rect" x="0" y="0" width="$(width)" height="$(height)" />
    </clipPath>
</defs>
<style type="text/css">
    rect[rx]:hover { stroke:black; stroke-width:1; }
    text:hover { stroke:black; stroke-width:1; stroke-opacity:0.35; }
</style>
<g id="$fig_id-frame" clip-path="url(#$fig_id-image-frame)">
<rect class="background" x="0.0" y="0" width="$(width).0" height="$(height).0" fill="url(#background)"  />
<text class="background" text-anchor="middle" x="600" y="24" font-size="17" font-family="$(font)" fill="rgb(0,0,0)"  >Profile results</text>
<text text-anchor="left" x="10" y="$y_msg" font-size="12" font-family="$(font)" fill="rgb(0,0,0)"  >Function:</text>
<text text-anchor="" x="70" y="$y_msg" font-size="12" font-family="$(font)" fill="rgb(0,0,0)" id="$fig_id-details" > </text>
<g id="$fig_id-viewport" transform="scale(1)">
""")
end


function svgfinish(f::IO, fig_id)
    print(f, """
        </g></g>
        <script><![CDATA[$(escape_script(readall(snapsvgjs)))]]></script>
        <script><![CDATA[
            $(escape_script(readall(viewerjs)))
            (function (glob, factory) {
                if (typeof require === "function" && typeof define === "function" && define.amd) {
                    require(["Snap.svg", "ProfileView"], function (Snap, ProfileView) {
                        factory(Snap, ProfileView);
                    });
              } else {
                  factory(glob.Snap, glob.ProfileView);
              }
            })(window, function (Snap, ProfileView) {
                var fig = {};

                fig.viewport = Snap.select('#$fig_id-viewport');

                fig.viewport_cx = fig.viewport.getBBox().cx;

                fig.rects = Snap.selectAll('#$fig_id-viewport rect');
                fig.texts = Snap.selectAll('#$fig_id-viewport text');

                fig.clip_width = Snap.select('#$fig_id-clip-rect').getBBox().w;
                fig.clip_middle = Snap.select('#$fig_id-clip-rect').getBBox().cy;
                fig.details = document.getElementById("$fig_id-details").firstChild; 

                ProfileView.reset(fig)

                fig.rects.forEach(function(rect, i){
                    rect.dblclick(function(){
                        bbox = rect.getBBox();
                        ProfileView.move_and_zoom(bbox.cx, fig.clip_width/bbox.w, fig);
                    })
                    .mouseover(function(){
                        fig.details.nodeValue = rect.node.getAttribute("data-info");
                    })
                    .mouseout(function(){
                        fig.details.nodeValue = "";
                    });

                })
                fig.texts.forEach(function(text, i){
                    text.dblclick(function(){
                        bbox = fig.rects[i].getBBox();
                        ProfileView.move_and_zoom(bbox.cx, fig.clip_width/bbox.w, fig);
                    })
                    .mouseover(function(){
                        fig.details.nodeValue = fig.rects[i].node.getAttribute("data-info");
                    })
                    .mouseout(function(){
                        fig.details.nodeValue = "";
                    });
                })
                Snap.selectAll("#$fig_id-frame .background").forEach(function(bg){
                   bg.dblclick(function(e){
                       ProfileView.reset(fig);
                    });
                });

            fig.viewport.drag();
    }); ]]></script>
    </svg>
    """)
end
