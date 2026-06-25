module TreeView

using Gtk4
using Profile
using IOCapture

using ..ProfileView

struct Node
    label::String
    children::Vector{Node}
    url::String
end
Node(label) = Node(label, Node[], "")

# Helper for converting ANSI SGR codes to Pango markup
const PANGO_COLOR_MAP = Dict(
    # Standard FG
    30 => "black", 31 => "red", 32 => "green", 33 => "yellow",
    34 => "blue", 35 => "magenta", 36 => "cyan", 37 => "lightgray", # ANSI 'white' often maps to light gray
    39 => :default_fg, # Special marker for default foreground color

    # Bright FG
    90 => "darkgray", 91 => "red", 92 => "green", 93 => "yellow", # Pango might not have "lightyellow", use "yellow"
    94 => "blue", 95 => "magenta", 96 => "cyan", 97 => "white"   # ANSI 'light_white' often maps to pure white
)

function ansi_to_pango(s::String)
    buffer = IOBuffer()
    last_idx = 1
    open_tags = String[] # Stack of Pango closing tags
    active_styles = Dict{Int,String}() # Map SGR codes to their Pango closing tags

    # Regex to find SGR escape sequences: \e[ followed by params (digits and semicolons) followed by m
    sgr_regex = r"\x1B\[([0-9;]*)m"

    for m in eachmatch(sgr_regex, s)
        # Write text before this match, escaping Pango special characters
        if m.offset > last_idx
            segment = s[last_idx : m.offset-1]
            write(buffer, Gtk4.GLib.G_.markup_escape_text(segment, ncodeunits(segment)))
        end

        params_str = m.captures[1]
        local params = if isempty(params_str)
            [0] # Reset
        else
            # Split params string (e.g., "1;31") and parse to integers
            parsed_params = filter(!isempty, split(params_str, ';'))
            isempty(parsed_params) ? [0] : parse.(Int, parsed_params)
        end

        for p in params
            if p == 0 # Reset all attributes
                # Close all open tags in reverse order
                while !isempty(open_tags)
                    write(buffer, pop!(open_tags))
                end
                empty!(active_styles)
            elseif p == 1 && !haskey(active_styles, p) # Bold
                write(buffer, "<b>")
                push!(open_tags, "</b>")
                active_styles[p] = "</b>"
            elseif p == 22 && haskey(active_styles, 1) # Normal intensity (undo bold)
                # Find and remove bold tag
                idx = findlast(==(active_styles[1]), open_tags)
                if idx !== nothing
                    # Close all tags after and including bold, then reopen the ones after
                    for i in length(open_tags):-1:idx
                        write(buffer, open_tags[i])
                    end
                    deleteat!(open_tags, idx)
                    for i in idx:length(open_tags)
                        write(buffer, replace(open_tags[i], r"</.*>" => s->s[2:end-1]))
                    end
                    delete!(active_styles, 1)
                end
            elseif (p >= 30 && p <= 37) || (p >= 90 && p <= 97) # Foreground colors
                # Close any existing foreground color
                for code in keys(active_styles)
                    if (code >= 30 && code <= 37) || (code >= 90 && code <= 97)
                        idx = findlast(==("</span>"), open_tags)
                        if idx !== nothing
                            # Same process as with bold - close and reopen spanning tags
                            for i in length(open_tags):-1:idx
                                write(buffer, open_tags[i])
                            end
                            deleteat!(open_tags, idx)
                            for i in idx:length(open_tags)
                                write(buffer, replace(open_tags[i], r"</.*>" => s->s[2:end-1]))
                            end
                            delete!(active_styles, code)
                        end
                        break
                    end
                end
                # Apply new color
                if (color_name = get(PANGO_COLOR_MAP, p, nothing)) !== nothing
                    write(buffer, "<span foreground='$(color_name)'>")
                    push!(open_tags, "</span>")
                    active_styles[p] = "</span>"
                end
            elseif p == 39 # Default foreground color
                # Remove any active foreground color
                for code in keys(active_styles)
                    if (code >= 30 && code <= 37) || (code >= 90 && code <= 97)
                        idx = findlast(==("</span>"), open_tags)
                        if idx !== nothing
                            for i in length(open_tags):-1:idx
                                write(buffer, open_tags[i])
                            end
                            deleteat!(open_tags, idx)
                            for i in idx:length(open_tags)
                                write(buffer, replace(open_tags[i], r"</.*>" => s->s[2:end-1]))
                            end
                            delete!(active_styles, code)
                        end
                        break
                    end
                end
            end
        end
        last_idx = m.offset + length(m.match)
    end

    # Write any remaining text after the last SGR sequence
    if last_idx <= ncodeunits(s)
        segment = s[last_idx : end]
        write(buffer, Gtk4.GLib.G_.markup_escape_text(segment, ncodeunits(segment)))
    end

    # Close any remaining tags in reverse order
    for tag in reverse(open_tags)
        write(buffer, tag)
    end

    return String(take!(buffer))
