var viewport = Snap.select('#viewport');
var viewport_scale = 0.9;
var viewport_cx = viewport.getBBox().cx;

var rects = Snap.selectAll('#viewport rect');
var texts = Snap.selectAll('#viewport text');
var clip_width = Snap.select('#clip-rect').getBBox().w;
var clip_middle = Snap.select('#clip-rect').getBBox().cy;

var avgcharwidth = 6;
var rects = Snap.selectAll('#viewport rect')
var texts = Snap.selectAll('#viewport text')

var details = document.getElementById("details").firstChild; 
//function s(info) { details.nodeValue = info; }
//function c() { details.nodeValue = ' '; }


// Shift the view port to center on xc, then scale in the x direction
var move_and_zoom = function(xc, xScale){
    xScale *= viewport_scale;

    var xshift = -(xc - 0.5*clip_width);
    var rMatrix = new Snap.Matrix;
    rMatrix.translate(xshift, 0);
    rMatrix.scale(xScale, 1, xc, clip_middle);

    var bbox;
    var text;
    var shortinfo;

    rects.forEach(function(rect, i){
        rect.attr({
            rx: 2/xScale,
            ry: 2/xScale
        });
        var bbox = rect.getBBox();
        var text = texts[i];
        var shortinfo = rect.node.getAttribute("data-shortinfo");

        var tMatrix = new Snap.Matrix;
        tMatrix.scale(1.0/xScale, 1, bbox.x, bbox.y);

        text.node.textContent = format_text(shortinfo, bbox.w*xScale);
        text.transform(tMatrix);
    });

    viewport.animate({
        transform: rMatrix
    }, 100);
}

var format_text = function(text, available_len){
    if (available_len < 3*avgcharwidth) {
        return "";
    }
    else if (text.length*avgcharwidth > available_len) {
        nchars = Math.round(available_len/avgcharwidth)-2;
        return text.slice(0,nchars) + ".."
    }
    return text;
}


rects.forEach(function(rect, i){
    rect.dblclick(function(e){
        bbox = rect.getBBox();
        move_and_zoom(bbox.cx, clip_width/bbox.w)
    });
    rect.mouseover(function(e){
        details.nodeValue = rect.node.getAttribute("data-info");
        console.log(details.nodeValue)
    });
    rect.mouseout(function(e){
        details.nodeValue = "";
    });
}) 

texts.forEach(function(rect, i){
    rect.dblclick(function(e){
        bbox = rects[i].getBBox();
        move_and_zoom(bbox.cx, clip_width/bbox.w)
    })
    rect.mouseover(function(e){
        details.nodeValue = rects[i].node.getAttribute("data-info");
    });
    rect.mouseout(function(e){
        console.log("out")
        details.nodeValue = "";
    });

}) 

viewport.drag();
Snap.selectAll(".background").forEach(function(bg){
   bg.dblclick(function(e){
    move_and_zoom(viewport_cx, viewport_scale)
    });
});

move_and_zoom(viewport_cx, viewport_scale)
