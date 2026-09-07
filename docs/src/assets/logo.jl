# Generate the PkgFactory logo from the repository root:
#   julia --startup-file=no docs/src/assets/logo.jl
# Or in the Julia REPL:
#   include("docs/src/assets/logo.jl")
# No package dependencies are required. Output is relative to this script.
#
# Canvas dimensions and Julia colors follow https://github.com/JuliaFewBody/logo.
# Export a transparent 1300 x 1200 PNG with Inkscape from docs/src/assets:
#   inkscape logo.svg --export-type=png --export-width=1300 --export-filename=logo.png

let
    width, height = 325, 300
    green, red, purple, blue = "#389826", "#CB3C33", "#9558B2", "#4063D8"

    # Three repeated right triangles suggest a factory's sawtooth roof.
    # Keep the gaps generous enough to survive at small icon sizes.
    left = 37.5
    bay_width = 76
    gap = 11
    roof_top, roof_bottom = 70, 158
    body_top, body_bottom = 169, 230
    body_width = 3bay_width + 2gap
    window_size = 18
    window_y = 190.5

    roofs = join(map(enumerate((green, red, purple))) do (i, color)
        x = left + (i - 1) * (bay_width + gap)
        """  <polygon points="$(x),$(roof_bottom) $(x + bay_width),$(roof_top) $(x + bay_width),$(roof_bottom)" fill="$(color)"/>"""
    end, "\n")

    # Oppositely wound subpaths cut transparent windows into the blue body.
    # The evenodd rule also makes this independent of winding direction.
    body = "M $(left) $(body_top) h $(body_width) v $(body_bottom - body_top) h $(-body_width) Z"
    for i in 1:3
        x = left + (i - 1) * (bay_width + gap) + (bay_width - window_size) / 2
        body *= " M $(x) $(window_y) v $(window_size) h $(window_size) v $(-window_size) Z"
    end

    svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" version="1.1"
         width="$(width)pt" height="$(height)pt" viewBox="0 0 $(width) $(height)"
         role="img" aria-labelledby="title desc">
      <title id="title">PkgFactory.jl</title>
      <desc id="desc">An abstract factory with three green, red, and purple triangular roofs above a blue base with three transparent square windows.</desc>
    $(roofs)
      <path d="$(body)" fill="$(blue)" fill-rule="evenodd"/>
    </svg>
    """

    write(joinpath(@__DIR__, "logo.svg"), svg)
end