end

"""
    remove_ansi_links(s::String) -> String

Remove ANSI OSC 8 hyperlink escape sequences from a string, keeping the link text.
"""
function remove_ansi_links(s::String)
    # OSC 8 hyperlink format: \e]8;PARAMS;URL\e\\ (String Terminator ST)
    # This function removes the link sequences, keeping the display text.
    # It specifically matches ST (\x1B\x5C). For more details on OSC 8:
    # https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda
    
    # Remove the main hyperlink sequence (link part):
    s = replace(s, r"\x1B]8;[^;\x1B\x5C]*;[^\x1B\x5C]*\x1B\x5C" => "")

    # Remove the hyperlink text termination sequence:
    s = replace(s, r"\x1B]8;;\x1B\x5C" => "")
    return s
end

"""
    parse_url_from_ansi_link(s::String)

Extract the URL from an ANSI OSC 8 hyperlink escape sequence.
"""
function parse_url_from_ansi_link(s::String)
    # Extract URL from OSC 8 hyperlink: \e]8;params;URL\e\\
    m = match(r"\x1B]8;[^;\x1B\x5C]*;([^\x1B\x5C]*)\x1B\x5C", s)
    return m === nothing ? "" : m.captures[1]
end

"""
    parse_profile_output(io::IO)

Parse the text output from Profile.print into a tree structure.
"""
function parse_profile_output(io::IO)
    root = Node("Profile")
    stack = [root]

    offset = 0

    for ln in eachline(io)
        # Skip common header or separator lines
        occursin("===", ln) && continue
        occursin("Overhead ╎", ln) && continue
        isempty(strip(ln)) && continue
        ln = collect(ln)

        seen_spacer = false
        depth = 0
        for c in ln
            if c == ' '
            elseif c == '╎'
                seen_spacer = true
            else
                seen_spacer && break
            end
            depth += textwidth(c)
        end
        if offset == 0
            offset = depth - 1
        end

        label = String(ln[depth+1:end])
        url = parse_url_from_ansi_link(label)
        label = remove_ansi_links(label) # Remove OSC 8 link escape codes

        while length(stack) > depth - offset
            pop!(stack)
        end

        # Create node with all fields initialized
        node = Node(label, Node[], url)
        push!(stack[end].children, node)
        push!(stack, node)
    end
    return root
end

"""
    to_treestore(root::Node)

Convert a Node tree to a GtkTreeStore.
"""
function to_treestore(root::Node)
    # Create tree store with two columns: label (String) and URL (String)
    ts = GtkTreeStore(String, String)
    _fill!(ts, nothing, root)
    return ts
end

function _fill!(ts, parent_iter, node::Node)
    # Store both label and URL in the tree store
    iter = Gtk4.push!(ts, (ansi_to_pango(node.label), node.url), parent_iter)
    foreach(child -> _fill!(ts, iter, child), node.children)
end

# Helper function to open URL for a given iterator
function _open_url_for_iter(model, iter)
    label, url = model[iter]
    if !isempty(url)
        try
            if Sys.isapple()
                run(`open $url`)
            elseif Sys.iswindows()
                run(`cmd /c start $url`)
            elseif Sys.islinux()
                run(`xdg-open $url`)
            end
            @info "Opened URL: $url"
        catch e
            @warn "Failed to open URL: $url" exception=e
        end
        return true # URL was processed
    end
    return false # No URL to process
end

## Broken Gtk4 workarounds
function _iter(treeModel::Gtk4.GtkTreeStoreLeaf, path::Gtk4.GtkTreePath)
    it = Ref{Gtk4._GtkTreeIter}()
    ret = ccall((:gtk_tree_model_get_iter, Gtk4.libgtk4), Cint, (Ptr{Gtk4.GObject}, Ptr{Gtk4._GtkTreeIter}, Ptr{Gtk4.GtkTreePath}),
                    treeModel, it, path) != 0
    ret, it[]
end

_path(treeModel, iter) = Gtk4.GtkTreePath(ccall((:gtk_tree_model_get_path, Gtk4.libgtk4), Ptr{Gtk4.GtkTreePath},
                            (Ptr{Gtk4.GObject}, Ref{Gtk4._GtkTreeIter}),
                            treeModel, iter))


##

