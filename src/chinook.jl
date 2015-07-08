using Compat

const CHINOOK_TABLES = ["Artist", "Album", "Playlist", "PlaylistTrack", "Track",
              "MediaType", "Genre", "InvoiceLine", "Invoice", "Employee",
              "Customer"]

function loadchinook()
    path = joinpath(Pkg.dir("SQLAlchemy"), "deps", "data", "Chinook_Sqlite.sqlite")
    engine = createengine("sqlite:///$path")
    schema = MetaData(engine)
    db = connect(engine)
    db, schema
end

