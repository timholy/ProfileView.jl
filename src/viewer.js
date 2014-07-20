var viewport = Snap.select('#viewport')
var rects = Snap.selectAll('#viewport rect')
var texts = Snap.selectAll('#viewport text')
var clip_width = Snap.select('#clip-rect').getBBox().w
var clip_middle = Snap.select('#clip-rect').getBBox().cy

// Shift the view port to center on xc, then scale in the x direction
var move_and_zoom = function(xc, xScale){
    xshift = -(xc - 0.5*clip_width);
    tMatrix = new Snap.Matrix;
    tMatrix.translate(xshift, 0);
    tMatrix.scale(xScale, 1, xc, clip_middle);
    
    viewport.transform(tMatrix);
}


Snap.selectAll('#viewport rect').forEach(function(rect){
    rect.dblclick(function(e){
        bbox = rect.getBBox();
        move_and_zoom(bbox.cx, clip_width/bbox.w)
    })
}) 