const TREE_CSS = """
.tree-dark,
.tree-dark treeview {
    background-color: #2d2d2d;
    color: #ffffff;
}

.tree-dark treeview:hover,
.tree-dark treeview row:hover {
    background-color: rgba(255, 255, 255, 0.1);
}

.tree-dark treeview:selected,
.tree-dark treeview row:selected {
    color: #ffffff;
    background-color: #215d9c;
}

.tree-dark treeview:selected:backdrop,
.tree-dark treeview row:selected:backdrop {
    color: #d0d0d0;
    background-color: #1a4a7d;
}

treeview.tree-dark row expander,
treeview.tree-dark row .indent { /* .indent might be specific; expander is standard */
  min-width: 2px;           /* default ≈18 px */
}
"""

"""
    build_treeview(model::GtkTreeStore)

Create a GtkTreeView from a GtkTreeStore.
"""
function build_treeview(model::GtkTreeStore)
    view = GtkTreeView(; model=model)
    r = GtkCellRendererText()
    c = GtkTreeViewColumn("Call stack", r, Dict([(:markup, 0)]))

    # Apply dark theme styling with high priority (GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = 600)
    provider = GtkCssProvider(TREE_CSS)
    sc = Gtk4.style_context(view)
    push!(sc, provider, 600)
    add_css_class(view, "tree-dark")

    Gtk4.G_.set_resizable(c, true)
    Gtk4.G_.set_expand(c, true)
    push!(view, c)
    Gtk4.G_.set_expander_column(view, c)

    # Add click handler
    click = GtkGestureClick(view)
    signal_connect(click, "released") do controller, npress, x, y
        # Get path at clicked coordinates
        path_info = Gtk4.G_.get_path_at_pos(view, round(Int, x), round(Int, y))
        if path_info !== nothing
            path = path_info[2]
            # cell_x, cell_y = path_info[end-1:end] # Not used currently
            if path !== nothing
                is_valid, iter = Gtk4.G_.get_iter_from_string(model, Gtk4.G_.to_string(path))
                if is_valid
                    _open_url_for_iter(model, iter)
                    # Potentially return Gtk4.EVENT_STOP if _open_url_for_iter indicates success
                end
            end
        end
    end

    # Add key press handler
    key_controller = GtkEventControllerKey(view)
    signal_connect(key_controller, "key-pressed") do controller, keyval, keycode, state
        selection = Gtk4.selection(view)
        if Gtk4.hasselection(selection)
            iter = Gtk4.selected(selection)
            if keyval == Gtk4.KEY_space
                path = _path(model, iter)
                if Gtk4.G_.row_expanded(view, path)
                    Gtk4.G_.collapse_row(view, path)
                else
                    Gtk4.G_.expand_row(view, path, true) # Old direct expansion
                end
                return Gtk4.EVENT_STOP # Indicate event handled
            elseif keyval == Gtk4.KEY_Return
                if _open_url_for_iter(model, iter)
                    return Gtk4.EVENT_STOP # Indicate event handled
                end
            end
        end
        return Gtk4.EVENT_PROPAGATE # Allow other handlers
    end

    Gtk4.G_.expand_all(view)  # Expand all nodes by default
    Gtk4.G_.set_level_indentation(view, 0)
    return view
end

"""
    show_profile_tree(data::Vector{UInt64}=Profile.fetch(); lidict=nothing, windowname="Profile Tree View", kwargs...)

Display the output of Profile.print in a collapsible tree view.
"""
function show_profile_tree(data::Vector{UInt64}=Profile.fetch(); lidict=nothing, windowname="Profile Tree View", kwargs...)
    # Capture Profile.print output
    captured = IOCapture.capture(color=true, io_context = [:displaysize=>(1000,1000)]) do
        if lidict === nothing
            Profile.print(data; kwargs...)
        else
            Profile.print(data, lidict; kwargs...)
        end
    end

    io = IOBuffer(captured.output)

    # Parse and create tree
    root = parse_profile_output(io)
    model = to_treestore(root)
    view = build_treeview(model)

    # Create window with tree view
    scroll = GtkScrolledWindow(; hexpand=true, vexpand=true)
    scroll[] = view

    win = GtkWindow(windowname, 900, 600)
    win[] = scroll

    # Register the window with the window registry so it's closed with ProfileView.closeall()
    ProfileView.window_wrefs[win] = nothing

    # Add keyboard shortcuts for closing (Ctrl-q and Ctrl-w)
    kc = GtkEventControllerKey(win)
    signal_connect(ProfileView.close_cb, kc, "key-pressed", Cint, (UInt32, UInt32, UInt32), false, (win))

    # Show the window
    Gtk4.show(win)
    return win
end

end # module TreeView
