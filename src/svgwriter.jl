const reactjs = Pkg.dir("ProfileView", "templates", "react.min.js")
const viewerjs = Pkg.dir("ProfileView", "src", "viewer.js")

function escape_script(js::String)
    return replace(js, "]]", "] ]")
end

function svgheader(f::IO, fig_id::String; width=1200, height=706, font="Verdana")

    y_msg = height - 17
    print(f, 
    """<!DOCTYPE html>
       <html>
       <head>
        <script>
        $(escape_script(readall(reactjs)))
        </script>
       </head>
       <body>
       <svg width="$(width)" height="$(height)" viewBox="0 0 $(width) $(height)"> 
       <defs>
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
           text {font-family: "Verdana"; color: black;}
           .info:hover { stroke:black; stroke-width:1; stroke-opacity:0.35; }
           .info {font-size:12px; color: black;}
       </style>
       <g id="$fig_id-frame" clip-path="url(#$fig_id-image-frame)">
       <g id="content"></g></g>
       </svg>
       """)
end


function svgfinish(f::IO, fig_id)
    print(f, """
        <script>
            $(escape_script(readall(viewerjs)))
        </script>
        </body>
        </html>
    """)
end
