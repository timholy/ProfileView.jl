const snapsvgjs = Pkg.dir("ProfileView", "templates", "snap.svg-min.js")
const viewerjs = Pkg.dir("ProfileView", "src", "viewer.js")

function escape_script(js::String)
    return replace(js, "]]", "] ]")
end

function svgheader(f::IO; width=1200, height=706, font="Verdana")

    y_msg = height - 17
    print(f, """<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="$(width)" height="$(height)" onload="init(evt)" viewBox="0 0 $(width) $(height)" xmlns="http://www.w3.org/2000/svg" >
<defs >
    <linearGradient id="background" y1="0" y2="1" x1="0" x2="0" >
        <stop stop-color="#eeeeee" offset="5%" />
        <stop stop-color="#eeeeb0" offset="95%" />
    </linearGradient>
    <clipPath id="image-frame">
      <rect id="clip-rect" x="0" y="0" width=$(width) height=$(height) />
    </clipPath>
</defs>
<style type="text/css">
    rect[rx]:hover { stroke:black; stroke-width:1; }
    text:hover { stroke:black; stroke-width:1; stroke-opacity:0.35; }
</style>
<script type="text/ecmascript">
<![CDATA[
    var details;
    function init(evt) { details = document.getElementById("details").firstChild; }
    function s(info) { details.nodeValue = info; }
    function c() { details.nodeValue = ' '; }
]]>
</script>
<g id="frame" clip-path="url(#image-frame)">
<rect class="background" x="0.0" y="0" width="$(width).0" height="$(height).0" fill="url(#background)"  />
<text class="background" text-anchor="middle" x="600" y="24" font-size="17" font-family="$(font)" fill="rgb(0,0,0)"  >Profile results</text>
<text text-anchor="left" x="10" y="$y_msg" font-size="12" font-family="$(font)" fill="rgb(0,0,0)"  >Function:</text>
<text text-anchor="" x="70" y="$y_msg" font-size="12" font-family="$(font)" fill="rgb(0,0,0)" id="details" > </text>
<g id="viewport" transform="scale(1)">
""")
end
