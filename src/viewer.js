(function(glob, factory){
    if (typeof define == "function" && define.amd) {
        define("ProfileView", ["React"], function (React){
            return factory(React);
        });
    }
    else {
        glob.ProfileView = factory(glob.React);
    }
}(this, function(React){

var avgcharwidth = 6;
var svgroot = document.getElementById('profileview')

var ProfileView = React.createClass({displayName: 'ProfileView',
    getInitialState: function(){
        return ({scale: 1.0, xc: 600})
    },
    reset: function(){
        this.setState({scale: 1.0, xc: 600});
    },
    zoomHandler: function(index){ //scale, xc){
        entry = this.props.data[index]
        this.setState({
            scale: 1200/entry.width,
            xc: entry.x + 0.5*entry.width
        })
    },
    render: function(){
        return (
            React.DOM.svg( {id:"profileview"}, 
                React.DOM.rect( {x:0, y:0, width:"100%", height:"100%", fill:"url(#background)", onDoubleClick:this.reset}),
                React.DOM.text( {textAnchor:"middle", x:600, y:24, fontSize:"24px"}, "Profile results"),
                React.DOM.g( {id:"rectlayer"}, 
                    RectLayer( {data:this.props.data, scale:this.state.scale, xc:this.state.xc, zoomHandler:this.zoomHandler})
                ),
                React.DOM.g( {id:"textlayer"}, 
                    TextLayer( {data:this.props.data, scale:this.state.scale, xc:this.state.xc, zoomHandler:this.zoomHandler})
                )
            )
        )
    }
})

var Rect = React.createClass({displayName: 'Rect',
    clickHandler: function(e){
        this.props.zoom(this.props.key)
    },
    render: function(){
        return React.DOM.rect( {'vector-effect':"non-scaling-stroke", key:this.props.key, x:this.props.x, y:this.props.y, width:this.props.width, height:this.props.height, fill:"#" + this.props.fill, onDoubleClick:this.clickHandler});
    }
})

var RectLayer = React.createClass({displayName: 'RectLayer',
    render: function(){
        return (
            React.DOM.g( {transform:"matrix(" + this.props.scale + " 0 0 1 " + ((600-this.props.xc) + this.props.xc*(1-this.props.scale)) + " 0)"}, 
                this.props.data.map(function(result, index){
                    return Rect( {key:index, x:result.x, y:result.y, width:result.width, height:result.height, fill:result.fill, zoom:this.props.zoomHandler});}.bind(this))

            )
        )
    }
})


var format_text = function(text, available_len){
    if (text.length*avgcharwidth > available_len) {
        nchars = Math.round(available_len/avgcharwidth)-5;
        return text.slice(0,nchars) + ".."
    }
    return text;
}

var Text = React.createClass({displayName: 'Text',
    clickHandler: function(){
        this.props.zoom(this.props.key);
    },
    render: function(){
        return React.DOM.text( {className:"info", x:this.props.x, y:this.props.y, onDoubleClick:this.clickHandler}, this.props.value)
    }
})

var TextLayer = React.createClass({displayName: 'TextLayer',
    render: function(){
        sx = this.props.scale
        xc = this.props.xc
        var texts = this.props.data.map(function(result, index){
            if ((sx*result.width < 60) || (result.x < xc-600/sx) || (result.x > xc+600/sx)){
                return null;
            }
            else {
                return Text( {key:index, x:4 + sx*result.x + (600-xc) + xc*(1-sx), y:result.y+11.5, value:format_text(result.shortinfo, sx*result.width), zoom:this.props.zoomHandler});
            }
        }.bind(this));
        console.log(texts.filter(function(e){return e}).length)
        return (
            React.DOM.g( {id:"textlayer"}, 
                texts
            )
        )
    }
})

React.renderComponent(
    ProfileView( {data:data} ),
    document.getElementById("content")    
)
}));
