/** @jsx React.DOM */

var avgcharwidth = 6;

var RectLayer = React.createClass({displayName: 'RectLayer',
    render: function(){
        return (
            React.DOM.g(null, 
                this.props.data.map(function(result, index){
                    return React.DOM.rect( {'vector-effect':"non-scaling-stroke", key:index, x:result.x, y:result.y, width:result.width, height:result.height, fill:"#" + result.fill});})
            )
        )
    }
})


var format_text = function(text, available_len){
        if (available_len < 3*avgcharwidth) {
            return "";
        }
        else if (text.length*avgcharwidth > available_len) {
            nchars = Math.round(available_len/avgcharwidth)-5;
            return text.slice(0,nchars) + ".."
        }
        return text;
    }

var TextLayer = React.createClass({displayName: 'TextLayer',
    render: function(){
        return (
            React.DOM.g(null, 
                this.props.data.map(function(result, index){
                    if (result.width < 60) {
                        return null;
                    }                        
                    return Text( {key:index, x:result.x+4, y:result.y+11.5, value:format_text(result.shortinfo, result.width)});})
            )
        )
    }
})

var Text = React.createClass({displayName: 'Text',
    render: function(){
        return React.DOM.text( {x:this.props.x, y:this.props.y}, this.props.value)
    }
})


React.renderComponent(
    RectLayer( {data:data}), 
    document.getElementById("rectlayer")
)

React.renderComponent(
    TextLayer( {data:data}), 
    document.getElementById("textlayer")
)
