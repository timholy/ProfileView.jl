(function(glob, factory){
    if (typeof define == "function" && define.amd) {
        define("ProfileView", ["Snap.svg"], function (Snap){
            return factory(Snap);
        });
    }
    else {
        glob.ProfileView = factory(glob.Snap);
    }
}(this, function(Snap){
    var ProfileView = {};

    var avgcharwidth = 6;
    var default_transition_time = 200;
    var viewport_scale = 0.9;

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

    // Shift the view port to center on xc, then scale in the x direction
    ProfileView.move_and_zoom = function(xc, xScale, fig, delta_t){
        if (typeof delta_t === 'undefined') { delta_t = default_transition_time; }

        xScale *= viewport_scale;

        var xshift = -(xc - 0.5*fig.clip_width);
        var rMatrix = new Snap.Matrix;
        rMatrix.translate(xshift, 0);
        rMatrix.scale(xScale, 1, xc, fig.clip_middle);

        var bbox;
        var text;
        var shortinfo;

        fig.textx.forEach(function(rect, i){
            text.node.textContent = "";
        });

        if (delta_t != 0){
            fig.viewport.animate({
                transform: rMatrix
            }, delta_t);
        }
        else {
            fig.viewport.transform(rMatrix);
        }
        fig.rects.forEach(function(rect, i){
            rect.attr({
                rx: 2/xScale,
                ry: 2/xScale
            });
            var bbox = rect.getBBox();
            var text = fig.texts[i];
            var shortinfo = rect.node.getAttribute("data-shortinfo");

            var tMatrix = new Snap.Matrix;
            tMatrix.scale(1.0/xScale, 1, bbox.x, bbox.y);

            text.node.textContent = format_text(shortinfo, bbox.w*xScale);
            text.transform(tMatrix);
        });
    }

    ProfileView.reset = function(fig) {
        ProfileView.move_and_zoom(fig.viewport_cx, viewport_scale, fig);
    }

    return ProfileView;
}));
